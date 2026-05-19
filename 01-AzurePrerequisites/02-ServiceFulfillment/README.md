# Stage 02 - Service Fulfillment Infrastructure

This Terraform configuration creates the service fulfillment infrastructure for the MFT (Managed File Transfer) solution on Azure.

## Architecture Overview

The infrastructure includes:

1. **Virtual Network** with 5 subnets:
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
   - OIDC issuer enabled for workload identity

4. **Application Gateway + AGIC Integration**:
   - Application Gateway v2 for public ingress
   - Managed identity for AGIC with required RBAC permissions
   - Application Gateway Ingress Controller (AGIC) for dynamic backend configuration
   - Automatic routing from Application Gateway to AKS workloads

5. **PostgreSQL Database**:
   - Azure Database for PostgreSQL Flexible Server
   - Two databases: `mft_online` and `mft_archive`
   - Private endpoint in dedicated subnet
   - Private DNS zone for internal resolution

6. **Security**:
   - Network Security Groups with IP whitelisting
   - Managed identities for ACR access and AGIC
   - Private networking for AKS and PostgreSQL

## Prerequisites

1. Completed **01-ServiceDelivery** setup (ACR must exist)
2. Azure CLI installed and authenticated
3. Terraform >= 1.0 installed
4. kubectl installed (for AKS management)
5. Helm 3 installed (for deploying AGIC and test applications)

## Understanding the Deployment Architecture

### Why is AGIC Not Installed by Terraform?

**AGIC (Application Gateway Ingress Controller) is a Kubernetes application**, not Azure infrastructure. Here's why it's installed separately:

1. **Terraform provisions Azure infrastructure** (VMs, networks, AKS cluster, Application Gateway)
2. **AGIC runs as pods inside AKS** and watches for Kubernetes Ingress resources
3. **AGIC must be installed after AKS is running** - you can't deploy Kubernetes applications before the cluster exists
4. **Kubernetes-native tools (helm/kubectl) are the standard** for deploying cluster applications

**The deployment flow:**
```
Terraform (Infrastructure) → AKS Running → Helm/kubectl (AGIC Installation) → Deploy Workloads
```

This separation follows cloud-native best practices:
- **Infrastructure as Code (Terraform)**: Manages Azure resources
- **GitOps/Helm (Kubernetes)**: Manages cluster applications

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

3. **Optional**: Configure role assignment behavior:
   - `enable_agic_role_assignments`: Set to `true` only if your service principal has `Microsoft.Authorization/roleAssignments/write` permissions (default: `false`)
   - When `false` (default), you must manually grant AGIC permissions after `terraform apply` (see output `manual_permission_grants_required`)
   - When `true`, Terraform will automatically create role assignments (requires elevated permissions)

## Deployment Guide

This deployment follows a **platform-first, workload-second** approach:

1. **Phase 1: Infrastructure Provisioning** - Deploy Azure resources via Terraform
2. **Phase 2: AGIC Installation** - Install the ingress controller in AKS
3. **Phase 3: Workload Validation** - Deploy test application to verify connectivity

---

## Phase 1: Infrastructure Provisioning

### Step 1: Initialize Terraform

```bash
terraform init
```

### Step 2: Review the Plan

```bash
terraform plan
```

### Step 3: Apply the Infrastructure Configuration

Choose your deployment path based on your permissions:

#### Option A: Full Permissions (Recommended)

If your service principal has **User Access Administrator** or **Owner** permissions:

```bash
terraform apply --auto-approve --var-file=./ibm-test.tfvars --var-file=./full.tfvars
```

This creates everything in one step, including role assignments.

#### Option B: Limited Permissions (Phased Deployment)

If your service principal only has **Contributor** permissions:

**Step 3a: Deploy Infrastructure**
```bash
terraform apply --auto-approve --var-file=./ibm-test.tfvars --var-file=./phase1.tfvars
```

**Step 3b: Grant AGIC Permissions Manually**

After Terraform completes, check the output for exact commands:
```bash
terraform output manual_permission_grants_required
```

