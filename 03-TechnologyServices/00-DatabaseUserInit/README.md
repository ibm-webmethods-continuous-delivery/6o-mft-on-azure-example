# Database User Initialization for Azure PostgreSQL

This component creates the application database users required by IBM webMethods Active Transfer before running the Database Configurator.

## Purpose

Terraform provisions the PostgreSQL server and databases but does **not** create application users. This component fills that gap by creating lower-privilege application users that will be used by:

1. Database Configurator (DBC) - to create webMethods schemas
2. Active Transfer pods - to connect to the databases

## Execution Order

```
00-DatabaseUserInit → 01-DatabaseConfigurator → 02-AT
```

## Architecture

This component uses **Azure Key Vault with CSI Secrets Store driver** for secure credential management:

```
┌─────────────────────────────────────────────────────────────────┐
│ Kubernetes Job: database-user-init                              │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ ServiceAccount: database-user-init-sa                     │  │
│  │ Annotation: azure.workload.identity/client-id             │  │
│  └──────────────────────────────────────────────────────────┘  │
│                           │                                      │
│                           │ OIDC Token Exchange                  │
│                           ▼                                      │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Azure Managed Identity (mft-identity)                     │  │
│  │ - Federated Credential: database-user-init-sa             │  │
│  │ - RBAC: Key Vault Secrets User                            │  │
│  └──────────────────────────────────────────────────────────┘  │
│                           │                                      │
│                           │ Authenticate & Fetch Secrets         │
│                           ▼                                      │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ SecretProviderClass: db-user-init-azure-kv-secrets        │  │
│  │ - Maps Key Vault secrets to pod volumes                   │  │
│  │ - Syncs to Kubernetes Secret                              │  │
│  └──────────────────────────────────────────────────────────┘  │
│                           │                                      │
│                           ▼                                      │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ CSI Volume Mount: /mnt/secrets-store                      │  │
│  │ Kubernetes Secret: db-user-init-credentials-synced        │  │
│  └──────────────────────────────────────────────────────────┘  │
│                           │                                      │
│                           ▼                                      │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Container: postgres-client                                │  │
│  │ - Reads credentials from synced secret                    │  │
│  │ - Creates PostgreSQL application users                    │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                           │
                           ▼
              ┌────────────────────────┐
              │ Azure PostgreSQL       │
              │ - Creates app users    │
              │ - Grants privileges    │
              └────────────────────────┘
```

### Key Components

1. **ServiceAccount with Workload Identity**: Enables OIDC authentication to Azure
2. **Federated Credential**: Maps Kubernetes ServiceAccount to Azure Managed Identity
3. **SecretProviderClass**: Defines which secrets to fetch from Key Vault
4. **CSI Driver**: Mounts secrets as files and syncs to Kubernetes Secret
5. **Job**: Executes PostgreSQL user creation script

## Prerequisites

### 1. Terraform Applied

Ensure Terraform has been applied in the Service Fulfillment stack:

```bash
cd /aio/work/c/iwcd/6o-mft-on-azure-example/01-AzurePrerequisites/02-ServiceFulfillment
terraform apply -var-file=<your-tfvars-file>
```

This creates:
- Azure Key Vault
- Database credentials as Key Vault secrets (with naming convention: `${environment}-dbc-*`)
- Managed identity with federated credential for `database-user-init-sa`
- RBAC role assignments for Key Vault access

### 2. Database Credentials in Key Vault

Terraform automatically creates the following secrets in Key Vault (default environment is `vanilla`):

- `${environment}-mft-db-postgres-server-fqdn` - PostgreSQL server FQDN
- `${environment}-mft-db-postgres-online-db` - Online database name
- `${environment}-mft-db-postgres-archive-db` - Archive database name
- `${environment}-mft-db-postgres-admin-user` - PostgreSQL admin username
- `${environment}-mft-db-postgres-admin-password` - PostgreSQL admin password
- `${environment}-mft-db-postgres-online-user` - Application username for online database (shared by MFT tools)
- `${environment}-mft-db-postgres-online-password` - Password for online database user (shared by MFT tools)
- `${environment}-mft-db-postgres-archive-user` - Application username for archive database
- `${environment}-mft-db-postgres-archive-password` - Password for archive database user

