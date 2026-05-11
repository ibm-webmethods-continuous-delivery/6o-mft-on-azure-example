# Stage 02 - Service Fulfilment Infrastructure

This Terraform configuration creates the service fulfilment infrastructure for the MFT (Managed File Transfer) solution on Azure.

## Architecture Overview

The infrastructure includes:

1. **Virtual Network** with 4 subnets:
   - 2 Public subnets for SFTP VMs
   - 2 Private subnets (one for AKS, one for PostgreSQL)
   - 1 Application Gateway subnet

2. **SFTP Service**:
   - 2 Linux VMs with Docker and Docker Compose
   - Network Load Balancer (NLB) in front serving port 55022
   - Automatic ACR login using managed identity
   - Pre-configured SFTP service via Docker Compose

3. **AKS Cluster**:
   - Minimal configuration with 2 nodes (configurable)
   - Private subnet deployment
   - Integrated with ACR for image pulling
   - Application Gateway for ingress traffic

4. **PostgreSQL Database**:
   - Azure Database for PostgreSQL Flexible Server
   - Two databases: `mft_online` and `mft_archive`
   - Private endpoint in dedicated subnet
   - Private DNS zone for internal resolution

5. **Security**:
   - Network Security Groups with IP whitelisting
   - Managed identities for ACR access
   - Private networking for AKS and PostgreSQL

## Prerequisites

1. Completed **01-ServiceDelivery** setup (ACR must exist)
2. Azure CLI installed and authenticated
3. Terraform >= 1.0 installed
4. kubectl installed (for AKS management)
5. Helm 3 installed (for deploying the test application)

## Configuration

1. Copy the example variables file:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Edit `terraform.tfvars` and update the following required values:
   - `resource_group_name`: Your Azure resource group name
   - `prefix`: Unique prefix for resource names
   - `allowed_ip_ranges`: Your IP addresses/ranges for access
   - `ssh_admin_pub_key`: Your SSH public key
   - `acr_name`: ACR name from 01-ServiceDelivery (must match exactly)
   - `postgres_admin_password`: Strong password for PostgreSQL

## Deployment

### Step 1: Initialize Terraform

```bash
terraform init
```

### Step 2: Review the Plan

```bash
terraform plan
```

### Step 3: Apply the Configuration

```bash
terraform apply
```

This will create:
- Virtual network with subnets
- Network security groups
- 2 SFTP VMs with Docker/Docker Compose
- Load balancer for SFTP
- AKS cluster
- PostgreSQL Flexible Server with 2 databases
- Application Gateway

### Step 4: Get AKS Credentials

After deployment, configure kubectl to access the AKS cluster:

```bash
az aks get-credentials --resource-group <resource-group-name> --name <aks-cluster-name>
```

Or use Terraform output:

```bash
terraform output -raw aks_kube_config > ~/.kube/config-mft
export KUBECONFIG=~/.kube/config-mft
```

### Step 5: Deploy Test Application to AKS

Deploy the simple web server to verify Application Gateway connectivity:

```bash
cd helm/simple-web
helm install simple-web . --create-namespace --namespace mft-test
```

### Step 6: Configure Application Gateway Backend

After deploying the Helm chart, you need to update the Application Gateway backend pool with the service IP:

```bash
# Get the service ClusterIP
kubectl get svc simple-web -n mft-test

# Update Application Gateway backend pool via Azure Portal or CLI
# Add the service IP to the "aks-backend-pool"
```

Alternatively, you can use an Ingress Controller for automatic backend configuration.

## Verification

### Verify SFTP Service

1. Get the SFTP endpoint:
   ```bash
   terraform output sftp_endpoint
   ```

2. Test SFTP connection (default credentials: user/pass):
   ```bash
   sftp -P 55022 user@<sftp-lb-ip>
   ```

### Verify Web Application

1. Get the Application Gateway public IP:
   ```bash
   terraform output web_endpoint
   ```

2. Open in browser:
   ```bash
   curl http://<app-gateway-ip>
   # or
   open http://<app-gateway-ip>
   ```

### Verify PostgreSQL

1. Get connection strings:
   ```bash
   terraform output postgres_connection_string_online
   terraform output postgres_connection_string_archive
   ```

2. Connect using psql:
   ```bash
   psql "<connection-string>"
   ```

## Outputs

Key outputs available after deployment:

- `sftp_endpoint`: SFTP connection endpoint
- `web_endpoint`: Web application endpoint
- `sftp_lb_public_ip`: Public IP of SFTP load balancer
- `app_gateway_public_ip`: Public IP of Application Gateway
- `aks_cluster_name`: Name of the AKS cluster
- `postgres_server_fqdn`: PostgreSQL server FQDN
- `postgres_connection_string_online`: Connection string for online DB
- `postgres_connection_string_archive`: Connection string for archive DB

View all outputs:
```bash
terraform output
```

## Customization

### Scaling SFTP VMs

To change VM size or add more VMs, modify in `terraform.tfvars`:
```hcl
sftp_vm_size = "Standard_D2s_v3"
```

### Scaling AKS

To change node count or size:
```hcl
aks_node_count = 3
aks_node_size  = "Standard_D2s_v3"
```

### PostgreSQL Configuration

To change PostgreSQL tier or storage:
```hcl
postgres_sku_name   = "GP_Standard_D2s_v3"
postgres_storage_mb = 65536  # 64 GB
```

## Security Considerations

1. **IP Whitelisting**: Only specified IPs in `allowed_ip_ranges` can access SFTP and management interfaces
2. **Private Networking**: AKS and PostgreSQL are in private subnets
3. **Managed Identities**: VMs and AKS use managed identities for ACR access (no credentials stored)
4. **Network Security Groups**: Restrict traffic between subnets
5. **PostgreSQL**: Uses private DNS and subnet delegation for secure access

## Troubleshooting

### SFTP VMs Not Accessible

1. Check NSG rules:
   ```bash
   az network nsg show --resource-group <rg> --name <nsg-name>
   ```

2. Verify your IP is in `allowed_ip_ranges`

3. Check VM status:
   ```bash
   az vm list --resource-group <rg> --output table
   ```

### AKS Connection Issues

1. Verify credentials:
   ```bash
   kubectl cluster-info
   ```

2. Check node status:
   ```bash
   kubectl get nodes
   ```

### PostgreSQL Connection Issues

1. Verify private DNS resolution from within VNet
2. Check firewall rules
3. Ensure connection string format is correct

### Application Gateway Not Routing Traffic

1. Verify backend pool has correct IPs
2. Check health probe status in Azure Portal
3. Verify NSG allows traffic from Application Gateway subnet

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning**: This will delete all resources including databases. Ensure you have backups if needed.

## Next Steps

1. Configure custom SFTP service in Docker Compose
2. Deploy your actual application to AKS
3. Set up monitoring and logging
4. Configure backup policies for PostgreSQL
5. Implement CI/CD pipelines for application deployment

## Support

For issues or questions, refer to:
- [Azure Terraform Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [AKS Documentation](https://docs.microsoft.com/en-us/azure/aks/)
- [PostgreSQL Flexible Server Documentation](https://docs.microsoft.com/en-us/azure/postgresql/flexible-server/)
