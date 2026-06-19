# MFT Configuration Management

This directory provides tools, templates, and documentation for managing IBM webMethods Active Transfer (MFT) configuration in Azure Key Vault.

## Overview

All MFT-related secrets and configuration are centrally managed in Azure Key Vault with a hierarchical naming convention that supports multiple environments. This approach provides:

- **Centralized Management**: Single source of truth for all MFT secrets
- **Environment Isolation**: Separate secrets per environment (vanilla, dev, test, prod)
- **Audit Trail**: All access logged in Azure Monitor
- **Automatic Rotation**: Secrets can be rotated without application downtime
- **RBAC Integration**: Fine-grained access control via Azure AD

## Key Vault Secret Naming Convention

All secrets follow the pattern: `${environment}-${component}-${secret-name}`

### Environment Prefixes

- `vanilla` - Default ephemeral/scratch environment (default)
- `dev` - Development environment
- `test` - Testing/staging environment
- `prod` - Production environment

**Note**: The default environment is `vanilla` (changed from `dev` to emphasize ephemeral nature). To use a different environment, explicitly set it in Terraform variables.

## MFT Key Vault Secrets Reference

### Database Credentials (`mft-db-*`)

Database connection and authentication secrets for PostgreSQL.

| Secret Name | Description | Used By | Example Value |
|-------------|-------------|---------|---------------|
| `${env}-mft-db-postgres-server-fqdn` | PostgreSQL Flexible Server FQDN | All DB components | `myserver.postgres.database.azure.com` |
| `${env}-mft-db-postgres-online-db` | Online database name | DatabaseConfigurator, AT | `mft_online` |
| `${env}-mft-db-postgres-archive-db` | Archive database name | DatabaseConfigurator, AT | `mft_archive` |
| `${env}-mft-db-postgres-admin-user` | PostgreSQL admin username (bootstrap only) | DatabaseUserInit | `psqladmin` |
| `${env}-mft-db-postgres-admin-password` | PostgreSQL admin password (bootstrap only) | DatabaseUserInit | `SecureAdminPass123!` |
| `${env}-mft-db-postgres-online-user` | Application user for online DB (shared by MFT tools) | DatabaseConfigurator, AT | `mft_app_user` |
| `${env}-mft-db-postgres-online-password` | Password for online DB user (shared by MFT tools) | DatabaseConfigurator, AT | `SecureOnlinePass456!` |
| `${env}-mft-db-postgres-archive-user` | Application user for archive DB | DatabaseConfigurator, AT | `mft_archive_user` |
| `${env}-mft-db-postgres-archive-password` | Password for archive DB user | DatabaseConfigurator, AT | `SecureArchivePass789!` |

**Security Notes**:
- Admin credentials should only be used for initial database setup
- Application users have limited privileges (no DDL, only DML)
- Online and archive users are separate for security isolation
- Passwords should be rotated regularly (90-day expiration recommended)

### MFT Application Secrets (`mft-*`)

Core MFT application configuration and authentication.

| Secret Name | Description | Used By | Example Value |
|-------------|-------------|---------|---------------|
| `${env}-mft-admin-password` | MFT administrator password | Admin UI, Management | `AdminPass123!` |

**Note:** The MFT runtime configuration (`mft-config.json`) is now managed as a ConfigMap in the Helm chart's gitops folder (`helm/gitops/config/<env>/mft-config.json`), not as a Key Vault secret.

### Certificate and Keystore Secrets (`mft-*`)

SSL/TLS certificates and keystore passwords for secure communication.