Run the three Azure CLI commands provided (requires elevated account):
```bash
# Example commands (use actual values from output):
az role assignment create \
  --assignee <AGIC_PRINCIPAL_ID> \
  --role Contributor \
  --scope <APP_GATEWAY_RESOURCE_ID>

az role assignment create \
  --assignee <AGIC_PRINCIPAL_ID> \
  --role Reader \
  --scope <RESOURCE_GROUP_ID>

az role assignment create \
  --assignee <AKS_KUBELET_OBJECT_ID> \
  --role "Managed Identity Operator" \
  --scope <AGIC_IDENTITY_RESOURCE_ID>
```

**Wait 2-3 minutes** for role assignments to propagate.

**Step 3c: Complete Deployment**
```bash
terraform apply --auto-approve --var-file=./ibm-test.tfvars --var-file=./phase2.tfvars
```

### Step 4: Get AKS Credentials

After deployment, configure kubectl to access the AKS cluster:

```bash
az aks get-credentials --resource-group <resource-group-name> --name <aks-cluster-name>
```

Or use Terraform output:

```bash
mkdir -p ~/.kube
terraform output -raw aks_kube_config > ~/.kube/config-mft
export KUBECONFIG=~/.kube/config-mft
```

Verify connectivity:
```bash
kubectl cluster-info
kubectl get nodes
```

**Infrastructure provisioning is now complete.** Proceed to Phase 2.

---

## Phase 2: AGIC Installation

AGIC is the integration layer that enables Application Gateway to dynamically route traffic to AKS workloads.

### Understanding AGIC Components

AGIC requires two components:
1. **Microsoft Entra Workload ID** (formerly AAD Pod Identity) - Handles Azure authentication
2. **AGIC Controller** - Watches Ingress resources and updates Application Gateway

### Step 1: Get Required Values from Terraform

```bash
# Export all required values
export SUBSCRIPTION_ID=$(az account show --query id -o tsv)
export RESOURCE_GROUP=$(terraform output -raw resource_group_name)
export APP_GATEWAY_NAME=$(terraform output -raw app_gateway_name)
export AGIC_IDENTITY_CLIENT_ID=$(terraform output -raw agic_identity_client_id)
export AGIC_IDENTITY_RESOURCE_ID=$(terraform output -raw agic_identity_id)
```

### Step 2: Install Microsoft Entra Workload ID

**Note**: This replaces the deprecated AAD Pod Identity system.

```bash
# Create namespace
kubectl create namespace aad-pod-identity

# Install via Helm
helm repo add aad-pod-identity https://raw.githubusercontent.com/Azure/aad-pod-identity/master/charts
helm repo update

helm install aad-pod-identity aad-pod-identity/aad-pod-identity \
  --namespace aad-pod-identity \
  --set nmi.allowNetworkPluginKubenet=true
```

Verify installation:
```bash
kubectl get pods -n aad-pod-identity
```

Expected: `mic` and `nmi` pods in Running state.

### Step 3: Create AzureIdentity and AzureIdentityBinding

Create the identity configuration:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: "aadpodidentity.k8s.io/v1"
kind: AzureIdentity
metadata:
  name: agic-identity
  namespace: default
spec:
  type: 0
  resourceID: ${AGIC_IDENTITY_RESOURCE_ID}
  clientID: ${AGIC_IDENTITY_CLIENT_ID}
---
apiVersion: "aadpodidentity.k8s.io/v1"
kind: AzureIdentityBinding
metadata:
  name: agic-identity-binding
  namespace: default
spec:
  azureIdentity: agic-identity
  selector: ingress-azure
EOF
```

Verify:
```bash
kubectl get azureidentity
kubectl get azureidentitybinding
```

### Step 4: Install AGIC via Helm (OCI Registry)

**Important**: Microsoft now hosts AGIC in their OCI registry, not the old blob storage.

```bash
# Create Helm values file
cat > agic-values.yaml <<EOF
# Verbosity level of the App Gateway Ingress Controller
verbosityLevel: 3

################################################################################
# Specify which application gateway the ingress controller will manage
#
appgw:
    subscriptionId: ${SUBSCRIPTION_ID}
    resourceGroup: ${RESOURCE_GROUP}
    name: ${APP_GATEWAY_NAME}
    usePrivateIP: false
    shared: false

