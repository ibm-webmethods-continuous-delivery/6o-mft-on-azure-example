# Gateway Deployment Pipeline Setup

## Overview

The `deploy-gateways-pipeline.yml` provides automated deployment of ActiveTransfer Gateway services to Azure VMs using Azure DevOps Pipelines.

**Important Notes:**
- This pipeline uses SSH connections which require either public IPs, Azure Bastion, or VPN/ExpressRoute connectivity
- For environments without these, consider using Azure VM Run Command instead (see Alternative Approach section)
- Gateway IPs are configured in the **secret template** (`03-TechnologyServices/02-AT/helm/templates/secret-mft-config.yaml.template`), not in values.yaml

## Prerequisites

### 1. Network Connectivity

Choose one of the following options:

**Option A: Public IPs (Not Recommended for Production)**
- Assign public IPs to gateway VMs
- Configure NSG to allow SSH from Azure DevOps agent IPs

**Option B: Azure Bastion (Recommended for Production)**
- Deploy Azure Bastion in the VNet
- Configure Azure DevOps agents to use Bastion for SSH

**Option C: VPN/ExpressRoute**
- Establish VPN or ExpressRoute connection
- Configure Azure DevOps self-hosted agents in connected network

### 2. Azure DevOps Service Connections

Create SSH service connections for both gateway VMs:

#### Gateway VM 1 Connection
- **Name**: `gateway-vm-1-ssh`
- **Type**: SSH
- **Host**: Public IP, Bastion FQDN, or private IP (depending on connectivity option)
- **Port**: 22
- **Username**: `azureuser`
- **Authentication**: SSH private key (corresponding to the public key used in Terraform)

#### Gateway VM 2 Connection
- **Name**: `gateway-vm-2-ssh`
- **Type**: SSH
- **Host**: Public IP, Bastion FQDN, or private IP (depending on connectivity option)
- **Port**: 22
- **Username**: `azureuser`
- **Authentication**: SSH private key (corresponding to the public key used in Terraform)

#### AKS Cluster Connection (for connectivity tests)
- **Name**: `aks-cluster-connection`
- **Type**: Kubernetes
- **Authentication**: Service Account or Azure Subscription

### 3. Variable Group

Create a variable group named `mft-azure-variables` with:

| Variable Name | Description | Example Value | Secret |
|--------------|-------------|---------------|--------|
| `ACR_LOGIN_SERVER` | ACR login server URL | `myacr.azurecr.io` | No |
| `GATEWAY_VM1_PUBLIC_IP` | Public IP of Gateway VM 1 (for reference) | `20.x.x.x` | No |
| `GATEWAY_VM2_PUBLIC_IP` | Public IP of Gateway VM 2 (for reference) | `20.x.x.x` | No |

**Note:** These IPs are for reference only. The actual gateway IPs used by ActiveTransfer (10.1.0.4, 10.1.1.4) are configured in the secret template.

### 4. Repository Setup

Ensure the pipeline has access to:
- `03-TechnologyServices/03-ATGateway/gateway1/` directory
- `03-TechnologyServices/03-ATGateway/gateway2/` directory

## Pipeline Stages

### Stage 1: Deploy Gateway 1
1. Copies deployment files to Gateway VM 1
2. Runs deployment script
3. Starts the systemd service
4. Verifies container health

### Stage 2: Deploy Gateway 2
1. Copies deployment files to Gateway VM 2
2. Runs deployment script
3. Starts the systemd service
4. Verifies container health

### Stage 3: Verify Connectivity
1. Tests connectivity from AKS to Gateway 1 (port 8500)
2. Tests connectivity from AKS to Gateway 2 (port 8500)

## Usage

### Automatic Trigger
The pipeline automatically triggers on:
- Commits to `main` branch
- Changes in `03-TechnologyServices/03-ATGateway/**` path

### Manual Trigger
1. Navigate to Pipelines in Azure DevOps
2. Select the gateway deployment pipeline
3. Click "Run pipeline"
4. Select branch and click "Run"

## Alternative Approach: Azure VM Run Command

For environments without SSH connectivity (no public IPs, Bastion, or VPN), consider using Azure VM Run Command instead:

### Benefits
- No SSH access required
- No public IPs needed
- Works with VMs in private networks
- Uses Azure RBAC for access control
- Simpler setup

### Implementation

Create a pipeline using Azure CLI tasks instead of SSH tasks:

```yaml
- task: AzureCLI@2
  displayName: 'Deploy Gateway 1'
  inputs:
    azureSubscription: 'azure-service-connection'
    scriptType: 'bash'
    scriptLocation: 'inlineScript'
    inlineScript: |
      az vm run-command invoke \
        --resource-group $(RESOURCE_GROUP) \
        --name $(GATEWAY1_VM_NAME) \
        --command-id RunShellScript \
        --scripts @$(Build.SourcesDirectory)/03-TechnologyServices/03-ATGateway/deploy-gateway1-vm-run-command.sh
```

See `03-TechnologyServices/03-ATGateway/README.md` for detailed VM Run Command usage.

## Troubleshooting

### SSH Connection Failures
- Verify SSH service connection credentials
- Check VM NSG rules allow SSH from Azure DevOps agent IPs
- Verify VM is running and accessible
- For Bastion: Ensure proper Bastion configuration
- For VPN: Verify self-hosted agent connectivity

### Deployment Script Failures
- Check VM has Docker and docker-compose installed
- Verify ACR authentication is configured (managed identity or acr-login.service)
- Check VM has sufficient disk space
- Review deployment logs in Azure DevOps

### Container Health Check Failures
- Review container logs: `sudo docker logs at-gateway1 -f`
- Verify ACR image is accessible
- Check configuration file syntax
- Verify logs directory permissions (must be owned by UID 1724)

### Connectivity Test Failures
- Verify NSG rules allow traffic from AKS subnet (10.1.10.0/24) to ports 8500-8501
- Check gateway containers are running and healthy
- Verify AKS cluster has network connectivity to VM private IPs (10.1.0.4, 10.1.1.4)
- Test manually from AKS pod: `kubectl run test --image=busybox --rm -it -n mft -- nc -zv 10.1.0.4 8500`

## Security Considerations

1. **SSH Keys**: Store private keys securely in Azure DevOps Library
2. **ACR Access**: Use managed identity for VM-to-ACR authentication
3. **Network Security**: Ensure NSG rules are properly configured
4. **Secrets**: Never commit secrets to the repository
5. **Least Privilege**: Use service principals with minimal required permissions
6. **Audit**: Enable Azure Activity Log for pipeline operations

## Next Steps After Pipeline Success

1. **Verify Gateway Deployment**:
   ```bash
   # Check service status on VMs
   sudo systemctl status at-gateway.service
   sudo docker ps | grep at-gateway
   ```

2. **Test Connectivity from AKS**:
   ```bash
   kubectl run test-gw1 --image=busybox --rm -it --restart=Never -n mft -- nc -zv 10.1.0.4 8500
   kubectl run test-gw2 --image=busybox --rm -it --restart=Never -n mft -- nc -zv 10.1.1.4 8500
   ```

3. **Update ActiveTransfer Configuration**:
   - Gateway IPs are already configured in `templates/secret-mft-config.yaml.template`
   - The template uses placeholders that are replaced during secret generation
   - Actual IPs: Gateway1=10.1.0.4, Gateway2=10.1.1.4

4. **Upgrade Helm Release**:
   ```bash
   cd 03-TechnologyServices/02-AT/helm
   helm upgrade active-transfer . --namespace mft --values ibm_values.yaml --wait --timeout 10m
   ```

5. **Verify Gateway Registration**:
   - Access ActiveTransfer Admin UI
   - Navigate to: Settings > Gateways
   - Verify both gateways show as Connected with Green health status

6. **Test End-to-End**:
   - Create a test file transfer
   - Verify transfer goes through gateways
   - Check gateway logs for activity

## Related Documentation

- [Gateway Deployment Guide](../../03-TechnologyServices/03-ATGateway/README.md)
- [VM Run Command Deployment](../../03-TechnologyServices/03-ATGateway/README.md#method-1-azure-vm-run-command-recommended)
- [Helm Upgrade Procedure](../../03-TechnologyServices/02-AT/HELM-UPGRADE.md)
- [Session Documentation](../../.ai-assist/sessions/2026/05/22/03_add_gateways/)