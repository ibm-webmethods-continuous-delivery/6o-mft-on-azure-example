# Deploying Gateways with Azure VM Run Command

## Overview

This guide explains how to deploy ActiveTransfer Gateways using **Azure VM Run Command**, which allows you to execute scripts on Azure VMs without requiring SSH access or public IP addresses. This is the recommended method for development and testing environments.

## Why Azure VM Run Command?

**Advantages:**
- ✅ No SSH access required
- ✅ No public IP addresses needed
- ✅ Works with VMs in private networks
- ✅ Uses Azure RBAC for access control
- ✅ Audit trail in Azure Activity Log
- ✅ Simple and straightforward

**Best For:**
- Development environments
- Testing and validation
- Quick deployments
- Environments without bastion hosts

## Prerequisites

### 1. Azure CLI

Install and authenticate with Azure CLI:

```bash
# Install Azure CLI (if not already installed)
# See: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli

# Login to Azure
az login

# Set your subscription (if you have multiple)
az account set --subscription "<subscription-id-or-name>"

# Verify you're in the correct subscription
az account show
```

### 2. Required Permissions

You need the following Azure RBAC permissions:
- `Microsoft.Compute/virtualMachines/runCommand/action` on the target VMs
- Or the built-in role: **Virtual Machine Contributor**

### 3. Environment Information

Gather the following information from your Terraform outputs:

```bash
# Navigate to Terraform directory
cd /aio/work/c/iwcd/6o-mft-on-azure-example/01-AzurePrerequisites/02-ServiceFulfillment

# Get outputs
terraform output

# You need:
# - resource_group_name
# - sftp_vm_names (both gateway VMs)
# - acr_login_server
```

Example output:
```
resource_group_name = "rg-mft-dev"
sftp_vm_names = [
  "vm-mft-gateway1",
  "vm-mft-gateway2"
]
acr_login_server = "acrmftdev.azurecr.io"
```

## Deployment Steps

### Step 1: Set Environment Variables

```bash
# Set your Azure resource information
export RESOURCE_GROUP="rg-mft-dev"
export GATEWAY1_VM_NAME="vm-mft-gateway1"
export GATEWAY2_VM_NAME="vm-mft-gateway2"
export ACR_LOGIN_SERVER="acrmftdev.azurecr.io"

# Verify variables are set
echo "Resource Group: ${RESOURCE_GROUP}"
echo "Gateway 1 VM: ${GATEWAY1_VM_NAME}"
echo "Gateway 2 VM: ${GATEWAY2_VM_NAME}"
echo "ACR: ${ACR_LOGIN_SERVER}"
```

### Step 2: Deploy Gateway 1

```bash
# Navigate to gateway deployment directory
cd /aio/work/c/iwcd/6o-mft-on-azure-example/03-TechnologyServices/03-ATGateway

# Make script executable
chmod +x deploy-gateway1-vm-run-command.sh

# Run deployment
./deploy-gateway1-vm-run-command.sh
```

**Expected Output:**
```
==========================================
Deploying ActiveTransfer Gateway 1
==========================================
Resource Group: rg-mft-dev
VM Name: vm-mft-gateway1
ACR: acrmftdev.azurecr.io

==> Running deployment script on VM...

Command "RunShellScript" succeeded.
Value[0]:
  Message : Enable succeeded:
[stdout]
==> Creating deployment directory...
==> Creating docker-compose.yml...
==> Creating gateway configuration...
==> Creating .env file...
==> Setting permissions...
==> Creating systemd service...
==> Reloading systemd...
==> Enabling service...
==> Starting service...
==> Waiting for service to start...
==> Checking service status...
● at-gateway.service - ActiveTransfer Gateway Service
     Loaded: loaded (/etc/systemd/system/at-gateway.service; enabled)
     Active: active (exited) since ...
==> Checking container status...
at-gateway1   Up 5 seconds   0.0.0.0:8500->8500/tcp, 0.0.0.0:8501->8501/tcp
==> Checking container logs (last 20 lines)...
[INFO] Starting ActiveTransfer Gateway...
[INFO] Gateway mode enabled
[INFO] Listening on port 8500
==========================================
Gateway 1 deployment completed!
==========================================
```

### Step 3: Verify Gateway 1

```bash
# Check service status
az vm run-command invoke \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${GATEWAY1_VM_NAME}" \
    --command-id RunShellScript \
    --scripts "systemctl status at-gateway.service" \
    --output table

# Check container logs
az vm run-command invoke \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${GATEWAY1_VM_NAME}" \
    --command-id RunShellScript \
    --scripts "docker logs at-gateway1 --tail 50" \
    --output table
```

### Step 4: Deploy Gateway 2

```bash
# Make script executable
chmod +x deploy-gateway2-vm-run-command.sh

# Run deployment
./deploy-gateway2-vm-run-command.sh
```

### Step 5: Verify Gateway 2