################################################################################
# Specify which kubernetes namespace the ingress controller will watch
# Default value is "default"
# Leave blank to watch all namespaces
#
kubernetes:
    watchNamespace: ""

################################################################################
# Specify the authentication with Azure Resource Manager
#
armAuth:
    type: aadPodIdentity
    identityResourceID: ${AGIC_IDENTITY_RESOURCE_ID}
    identityClientID: ${AGIC_IDENTITY_CLIENT_ID}

################################################################################
# Specify if the cluster is RBAC enabled or not
rbac:
    enabled: true
EOF

# Install AGIC from Microsoft Container Registry (OCI format)
helm install ingress-azure \
  oci://mcr.microsoft.com/azure-application-gateway/charts/ingress-azure \
  --version 1.7.5 \
  --namespace default \
  --values agic-values.yaml
```

**Note**: Version 1.7.5 is used here. Check for latest version at: https://mcr.microsoft.com/v2/azure-application-gateway/charts/ingress-azure/tags/list

### Step 5: Verify AGIC Installation

```bash
# Check AGIC pod status
kubectl get pods -l app=ingress-azure

# Check AGIC logs (should show successful connection to Application Gateway)
kubectl logs -l app=ingress-azure --tail=50

# Verify IngressClass was created
kubectl get ingressclass
```

Expected output:
- AGIC pod in `Running` state
- Logs show: "successfully connected to Application Gateway"
- IngressClass `azure-application-gateway` exists

**AGIC installation is now complete.** The platform is ready to route traffic.

---

## Phase 3: Workload Validation

### Step 1: Deploy Test Application

Deploy the simple-web test application to verify end-to-end connectivity:

```bash
cd helm/simple-web
helm install simple-web . --create-namespace --namespace mft-test
```

This deploys:
- 2 nginx pods
- ClusterIP service
- Ingress resource with AGIC annotations

### Step 2: Verify Ingress Configuration

Check that AGIC has processed the ingress and updated Application Gateway:

```bash
# Check ingress status
kubectl get ingress -n mft-test

# Expected output after 1-2 minutes:
# NAME         CLASS                       HOSTS              ADDRESS          PORTS   AGE
# simple-web   azure-application-gateway   simple-web.local   <APP_GW_IP>      80      2m
```

The ingress ADDRESS should show the Application Gateway public IP.

### Step 3: Verify Backend Health

```bash
# Check Application Gateway backend health
az network application-gateway show-backend-health \
  --resource-group $(terraform output -raw resource_group_name) \
  --name $(terraform output -raw app_gateway_name) \
  --query 'backendAddressPools[].backendHttpSettingsCollection[].servers[].health' \
  --output table
```

Expected: All backends show `Healthy` status.

### Step 4: Test End-to-End Connectivity

Test HTTP access through Application Gateway:

```bash
# Get Application Gateway public IP
APP_GW_IP=$(terraform output -raw app_gateway_public_ip)

# Test with Host header
curl -H "Host: simple-web.local" http://$APP_GW_IP/

