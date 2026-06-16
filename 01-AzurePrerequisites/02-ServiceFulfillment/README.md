# Stage 02 - Service Fulfillment Infrastructure

Provision the Azure infrastructure for the MFT service-fulfillment stage:

- 2 SFTP VMs behind a public Load Balancer on port `55022`
- 1 AKS cluster for HTTP workloads
- 1 Application Gateway for ingress
- 1 PostgreSQL Flexible Server with private networking

This folder contains both the Terraform stack and the helper scripts used after `terraform apply`.

## What you need first

Complete **01-ServiceDelivery** before using this stack.

Required tools:

- Terraform
- Azure CLI
- kubectl
- Helm

## Files you will use most

- `common.tfvars`: shared configuration
- `full.tfvars`: one-step deployment settings
- `phase1.tfvars`: infrastructure-only deployment for limited permissions
- `phase2.tfvars`: second apply after manual role grants
- `01a-tf-apply-full.sh`: full deployment helper
- `01b-tf-apply-phased.sh`: phased deployment helper
- `02-import-kube-config.sh`: writes kubeconfig from Terraform output if missing
- `04-apply-kube-prerequisites.sh`: creates the AGIC namespace
- `05-deploy-agic-helm.sh`: installs or upgrades AGIC
- `06-deploy-web-test-app.sh`: deploys the `simple-web` validation app
- `07-test.sh`: tests ingress routing through Application Gateway

## Deployment options

Choose one of these paths.

### Option A - full deployment

Use this when the identity running Terraform can also create Azure role assignments.

1. Prepare your variables in `common.tfvars` or your own `.tfvars` file.
2. Initialize Terraform:
   ```sh
   terraform init
   ```
3. Apply:
   ```sh
   ./01a-tf-apply-full.sh ./common.tfvars
   ```

### Option B - phased deployment

Use this when Terraform can create resources but cannot create role assignments.

1. Prepare your variables in `common.tfvars` or your own `.tfvars` file.
2. Initialize Terraform:
   ```sh
   terraform init
   ```
3. Apply phase 1:
   ```sh
   terraform apply --auto-approve --var-file=./common.tfvars --var-file=./phase1.tfvars
   ```
4. Grant the missing permissions with an account that has elevated Azure RBAC permissions.
5. Wait a few minutes for RBAC propagation.
6. Apply phase 2:
   ```sh
   terraform apply --auto-approve --var-file=./common.tfvars --var-file=./phase2.tfvars
   ```

## Required configuration

At minimum, set these values:

- `resource_group_name`
- `resource_group_name_existing`
- `location`
- `prefix`
- `allowed_ip_ranges`
- `ssh_admin_pub_key`
- `acr_name`
- `postgres_admin_password`

Notes:

- `resource_group_name_existing` must point to the resource group that already contains the ACR from stage 01.
- `allowed_ip_ranges` controls inbound access to SSH and SFTP.
- Keep secrets out of committed files.

## After Terraform apply

### 1. Import kubeconfig

```sh
./02-import-kube-config.sh
```

### 2. Create Kubernetes prerequisites

```sh
./04-apply-kube-prerequisites.sh
```

### 3. Install AGIC

```sh
./05-deploy-agic-helm.sh
```

This deployment uses:

- a **user-assigned managed identity** created by Terraform
- AGIC installed by Helm
- Application Gateway as the ingress target

### 4. Deploy the validation app

```sh
./06-deploy-web-test-app.sh
```

### 5. Run the ingress test

```sh
./07-test.sh
```

## Validation flow

Expected validation sequence:

1. Terraform completes successfully
2. `./02-import-kube-config.sh` creates or reuses `~/.kube/config-mft`
3. AGIC installs successfully in namespace `agic`
4. `simple-web` is deployed into namespace `http-test`
5. The ingress receives the Application Gateway public IP
6. `./07-test.sh` returns the nginx page through Application Gateway

## Useful outputs

Examples:

```sh
terraform output app_gateway_public_ip
terraform output sftp_endpoint
terraform output postgres_server_fqdn
terraform output aks_cluster_name
```

Show all outputs:

```sh
terraform output
```

## Common issues

### AGIC install fails

Check:

```sh
kubectl get pods -n agic
kubectl logs -n agic -l app=ingress-azure --tail=100
```

Also verify the AGIC identity has these permissions:

- `Contributor` on the Application Gateway
- `Reader` on the resource group
- `Managed Identity Operator` on the AGIC managed identity for the AKS kubelet identity

### Ingress has no public IP yet

Wait a short time, then check:

```sh
kubectl get ingress -n http-test
kubectl logs -n agic -l app=ingress-azure --tail=100
```

### App Gateway returns backend errors

Check:

```sh
kubectl get pods -n http-test
kubectl get svc -n http-test
kubectl describe ingress simple-web -n http-test
```

### kubectl cannot connect

Recreate kubeconfig:

```sh
rm -f ~/.kube/config-mft
./02-import-kube-config.sh
```

## Cleanup

Destroy all Azure resources created by this stack:

```sh
terraform destroy --var-file=./common.tfvars --var-file=./full.tfvars
```

Use the same variable set you used for deployment.

## Review notes

Main improvements recommended for this folder:

- keep the managed-identity AGIC flow consistent across Terraform, scripts, and docs
- complete `01b-tf-apply-phased.sh` so the phased path is as easy as the full path
- reduce duplication between `terraform.tfvars.example` and `common.tfvars`
- add explicit validation for `resource_group_name_existing`
- avoid storing secrets in plain example files beyond placeholders


## Azure Key Vault Integration

This Terraform stack automatically provisions an Azure Key Vault and populates it with secrets required by MFT components.

### Key Vault Features

- **RBAC Authorization**: Uses Azure RBAC instead of access policies
- **Workload Identity**: Integrated with AKS OIDC for secure, credential-free access
- **Automatic Secret Rotation**: CSI Secrets Store driver rotates secrets every 2 minutes
- **Private Networking**: Can be configured for private endpoint access (controlled by `key_vault_public_access_enabled`)
- **Soft Delete & Purge Protection**: 90-day retention for deleted secrets

### Managed Identity for Workload Access

The stack creates a user-assigned managed identity (`mft-identity`) with:

- Federated credential for AKS OIDC authentication
- `Key Vault Secrets User` role on the Key Vault
- `Key Vault Certificate User` role on the Key Vault

This identity is used by Kubernetes workloads via Azure Workload Identity (no credentials stored in Kubernetes).

### Secrets Automatically Created

#### 1. Database Configurator Credentials

The following secrets are created for the Database Configurator component:

- `${environment}-dbc-postgres-server-fqdn`: PostgreSQL server FQDN
- `${environment}-dbc-postgres-online-db`: Online database name
- `${environment}-dbc-postgres-archive-db`: Archive database name
- `${environment}-dbc-postgres-user`: Application user for online database
- `${environment}-dbc-postgres-password`: Password for online database user
- `${environment}-dbc-postgres-archive-user`: Application user for archive database
- `${environment}-dbc-postgres-archive-password`: Password for archive database user

**Configuration Variables:**

```hcl
# In your .tfvars file
postgres_dbc_user             = "mft_app_user"
postgres_dbc_password         = "YourSecurePassword456!"
postgres_dbc_archive_user     = "mft_archive_user"
postgres_dbc_archive_password = "YourSecurePassword789!"
```

#### 2. MFT Default Secrets

Default placeholder secrets for MFT components (should be updated after deployment):

- `${environment}-mft-secret-admin-password`
- `${environment}-mft-secret-db-online-password`
- `${environment}-mft-secret-db-archive-password`
- `${environment}-mft-secret-admin-ui-keystore-password`
- `${environment}-mft-secret-admin-ui-truststore-password`
- `${environment}-mft-secret-web-client-keystore-password`
- `${environment}-mft-secret-web-client-truststore-password`
- `${environment}-mft-secret-sftp-ssh-private-key`
- `${environment}-mft-secret-config-json`

**⚠️ WARNING**: These default secrets have placeholder values and expire in 90 days. Update them immediately after deployment.

#### 3. Certificate Files (Optional)

When `upload_certificates = true`, the stack uploads certificate files to Key Vault:

- Admin UI keystores (PKCS12, JKS)
- Web Client keystores (PKCS12, JKS)
- Truststores (PKCS12, JKS)
- CA bundle (PEM)
- SFTP SSH private key

### Secret Naming Convention

All secrets follow a hierarchical naming pattern:


### Certificate File Management

#### Overview

MFT requires several certificate files (JKS keystores, truststores, SSH keys) that must be stored in Key Vault. These are binary files that cannot be directly managed by Terraform and require manual upload.

#### Required Certificate Files

The following certificate files must be uploaded to Key Vault:

| Secret Name | Purpose | Source File | Format |
|-------------|---------|-------------|--------|
| `${environment}-mft-admin-ui-keystore-jks` | Admin UI HTTPS certificate | `3p-certificates/data/subjects/az-certs/02-admin-ui/out/rsa/full.chain.key.store.jks` | JKS binary |
| `${environment}-mft-admin-ui-truststore-jks` | Admin UI truststore | `3p-certificates/data/subjects/az-certs/02-admin-ui/out/rsa/simple.trust.store.jks` | JKS binary |
| `${environment}-mft-web-client-keystore-jks` | Web Client HTTPS certificate | `3p-certificates/data/subjects/az-certs/03-web-client/out/rsa/full.chain.key.store.jks` | JKS binary |
| `${environment}-mft-web-client-truststore-jks` | Web Client truststore | `3p-certificates/data/subjects/az-certs/03-web-client/out/rsa/simple.trust.store.jks` | JKS binary |
| `${environment}-mft-sftp-ssh-private-key` | SFTP server RSA private key | `3p-certificates/data/subjects/az-certs/04-sftp-server/out/id_rsa` | PEM text |
| `${environment}-mft-sftp-ssh-public-key` | SFTP server RSA public key | `3p-certificates/data/subjects/az-certs/04-sftp-server/out/id_rsa.pub` | PEM text |

#### Upload Certificate Files to Key Vault

**Prerequisites:**
1. Generate certificates using the `3p-certificates` project
2. Ensure certificates are available in the paths listed above
3. Have Azure CLI authenticated with appropriate permissions

**Upload Script:**

```bash
#!/bin/bash
# Upload certificate files to Azure Key Vault

# Get Key Vault name from Terraform output
KV_NAME=$(terraform output -raw key_vault_name)
ENV=$(terraform output -raw environment_name)

# Certificate base path (adjust to your local path)
CERT_BASE_PATH="../../../3p-certificates/data/subjects/az-certs"

# Upload Admin UI certificates
echo "Uploading Admin UI certificates..."
az keyvault secret set \
  --vault-name "$KV_NAME" \
  --name "${ENV}-mft-admin-ui-keystore-jks" \
  --file "${CERT_BASE_PATH}/02-admin-ui/out/rsa/full.chain.key.store.jks" \
  --encoding base64

az keyvault secret set \
  --vault-name "$KV_NAME" \
  --name "${ENV}-mft-admin-ui-truststore-jks" \
  --file "${CERT_BASE_PATH}/02-admin-ui/out/rsa/simple.trust.store.jks" \
  --encoding base64

# Upload Web Client certificates
echo "Uploading Web Client certificates..."
az keyvault secret set \
  --vault-name "$KV_NAME" \
  --name "${ENV}-mft-web-client-keystore-jks" \
  --file "${CERT_BASE_PATH}/03-web-client/out/rsa/full.chain.key.store.jks" \
  --encoding base64

az keyvault secret set \
  --vault-name "$KV_NAME" \
  --name "${ENV}-mft-web-client-truststore-jks" \
  --file "${CERT_BASE_PATH}/03-web-client/out/rsa/simple.trust.store.jks" \
  --encoding base64

# Upload SFTP SSH keys
echo "Uploading SFTP SSH keys..."
az keyvault secret set \
  --vault-name "$KV_NAME" \
  --name "${ENV}-mft-sftp-ssh-private-key" \
  --file "${CERT_BASE_PATH}/04-sftp-server/out/id_rsa"

az keyvault secret set \
  --vault-name "$KV_NAME" \
  --name "${ENV}-mft-sftp-ssh-public-key" \
  --file "${CERT_BASE_PATH}/04-sftp-server/out/id_rsa.pub"

echo "Certificate upload complete!"
```

**Verify Upload:**

```bash
# List all certificate secrets
az keyvault secret list --vault-name "$KV_NAME" | grep -E "(keystore|truststore|ssh)"

# Check a specific secret (shows metadata, not content)
az keyvault secret show --vault-name "$KV_NAME" --name "${ENV}-mft-admin-ui-keystore-jks"
```

#### Certificate File Handling in Kubernetes

When the CSI Secrets Store driver mounts these secrets:

1. **Binary files are base64-decoded automatically** by the CSI driver
2. **Files are mounted at specified paths** in the pod (e.g., `/mnt/certs/admin-ui/keystore.jks`)
3. **MFT configuration references these mounted paths** in `mft-config.json`

**Example mft-config.json reference:**

```json
{
  "declareMftCertificateList": [
    {
      "certificateId": "adminUiCert",
      "path": "/mnt/certs/admin-ui/keystore.jks",
      "keyPassword": "<from-key-vault>",
      "keyStorePassword": "<from-key-vault>"
    }
  ]
}
```

#### Troubleshooting Certificate Issues