| Secret Name | Description | Used By | Example Value |
|-------------|-------------|---------|---------------|
| `${env}-mft-admin-ui-jks-keystore-password` | Admin UI JKS keystore password | Admin UI | `KeystorePass123!` |
| `${env}-mft-admin-ui-pkcs12-keystore-password` | Admin UI PKCS12 keystore password | Admin UI | `KeystorePass123!` |
| `${env}-mft-admin-ui-jks-truststore-password` | Admin UI JKS truststore password | Admin UI | `TruststorePass123!` |
| `${env}-mft-admin-ui-pkcs12-truststore-password` | Admin UI PKCS12 truststore password | Admin UI | `TruststorePass123!` |
| `${env}-mft-web-client-jks-keystore-password` | Web Client JKS keystore password | Web Client | `KeystorePass456!` |
| `${env}-mft-web-client-pkcs12-keystore-password` | Web Client PKCS12 keystore password | Web Client | `KeystorePass456!` |
| `${env}-mft-web-client-jks-truststore-password` | Web Client JKS truststore password | Web Client | `TruststorePass456!` |
| `${env}-mft-web-client-pkcs12-truststore-password` | Web Client PKCS12 truststore password | Web Client | `TruststorePass456!` |
| `${env}-mft-cert-jks-truststore-password` | Global MFT JKS truststore password | All components | `GlobalTrustPass123!` |
| `${env}-mft-cert-pkcs12-truststore-password` | Global MFT PKCS12 truststore password | All components | `GlobalTrustPass123!` |

**Keystore and Truststore Naming Rules:**

- **Keystores** (`${env}-mft-${config-name}-{keystore-type}-keystore`): Contain private keys and are encrypted at rest when deployed in PODs. The corresponding password is a Key Vault secret with the name `${env}-mft-${config-name}-{keystore-type}-keystore-password`
  - Example: `vanilla-mft-cert-admin-ui-jks-keystore` with password `vanilla-mft-admin-ui-jks-keystore-password`

- **Truststores** (`${env}-mft-${config-name}-{truststore-type}-truststore`): Contain trusted certificates but no private keys, and are encrypted at rest when deployed in PODs. The corresponding password is a Key Vault secret with the name `${env}-mft-${config-name}-{truststore-type}-truststore-password`
  - Example: `vanilla-mft-cert-truststore-jks` with password `vanilla-mft-cert-jks-truststore-password`

- **Bag/Entry Passwords**: For PKCS12 stores, bag names and passwords, as well as entry passwords in JKS stores, are managed separately. For the current scope, bag or entry passwords are assumed to coincide with the store passwords. Bag or entry names are resolved in the `mft-config.json` file that references the secrets.

### Certificate Files (`mft-cert-*`)

Base64-encoded certificate files stored as secrets.

| Secret Name | Description | Format | Used By |
|-------------|-------------|--------|---------|
| `${env}-mft-cert-admin-ui-keystore-pkcs12` | PKCS12 keystore, encrypted to open HTTPS ports for administration UI. Password: `${env}-mft-admin-ui-pkcs12-keystore-password` | Base64 | Admin UI |
| `${env}-mft-cert-admin-ui-keystore-jks` | JKS formatted keystore, encrypted to open HTTPS ports for administration UI. Password: `${env}-mft-admin-ui-jks-keystore-password` | Base64 | Admin UI |
| `${env}-mft-cert-web-client-keystore-pkcs12` | Keystore for web client HTTPS port, in PKCS12 format. Password: `${env}-mft-web-client-pkcs12-keystore-password` | Base64 | Web Client |
| `${env}-mft-cert-web-client-keystore-jks` | Keystore for web client HTTPS port, in JKS format. Password: `${env}-mft-web-client-jks-keystore-password` | Base64 | Web Client |
| `${env}-mft-cert-truststore-pkcs12` | Global truststore for MFT, in PKCS12 format, encrypted. Password: `${env}-mft-cert-pkcs12-truststore-password` | Base64 | All components |
| `${env}-mft-cert-truststore-jks` | Global truststore for MFT, in JKS format, encrypted. Password: `${env}-mft-cert-jks-truststore-password` | Base64 | All components |
| `${env}-mft-cert-ca-bundle-pem` | Bundle of certificates, in PEM format, without encryption | Base64 | All components |

### Certificate Objects (Key Vault Certificates)

Certificates imported as Key Vault certificate objects (not just secrets).

