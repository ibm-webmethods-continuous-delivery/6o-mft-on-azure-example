# Stage B - Infrastructure Team Deployment

## Overview

Stage B provisions the Azure infrastructure resources for both Service Delivery and Service Fulfillment domains. This stage is executed by the **Infrastructure Team** using the service principal created in Stage A.

**Key Characteristics:**
- Uses Terraform with Azure provider only (no Azure CLI required)
- Authenticates using service principal from Stage A
- Provisions ~55 Azure infrastructure resources
- Excludes Azure DevOps resources (deferred to Stage C)
- Integrates with Key Vault from `01-vault/`
- Configures workload identities for MFT and AGIC

## Prerequisites

### From Stage A
You must have completed Stage A and have the following outputs:
- Infrastructure service principal credentials (`infra_sp_application_id`, `infra_sp_client_secret`)
- Resource group names (`delivery_resource_group_name`, `fulfillment_resource_group_name`)
- MFT managed identity details (`mft_identity_id`, `mft_identity_principal_id`, `mft_identity_client_id`)
- AGIC managed identity details (`agic_identity_id`, `agic_identity_principal_id`, `agic_identity_client_id`)

### From 01-vault/
You must have deployed the Key Vault and have:
- Key Vault name
- Key Vault resource group name

### Required Tools
- Terraform >= 1.0
- SSH key pair for VM access

## Resources Provisioned

### Service Delivery Domain
1. **Network**: Virtual Network, Subnet, Network Security Group
2. **Compute**: Virtual Machine Scale Set (VMSS) for Azure DevOps agents
3. **Storage**: Storage Account with File Share for container images
4. **Container Registry**: Azure Container Registry (ACR)

### Service Fulfillment Domain
1. **Network**: 
   - Virtual Network with 5 subnets (2 public, 2 private, 1 for App Gateway)
   - 2 Network Security Groups (SFTP, AKS)
2. **SFTP Infrastructure**:
   - Load Balancer with public IP
   - 2 Ubuntu VMs with Docker installed
3. **AKS Cluster**:
   - Kubernetes cluster with workload identity enabled
   - OIDC issuer enabled
   - Key Vault Secrets Provider (CSI driver)
4. **Database**:
   - PostgreSQL Flexible Server (private endpoint)
   - 2 databases (online, archive)
   - Private DNS zone
5. **Application Gateway**:
   - Standard_v2 SKU
   - Public IP
   - Basic HTTP configuration (AGIC will manage)

### Workload Identity Integration
1. **MFT Identity**:
   - Federated credentials for 4 service accounts (MFT, DBC, DB User Init, MFT Service)
   - Key Vault Secrets User role
   - Key Vault Certificate User role
2. **AGIC Identity**:
   - Federated credential for AGIC service account
   - Contributor role on Application Gateway
   - Reader role on Resource Group
   - Network Contributor role on App Gateway subnet

### Key Vault Integration
1. **Default Secrets**: MFT passwords, keystore passwords, SSH keys, metering config
2. **Database Credentials**: PostgreSQL connection details and credentials
3. **Certificates** (optional): Keystores, truststores, CA bundles
4. **RBAC**: Role assignments for MFT identity and Terraform identity

## Authentication

Stage B uses the infrastructure service principal from Stage A. Set these environment variables before running Terraform:

```bash
# Get values from Stage A outputs
export ARM_CLIENT_ID="<infra-sp-client-id>"
export ARM_CLIENT_SECRET="<infra-sp-client-secret>"
export ARM_TENANT_ID="<tenant-id>"
export ARM_SUBSCRIPTION_ID="<subscription-id>"
```

Or use a script:
```bash
# set-env.sh
export ARM_CLIENT_ID=$(cd ../02-sec-stage-A && terraform output -raw infra_sp_application_id)
export ARM_CLIENT_SECRET=$(cd ../02-sec-stage-A && terraform output -raw infra_sp_client_secret)
export ARM_TENANT_ID=$(cd ../02-sec-stage-A && terraform output -raw infra_sp_tenant_id)
export ARM_SUBSCRIPTION_ID=$(cd ../02-sec-stage-A && terraform output -raw infra_sp_subscription_id)
```

## Configuration

### 1. Copy and Edit Variables File

```bash
cp terraform.tfvars.example terraform.tfvars
```

### 2. Required Variables

Edit `terraform.tfvars` and set at minimum:

```hcl
# Basic Configuration
prefix   = "mftdemo"
location = "westeurope"

# Stage A Handoff (from Stage A outputs)
delivery_resource_group_name   = "mftdemo-s-delivery"
fulfillment_resource_group_name = "mftdemo-s-fulfillment"
mft_identity_id                = "/subscriptions/.../resourceGroups/.../providers/Microsoft.ManagedIdentity/userAssignedIdentities/mftdemo-mft-identity"
mft_identity_principal_id      = "..."
mft_identity_client_id         = "..."
agic_identity_id               = "/subscriptions/.../resourceGroups/.../providers/Microsoft.ManagedIdentity/userAssignedIdentities/mftdemo-agic-identity"
agic_identity_principal_id     = "..."
agic_identity_client_id        = "..."

# Key Vault (from 01-vault/)
key_vault_name                = "mftdemovault"
key_vault_resource_group_name = "mftdemo-vault-rg"

# SSH Key
ssh_admin_pub_key = "ssh-rsa AAAAB3NzaC1yc2E..."

# PostgreSQL Credentials
postgres_admin_password        = "SecurePassword123!"
postgres_dbc_password          = "SecurePassword123!"
postgres_dbc_archive_password  = "SecurePassword123!"
```