```bash
# Check service status
az vm run-command invoke \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${GATEWAY2_VM_NAME}" \
    --command-id RunShellScript \
    --scripts "systemctl status at-gateway.service" \
    --output table

# Check container logs
az vm run-command invoke \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${GATEWAY2_VM_NAME}" \
    --command-id RunShellScript \
    --scripts "docker logs at-gateway2 --tail 50" \
    --output table
```

### Step 6: Test Connectivity from AKS

```bash
# Test Gateway 1
kubectl run test-gateway1 --image=busybox --rm -it --restart=Never -n mft -- \
    sh -c "nc -zv 10.1.0.4 8500 && echo 'Gateway 1 is reachable'"

# Test Gateway 2
kubectl run test-gateway2 --image=busybox --rm -it --restart=Never -n mft -- \
    sh -c "nc -zv 10.1.1.4 8500 && echo 'Gateway 2 is reachable'"
```

**Expected Output:**
```
10.1.0.4 (10.1.0.4:8500) open
Gateway 1 is reachable
pod "test-gateway1" deleted

10.1.1.4 (10.1.1.4:8500) open
Gateway 2 is reachable
pod "test-gateway2" deleted
```

### Step 7: Update ActiveTransfer Helm Chart

Once both gateways are deployed and verified:

```bash
cd ../02-AT/helm

# Upgrade ActiveTransfer with gateway configuration
helm upgrade active-transfer . \
    --namespace mft \
    --values ibm_values.yaml \
    --wait \
    --timeout 10m
```

See [HELM-UPGRADE.md](../02-AT/HELM-UPGRADE.md) for detailed upgrade instructions.

## Common Operations

### View Gateway Logs

```bash
# Gateway 1 logs
az vm run-command invoke \
    -g "${RESOURCE_GROUP}" \
    -n "${GATEWAY1_VM_NAME}" \
    --command-id RunShellScript \
    --scripts "docker logs at-gateway1 --tail 100 -f" \
    --output table

# Gateway 2 logs
az vm run-command invoke \
    -g "${RESOURCE_GROUP}" \
    -n "${GATEWAY2_VM_NAME}" \
    --command-id RunShellScript \
    --scripts "docker logs at-gateway2 --tail 100 -f" \
    --output table
```

### Restart Gateway Service

```bash
# Restart Gateway 1
az vm run-command invoke \
    -g "${RESOURCE_GROUP}" \
    -n "${GATEWAY1_VM_NAME}" \
    --command-id RunShellScript \
    --scripts "systemctl restart at-gateway.service" \
    --output table

# Restart Gateway 2
az vm run-command invoke \
    -g "${RESOURCE_GROUP}" \
    -n "${GATEWAY2_VM_NAME}" \
    --command-id RunShellScript \
    --scripts "systemctl restart at-gateway.service" \
    --output table
```

### Check Container Status

```bash
# Gateway 1 status
az vm run-command invoke \
    -g "${RESOURCE_GROUP}" \
    -n "${GATEWAY1_VM_NAME}" \
    --command-id RunShellScript \
    --scripts "docker ps | grep at-gateway" \
    --output table

# Gateway 2 status
az vm run-command invoke \
    -g "${RESOURCE_GROUP}" \
    -n "${GATEWAY2_VM_NAME}" \
    --command-id RunShellScript \
    --scripts "docker ps | grep at-gateway" \
    --output table
```

### Update Gateway Configuration

```bash
# Example: Update Gateway 1 configuration
az vm run-command invoke \
    -g "${RESOURCE_GROUP}" \
    -n "${GATEWAY1_VM_NAME}" \
    --command-id RunShellScript \
    --scripts "
        # Edit configuration
        sed -i 's/mft.server.log.level=INFO/mft.server.log.level=DEBUG/' /opt/at-gateway/config/properties.cnf
        
        # Restart service to apply changes
        systemctl restart at-gateway.service
    " \
    --output table
```

### Pull Latest Container Image

```bash
# Update Gateway 1 image
az vm run-command invoke \
    -g "${RESOURCE_GROUP}" \
    -n "${GATEWAY1_VM_NAME}" \
    --command-id RunShellScript \
    --scripts "
        cd /opt/at-gateway
        docker compose pull
        systemctl restart at-gateway.service
    " \
    --output table

# Update Gateway 2 image
az vm run-command invoke \
    -g "${RESOURCE_GROUP}" \
    -n "${GATEWAY2_VM_NAME}" \
    --command-id RunShellScript \
    --scripts "
        cd /opt/at-gateway
        docker compose pull
        systemctl restart at-gateway.service
    " \
    --output table
```

## Troubleshooting

### Issue: VM Run Command Times Out

**Symptoms:**
```
ERROR: The command timed out
```

**Solutions:**
1. Check VM is running:
   ```bash
   az vm get-instance-view -g "${RESOURCE_GROUP}" -n "${GATEWAY1_VM_NAME}" --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" -o tsv
   ```

