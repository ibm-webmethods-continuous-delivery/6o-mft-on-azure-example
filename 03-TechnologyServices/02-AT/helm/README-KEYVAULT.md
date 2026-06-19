# Azure Key Vault Integration for MFT on AKS

## Overview

This Helm chart supports two secret management modes:
1. **Kubernetes Secrets** (default, existing behavior)
2. **Azure Key Vault** (new, enhanced security)

## Prerequisites

### For Key Vault Mode

1. Azure Key Vault provisioned via Terraform (Phase 1)
2. AKS cluster with:
   - OIDC issuer enabled
   - Workload identity enabled
   - Secrets Store CSI driver enabled
3. Managed identity with Key Vault access
4. Secrets populated in Key Vault

## Quick Start

### 1. Deploy with Kubernetes Secrets (Default)

```bash
helm install active-transfer . \
  --set secretProvider.type=kubernetes
```

### 2. Deploy with Azure Key Vault

```bash
# Get Terraform outputs
cd ../../01-AzurePrerequisites/02-ServiceFulfillment
terraform output -json > ../../03-TechnologyServices/02-AT/terraform-outputs.json

# Extract values
KEY_VAULT_NAME=$(jq -r '.key_vault_name.value' terraform-outputs.json)
TENANT_ID=$(jq -r '.tenant_id.value' terraform-outputs.json)
CLIENT_ID=$(jq -r '.mft_managed_identity_client_id.value' terraform-outputs.json)
ENVIRONMENT=$(jq -r '.environment_name.value' terraform-outputs.json)

# Deploy with Key Vault
helm install active-transfer . \
  --set secretProvider.type=azureKeyVault \
  --set azureKeyVault.name=$KEY_VAULT_NAME \
  --set azureKeyVault.tenantId=$TENANT_ID \
  --set azureKeyVault.clientId=$CLIENT_ID \
  --set azureKeyVault.environment=$ENVIRONMENT
```

## Secret Naming Convention

Secrets in Key Vault follow hierarchical naming:

```
<environment>-mft-<component>-<secret-name>
```

### Database Secrets
- `<env>-mft-db-postgres-online-password`
- `<env>-mft-db-postgres-archive-password`
- `<env>-mft-db-postgres-online-user`
- `<env>-mft-db-postgres-archive-user`

### Certificate Passwords (Format-Specific)
- `<env>-mft-admin-ui-jks-keystore-password`
- `<env>-mft-admin-ui-jks-truststore-password`
- `<env>-mft-admin-ui-pkcs12-keystore-password`
- `<env>-mft-admin-ui-pkcs12-truststore-password`
- `<env>-mft-web-client-jks-keystore-password`
- `<env>-mft-web-client-jks-truststore-password`
- `<env>-mft-web-client-pkcs12-keystore-password`
- `<env>-mft-web-client-pkcs12-truststore-password`

### Global Truststore Passwords
- `<env>-mft-cert-jks-truststore-password`
- `<env>-mft-cert-pkcs12-truststore-password`

### Other Secrets
- `<env>-mft-admin-password`
- `<env>-mft-sftp-ssh-private-key`
- `<env>-mft-metering-config-xml-file`

**Note:** The `<env>-mft-config-json` secret has been removed. MFT runtime configuration is now managed as a ConfigMap in the gitops folder (`helm/gitops/config/<env>/mft-config.json`).

Examples:
- `vanilla-mft-admin-password`
- `vanilla-mft-db-postgres-online-password`
- `vanilla-mft-admin-ui-jks-keystore-password`
- `vanilla-mft-metering-config-xml-file`

## Metering Configuration

When `metering.enabled=true`, the chart mounts the Key Vault secret
`<env>-mft-metering-config-xml-file` into the Active Transfer container at:

`{{ .Values.activeTransfer.installDir }}/common/metering/conf/meteringConfiguration.xml`

You can override the target path with `metering.mountPath`, but the default behavior
matches the documented Active Transfer metering location.

The Terraform stack initializes this secret with a placeholder XML value that must be
replaced with a valid file downloaded from https://ibm.biz/metering before production use.

## Certificate Storage Options

The chart supports 4 certificate storage approaches:

### Option 1: Truststore as Certificate
- Stored as Key Vault certificate
- No encryption at rest in pod
- Direct mount from CSI driver

