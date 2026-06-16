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
- Azure Key Vault with application database passwords
- Network connectivity from AKS to PostgreSQL (private endpoint or service endpoint)

### 2. Azure Key Vault Setup with CSI Driver Integration

This component uses **Azure Key Vault with Secrets Store CSI Driver** for secure secrets management. Database credentials are stored in Azure Key Vault and mounted directly into pods using Azure Workload Identity (OIDC-based authentication).

#### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│  AKS Cluster                                                │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Pod: database-configurator                           │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │  ServiceAccount: database-configurator-sa       │  │  │
│  │  │  (with workload identity annotation)            │  │  │
│  │  └─────────────────────────────────────────────────┘  │  │
│  │                      │                                 │  │
│  │                      ▼                                 │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │  CSI Secrets Store Driver                       │  │  │
│  │  │  - Mounts secrets from Key Vault                │  │  │
│  │  │  - Creates K8s Secret (synced)                  │  │  │
│  │  │  - Auto-rotation every 2 minutes                │  │  │
│  │  └─────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                          │
                          │ OIDC Token Exchange
                          ▼
┌─────────────────────────────────────────────────────────────┐
│  Azure AD                                                   │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Managed Identity: mft-identity                       │  │
│  │  - Federated Credential (OIDC)                        │  │
│  │  - Subject: system:serviceaccount:default:...        │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                          │
                          │ Authenticated Access
                          ▼
┌─────────────────────────────────────────────────────────────┐
│  Azure Key Vault                                            │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Secrets (hierarchical naming):                       │  │
│  │  - vanilla-mft-db-postgres-server-fqdn                       │  │
│  │  - vanilla-mft-db-postgres-online-db                         │  │
│  │  - vanilla-mft-db-postgres-archive-db                        │  │
│  │  - vanilla-mft-db-postgres-user                              │  │
│  │  - vanilla-mft-db-postgres-password                          │  │
│  │  - vanilla-mft-db-postgres-archive-user                      │  │
│  │  - vanilla-mft-db-postgres-archive-password                  │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

#### How It Works

1. **Workload Identity Authentication**:
   - Pod uses ServiceAccount with Azure Workload Identity annotation
   - AKS OIDC issuer provides token to Azure AD
   - Azure AD validates token against federated credential
   - Managed identity is granted access to Key Vault

2. **Secret Mounting**:
   - CSI driver mounts secrets as files in `/mnt/secrets-store`
   - Secrets are also synced to Kubernetes Secret: `dbc-postgres-credentials-synced`
   - Pod uses standard `envFrom.secretRef` pattern

3. **Automatic Rotation**:
   - CSI driver polls Key Vault every 2 minutes
   - Updated secrets are automatically remounted
   - No pod restart required for secret updates

#### Infrastructure Prerequisites (Configured in Terraform)

The following are automatically configured when you apply the Terraform in `01-AzurePrerequisites/02-ServiceFulfillment`:

✅ **AKS Cluster**:
- OIDC issuer enabled
- CSI Secrets Store driver enabled with 2-minute rotation

✅ **Managed Identity**:
- User-assigned identity: `${prefix}-mft-identity`
- Federated credential for workload identity
- Subject: `system:serviceaccount:default:database-configurator-sa`

✅ **Key Vault**:
- RBAC authorization enabled
- Role assignments:
  - `Key Vault Secrets User` → MFT managed identity
  - `Key Vault Administrator` → Terraform identity (for secret creation)

✅ **Network**:
- Private endpoint (if `key_vault_public_access_enabled = false`)
- Service endpoint from AKS subnet

#### Required Secrets in Key Vault

Before running the Database Configurator, ensure these secrets exist in Key Vault:

| Secret Name | Description | Example Value |
|-------------|-------------|---------------|
| `<env>-mft-db-postgres-server-fqdn` | PostgreSQL server FQDN | `myserver.postgres.database.azure.com` |
| `<env>-mft-db-postgres-online-db` | Online database name | `mft_online` |
| `<env>-mft-db-postgres-archive-db` | Archive database name | `mft_archive` |
| `<env>-mft-db-postgres-online-user` | Online DB application user (shared by MFT tools) | `mft_app_user` |
| `<env>-mft-db-postgres-online-password` | Online DB password (shared by MFT tools) | `SecurePassword123!` |
| `<env>-mft-db-postgres-archive-user` | Archive DB application user | `mft_archive_user` |
| `<env>-mft-db-postgres-archive-password` | Archive DB password | `SecurePassword456!` |

