# Database Configurator for Azure PostgreSQL

This component initializes the webMethods database schemas required for IBM webMethods Active Transfer (MFT) in Azure PostgreSQL Flexible Server.

## Overview

The Database Configurator (DBC) is a one-time initialization job that creates the necessary database schemas for:

1. **Online Database** - Active transaction data (ISInternal, ISCoreAudit, ActiveTransfer, CentralUsers)
2. **Archive Database** - Historical data (ActiveTransferArchive, ComponentTracker, TaskArchive)

## Architecture

```
┌────────────────────────────────────────────────────────────┐
│                    Kubernetes Job                          │
│  ┌────────────────────────────────────────────────────┐    │
│  │  database-configurator                             │    │
│  │  ┌──────────────────────────────────────────────┐  │    │
│  │  │  Container: active-transfer-dcc              │  │    │
│  │  │  - Runs dbConfigurator.sh                    │  │    │
│  │  │  - Initializes online database               │  │    │
│  │  │  - Initializes archive database              │  │    │
│  │  └──────────────────────────────────────────────┘  │    │
│  │                                                    │    │
│  │  Mounts:                                           │    │
│  │  - ConfigMap: entrypoint script                    │    │
│  │  - Secret: database credentials                    │    │
│  └────────────────────────────────────────────────────┘    │
└────────────────────────────────────────────────────────────┘
                            │
                            ▼
              ┌──────────────────────────┐
              │  Azure PostgreSQL        │
              │  Flexible Server         │
              │                          │
              │  - Online Database       │
              │  - Archive Database      │
              └──────────────────────────┘
```

## Prerequisites

### 1. Azure Infrastructure

Ensure the following resources are provisioned (via Terraform in `01-AzurePrerequisites`):

- Azure PostgreSQL Flexible Server
- Online database created
- Archive database created
- Database users with appropriate permissions
- Network connectivity from AKS to PostgreSQL (private endpoint or service endpoint)

### 2. Container Image

The Database Configurator container image must be available in your Azure Container Registry (ACR):

```bash
# Get ACR login server from Terraform
terraform output -raw acr_login_server

# Expected image: <ACR_LOGIN_SERVER>/active-transfer-dcc:latest
```

This image is built in `02-ContainerImages/02-active-transfer-dcc-ingest/`.

### 3. Kubernetes Access

- `kubectl` configured with access to target AKS cluster
- Appropriate RBAC permissions to create Jobs, ConfigMaps, and Secrets

## Deployment

## Execution Order

Run the database preparation flow in this order:

1. `../00-DatabaseUserInit` - create/grant application users
2. `01-DatabaseConfigurator` - create webMethods schemas using those application users
3. `../02-AT` - deploy Active Transfer using the same application users

### Step 1: Create Application Users First

Before running DBC, deploy `../00-DatabaseUserInit` to create the application users required by DBC and Active Transfer.

### Step 2: Create Database Credentials Secret

1. Copy the secret template:
   ```bash
   cp kubernetes/secret-dbc-creds.yaml.template kubernetes/secret-dbc-creds.yaml
   ```

2. Get values from Terraform outputs using the helper script:
   ```bash
   ./show_db_tf_outputs.sh
   ```

   This will display all database connection values from Terraform in a convenient format.

3. Edit `kubernetes/secret-dbc-creds.yaml` and fill in the values:
   - `POSTGRES_SERVER_FQDN`: PostgreSQL server FQDN from Terraform
   - `POSTGRES_ONLINE_DB`: Online database name from Terraform
   - `POSTGRES_ARCHIVE_DB`: Archive database name from Terraform
   - `POSTGRES_USER`: application username created by `00-DatabaseUserInit`
   - `POSTGRES_PASSWORD`: application password created for the online database user
   - `POSTGRES_ARCHIVE_USER`: application username created by `00-DatabaseUserInit`
   - `POSTGRES_ARCHIVE_PASSWORD`: application password created for the archive database user

4. Apply the secret:
   ```bash
   kubectl apply -f kubernetes/secret-dbc-creds.yaml
   ```

### Step 3: Deploy Using Script (Recommended)

The deployment script automatically retrieves the ACR login server from Terraform and generates the job manifest:

```bash
# Deploy with default settings
./deploy.sh

# Deploy with options
./deploy.sh --namespace mft --delete --logs

# Dry run to see what would be deployed
./deploy.sh --dry-run
```

**What the script does automatically:**
1. Retrieves ACR login server from Terraform outputs
2. Generates `kubernetes/job-dbc.yaml` from the template
3. Validates prerequisites (kubectl, cluster access, secret exists)
4. Deploys ConfigMap and Job
5. Shows deployment status and helpful commands

### Step 4: Deploy Manually (Alternative)

If you prefer manual deployment or need to customize the process:

1. **Get ACR login server from Terraform:**
   ```bash
   cd ../../01-AzurePrerequisites/02-ServiceFulfillment
   export ACR_LOGIN_SERVER=$(terraform output -raw acr_login_server)
   cd -
   ```