| Certificate Name | Description | Used By |
|------------------|-------------|---------|
| `${env}-mft-admin-ui-cert-with-chain` | Admin UI cert with full chain | Admin UI |
| `${env}-mft-admin-ui-cert-no-chain` | Admin UI cert without chain | Admin UI |
| `${env}-mft-web-client-cert-with-chain` | Web Client cert with full chain | Web Client |
| `${env}-mft-web-client-cert-no-chain` | Web Client cert without chain | Web Client |

### SFTP Secrets (`mft-sftp-*`)

SFTP server authentication credentials.

| Secret Name | Description | Used By | Example Value |
|-------------|-------------|---------|---------------|
| `${env}-mft-sftp-ssh-private-key` | SSH private key for SFTP server | SFTP VMs | `-----BEGIN RSA PRIVATE KEY-----...` |
| `${env}-mft-sftp-ssh-private-key-loaded` | Loaded SSH private key (from cert generation) | SFTP VMs | `-----BEGIN RSA PRIVATE KEY-----...` |

## Secret Lifecycle Management

### Creation

Secrets are created via Terraform in `01-AzurePrerequisites/02-ServiceFulfillment/main.tf`:

```hcl
# Database credentials
resource "azurerm_key_vault_secret" "mft_db_credentials" {
  for_each = local.mft_db_credentials
  
  name         = "${local.environment}-mft-db-${each.key}"
  value        = each.value.value
  key_vault_id = azurerm_key_vault.main.id
  
  tags = {
    Description = each.value.description
  }
}

# Default MFT secrets
resource "azurerm_key_vault_secret" "defaults" {
  for_each = local.default_secrets
  
  name         = each.key
  value        = each.value.value
  key_vault_id = azurerm_key_vault.main.id
  
  tags = {
    Description = each.value.description
  }
}
```

### Rotation

**Recommended Rotation Schedule**:
- Database passwords: Every 90 days
- Application passwords: Every 90 days
- Certificates: Before expiration (typically 365 days)
- SSH keys: Every 180 days

**Rotation Process**:
1. Generate new secret value
2. Update in Key Vault
3. CSI driver automatically refreshes (2-minute interval)
4. Pods pick up new value on next mount
5. Verify application connectivity
6. Remove old secret after grace period

### Expiration

Secrets have expiration dates set via Terraform:

```hcl
expiration_date = timeadd(timestamp(), "2160h")  # 90 days
```

**Monitoring Expiration**:
```bash
# List secrets expiring in next 30 days
az keyvault secret list --vault-name <kv-name> \
  --query "[?attributes.expires < '$(date -u -d '+30 days' +%Y-%m-%dT%H:%M:%SZ)'].{name:name, expires:attributes.expires}" \
  -o table
```

## Access Patterns

### Kubernetes Workload Identity (Recommended)

MFT components use Azure Workload Identity (OIDC) for secure, credential-less access:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: mft-service-account
  annotations:
    azure.workload.identity/client-id: "<managed-identity-client-id>"
---
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: mft-azure-kv-secrets
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "false"
    clientID: "<managed-identity-client-id>"
    keyvaultName: "<key-vault-name>"
    tenantId: "<tenant-id>"
    objects: |
      array:
        - objectName: vanilla-mft-db-postgres-online-password
          objectType: secret
```

### Azure CLI (Manual Operations)

For manual operations or troubleshooting:

```bash
# Set environment
ENV="vanilla"
KV_NAME="<your-key-vault-name>"

# Read a secret
az keyvault secret show \
  --vault-name "$KV_NAME" \
  --name "${ENV}-mft-db-postgres-online-password" \
  --query "value" -o tsv

# Update a secret
az keyvault secret set \
  --vault-name "$KV_NAME" \
  --name "${ENV}-mft-db-postgres-online-password" \
  --value "NewSecurePassword123!"

# List all MFT secrets for an environment
az keyvault secret list \
  --vault-name "$KV_NAME" \
  --query "[?starts_with(name, '${ENV}-mft')].name" \
  -o table