### 3. Optional Variables

See `variables.tf` for all available options, including:
- Network address spaces
- VM sizes and counts
- Storage quotas
- Certificate upload configuration
- Private storage for MFT VFS

## Deployment

### Initialize Terraform

```bash
terraform init
```

### Plan Deployment

```bash
terraform plan -out=tfplan
```

Review the plan carefully. You should see approximately 55 resources to be created.

### Apply Configuration

```bash
terraform apply tfplan
```

Deployment typically takes 15-20 minutes due to AKS cluster creation.

## Post-Deployment

### 1. Verify Resources

```bash
# List all outputs
terraform output

# Get specific outputs
terraform output aks_cluster_name
terraform output app_gateway_public_ip
terraform output sftp_lb_public_ip
```

### 2. Configure kubectl Access

```bash
az aks get-credentials \
  --resource-group $(terraform output -raw fulfillment_resource_group_name) \
  --name $(terraform output -raw aks_cluster_name)
```

### 3. Verify Workload Identity

```bash
# Check OIDC issuer
kubectl get --raw /.well-known/openid-configuration | jq

# Verify service accounts will be created by applications
kubectl get serviceaccount -A
```

### 4. Deploy AGIC (Application Gateway Ingress Controller)

```bash
# Add Helm repository
helm repo add application-gateway-kubernetes-ingress https://appgwingress.blob.core.windows.net/ingress-azure-helm-package/
helm repo update

# Install AGIC with workload identity
helm install ingress-azure application-gateway-kubernetes-ingress/ingress-azure \
  --set appgw.applicationGatewayID=$(terraform output -raw app_gateway_id) \
  --set armAuth.type=workloadIdentity \
  --set armAuth.identityClientID=$(terraform output -raw agic_identity_client_id) \
  --set rbac.enabled=true
```

### 5. Access Key Vault Secrets

```bash
# List secrets
az keyvault secret list --vault-name $(terraform output -raw key_vault_name)

# Get a specific secret
az keyvault secret show --vault-name $(terraform output -raw key_vault_name) --name dev-mft-admin-password
```

### 6. Test SFTP Access

```bash
# Get SFTP endpoint
SFTP_IP=$(terraform output -raw sftp_lb_public_ip)
echo "SFTP Endpoint: $SFTP_IP:55022"

# Test connection (after SFTP containers are deployed)
sftp -P 55022 user@$SFTP_IP
```

## Handoff to Stage C

Stage C (Azure DevOps setup) requires the following information from Stage B:

```bash
# Get handoff information
terraform output stage_c_handoff
```

This includes:
- VMSS name and resource group (for agent pool registration)
- ACR name and login server (for pipeline configuration)
- Key Vault name and URI (for pipeline secrets)

## Troubleshooting

### Authentication Issues

```bash
# Verify service principal credentials
az login --service-principal \
  --username $ARM_CLIENT_ID \
  --password $ARM_CLIENT_SECRET \
  --tenant $ARM_TENANT_ID

# Check role assignments
az role assignment list --assignee $ARM_CLIENT_ID
```

### AKS Issues

```bash
# Check AKS cluster status
az aks show --resource-group <rg-name> --name <aks-name> --query provisioningState

# Get AKS credentials
az aks get-credentials --resource-group <rg-name> --name <aks-name> --overwrite-existing

# Verify nodes
kubectl get nodes
```

### PostgreSQL Connection Issues

```bash
# Test PostgreSQL connectivity from AKS subnet
# The server is only accessible from the private subnet

# Get connection details
terraform output postgres_server_fqdn
terraform output postgres_online_db_name
```

### Key Vault Access Issues

```bash
# Check Key Vault access policies
az keyvault show --name <vault-name> --query properties.enableRbacAuthorization

# List role assignments on Key Vault
az role assignment list --scope $(terraform output -raw key_vault_id)
```

## Cleanup

To destroy all resources created in Stage B:

```bash
terraform destroy
```

**Warning**: This will delete all infrastructure resources. Ensure you have backups of any important data.

## Architecture Alignment

This stage implements the infrastructure layer of the Archimate model:
- **Service Delivery**: Agent infrastructure, container registry, storage
- **Service Fulfillment**: Runtime infrastructure (AKS, PostgreSQL, SFTP, App Gateway)
- **Technology Services**: Network, compute, storage, database services

## Security Considerations

1. **Network Isolation**: Private subnets for AKS and PostgreSQL
2. **Managed Identities**: No service principal secrets in application code
3. **Key Vault RBAC**: Fine-grained access control for secrets
4. **NSG Rules**: Restricted inbound access to SFTP and management ports
5. **Private Endpoints**: PostgreSQL accessible only from VNet

## Next Steps

After completing Stage B:
1. Proceed to Stage C for Azure DevOps setup (if using Terraform automation)
2. Or manually configure Azure DevOps resources via UI
3. Deploy MFT application to AKS
4. Configure SFTP containers on SFTP VMs
5. Set up monitoring and logging

## References

- [Stage A Documentation](../02-sec-stage-A/README.md)
- [Stage C Documentation](../04-azdo-stage-C/README.md) (when available)
- [Repository README](../../README.md)
- [Conventions](../CONVENTIONS.md)