**Note**: The passwords are set via Terraform variables. Ensure you've configured secure passwords in your `terraform.tfvars` file:

```hcl
postgres_dbc_user             = "mft_app_user"
postgres_dbc_password         = "YourSecurePassword123!"
postgres_dbc_archive_user     = "mft_archive_user"
postgres_dbc_archive_password = "YourSecurePassword456!"
```

### 3. AKS Cluster with CSI Driver

The AKS cluster must have the CSI Secrets Store driver enabled (already configured in Terraform):

```bash
# Verify CSI driver is available
kubectl get csidriver secrets-store.csi.k8s.io
```

## Quick Start

### Deploy the Job

The deployment script automatically:
1. Retrieves configuration from Terraform outputs
2. Generates ServiceAccount and SecretProviderClass manifests
3. Deploys all required Kubernetes resources

```bash
cd /aio/work/c/iwcd/6o-mft-on-azure-example/03-TechnologyServices/00-DatabaseUserInit

# Deploy and follow logs
./deploy.sh --logs

# Or deploy without following logs
./deploy.sh

# Delete existing job before deploying (useful for re-runs)
./deploy.sh --delete --logs

# Dry run to see what would be deployed
./deploy.sh --dry-run
```

### Verify Deployment

```bash
# Check job status
kubectl get job database-user-init

# Check pod status
kubectl get pods -l app=database-user-init

# View logs
kubectl logs -l app=database-user-init

# Check SecretProviderClass
kubectl get secretproviderclass db-user-init-azure-kv-secrets

# Check synced secret (created when pod starts)
kubectl get secret db-user-init-credentials-synced

# Describe pod to see CSI volume mount details
kubectl describe pod -l app=database-user-init
```

## What Gets Created

The initialization job:

1. **Authenticates to Azure** using Workload Identity (OIDC)
2. **Fetches credentials** from Azure Key Vault via CSI driver
3. **Connects to PostgreSQL** using admin credentials
4. **Creates application users** with passwords from Key Vault
5. **Grants necessary privileges** on the online and archive databases
6. **Is idempotent** and can be re-run safely

### Application Users

The usernames and passwords are retrieved from Key Vault secrets:

- **Online database user**: Value from `${environment}-mft-db-postgres-online-user` secret
- **Online database password**: Value from `${environment}-mft-db-postgres-online-password` secret
- **Archive database user**: Value from `${environment}-mft-db-postgres-archive-user` secret
- **Archive database password**: Value from `${environment}-mft-db-postgres-archive-password` secret

## Files

### Kubernetes Manifests

- `kubernetes/serviceaccount-db-user-init.yaml.template` - ServiceAccount with Workload Identity annotation
- `kubernetes/secretproviderclass-db-user-init.yaml.template` - SecretProviderClass for Key Vault integration
- `kubernetes/configmap-db-user-init-script.yaml` - PostgreSQL user creation script
- `kubernetes/job-db-user-init.yaml` - Kubernetes Job definition

### Scripts

- `deploy.sh` - Automated deployment script
- `show_db_tf_outputs.sh` - Display Terraform outputs (for reference)

### Deprecated Files

- `scripts/generate-secret.sh` - **DEPRECATED**: Legacy manual secret generation (kept for reference)
- `kubernetes/secret-db-user-init-admin-creds.yaml.template` - **DEPRECATED**: Legacy secret template

**Note**: The CSI driver approach eliminates the need for manual secret generation. The deprecated files are kept for reference but should not be used.

## Troubleshooting

### Error: CSI driver not found

**Symptom**: `kubectl get csidriver secrets-store.csi.k8s.io` fails