### Option 2: PKCS12 as Certificate
- Stored as Key Vault certificate
- Used for HTTPS ports
- No encryption at rest in pod

### Option 3: PKCS12 as Secret Value
- Stored as Key Vault secret
- Encrypted at rest in pod
- Password from environment variable

### Option 4: JKS as Secret Value
- Stored as Key Vault secret
- Encrypted at rest in pod
- Password from environment variable

Enable/disable options in values.yaml:
```yaml
azureKeyVault:
  certificateOptions:
    truststoreAsCertificate: true
    pkcs12AsCertificate: true
    pkcs12AsSecretValue: true
    jksAsSecretValue: true
```

## Secret Rotation

### Automatic Rotation
- CSI driver checks Key Vault every 2 minutes
- Secrets automatically updated in pod
- **Note**: Application restart may be required

### Manual Secret Update

```bash
# Update secret in Key Vault
az keyvault secret set \
  --vault-name <key-vault-name> \
  --name dev/mft/admin/password \
  --value <new-password> \
  --expires $(date -u -d "+90 days" +"%Y-%m-%dT%H:%M:%SZ")

# Wait for CSI driver to sync (up to 2 minutes)

# Restart pod to pick up new secret
kubectl rollout restart deployment active-transfer
```

### Rotation Notification (Placeholder)
Future implementation will:
- Monitor rotation events
- Call notification API: `https://placeholder.example.com/api/secret-rotated`
- Optionally restart pods automatically

## Configuration

### values.yaml Configuration

```yaml
# Secret provider type
secretProvider:
  type: "azureKeyVault"  # or "kubernetes"

# Azure Key Vault settings
azureKeyVault:
  name: "my-keyvault"
  tenantId: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  clientId: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  environment: "dev"
  
  # Certificate options
  certificateOptions:
    truststoreAsCertificate: true
    pkcs12AsCertificate: true
    pkcs12AsSecretValue: true
    jksAsSecretValue: true
  
  # Sync to Kubernetes secrets
  syncToK8sSecrets: true
  
  # Rotation settings
  rotation:
    enabled: true
    interval: "2m"
    notificationApiUrl: "https://placeholder.example.com/api/secret-rotated"
    restartPodOnRotation: true
```

## Troubleshooting

### Pod fails to start with Key Vault errors

**Check workload identity**:
```bash
kubectl describe serviceaccount mft-service-account
# Should show: azure.workload.identity/client-id annotation

kubectl describe pod <pod-name>
# Should show: azure.workload.identity/use: "true" label
```

**Check CSI driver**:
```bash
kubectl get pods -n kube-system -l app=secrets-store-csi-driver
kubectl logs -n kube-system -l app=secrets-store-csi-driver
```

**Check SecretProviderClass**:
```bash
kubectl get secretproviderclass
kubectl describe secretproviderclass active-transfer-azure-kv
```

### Secrets not syncing to Kubernetes

**Check CSI driver logs**:
```bash
kubectl logs -n kube-system -l app=secrets-store-csi-driver --tail=100
```

**Verify secret mount**:
```bash
kubectl exec <pod-name> -- ls -la /mnt/secrets-store
```

**Check synced secrets**:
```bash
kubectl get secrets
kubectl describe secret mft-admin-credentials
```

### Permission errors accessing Key Vault

**Verify RBAC assignments**:
```bash
az role assignment list \
  --scope /subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<kv-name> \
  --assignee <managed-identity-principal-id>
```

**Check Key Vault access policies** (if using access policies instead of RBAC):
```bash
az keyvault show --name <key-vault-name> --query properties.accessPolicies
```

### Secrets not updating after rotation

**Symptoms**:
- Secret updated in Key Vault
- Pod still using old value

**Solutions**:
1. Check CSI driver rotation interval (default: 2m)
2. Wait for next sync cycle
3. Manually restart pod:
   ```bash
   kubectl rollout restart deployment active-transfer
   ```
4. Check CSI driver logs for errors:
   ```bash
   kubectl logs -n kube-system -l app=secrets-store-csi-driver --tail=50
   ```

### Private Key Vault DNS resolution issues

**Symptoms**:
- Pod cannot connect to Key Vault
- DNS resolution fails

**Solutions**:
1. Verify private endpoint exists:
   ```bash
   az network private-endpoint list --resource-group <rg>
   ```