```

## Tools and Scripts

### Available Tools

#### Secret Management Scripts

1. **`view-at-vault-secrets.sh`** - View MFT secrets with descriptions
   
   Lists all MFT secrets in Azure Key Vault with detailed information including type, description, enabled status, and expiration dates.
   
   ```bash
   # List all secrets (without values)
   ./view-at-vault-secrets.sh
   
   # List secrets for specific environment
   ./view-at-vault-secrets.sh dev
   
   # Show secret values (use with caution!)
   ./view-at-vault-secrets.sh --show-values
   
   # Show values for specific environment
   ./view-at-vault-secrets.sh dev --show-values
   ```
   
   **Features:**
   - Organized by category (Database, Application, Certificates)
   - Color-coded output for easy reading
   - Optional value display with truncation for long values
   - Retrieves descriptions from Key Vault tags

2. **`set-at-helm-secret.sh`** - Set or update a secret value
   
   Helps operators set or update secret values in Azure Key Vault with proper naming conventions and content types.
   
   ```bash
   # Set admin password
   ./set-at-helm-secret.sh mft-admin-password "MySecurePassword123!"
   
   # Set database password for specific environment
   ./set-at-helm-secret.sh mft-db-postgres-online-password "DbPassword456" dev
   
   # Set SSH private key from file
   ./set-at-helm-secret.sh mft-sftp-ssh-private-key "$(cat ~/.ssh/id_rsa)"
   
   # Set metering config XML from file
   ./set-at-helm-secret.sh mft-metering-config-xml-file "$(cat metering.xml)"
   ```
   
   **Features:**
   - Automatic environment prefix handling
   - Content type detection (JSON, XML, binary)
   - JSON validation for config files
   - Confirmation for existing secrets
   - Next steps guidance after setting secrets

3. **`check-at-helm-secrets-presence.sh`** - Validate secret completeness
   
   Validates that all secrets required by the Helm chart are present in Azure Key Vault before deployment.
   
   ```bash
   # Check secrets for default environment
   ./check-at-helm-secrets-presence.sh
   
   # Check secrets for specific environment
   ./check-at-helm-secrets-presence.sh dev
   ```
   
   **Features:**
   - Validates all required secrets for Helm deployment
   - Distinguishes between required and optional secrets
   - Detailed summary with counts
   - Actionable recommendations for missing secrets
   - Exit code 0 if all required secrets present, 1 otherwise

#### Legacy Tools

- `list-secrets.sh` - Basic secret listing (legacy, use `view-at-vault-secrets.sh` instead)
- `validate-secrets.sh` - Basic validation (legacy, use `check-at-helm-secrets-presence.sh` instead)
- `update-kv/list-current-secrets.sh` - List all secrets in Key Vault
- Additional helper scripts (see subdirectories)

**Note:** The `update-mft-config-json-secret.sh` script is obsolete. MFT configuration is now managed in `helm/gitops/config/<env>/mft-config.json`.

### Recommended Workflow

1. **Before Deployment**: Check secret completeness
   ```bash
   ./check-at-helm-secrets-presence.sh
   ```

2. **View Current Secrets**: Review what's in Key Vault
   ```bash
   ./view-at-vault-secrets.sh
   ```

3. **Update Secrets**: Change default passwords and set actual values
   ```bash
   ./set-at-helm-secret.sh mft-admin-password "NewSecurePassword"
   ./set-at-helm-secret.sh mft-db-postgres-online-password "DbPassword"
   ```

4. **Verify Changes**: Confirm secrets are set correctly
   ```bash
   ./view-at-vault-secrets.sh --show-values | grep -A 5 "mft-admin-password"
   ```

5. **Final Check**: Validate before Helm deployment
   ```bash
   ./check-at-helm-secrets-presence.sh
   ```

### Planned Tools

- `rotate-db-passwords.sh` - Automated database password rotation
- `export-secrets.sh` - Export secrets for backup (encrypted)
- `import-secrets.sh` - Import secrets from backup

## Security Best Practices

### Access Control

1. **Use Managed Identities**: Prefer workload identity over service principals
2. **Least Privilege**: Grant only required permissions (Key Vault Secrets User, not Administrator)
3. **Separate Environments**: Use different Key Vaults or strict RBAC for prod vs non-prod
4. **Audit Logging**: Enable diagnostic settings for Key Vault access logs

### Secret Management

1. **Never Commit Secrets**: Use `.gitignore` for generated files with secrets
2. **Rotate Regularly**: Implement automated rotation for critical secrets
3. **Use Strong Passwords**: Minimum 16 characters, mixed case, numbers, symbols
4. **Set Expiration**: All secrets should have expiration dates
5. **Monitor Access**: Set up alerts for unauthorized access attempts

### Network Security

1. **Private Endpoints**: Use private endpoints for Key Vault in production
2. **Firewall Rules**: Restrict Key Vault access to specific networks
3. **Disable Public Access**: Set `key_vault_public_access_enabled = false` in Terraform

## Troubleshooting

### Common Issues

#### Secret Not Found

```bash
# Verify secret exists
az keyvault secret show --vault-name "$KV_NAME" --name "${ENV}-mft-db-postgres-online-password"