2. Increase timeout (default is 90 seconds):
   ```bash
   az vm run-command invoke \
       -g "${RESOURCE_GROUP}" \
       -n "${GATEWAY1_VM_NAME}" \
       --command-id RunShellScript \
       --scripts "your-script" \
       --timeout 300  # 5 minutes
   ```

### Issue: Permission Denied

**Symptoms:**
```
ERROR: (AuthorizationFailed) The client does not have authorization to perform action
```

**Solution:**
Verify you have the required permissions:
```bash
# Check your role assignments
az role assignment list --assignee $(az account show --query user.name -o tsv) --all
```

Request **Virtual Machine Contributor** role if needed.

### Issue: ACR Authentication Fails

**Symptoms:**
```
Error response from daemon: pull access denied
```

**Solutions:**

1. Verify ACR role assignment is enabled in Terraform:
   ```bash
   cd /aio/work/c/iwcd/6o-mft-on-azure-example/01-AzurePrerequisites/02-ServiceFulfillment
   terraform output enable_sftp_vm_acr_role
   ```

2. If false, enable it:
   ```bash
   # Edit terraform.tfvars
   echo 'enable_sftp_vm_acr_role = true' >> terraform.tfvars
   
   # Apply changes
   terraform apply
   ```

3. Manually trigger ACR login on VM:
   ```bash
   az vm run-command invoke \
       -g "${RESOURCE_GROUP}" \
       -n "${GATEWAY1_VM_NAME}" \
       --command-id RunShellScript \
       --scripts "systemctl restart acr-login.service" \
       --output table
   ```

### Issue: Container Won't Start

**Symptoms:**
```
Container at-gateway1 exited with code 1
```

**Diagnosis:**
```bash
# Check container logs
az vm run-command invoke \
    -g "${RESOURCE_GROUP}" \
    -n "${GATEWAY1_VM_NAME}" \
    --command-id RunShellScript \
    --scripts "docker logs at-gateway1" \
    --output table

# Check configuration file
az vm run-command invoke \
    -g "${RESOURCE_GROUP}" \
    -n "${GATEWAY1_VM_NAME}" \
    --command-id RunShellScript \
    --scripts "cat /opt/at-gateway/config/properties.cnf" \
    --output table
```

### Issue: Network Connectivity Problems

**Symptoms:**
```
nc: connect to 10.1.0.4 port 8500 (tcp) failed: Connection refused
```

**Solutions:**

1. Verify NSG rules allow traffic from AKS:
   ```bash
   cd /aio/work/c/iwcd/6o-mft-on-azure-example/01-AzurePrerequisites/02-ServiceFulfillment
   
   # Check NSG rules
   terraform show | grep -A 20 "azurerm_network_security_rule"
   ```

2. Verify gateway is listening:
   ```bash
   az vm run-command invoke \
       -g "${RESOURCE_GROUP}" \
       -n "${GATEWAY1_VM_NAME}" \
       --command-id RunShellScript \
       --scripts "netstat -tlnp | grep 8500" \
       --output table
   ```

## Comparison with Other Methods

| Method | Pros | Cons | Best For |
|--------|------|------|----------|
| **VM Run Command** | No SSH needed, No public IP, Simple | Limited to Azure CLI, Slower for large scripts | Development, Testing |
| **Azure Bastion** | Secure, Full SSH access | Requires additional infrastructure, Cost | Production, Interactive work |
| **Azure Pipeline** | Automated, Repeatable, Auditable | Requires setup, More complex | Production, CI/CD |

## Security Considerations

1. **Access Control**: VM Run Command uses Azure RBAC - ensure only authorized users have permissions
2. **Audit Trail**: All commands are logged in Azure Activity Log
3. **No Credentials**: No need to manage SSH keys or passwords
4. **Network Security**: VMs remain in private network without public IPs
5. **Managed Identity**: ACR authentication uses VM managed identity

## Next Steps

After successful deployment:

1. ✅ Verify both gateways are running
2. ✅ Test connectivity from AKS
3. ✅ Update ActiveTransfer helm chart
4. ✅ Verify gateway registration in AT Admin UI
5. ✅ Test file transfer through gateways
6. ✅ Set up monitoring and alerting
7. ✅ Document any environment-specific configurations

## Related Documentation

- [Main README](./README.md) - Overview and all deployment methods
- [Troubleshooting Guide](./TROUBLESHOOTING.md) - Detailed troubleshooting
- [Azure Pipeline Setup](../../02-ContainerImages/PIPELINE-SETUP.md) - Production deployment
- [Helm Upgrade Guide](../02-AT/HELM-UPGRADE.md) - ActiveTransfer upgrade procedure

## Support

For issues or questions:
1. Check this guide and the troubleshooting documentation
2. Review Azure Activity Log for VM Run Command execution details
3. Check container and service logs on the VMs
4. Verify network connectivity and NSG rules