2. Check private DNS zone:
   ```bash
   az network private-dns zone show \
     --resource-group <rg> \
     --name privatelink.vaultcore.azure.net
   ```
3. Test DNS from pod:
   ```bash
   kubectl run -it --rm dns-test --image=busybox --restart=Never -- \
     nslookup <keyvault-name>.vault.azure.net
   ```
   Should resolve to private IP (10.x.x.x)

## Switching Between Modes

### From Kubernetes Secrets to Key Vault

1. Ensure Key Vault is provisioned and populated
2. Update Helm release:
   ```bash
   helm upgrade active-transfer . \
     --set secretProvider.type=azureKeyVault \
     --set azureKeyVault.name=<kv-name> \
     --set azureKeyVault.tenantId=<tenant-id> \
     --set azureKeyVault.clientId=<client-id>
   ```

### From Key Vault to Kubernetes Secrets (Rollback)

1. Update Helm release:
   ```bash
   helm upgrade active-transfer . \
     --set secretProvider.type=kubernetes
   ```
2. Ensure Kubernetes secrets exist (should be maintained as backup)

## Security Best Practices

1. **Always use private Key Vault** in production
2. **Rotate secrets regularly** (90-day expiration enforced)
3. **Monitor Key Vault access logs** (enable diagnostic settings)
4. **Use managed identities** (avoid service principals when possible)
5. **Keep Kubernetes secrets as backup** during transition period
6. **Enable soft delete and purge protection** on Key Vault
7. **Use RBAC** instead of access policies for better control
8. **Audit secret access** regularly

## Migration from Service Principals to Managed Identities

If Terraform initially used service principals due to apply segmentation:

1. Create managed identity manually or via separate Terraform run
2. Configure federated credential
3. Grant Key Vault permissions
4. Update Helm values with new client ID
5. Remove service principal

See Terraform documentation for detailed steps.

## Advanced Configuration

### Custom Secret Rotation Interval

```yaml
azureKeyVault:
  rotation:
    enabled: true
    interval: "5m"  # Check every 5 minutes instead of 2
```

### Disable Secret Sync to Kubernetes

If you only want to mount secrets as files (not environment variables):

```yaml
azureKeyVault:
  syncToK8sSecrets: false
```

**Note**: This requires modifying the deployment to read secrets from `/mnt/secrets-store` instead of environment variables.

### Selective Certificate Options

Enable only the certificate storage methods you need:

```yaml
azureKeyVault:
  certificateOptions:
    truststoreAsCertificate: false
    pkcs12AsCertificate: true
    pkcs12AsSecretValue: false
    jksAsSecretValue: false
```

## Monitoring and Observability

### Key Vault Metrics

Monitor Key Vault usage:
```bash
az monitor metrics list \
  --resource /subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<kv-name> \
  --metric ServiceApiHit \
  --start-time 2026-06-15T00:00:00Z \
  --end-time 2026-06-15T23:59:59Z
```

### CSI Driver Metrics

Check CSI driver performance:
```bash
kubectl top pods -n kube-system -l app=secrets-store-csi-driver
```

### Secret Access Audit

Enable diagnostic settings on Key Vault to log all secret access:
```bash
az monitor diagnostic-settings create \
  --name keyvault-audit \
  --resource /subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<kv-name> \
  --logs '[{"category":"AuditEvent","enabled":true}]' \
  --workspace /subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.OperationalInsights/workspaces/<workspace-name>
```

## Future Enhancements

- [ ] Automatic pod restart on secret rotation
- [ ] Rotation notification API implementation
- [ ] Secret expiration monitoring
- [ ] Guardian application for automatic renewal
- [ ] Split config JSON (secrets extracted to Key Vault references)

## Support

For issues or questions:
1. Check this documentation
2. Review Terraform outputs
3. Check CSI driver logs
4. Verify RBAC assignments
5. Contact platform team

## References

- [Azure Key Vault Documentation](https://docs.microsoft.com/azure/key-vault/)
- [Secrets Store CSI Driver](https://secrets-store-csi-driver.sigs.k8s.io/)
- [Azure Workload Identity](https://azure.github.io/azure-workload-identity/)
- [AKS Best Practices](https://docs.microsoft.com/azure/aks/best-practices)
