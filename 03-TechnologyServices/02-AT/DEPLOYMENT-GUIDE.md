# Active Transfer Deployment Guide

Quick reference for deploying Active Transfer with Azure Key Vault integration.

## Prerequisites Checklist

- [ ] Terraform infrastructure deployed (`01-AzurePrerequisites/02-ServiceFulfillment`)
- [ ] Database users created (`00-DatabaseUserInit` deployed successfully)
- [ ] Database schemas initialized (`01-DatabaseConfigurator` deployed successfully)
- [ ] CLI tools installed: `helm`, `kubectl`, `jq`, `terraform` (or `az`)
- [ ] Access to Terraform state directory or outputs JSON file
- [ ] Kubernetes cluster access configured (`kubectl get nodes` works)

## Manual Secrets (One-Time Setup)

Before first deployment, create these secrets manually:

### 1. Admin Password in Key Vault

```bash
# Get Key Vault name from Terraform
cd /path/to/01-AzurePrerequisites/02-ServiceFulfillment
KV_NAME=$(terraform output -raw key_vault_name)
ENV=$(terraform output -raw environment_name)

# Store admin password
az keyvault secret set \
  --vault-name "$KV_NAME" \
  --name "${ENV}/mft/admin/password" \
  --value "YourSecureAdminPassword123!" \
  --expires $(date -u -d "+90 days" +"%Y-%m-%dT%H:%M:%SZ")
```

### 2. Certificate Files as Kubernetes Secrets

```bash
# Admin UI certificates
kubectl create secret generic mft-admin-ui-certs \
  --from-file=keystore.jks=/path/to/admin-keystore.jks \
  --from-file=truststore.jks=/path/to/admin-truststore.jks \
  -n default

# Web Client certificates
kubectl create secret generic mft-web-client-certs \
  --from-file=keystore.jks=/path/to/web-keystore.jks \
  --from-file=truststore.jks=/path/to/web-truststore.jks \
  -n default

# SFTP SSH keys
kubectl create secret generic mft-sftp-ssh-keys \
  --from-file=ssh_host_rsa_key=/path/to/ssh_host_rsa_key \
  --from-file=ssh_host_rsa_key.pub=/path/to/ssh_host_rsa_key.pub \
  -n default
```

### 3. Certificate Passwords in Key Vault

```bash
# Admin UI certificate passwords
az keyvault secret set \
  --vault-name "$KV_NAME" \
  --name "${ENV}/mft/admin-ui/keystore/password" \
  --value "KeystorePassword123!"

az keyvault secret set \
  --vault-name "$KV_NAME" \
  --name "${ENV}/mft/admin-ui/truststore/password" \
  --value "TruststorePassword123!"

# Web Client certificate passwords
az keyvault secret set \
  --vault-name "$KV_NAME" \
  --name "${ENV}/mft/web-client/keystore/password" \
  --value "KeystorePassword123!"

az keyvault secret set \
  --vault-name "$KV_NAME" \
  --name "${ENV}/mft/web-client/truststore/password" \
  --value "TruststorePassword123!"
```

### 4. MFT Config JSON Secret

```bash
# Create mft-config.json file first (see templates/secret-mft-config.yaml.template for structure)
kubectl create secret generic mft-config-json \
  --from-file=mft-config.json=/path/to/mft-config.json \
  -n default
```

### 5. SFTP SSH Private Key in Key Vault

```bash
# Store SSH private key (base64 encoded or as-is)
az keyvault secret set \
  --vault-name "$KV_NAME" \
  --name "${ENV}/mft/sftp/ssh/private-key" \
  --file /path/to/ssh_host_rsa_key
```

## Automated Deployment

### Option 1: Using Terraform State (Recommended)

```bash
cd /path/to/03-TechnologyServices/02-AT/scripts

# Dry run first to preview generated values
./deploy-with-keyvault.sh \
  --tfvars /path/to/your.tfvars \
  --dry-run

# Review generated values
cat ../helm/generated-values.keyvault.yaml

# Deploy for real
./deploy-with-keyvault.sh \
  --tfvars /path/to/your.tfvars
```

### Option 2: Using Pre-Generated Terraform Outputs