2. **Generate job manifest from template:**
   ```bash
   envsubst < kubernetes/job-dbc.yaml.template > kubernetes/job-dbc.yaml
   ```

3. **Deploy resources:**

```bash
# Apply ConfigMap
kubectl apply -f kubernetes/configmap-dbc-script.yaml

# Apply Job
kubectl apply -f kubernetes/job-dbc.yaml
```

## Monitoring

### Check Job Status

```bash
# Get job status
kubectl get job database-configurator

# Get pod status
kubectl get pods -l app=database-configurator

# Describe job for events
kubectl describe job database-configurator
```

### View Logs

```bash
# Follow logs in real-time
kubectl logs -l app=database-configurator -f

# View logs after completion
kubectl logs job/database-configurator
```

### Expected Output

Successful initialization will show:

```
==========================================
Database Configurator - Starting
==========================================
PostgreSQL Server: <your-server>.postgres.database.azure.com
Online Database: mft_online
Archive Database: mft_archive
Components: all
Archive Components: ActiveTransferArchive,ComponentTracker,TaskArchive
==========================================

Initializing online database: mft_online
------------------------------------------
[DBC output...]
✓ Online database initialized successfully

Initializing archive database: mft_archive
------------------------------------------
[DBC output...]
✓ Archive database initialized successfully

==========================================
Database Configurator - Completed
==========================================
```

## Troubleshooting

### Job Fails to Start

**Symptoms**: Job remains in pending state

**Possible Causes**:
- Secret not found
- Image pull errors
- Insufficient resources

**Solutions**:
```bash
# Check pod events
kubectl describe pod -l app=database-configurator

# Check secret exists
kubectl get secret dbc-postgres-credentials

# Check image pull
kubectl get events --sort-by='.lastTimestamp'
```

### Connection Errors

**Symptoms**: "Cannot connect to database" errors in logs

**Possible Causes**:
- Network connectivity issues
- Incorrect FQDN or database name
- Invalid credentials
- Firewall rules blocking AKS

**Solutions**:
```bash
# Verify network connectivity from AKS
kubectl run -it --rm debug --image=postgres:15 --restart=Never -- \
  psql -h <POSTGRES_FQDN> -U <USER> -d <DATABASE>

# Check PostgreSQL firewall rules in Azure Portal
# Ensure AKS subnet is allowed

# Verify credentials
kubectl get secret dbc-postgres-credentials -o yaml
```

### SSL/TLS Errors

**Symptoms**: SSL connection errors

**Possible Causes**:
- SSL mode mismatch
- Certificate validation issues

**Solutions**:
- Ensure `sslmode=require` is set in connection string
- Azure PostgreSQL Flexible Server provides SSL by default
- Check if custom CA certificates are needed

### Schema Already Exists

**Symptoms**: "Schema already exists" warnings

**Impact**: This is normal and expected. DBC is idempotent.

**Action**: No action needed. The job will complete successfully.

## Re-running the Job

The Database Configurator is **idempotent** and safe to run multiple times:

```bash
# Delete existing job
kubectl delete job database-configurator

# Redeploy
./deploy.sh
```

## Cleanup

```bash
# Delete the job (optional - auto-deletes after 24 hours)
kubectl delete job database-configurator

# Delete ConfigMap (if needed)
kubectl delete configmap dbc-entrypoint-script

# Delete Secret (keep for Active Transfer deployment)
# kubectl delete secret dbc-postgres-credentials
```

## Files Structure

```
01-DatabaseConfigurator/
├── kubernetes/
│   ├── job-dbc.yaml.template           # Job template (auto-generated to job-dbc.yaml)
│   ├── job-dbc.yaml                    # Generated Job manifest (gitignored)
│   ├── configmap-dbc-script.yaml       # ConfigMap with entrypoint script
│   └── secret-dbc-creds.yaml.template  # Secret template (copy and fill)
├── scripts/
│   └── entrypoint.sh                   # DBC initialization script
├── deploy.sh                           # Deployment automation script
├── show_db_tf_outputs.sh               # Helper to display Terraform outputs
└── README.md                           # This file
```

**Note**: The `job-dbc.yaml` file is auto-generated from the template by `deploy.sh` and is excluded from version control.

## Configuration

### Environment Variables

The following environment variables are used by the entrypoint script:

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `POSTGRES_SERVER_FQDN` | Azure PostgreSQL server FQDN | - | Yes |
| `POSTGRES_ONLINE_DB` | Online database name | - | Yes |
| `POSTGRES_ARCHIVE_DB` | Archive database name | - | Yes |
| `POSTGRES_USER` | Online database username | - | Yes |
| `POSTGRES_PASSWORD` | Online database password | - | Yes |
| `POSTGRES_ARCHIVE_USER` | Archive database username | - | Yes |
| `POSTGRES_ARCHIVE_PASSWORD` | Archive database password | - | Yes |
| `WM_HOME` | webMethods installation home | `/opt/softwareag` | No |
| `WM_DB_COMPONENTS` | Components to initialize | `all` | No |
| `WM_ARCHIVE_DB_COMPONENTS` | Archive components | `ActiveTransferArchive,ComponentTracker,TaskArchive` | No |