**Problem: Certificate file not found in pod**

```bash
# Check if secret exists in Key Vault
az keyvault secret show --vault-name "$KV_NAME" --name "${ENV}-mft-admin-ui-keystore-jks"

# Check SecretProviderClass configuration
kubectl describe secretproviderclass -n mft

# Check pod events for mount errors
kubectl describe pod -n mft -l app.kubernetes.io/name=active-transfer
```

**Problem: Certificate file is corrupted or invalid**

```bash
# Verify base64 encoding is correct
az keyvault secret show --vault-name "$KV_NAME" \
  --name "${ENV}-mft-admin-ui-keystore-jks" \
  --query "value" -o tsv | base64 -d > /tmp/test.jks

# Test the JKS file
keytool -list -keystore /tmp/test.jks -storepass <password>
```

**Problem: Permission denied accessing certificates**

```bash
# Verify managed identity has correct role
az role assignment list \
  --assignee $(terraform output -raw mft_managed_identity_client_id) \
  --scope $(terraform output -raw key_vault_id)

# Should show "Key Vault Secrets User" and "Key Vault Certificate User" roles
```



```
${environment}-${component}-${secret-name}
```

Examples:
- `dev-dbc-postgres-password`
- `prod-mft-secret-admin-password`
- `test-mft-cert-admin-ui-keystore-pkcs12`

This allows multiple environments to share the same Key Vault while maintaining clear separation.

### Using Secrets in Kubernetes

Kubernetes workloads access Key Vault secrets via the CSI Secrets Store driver:

1. **ServiceAccount** with workload identity annotation
2. **SecretProviderClass** defining which secrets to mount
3. **Pod/Job** mounting the CSI volume

Example SecretProviderClass:

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: dbc-azure-kv-secrets
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "false"
    clientID: "<mft_managed_identity_client_id>"
    keyvaultName: "<key_vault_name>"
    tenantId: "<tenant_id>"
    objects: |
      array:
        - |
          objectName: dev-dbc-postgres-password
          objectType: secret
          objectAlias: POSTGRES_PASSWORD
```

See the Database Configurator deployment (`03-TechnologyServices/01-DatabaseConfigurator`) for a complete working example.

### Key Vault Outputs

Retrieve Key Vault information:

```sh
terraform output key_vault_name
terraform output key_vault_uri
terraform output mft_managed_identity_client_id
terraform output tenant_id
terraform output environment_name
```

### Updating Secrets

**Via Azure CLI:**

```sh
KV_NAME=$(terraform output -raw key_vault_name)
ENV=$(terraform output -raw environment_name)

az keyvault secret set \
  --vault-name "$KV_NAME" \
  --name "${ENV}-dbc-postgres-password" \
  --value "NewSecurePassword123!"
```

**Via Terraform:**

Update the variable values in your `.tfvars` file and run `terraform apply`.

### Security Best Practices

1. **Never commit secrets to Git**: Use `.tfvars` files that are in `.gitignore`
2. **Use strong passwords**: Minimum 12 characters with complexity
3. **Rotate secrets regularly**: Set up Azure Key Vault secret rotation policies
4. **Monitor access**: Enable Azure Monitor logging for Key Vault
5. **Use private endpoints**: Set `key_vault_public_access_enabled = false` for production
6. **Limit RBAC permissions**: Grant only necessary roles to identities

### Troubleshooting

**Secret not found in Key Vault:**

```sh
# List all secrets
az keyvault secret list --vault-name "$KV_NAME" --query "[].name" -o tsv

# Check specific secret
az keyvault secret show --vault-name "$KV_NAME" --name "${ENV}-dbc-postgres-password"
```

**Workload cannot access secrets:**

1. Verify managed identity has correct roles:
   ```sh
   az role assignment list --assignee <mft_managed_identity_principal_id> --all
   ```

2. Check federated credential configuration:
   ```sh
   az identity federated-credential list \
     --identity-name <prefix>-mft-identity \
     --resource-group <resource_group_name>
   ```

3. Verify CSI driver is installed in AKS:
   ```sh
   kubectl get pods -n kube-system | grep csi-secrets-store
   ```

**Secret expired:**

Secrets created by Terraform have a 90-day expiration. Update them before expiry:

```sh
# Check expiration
az keyvault secret show --vault-name "$KV_NAME" \
  --name "${ENV}-dbc-postgres-password" \
  --query "attributes.expires"

# Update secret (removes expiration)
az keyvault secret set --vault-name "$KV_NAME" \
  --name "${ENV}-dbc-postgres-password" \
  --value "NewPassword123!"
```