# Expected output: HTML response from nginx
```

For browser testing, add to `/etc/hosts`:
```bash
echo "$APP_GW_IP simple-web.local" | sudo tee -a /etc/hosts
```

Then open: http://simple-web.local

**Workload validation is complete.** The platform successfully routes traffic from Application Gateway through AGIC to AKS workloads.

---

## Verification Checklist

Use this checklist to verify each component:

### ✅ Infrastructure Verification

**Virtual Network and Subnets:**
```bash
az network vnet show --resource-group <rg> --name <vnet-name>
az network vnet subnet list --resource-group <rg> --vnet-name <vnet-name> -o table
```

**AKS Cluster:**
```bash
kubectl cluster-info
kubectl get nodes
```

**Application Gateway:**
```bash
az network application-gateway show --resource-group <rg> --name <app-gateway-name>
```

### ✅ AGIC Verification

**Pod Status:**
```bash
kubectl get pods -l app=ingress-azure
# Expected: Running state
```

**AAD Pod Identity:**
```bash
kubectl get azureidentity
kubectl get azureidentitybinding
kubectl get pods -n aad-pod-identity
```

**AGIC Logs:**
```bash
kubectl logs -l app=ingress-azure --tail=100
# Look for: successful authentication, no permission errors
```

**IngressClass:**
```bash
kubectl get ingressclass
# Expected: azure-application-gateway class exists
```

### ✅ Workload Verification

**Pods:**
```bash
kubectl get pods -n mft-test
# Expected: 2 simple-web pods in Running state
```

**Service:**
```bash
kubectl get svc -n mft-test
kubectl get endpoints -n mft-test
# Expected: Service with 2 endpoints
```

**Ingress:**
```bash
kubectl get ingress -n mft-test
kubectl describe ingress simple-web -n mft-test
# Expected: ADDRESS field shows Application Gateway IP
```

**End-to-End HTTP Test:**
```bash
APP_GW_IP=$(terraform output -raw app_gateway_public_ip)
curl -v -H "Host: simple-web.local" http://$APP_GW_IP/
# Expected: 200 OK with nginx HTML response
```

### ✅ SFTP Service Verification

**SFTP Endpoint:**
```bash
terraform output sftp_endpoint
```

**Test SFTP Connection:**
```bash
sftp -P 55022 user@<sftp-lb-ip>
# Default credentials: user/pass
```

### ✅ PostgreSQL Verification

**Connection Strings:**
```bash
terraform output postgres_connection_string_online
terraform output postgres_connection_string_archive
```

**Test Connection:**
```bash
# From within VNet:
kubectl run -it --rm psql --image=postgres:14 --restart=Never -- \
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
- `agic_identity_client_id`: AGIC managed identity client ID
- `agic_identity_principal_id`: AGIC managed identity principal ID

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

## Troubleshooting

### AGIC Issues

**AGIC Pod Not Starting:**
```bash
# Check pod status and events
kubectl get pods -l app=ingress-azure
kubectl describe pod -l app=ingress-azure

# Check AAD Pod Identity
kubectl get pods -n aad-pod-identity
kubectl logs -n aad-pod-identity -l app.kubernetes.io/component=mic
```

**Permission Errors:**
```bash
# Verify RBAC assignments
az role assignment list --assignee $(terraform output -raw agic_identity_principal_id) -o table

# Expected roles:
# - Contributor on Application Gateway
# - Reader on Resource Group
# - Managed Identity Operator on AGIC identity (for AKS kubelet)
```

**Ingress Not Getting IP Address:**
```bash
# Check AGIC logs
kubectl logs -l app=ingress-azure --tail=100

# Verify ingress configuration
kubectl describe ingress -n mft-test

# Check Application Gateway backend pool
az network application-gateway show-backend-health \
  --resource-group <rg> \
  --name <app-gateway-name>
```

**Backend Health Probe Failures:**
```bash
# Check pod readiness
kubectl get pods -n mft-test
kubectl describe pod <pod-name> -n mft-test

# Verify service endpoints
kubectl get endpoints -n mft-test

# Test pod connectivity from within cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl http://simple-web.mft-test.svc.cluster.local
```

**Old Helm Repository Error (409):**

If you see this error:
```
Error: looks like "https://appgwingress.blob.core.windows.net/ingress-azure-helm-package/" is not a valid chart repository
```

**Solution**: Use the new OCI registry format:
```bash
helm install ingress-azure \
  oci://mcr.microsoft.com/azure-application-gateway/charts/ingress-azure \
  --version 1.7.5 \
  --namespace default \
  --values agic-values.yaml
```

### SFTP VMs Not Accessible

**Check NSG Rules:**
```bash
az network nsg show --resource-group <rg> --name <nsg-name>
```

**Verify IP Whitelisting:**
- Ensure your IP is in `allowed_ip_ranges` variable
- Check NSG rule priorities

**Check VM Status:**
```bash
az vm list --resource-group <rg> --output table
az vm get-instance-view --resource-group <rg> --name <vm-name>
```

### AKS Connection Issues

**Verify Credentials:**
```bash
kubectl cluster-info
kubectl get nodes
```

**Re-fetch Credentials:**
```bash
az aks get-credentials --resource-group <rg> --name <aks-name> --overwrite-existing
```