```bash
# Generate outputs JSON (in environment with Terraform)
cd /path/to/01-AzurePrerequisites/02-ServiceFulfillment
terraform output -json > /tmp/terraform-outputs.json

# Deploy using outputs file
cd /path/to/03-TechnologyServices/02-AT/scripts
./deploy-with-keyvault.sh \
  --tf-outputs /tmp/terraform-outputs.json
```

### Script Options

```bash
./deploy-with-keyvault.sh [OPTIONS]

Options:
  -n, --namespace NAME       Kubernetes namespace (default: default)
  -r, --release NAME         Helm release name (default: active-transfer)
      --tfvars FILE          Terraform tfvars file
      --tf-outputs FILE      Pre-generated terraform output JSON
      --dry-run              Preview without deploying
      --skip-verify          Skip post-deployment verification
  -h, --help                 Show help
```

## Verification Steps

### 1. Check Deployment Status

```bash
# Check Helm release
helm list -n default

# Check pods
kubectl get pods -n default -l app.kubernetes.io/name=active-transfer

# Check pod details
kubectl describe pod -n default -l app.kubernetes.io/name=active-transfer
```

### 2. Verify Key Vault Integration

```bash
# Check SecretProviderClass
kubectl get secretproviderclass -n default
kubectl describe secretproviderclass active-transfer-azure-kv -n default

# Check service account has workload identity
kubectl describe serviceaccount mft-service-account -n default | grep -A 3 "Annotations:"

# Check synced secrets
kubectl get secrets -n default | grep mft-
```

### 3. Verify Secret Mounts

```bash
# Get pod name
POD_NAME=$(kubectl get pod -n default -l app.kubernetes.io/name=active-transfer -o jsonpath='{.items[0].metadata.name}')

# Check mounted secrets
kubectl exec -n default "$POD_NAME" -- ls -la /mnt/secrets-store

# Check environment variables
kubectl exec -n default "$POD_NAME" -- env | grep -E "(POSTGRES|ADMIN|KEYSTORE)"
```

### 4. Check Application Logs

```bash
# Follow logs
kubectl logs -n default -l app.kubernetes.io/name=active-transfer -f

# Check for errors
kubectl logs -n default -l app.kubernetes.io/name=active-transfer | grep -i error
```

### 5. Access Admin UI

```bash
# Get ingress hostname
kubectl get ingress -n default active-transfer -o jsonpath='{.spec.rules[0].host}'

# Access in browser
# http://<hostname>:80 or https://<hostname>:443
```

## Troubleshooting

### Pods Not Starting

**Check pod events:**
```bash
kubectl describe pod -n default -l app.kubernetes.io/name=active-transfer
```

**Common issues:**
- CSI driver mount failures → Check workload identity configuration
- Image pull errors → Verify ACR credentials and image exists
- Resource limits → Check node capacity

### Key Vault Access Errors

**Error: AADSTS700213 (No matching federated identity)**

```bash
# Verify federated credential exists
IDENTITY_ID=$(terraform output -raw mft_managed_identity_id)
az identity federated-credential list \
  --identity-name $(basename $IDENTITY_ID) \
  --resource-group $(terraform output -raw resource_group_name)

# Should show: mft-service-account credential
```

**Error: Secret not found in Key Vault**

```bash
# List secrets in Key Vault
KV_NAME=$(terraform output -raw key_vault_name)
ENV=$(terraform output -raw environment_name)
az keyvault secret list --vault-name "$KV_NAME" | grep "${ENV}/mft"

# Verify secret exists with correct name
az keyvault secret show --vault-name "$KV_NAME" --name "${ENV}/mft/admin/password"
```

### Database Connection Errors

**Check database credentials:**
```bash
# Verify database secrets in Key Vault
az keyvault secret show --vault-name "$KV_NAME" --name "${ENV}-dbc-postgres-password"
az keyvault secret show --vault-name "$KV_NAME" --name "${ENV}-dbc-postgres-archive-password"
```

**Test database connectivity:**
```bash
# From pod
kubectl exec -n default "$POD_NAME" -- \
  psql -h <postgres-fqdn> -U <username> -d <database> -c "SELECT 1"
```

### JGroups Clustering Issues

**Check cluster formation:**
```bash
# Check logs for JGroups messages
kubectl logs -n default -l app.kubernetes.io/name=active-transfer | grep -i jgroups

# Look for: "Cluster view: [node1, node2]"
```