**Note**: `<env>` is the environment name from Terraform (default: `vanilla`)

#### Option 1: Create Secrets via Terraform (Recommended)

Add to `01-AzurePrerequisites/02-ServiceFulfillment/main.tf`:

```hcl
# Database credentials for Database Configurator
resource "azurerm_key_vault_secret" "dbc_credentials" {
  for_each = {
    "postgres-server-fqdn"      = azurerm_postgresql_flexible_server.main.fqdn
    "postgres-online-db"        = azurerm_postgresql_flexible_server_database.online.name
    "postgres-archive-db"       = azurerm_postgresql_flexible_server_database.archive.name
    "postgres-user"             = var.postgres_app_username
    "postgres-password"         = var.postgres_app_password
    "postgres-archive-user"     = var.postgres_archive_username
    "postgres-archive-password" = var.postgres_archive_password
  }
  
  name         = "${var.environment_name}-dbc-${each.key}"
  value        = each.value
  key_vault_id = azurerm_key_vault.main.id
  
  depends_on = [azurerm_role_assignment.terraform_kv_admin]
}
```

Then apply Terraform:

```bash
cd ../../01-AzurePrerequisites/02-ServiceFulfillment
terraform apply
```

#### Option 2: Create Secrets via Azure CLI

```bash
# Get Key Vault name and environment from Terraform
cd ../../01-AzurePrerequisites/02-ServiceFulfillment
KV_NAME=$(terraform output -raw key_vault_name)
ENV=$(terraform output -raw environment_name)
POSTGRES_FQDN=$(terraform output -raw postgres_server_fqdn)
ONLINE_DB=$(terraform output -raw postgres_online_db_name)
ARCHIVE_DB=$(terraform output -raw postgres_archive_db_name)

# Store database connection details
az keyvault secret set --vault-name "$KV_NAME" \
  --name "${ENV}-mft-db-postgres-server-fqdn" --value "$POSTGRES_FQDN"

az keyvault secret set --vault-name "$KV_NAME" \
  --name "${ENV}-mft-db-postgres-online-db" --value "$ONLINE_DB"

az keyvault secret set --vault-name "$KV_NAME" \
  --name "${ENV}-mft-db-postgres-archive-db" --value "$ARCHIVE_DB"

# Store application credentials (use same as DatabaseUserInit)
az keyvault secret set --vault-name "$KV_NAME" \
  --name "${ENV}-mft-db-postgres-user" --value "mft_app_user"

az keyvault secret set --vault-name "$KV_NAME" \
  --name "${ENV}-mft-db-postgres-password" --value "YOUR_ONLINE_PASSWORD"

az keyvault secret set --vault-name "$KV_NAME" \
  --name "${ENV}-mft-db-postgres-archive-user" --value "mft_archive_user"

az keyvault secret set --vault-name "$KV_NAME" \
  --name "${ENV}-mft-db-postgres-archive-password" --value "YOUR_ARCHIVE_PASSWORD"
```

#### Verifying Key Vault Setup

```bash
# List all DBC secrets
az keyvault secret list --vault-name "$KV_NAME" \
  --query "[?starts_with(name, '${ENV}-dbc-')].name" -o table

# Verify a specific secret (without showing value)
az keyvault secret show --vault-name "$KV_NAME" \
  --name "${ENV}-mft-db-postgres-server-fqdn" \
  --query "name"
```

### 3. Container Image

The Database Configurator container image must be available in your Azure Container Registry (ACR):

```bash
# Get ACR login server from Terraform
terraform output -raw acr_login_server

# Expected image: <ACR_LOGIN_SERVER>/active-transfer-dcc:latest
```

This image is built in `02-ContainerImages/02-active-transfer-dcc-ingest/`.

### 4. Kubernetes Access

- `kubectl` configured with access to target AKS cluster
- Appropriate RBAC permissions to create Jobs, ConfigMaps, and Secrets

### 5. Azure CLI Authentication

Ensure you are logged in to Azure CLI:

```bash
az login
az account show
```

## Deployment

### Execution Order

Run the database preparation flow in this order:

1. `../00-DatabaseUserInit` - create/grant application users
2. `01-DatabaseConfigurator` - create webMethods schemas using those application users
3. `../02-AT` - deploy Active Transfer using the same application users