**Solution**: Ensure AKS cluster has CSI Secrets Store driver enabled. This is configured in Terraform:

```hcl
key_vault_secrets_provider {
  secret_rotation_enabled  = true
  secret_rotation_interval = "2m"
}
```

### Error: Pod fails to mount secrets

**Symptom**: Pod events show "failed to mount secrets store objects"

**Possible Causes**:

1. **Federated credential not created**: Check Terraform applied successfully
   ```bash
   cd ../../01-AzurePrerequisites/02-ServiceFulfillment
   terraform output mft_managed_identity_id
   az identity federated-credential list \
     --identity-name <identity-name> \
     --resource-group <rg-name>
   ```

2. **Secret names don't match**: Verify secret names in Key Vault
   ```bash
   KV_NAME=$(terraform output -raw key_vault_name)
   ENV=$(terraform output -raw environment_name)
   az keyvault secret list --vault-name "$KV_NAME" | grep "${ENV}-mft-db"
   ```

3. **RBAC permissions missing**: Check managed identity has Key Vault Secrets User role
   ```bash
   az role assignment list \
     --assignee <managed-identity-principal-id> \
     --scope <key-vault-id>
   ```

### Error: Job fails with authentication error

**Symptom**: Logs show "AADSTS700213: No matching federated identity record found"

**Solution**: The federated credential subject must exactly match the ServiceAccount:

```
system:serviceaccount:default:database-user-init-sa
```

Verify in Terraform:

```hcl
resource "azurerm_federated_identity_credential" "db_user_init" {
  subject = "system:serviceaccount:default:database-user-init-sa"
  ...
}
```

### Error: Secrets not synced to Kubernetes Secret

**Symptom**: `kubectl get secret db-user-init-credentials-synced` not found

**Solution**: The secret is only created when a pod mounts the CSI volume. Check:

1. Pod is running: `kubectl get pods -l app=database-user-init`
2. Pod events: `kubectl describe pod -l app=database-user-init`
3. SecretProviderClass exists: `kubectl get secretproviderclass db-user-init-azure-kv-secrets`

### Error: PostgreSQL connection fails

**Symptom**: Job logs show "could not connect to server"

**Possible Causes**:

1. **Network connectivity**: Verify AKS can reach PostgreSQL (check firewall rules)
2. **Admin credentials incorrect**: Verify Terraform outputs match PostgreSQL configuration
3. **Database not ready**: Wait for PostgreSQL to be fully provisioned

## Security Considerations

### Workload Identity (OIDC)

- **No credentials stored in Kubernetes**: Authentication uses OIDC tokens
- **Automatic token rotation**: Tokens are short-lived and automatically refreshed
- **Least privilege**: Managed identity only has Key Vault Secrets User role

### Secret Management

- **Centralized in Key Vault**: Single source of truth for credentials
- **Automatic rotation**: CSI driver refreshes secrets every 2 minutes (configurable)
- **Audit trail**: All secret access logged in Azure Monitor

### Network Security

- **Private endpoints**: Key Vault can use private endpoint (controlled by Terraform variable)
- **Network policies**: Consider implementing Kubernetes network policies for pod-to-pod communication

## Next Steps

After successful user initialization:

1. **Deploy Database Configurator** (`01-DatabaseConfigurator`):
   ```bash
   cd ../01-DatabaseConfigurator
   ./deploy.sh --logs
   ```

2. **Deploy Active Transfer** (`02-AT`):
   ```bash
   cd ../02-AT
   # Follow deployment instructions in that directory
   ```

## References

- [Azure Workload Identity](https://azure.github.io/azure-workload-identity/)
- [CSI Secrets Store Driver](https://secrets-store-csi-driver.sigs.k8s.io/)
- [Azure Key Vault Provider](https://azure.github.io/secrets-store-csi-driver-provider-azure/)
- [Terraform Configuration](../../01-AzurePrerequisites/02-ServiceFulfillment/README.md)