# List all secrets
az keyvault secret list --vault-name "$KV_NAME" -o table
```

#### Access Denied

```bash
# Check managed identity has correct role
az role assignment list \
  --assignee <managed-identity-principal-id> \
  --scope /subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<kv-name>

# Grant Key Vault Secrets User role
az role assignment create \
  --assignee <managed-identity-principal-id> \
  --role "Key Vault Secrets User" \
  --scope /subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<kv-name>
```

#### CSI Driver Mount Failures

```bash
# Check pod events
kubectl describe pod <pod-name>

# Check CSI driver logs
kubectl logs -n kube-system -l app=secrets-store-csi-driver

# Verify SecretProviderClass
kubectl get secretproviderclass -o yaml
```

## Migration from Legacy Naming

If migrating from the old `dbc-*` naming convention:

1. **Create new secrets** with `mft-db-*` naming
2. **Update Kubernetes manifests** to reference new secret names
3. **Deploy updated applications** using new secrets
4. **Verify connectivity** and functionality
5. **Deprecate old secrets** after grace period
6. **Delete old secrets** after confirming no usage

**Migration Script** (example):

```bash
#!/bin/bash
ENV="vanilla"
KV_NAME="<your-kv-name>"

# Copy old secrets to new names
OLD_SECRETS=(
  "postgres-server-fqdn"
  "postgres-online-db"
  "postgres-archive-db"
  "postgres-online-user"
  "postgres-online-password"
  "postgres-archive-user"
  "postgres-archive-password"
)

for secret in "${OLD_SECRETS[@]}"; do
  OLD_NAME="${ENV}-dbc-${secret}"
  NEW_NAME="${ENV}-mft-db-${secret}"
  
  # Get old value
  VALUE=$(az keyvault secret show --vault-name "$KV_NAME" --name "$OLD_NAME" --query "value" -o tsv)
  
  # Set new secret
  az keyvault secret set --vault-name "$KV_NAME" --name "$NEW_NAME" --value "$VALUE"
  
  echo "Migrated: $OLD_NAME -> $NEW_NAME"
done
```

## References

- [Azure Key Vault Documentation](https://learn.microsoft.com/en-us/azure/key-vault/)
- [Secrets Store CSI Driver](https://secrets-store-csi-driver.sigs.k8s.io/)
- [Azure Workload Identity](https://azure.github.io/azure-workload-identity/)
- [Terraform Configuration](../../01-AzurePrerequisites/02-ServiceFulfillment/README.md)

## Support

For issues or questions:
1. Check this README for secret naming and usage
2. Review Terraform outputs for current configuration
3. Check Azure Monitor logs for Key Vault access
4. Consult component-specific READMEs (DatabaseUserInit, DatabaseConfigurator, etc.)