### Step 1: Create Application Users First

Before running DBC, deploy `../00-DatabaseUserInit` to create the application users required by DBC and Active Transfer.

### Step 2: Generate Database Credentials Secret

The script automatically retrieves Terraform outputs and fetches passwords from Azure Key Vault:

```bash
# Generate secret (fetches passwords from Key Vault)
./scripts/generate-secret.sh

# Apply the secret
kubectl apply -f kubernetes/secret-dbc-creds.yaml
```

**What the script does:**
- Retrieves database connection details from Terraform outputs
- Fetches Key Vault name from Terraform
- Retrieves application passwords from Azure Key Vault
- Generates Kubernetes secret with all required credentials

**Application User Details** (default usernames, can be customized):
- Online database: `mft_app_user`
- Archive database: `mft_archive_user`

To use custom usernames, set environment variables before running `generate-secret.sh`:

```bash
export POSTGRES_USER="custom_online_user"
export POSTGRES_ARCHIVE_USER="custom_archive_user"
./scripts/generate-secret.sh
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

### Key Vault Access Errors

**Symptoms**: "Failed to fetch password from Key Vault" errors

**Possible Causes**:
- Not logged in to Azure CLI
- Secret not set in Key Vault
- Insufficient permissions

**Solutions**:
```bash
# Verify Azure CLI login
az login
az account show

# Check secret exists
az keyvault secret show \
  --vault-name <KEY_VAULT_NAME> \
  --name dev-mft-secret-db-online-password

# Set the secret if missing
az keyvault secret set \
  --vault-name <KEY_VAULT_NAME> \
  --name dev-mft-secret-db-online-password \
  --value "YOUR_PASSWORD"
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
│   └── secret-dbc-creds.yaml.template  # Secret template (for reference)
├── scripts/
│   ├── entrypoint.sh                   # DBC initialization script
│   └── generate-secret.sh              # Secret generation from Key Vault
├── deploy.sh                           # Deployment automation script
├── show_db_tf_outputs.sh               # Helper to display Terraform outputs
└── README.md                           # This file
```

**Note**: The `job-dbc.yaml` and `secret-dbc-creds.yaml` files are auto-generated and excluded from version control.

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

This example uses Azure Key Vault for centralized secrets management, which is a significant improvement over basic Kubernetes Secrets. However, for production environments, consider additional security measures:

### Production Recommendations

#### 1. Azure Key Vault with Secrets Store CSI Driver (Recommended)

**Benefits**:
- Native Azure integration
- Automatic secret rotation
- Centralized secrets management
- Audit logging via Azure Monitor
- RBAC and access policies
- Secrets mounted directly into pods (no intermediate K8s secrets)

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
          objectName: dev-mft-secret-db-online-password
          objectType: secret
        - |
          objectName: dev-mft-secret-db-archive-password
          objectType: secret
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

**Reference**: https://external-secrets.io/

#### 3. HashiCorp Vault

**Benefits**:
- Enterprise-grade secrets management
- Dynamic secrets generation
- Detailed audit logs
- Secret versioning and rollback

**Reference**: https://www.vaultproject.io/

### Security Best Practices

1. **Credential Management**
   - Use Azure Key Vault for centralized secret storage
   - Implement credential rotation policies
   - Use separate credentials for different environments

2. **Access Control**
   - Use Azure Managed Identity for Key Vault access
   - Implement least-privilege access principles
   - Enable audit logging for secret access

3. **Network Security**
   - Use private endpoints for PostgreSQL
   - Implement network policies in Kubernetes
   - Restrict database access to specific subnets

4. **Monitoring and Auditing**
   - Track who accesses secrets and when
   - Monitor for unauthorized access attempts
   - Set up alerts for suspicious activity

5. **Pod Security**
   - Use restricted profile for production workloads
   - Implement security contexts (non-root, read-only filesystem where possible)
   - Enable Pod Security Standards

## Next Steps

After successful database initialization:

1. **Verify Database Schemas**
   - Connect to PostgreSQL and verify tables were created
   - Check schema versions

2. **Deploy Active Transfer Service**
   - Proceed to `03-TechnologyServices/02-AT/`
   - Use the same database credentials from Key Vault

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
- [Azure Key Vault](https://learn.microsoft.com/en-us/azure/key-vault/)
- [Azure Key Vault CSI Driver](https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-driver)