**Verify RBAC permissions:**
```bash
# Check Role and RoleBinding
kubectl get role active-transfer-jgroups -n default
kubectl get rolebinding active-transfer-jgroups -n default

# Test permissions
kubectl auth can-i list pods \
  --as=system:serviceaccount:default:mft-service-account \
  -n default
```

## Updating Deployment

### Update Configuration

```bash
# Edit vanilla-values.yaml or create custom values file
vim /path/to/custom-values.yaml

# Upgrade with custom values
helm upgrade active-transfer ./helm \
  -n default \
  -f ./helm/values.yaml \
  -f ./helm/generated-values.keyvault.yaml \
  -f /path/to/custom-values.yaml
```

### Update Secrets

```bash
# Update secret in Key Vault
az keyvault secret set \
  --vault-name "$KV_NAME" \
  --name "${ENV}/mft/admin/password" \
  --value "NewSecurePassword456!"

# Wait for CSI driver to sync (up to 2 minutes)
# Or restart pods immediately
kubectl rollout restart deployment active-transfer -n default
```

### Rollback

```bash
# List releases
helm history active-transfer -n default

# Rollback to previous version
helm rollback active-transfer -n default

# Rollback to specific revision
helm rollback active-transfer 2 -n default
```

## Cleanup

### Delete Deployment

```bash
# Delete Helm release
helm uninstall active-transfer -n default

# Delete PVC (if needed)
kubectl delete pvc active-transfer-vfs -n default

# Delete secrets (if needed)
kubectl delete secret mft-admin-ui-certs mft-web-client-certs \
  mft-sftp-ssh-keys mft-config-json -n default
```

### Clean Key Vault Secrets

```bash
# List MFT secrets
az keyvault secret list --vault-name "$KV_NAME" | grep "${ENV}/mft"

# Delete specific secret
az keyvault secret delete --vault-name "$KV_NAME" --name "${ENV}/mft/admin/password"

# Purge deleted secret (if soft-delete enabled)
az keyvault secret purge --vault-name "$KV_NAME" --name "${ENV}/mft/admin/password"
```

## Quick Reference

### Important Files

- `helm/vanilla-values.yaml` - Base configuration (defaults)
- `helm/generated-values.keyvault.yaml` - Auto-generated overrides (from Terraform)
- `scripts/deploy-with-keyvault.sh` - Automated deployment script
- `templates/secret-mft-config.yaml.template` - MFT configuration template (requires manual editing)

### Key Terraform Outputs Used

- `key_vault_name` - Azure Key Vault name
- `tenant_id` - Azure tenant ID
- `mft_managed_identity_client_id` - Workload identity client ID
- `environment_name` - Environment prefix for secrets
- `acr_login_server` - Container registry URL
- `postgres_server_fqdn` - Database server hostname
- `postgres_online_db_name` - Online database name
- `postgres_archive_db_name` - Archive database name
- `postgres_dbc_user` - Online database username
- `postgres_dbc_archive_user` - Archive database username
- `app_gateway_public_ip` - Application Gateway public IP
- `sftp_vm_1_private_ip` - Gateway 1 IP
- `sftp_vm_2_private_ip` - Gateway 2 IP

### Key Vault Secret Naming

All secrets follow: `<environment>/mft/<component>/<secret-name>`

Examples:
- `dev/mft/admin/password`
- `dev/mft/db/online/password`
- `dev/mft/admin-ui/keystore/password`

### Useful Commands

```bash
# Get pod logs
kubectl logs -n default -l app.kubernetes.io/name=active-transfer --tail=100

# Get pod shell
kubectl exec -it -n default <pod-name> -- bash

# Check secret mount
kubectl exec -n default <pod-name> -- ls -la /mnt/secrets-store

# Port forward to admin UI
kubectl port-forward -n default svc/active-transfer 5555:5555

# Check Helm values
helm get values active-transfer -n default

# Check rendered manifests
helm get manifest active-transfer -n default
```

## Support

- **Documentation**: See `README.md` and `README-KEYVAULT.md` in `helm/` directory
- **Known Limitations**: See "Known Limitations" section in `README.md`
- **Session Progress**: See `.ai-assist/sessions/2026/06/15/AT-on-Azure-example-DB-and-k8s-increment/agent/session_progress.md`