### Database Components

**Online Database Components** (default: `all`):
- `ISInternal` - Integration Server internal tables
- `ISCoreAudit` - Core audit logging
- `ActiveTransfer` - MFT transaction data
- `CentralUsers` - User management

**Archive Database Components**:
- `ActiveTransferArchive` - Historical MFT data
- `ComponentTracker` - Component tracking
- `TaskArchive` - Task history

## Security Considerations

### ⚠️ IMPORTANT: Production Secrets Management

This vanilla example uses **basic Kubernetes Secrets** for simplicity. This approach is **NOT recommended for production environments**.

### Production Recommendations

Organizations deploying this solution in production should implement enterprise-grade secrets management:

#### 1. Azure Key Vault with Secrets Store CSI Driver

**Benefits**:
- Native Azure integration
- Automatic secret rotation
- Centralized secrets management
- Audit logging via Azure Monitor
- RBAC and access policies

**Implementation**:
```bash
# Install CSI driver
helm repo add csi-secrets-store-provider-azure https://azure.github.io/secrets-store-csi-driver-provider-azure/charts
helm install csi csi-secrets-store-provider-azure/csi-secrets-store-provider-azure

# Create SecretProviderClass
kubectl apply -f - <<EOF
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: azure-kvname-system-msi
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "true"
    userAssignedIdentityID: "<IDENTITY_CLIENT_ID>"
    keyvaultName: "<KEY_VAULT_NAME>"
    objects: |
      array:
        - |
          objectName: postgres-server-fqdn
          objectType: secret
        - |
          objectName: postgres-online-db
          objectType: secret
        # ... more secrets
    tenantId: "<TENANT_ID>"
EOF
```

**Reference**: https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-driver

#### 2. External Secrets Operator (ESO)

**Benefits**:
- Multi-cloud support (Azure, AWS, GCP)
- Automatic secret synchronization
- GitOps-friendly
- Multiple backend support

**Implementation**:
```bash
# Install ESO
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets

# Create SecretStore
kubectl apply -f - <<EOF
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: azure-backend
spec:
  provider:
    azurekv:
      authType: ManagedIdentity
      vaultUrl: "https://<KEY_VAULT_NAME>.vault.azure.net"
      identityId: "<IDENTITY_CLIENT_ID>"
EOF

# Create ExternalSecret
kubectl apply -f - <<EOF
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: dbc-postgres-credentials
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: azure-backend
    kind: SecretStore
  target:
    name: dbc-postgres-credentials
  data:
  - secretKey: POSTGRES_SERVER_FQDN
    remoteRef:
      key: postgres-server-fqdn
  # ... more mappings
EOF
```

**Reference**: https://external-secrets.io/

#### 3. HashiCorp Vault

**Benefits**:
- Enterprise-grade secrets management
- Dynamic secrets generation
- Detailed audit logs
- Secret versioning and rollback

**Reference**: https://www.vaultproject.io/

#### 4. Sealed Secrets

**Benefits**:
- Encrypt secrets in Git repositories
- GitOps-friendly
- No external dependencies

**Reference**: https://github.com/bitnami-labs/sealed-secrets

### Security Best Practices

1. **Never commit actual credentials to version control**
   - Use `.gitignore` to exclude `secret-dbc-creds.yaml`
   - Only commit the `.template` file

2. **Use separate credentials for different environments**
   - Development, staging, and production should have different credentials
   - Implement least-privilege access

3. **Implement credential rotation policies**
   - Regularly rotate database passwords
   - Use automated rotation where possible

4. **Enable audit logging**
   - Track who accesses secrets and when
   - Monitor for unauthorized access attempts

5. **Use managed identities**
   - Prefer Azure Managed Identity over service principals
   - Eliminate the need to manage credentials for Azure resources

6. **Implement network security**
   - Use private endpoints for PostgreSQL
   - Implement network policies in Kubernetes
   - Restrict database access to specific subnets

7. **Enable Pod Security Standards**
   - Use restricted profile for production workloads
   - Implement security contexts (non-root, read-only filesystem where possible)

## Next Steps

After successful database initialization:

1. **Verify Database Schemas**
   - Connect to PostgreSQL and verify tables were created
   - Check schema versions

2. **Deploy Active Transfer Service**
   - Proceed to `03-TechnologyServices/02-AT/`
   - Use the same database credentials

3. **Configure Monitoring**
   - Set up alerts for database connectivity issues
   - Monitor database performance

## Support and Troubleshooting

For issues or questions:

1. Check the logs: `kubectl logs job/database-configurator`
2. Review Azure PostgreSQL metrics in Azure Portal
3. Verify network connectivity from AKS to PostgreSQL
4. Consult webMethods documentation for DBC-specific issues

## References

- [webMethods Database Configurator Documentation](https://www.ibm.com/docs/en/webmethods-integration/webmethods-installer/11.1.0?topic=iwpp-installing-products-creating-database-components-connecting-products-database-components)
- [Azure PostgreSQL Flexible Server](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/)
- [Kubernetes Jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/)
- [Azure Key Vault CSI Driver](https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-driver)