### PostgreSQL Connection Issues

**Verify Private DNS Resolution:**
```bash
# From within VNet (e.g., from a pod)
kubectl run -it --rm dns-test --image=busybox --restart=Never -- \
  nslookup <postgres-server-name>.postgres.database.azure.com
```

**Test Connection:**
```bash
# From within VNet
kubectl run -it --rm psql --image=postgres:14 --restart=Never -- \
  psql "$(terraform output -raw postgres_connection_string_online)"
```

### Application Gateway Issues

**Check Backend Health:**
```bash
az network application-gateway show-backend-health \
  --resource-group <rg> \
  --name <app-gateway-name> \
  --query 'backendAddressPools[].backendHttpSettingsCollection[].servers[].health'
```

**502 Bad Gateway:**
- Verify AGIC is running and has processed the ingress
- Check backend pod health and readiness probes
- Verify service endpoints exist
- Check Application Gateway backend health

**Ingress Not Working After AGIC Installation:**
- Ensure ingress has `ingressClassName: azure-application-gateway`
- Verify AGIC is watching the correct namespace
- Check AGIC logs for reconciliation errors
- Restart AGIC pod: `kubectl delete pod -l app=ingress-azure`

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning**: This will delete all resources including databases. Ensure you have backups if needed.

## Next Steps

Now that the platform is operational and validated, you can proceed with:

### 1. Deploy Production Workloads

Deploy your actual MFT application to AKS using the same pattern as simple-web:

```bash
# Example: Deploy active-transfer service
cd ../../02-ContainerImages
# Build and push images to ACR
# Then deploy via Helm with ingress configuration
```

### 2. Configure Custom SFTP Service

Customize the SFTP service on the VMs:
- Update Docker Compose configuration
- Configure user authentication
- Set up file transfer workflows
- Integrate with AKS workloads

### 3. Implement SSL/TLS

Add HTTPS support to Application Gateway:

```bash
# Create TLS certificate secret
kubectl create secret tls simple-web-tls \
  --cert=path/to/cert.pem \
  --key=path/to/key.pem \
  -n mft-test

# Update ingress to use TLS
# See helm/simple-web/values.yaml for TLS configuration example
```

### 4. Set Up Monitoring and Logging

Implement observability:
- Enable Azure Monitor for AKS
- Configure Application Gateway diagnostics
- Set up Log Analytics workspace
- Create alerts for critical metrics
- Monitor AGIC logs and Application Gateway health

### 5. Configure Backup Policies

Protect your data:
- Enable Azure Backup for PostgreSQL
- Configure retention policies
- Set up disaster recovery procedures
- Document restore procedures

### 6. Implement CI/CD Pipelines

Automate deployments:
- Create Azure DevOps or GitHub Actions pipelines
- Automate container image builds
- Implement Helm chart deployments
- Set up environment promotion workflows

### 7. Security Hardening

Enhance security posture:
- Implement Azure Policy for compliance
- Enable Azure Defender for AKS and PostgreSQL
- Configure network policies in AKS
- Implement pod security standards
- Regular security scanning of container images
- Review and tighten NSG rules

### 8. Performance Optimization

Optimize for production:
- Configure Application Gateway autoscaling
- Implement AKS cluster autoscaling
- Optimize PostgreSQL performance settings
- Set up CDN if needed
- Review and adjust resource requests/limits

## Additional Resources

- [AGIC Documentation](https://azure.github.io/application-gateway-kubernetes-ingress/)
- [AGIC GitHub Repository](https://github.com/Azure/application-gateway-kubernetes-ingress)
- [Microsoft Entra Workload ID](https://azure.github.io/aad-pod-identity/)
- [Application Gateway Documentation](https://docs.microsoft.com/en-us/azure/application-gateway/)
- [AKS Documentation](https://docs.microsoft.com/en-us/azure/aks/)
- [PostgreSQL Flexible Server Documentation](https://docs.microsoft.com/en-us/azure/postgresql/flexible-server/)

## Support

For issues or questions, refer to:
- [Azure Terraform Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- Project documentation in this repository
- Azure support channels