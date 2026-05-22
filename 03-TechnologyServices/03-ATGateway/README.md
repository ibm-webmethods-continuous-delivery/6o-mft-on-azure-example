# ActiveTransfer Gateway Deployment

## Quick Start

**Prerequisites:** Azure CLI authenticated, environment variables set, gateways deployed via Terraform.

```bash
# 1. Set environment variables
export RESOURCE_GROUP="<your-resource-group>"
export GATEWAY1_VM_NAME="<gateway1-vm-name>"
export GATEWAY2_VM_NAME="<gateway2-vm-name>"
export ACR_LOGIN_SERVER="<your-acr>.azurecr.io"

# 2. Deploy gateways using Azure VM Run Command
cd /aio/work/c/iwcd/6o-mft-on-azure-example/03-TechnologyServices/03-ATGateway
chmod +x deploy-gateway1-vm-run-command.sh deploy-gateway2-vm-run-command.sh
./deploy-gateway1-vm-run-command.sh
./deploy-gateway2-vm-run-command.sh

# 3. Verify connectivity from AKS
kubectl run test-gw1 --image=busybox --rm -it --restart=Never -n mft -- nc -zv 10.1.0.4 8500
kubectl run test-gw2 --image=busybox --rm -it --restart=Never -n mft -- nc -zv 10.1.1.4 8500

# 4. Update ActiveTransfer (gateways configured in secret-mft-config.yaml.template)
cd ../02-AT/helm
helm upgrade active-transfer . --namespace mft --values ibm_values.yaml --wait --timeout 10m
```

**Note:** Gateway configuration (IPs: 10.1.0.4, 10.1.1.4) is managed in the secret template file:
`/aio/work/c/iwcd/6o-mft-on-azure-example/03-TechnologyServices/02-AT/helm/templates/secret-mft-config.yaml.template`

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Directory Structure](#directory-structure)
- [Prerequisites](#prerequisites)
- [Deployment Methods](#deployment-methods)
  - [Method 1: Azure VM Run Command (Recommended)](#method-1-azure-vm-run-command-recommended)
  - [Method 2: Manual SSH Deployment](#method-2-manual-ssh-deployment)
  - [Method 3: Azure DevOps Pipeline](#method-3-azure-devops-pipeline)
- [Configuration Details](#configuration-details)
- [Post-Deployment Verification](#post-deployment-verification)
- [Common Operations](#common-operations)
- [Troubleshooting](#troubleshooting)
- [Security Considerations](#security-considerations)

---

## Overview

This directory contains deployment artifacts for ActiveTransfer Gateway services running on Azure VMs. The gateways provide a DMZ layer between external SFTP clients and the internal ActiveTransfer server running in AKS.

**Key Features:**
- Docker Compose-based deployment
- Systemd service management
- Automatic startup on VM boot
- ACR authentication via managed identity
- Same container image as ActiveTransfer server

**Gateway Configuration:**
- Gateway IPs are configured in the **secret template** file, not in values.yaml
- Location: `03-TechnologyServices/02-AT/helm/templates/secret-mft-config.yaml.template`
- The template uses placeholders: `REPLACE_WITH_GATEWAY1_IP` and `REPLACE_WITH_GATEWAY2_IP`
- These are replaced during secret generation with actual IPs: 10.1.0.4 and 10.1.1.4

---

## Architecture

```
External Clients
       ↓
   [Load Balancer] (Public IP)
       ↓
   ┌────────────────────────────┐
   │  Gateway VM 1 (10.1.0.4)   │ ← Public Subnet 1
   │  - Docker + docker-compose │
   │  - Port 8500 (Gateway)     │
   │  - Port 55022 (SFTP)       │
   └────────────────────────────┘
       ↓
   ┌────────────────────────────┐
   │  Gateway VM 2 (10.1.1.4)   │ ← Public Subnet 2
   │  - Docker + docker-compose │
   │  - Port 8500 (Gateway)     │
   │  - Port 55022 (SFTP)       │
   └────────────────────────────┘
       ↓
   [AKS Private Network] (10.1.10.0/24)
       ↓
   ┌─────────────────────────┐
   │ ActiveTransfer Pods     │
   │ - Connects to Gateways  │
   │ - Manages file transfers│
   └─────────────────────────┘
```

**How Gateways Work:**
- Gateways run in `Gateway` mode (configured via `mft.server.runtime.mode=Gateway`)
- They listen on port 8500 (configurable via `mft.gatewayServer.port`)
- ActiveTransfer server connects to gateways and dynamically opens required ports
- All configuration is managed by the internal server
- See: [IBM Documentation](https://www.ibm.com/docs/en/webmethods-activetransfer/11.1.0?topic=gateway-understanding-activetransfer)

---

## Directory Structure

```
03-ATGateway/
├── README.md                         # This file (consolidated documentation)
├── gateway1/                         # Gateway 1 deployment artifacts
│   ├── docker-compose.yml            # Docker compose configuration
│   ├── config/
│   │   └── properties.cnf            # Gateway configuration
│   ├── at-gateway.service            # Systemd service file
│   └── deploy.sh                     # Deployment script
├── gateway2/                         # Gateway 2 deployment artifacts
│   ├── docker-compose.yml            # Docker compose configuration
│   ├── config/
│   │   └── properties.cnf            # Gateway configuration
│   ├── at-gateway.service            # Systemd service file
│   └── deploy.sh                     # Deployment script
├── deploy-gateway1-vm-run-command.sh # Azure VM Run Command deployment (Gateway 1)
└── deploy-gateway2-vm-run-command.sh # Azure VM Run Command deployment (Gateway 2)
```

---

## Prerequisites

### Infrastructure Requirements

1. **Azure VMs** (provisioned via Terraform):
   - Gateway VM 1: `10.1.0.4` in public subnet 1
   - Gateway VM 2: `10.1.1.4` in public subnet 2
   - Both VMs have System-Assigned Managed Identity
   - Docker and docker-compose installed via cloud-init

2. **Network Security**:
   - NSG rules allowing ports 8500-8501 from AKS subnet (10.1.10.0/24)
   - NSG rules allowing port 55022 from allowed external IPs
   - NSG rules allowing SSH (port 22) for management

3. **ACR Access**:
   - VMs have AcrPull role assignment (set `enable_sftp_vm_acr_role = true` in Terraform)
   - ACR login service configured on VMs

4. **Container Image**:
   - `active-transfer-enhance:latest` available in ACR
   - Same image used by ActiveTransfer server in AKS

### Required Actions Before Deployment

1. **Enable ACR Role Assignment** (if not already done):
   ```bash
   # In Terraform directory: 01-AzurePrerequisites/02-ServiceFulfillment/
   # Edit terraform.tfvars and set:
   enable_sftp_vm_acr_role = true

   # Apply changes
   terraform apply
   ```

2. **Add NSG Rules for Gateway Ports** (if not already done):
   ```hcl
   # Add to main.tf in azurerm_network_security_group.sftp resource:
   security_rule {
     name                       = "AllowGatewayFromAKS"
     priority                   = 120
     direction                  = "Inbound"
     access                     = "Allow"
     protocol                   = "Tcp"
     source_port_range          = "*"
     destination_port_ranges    = ["8500", "8501"]
     source_address_prefix      = "10.1.10.0/24"  # AKS subnet
     destination_address_prefix = "*"
   }
   ```

3. **Verify Infrastructure**:
   ```bash
   # Get Terraform outputs
   cd /aio/work/c/iwcd/6o-mft-on-azure-example/01-AzurePrerequisites/02-ServiceFulfillment
   terraform output
   ```

---

## Deployment Methods

### Method 1: Azure VM Run Command (Recommended)

**Best for:** Development, testing, and environments without bastion hosts or public IPs.

This method uses Azure CLI to execute deployment scripts directly on the VMs without requiring SSH access.

#### Prerequisites

```bash
# Install and authenticate with Azure CLI
az login
az account set --subscription "<subscription-id-or-name>"

# Verify permissions (need Virtual Machine Contributor role)
az role assignment list --assignee $(az account show --query user.name -o tsv) --all
```

#### Deployment Steps

**Step 1: Set Environment Variables**

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

**Step 2: Deploy Gateway 1**

```bash
cd /aio/work/c/iwcd/6o-mft-on-azure-example/03-TechnologyServices/03-ATGateway
chmod +x deploy-gateway1-vm-run-command.sh
./deploy-gateway1-vm-run-command.sh
```

**Step 3: Verify Gateway 1**

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

**Step 4: Deploy Gateway 2**

```bash
chmod +x deploy-gateway2-vm-run-command.sh
./deploy-gateway2-vm-run-command.sh
```

**Step 5: Verify Gateway 2**

```bash
# Check service status
az vm run-command invoke \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${GATEWAY2_VM_NAME}" \
    --command-id RunShellScript \
    --scripts "systemctl status at-gateway.service" \
    --output table
```

**Step 6: Test Connectivity from AKS**

```bash
# Test Gateway 1
kubectl run test-gateway1 --image=busybox --rm -it --restart=Never -n mft -- \
    sh -c "nc -zv 10.1.0.4 8500 && echo 'Gateway 1 is reachable'"

# Test Gateway 2
kubectl run test-gateway2 --image=busybox --rm -it --restart=Never -n mft -- \
    sh -c "nc -zv 10.1.1.4 8500 && echo 'Gateway 2 is reachable'"
```

Expected output:
```
10.1.0.4 (10.1.0.4:8500) open
Gateway 1 is reachable
```

#### Common VM Run Command Operations

**View Logs:**
```bash
# Gateway logs
az vm run-command invoke \
    -g "${RESOURCE_GROUP}" \
    -n "${GATEWAY1_VM_NAME}" \
    --command-id RunShellScript \
    --scripts "docker logs at-gateway1 --tail 100" \
    --output table
```

**Restart Service:**
```bash
az vm run-command invoke \
    -g "${RESOURCE_GROUP}" \
    -n "${GATEWAY1_VM_NAME}" \
    --command-id RunShellScript \
    --scripts "systemctl restart at-gateway.service" \
    --output table
```

**Check Container Status:**
```bash
az vm run-command invoke \
    -g "${RESOURCE_GROUP}" \
    -n "${GATEWAY1_VM_NAME}" \
    --command-id RunShellScript \
    --scripts "docker ps | grep at-gateway" \
    --output table
```

**Update Container Image:**
```bash
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
```

---

### Method 2: Manual SSH Deployment

**Best for:** Environments with bastion hosts or when you need interactive access.

**Note:** This method requires either:
- Azure Bastion configured (not included in current Terraform)
- Public IPs assigned to VMs (not recommended for production)
- VPN/ExpressRoute connection to Azure VNet

**Steps:**

1. **Copy files to Gateway VMs**:
   ```bash
   # Via bastion or VPN
   scp -r gateway1/* azureuser@<GATEWAY1_PRIVATE_IP>:/tmp/at-gateway-deploy/
   scp -r gateway2/* azureuser@<GATEWAY2_PRIVATE_IP>:/tmp/at-gateway-deploy/
   ```

2. **SSH to each VM and run deployment**:
   ```bash
   # Gateway 1
   ssh azureuser@<GATEWAY1_PRIVATE_IP>
   cd /tmp/at-gateway-deploy
   chmod +x deploy.sh
   export ACR_LOGIN_SERVER=<your-acr>.azurecr.io
   sudo -E ./deploy.sh
   sudo systemctl start at-gateway.service
   ```

---

### Method 3: Azure DevOps Pipeline

**Best for:** Production environments with CI/CD requirements.

See `../../pipelines/azure/GATEWAYS-PIPELINE-SETUP.md` for detailed instructions.

**Prerequisites:**
- Create SSH service connections for both VMs
- Create variable group `mft-azure-variables`
- Configure pipeline in Azure DevOps

**Pipeline triggers automatically on changes to `03-TechnologyServices/03-ATGateway/**`**

---

## Configuration Details

### Gateway Configuration (properties.cnf)

Key settings in `config/properties.cnf`:

```properties
# Gateway mode (required)
mft.server.runtime.mode=Gateway

# Gateway port (default 8500)
mft.gatewayServer.port=8500

# Server ID (unique per gateway)
mft.server.id=Gateway1-Azure  # or Gateway2-Azure

# Accept connections from any IP (internal network)
mft.gatewayServer.accept.ip.list=
```

### Docker Compose Configuration

Key settings in `docker-compose.yml`:

```yaml
services:
  at-gateway:
    image: ${ACR_LOGIN_SERVER}/active-transfer-enhance:latest
    ports:
      - "8500:8500"  # Gateway port
      - "8501:8501"  # Secondary port
    volumes:
      - ./config/properties.cnf:/opt/softwareag/.../properties.cnf:ro
      - ./logs:/opt/softwareag/.../logs
    environment:
      - MFT_SERVER_RUNTIME_MODE=Gateway
      - JAVA_MIN_MEM=512m
      - JAVA_MAX_MEM=1024m
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

**Important:** The logs directory must be owned by UID 1724 (the container user):
```bash
chown -R 1724:1724 /opt/at-gateway/logs
chmod 755 /opt/at-gateway/logs
```

### Systemd Service

The `at-gateway.service` file:
- Depends on `docker.service` and `acr-login.service`
- Automatically pulls latest image on start
- Manages container lifecycle via docker-compose
- Enabled to start on boot

### ActiveTransfer Gateway Registration

**Gateway IPs are configured in the secret template, NOT in values.yaml:**

File: `03-TechnologyServices/02-AT/helm/templates/secret-mft-config.yaml.template`

```json
"declareGateways": [
  {
    "instanceName": "Gateway1",
    "host": "REPLACE_WITH_GATEWAY1_IP",
    "port": "8500",
    "active": true,
    "autoConnect": true
  },
  {
    "instanceName": "Gateway2",
    "host": "REPLACE_WITH_GATEWAY2_IP",
    "port": "8500",
    "active": true,
    "autoConnect": true
  }
]
```

The placeholders are replaced with actual IPs (10.1.0.4, 10.1.1.4) during secret generation.

---

## Post-Deployment Verification

### 1. Verify Gateway Services

```bash
# On each VM, check service status
sudo systemctl status at-gateway.service

# Check container is running
sudo docker ps | grep at-gateway

# Check container logs
sudo docker logs at-gateway1 -f  # or at-gateway2

# Test port connectivity
nc -zv localhost 8500
```

### 2. Test Connectivity from AKS

```bash
kubectl run test-gateway --image=busybox --rm -it --restart=Never -n mft -- sh -c "
  echo 'Testing Gateway 1...'
  nc -zv 10.1.0.4 8500
  echo 'Testing Gateway 2...'
  nc -zv 10.1.1.4 8500
"
```

### 3. Update ActiveTransfer Helm Chart

```bash
cd ../02-AT/helm

# Upgrade ActiveTransfer with gateway configuration
helm upgrade active-transfer . \
  --namespace mft \
  --values ibm_values.yaml \
  --wait \
  --timeout 10m
```

### 4. Verify Gateway Registration

1. Access ActiveTransfer Admin UI
2. Navigate to: Settings > Gateways
3. Verify both gateways show as:
   - Status: Connected
   - Health: Green
   - Last Heartbeat: Recent timestamp

---

## Common Operations

### View Logs

```bash
# Service logs
sudo journalctl -u at-gateway.service -f

# Container logs
sudo docker logs at-gateway1 -f  # or at-gateway2

# Docker compose logs
cd /opt/at-gateway
sudo docker compose logs -f
```

### Restart Service

```bash
# Restart via systemd
sudo systemctl restart at-gateway.service

# Or restart container directly
cd /opt/at-gateway
sudo docker compose restart
```

### Update Configuration

```bash
# Edit configuration
sudo vi /opt/at-gateway/config/properties.cnf

# Restart to apply changes
sudo systemctl restart at-gateway.service
```

### Update Container Image

```bash
# Pull latest image
cd /opt/at-gateway
sudo docker compose pull

# Restart with new image
sudo systemctl restart at-gateway.service
```

### Health Checks

```bash
# Check container health
sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Check service status
sudo systemctl status at-gateway.service

# Test port connectivity
nc -zv localhost 8500
```

---

## Troubleshooting

### Issue: ACR Authentication Failures

**Symptom:**
```
Error response from daemon: pull access denied for <acr>.azurecr.io/active-transfer-enhance
```

**Solutions:**

1. **Check managed identity:**
   ```bash
   az vm identity show --resource-group <rg-name> --name <vm-name>
   ```

2. **Verify ACR role assignment:**
   ```bash
   az role assignment list --assignee <vm-principal-id> --scope <acr-resource-id>
   ```

3. **Restart ACR login service:**
   ```bash
   sudo systemctl restart acr-login.service
   sudo journalctl -u acr-login.service -n 50
   ```

4. **Manual login:**
   ```bash
   sudo az acr login --name <acr-name> --identity
   ```

---

### Issue: Container Won't Start

**Symptom:**
```
Container at-gateway1 exits immediately after starting
```

**Diagnosis:**

```bash
# View container logs
sudo docker logs at-gateway1

# Check configuration file
cat /opt/at-gateway/config/properties.cnf

# Verify it's mounted in container
sudo docker inspect at-gateway1 | grep -A 10 Mounts

# Check .env file
cat /opt/at-gateway/.env
```

**Common causes:**
- Missing `mft.server.runtime.mode=Gateway` in properties.cnf
- Invalid port configuration
- Missing .env file with ACR_LOGIN_SERVER

---

### Issue: Permission Denied Errors

**Symptom:**
```
java.io.IOException: Permission denied
    at java.base/java.io.UnixFileSystem.createFileExclusively(Native Method)
```

**Solution:**

The container runs as UID 1724 (non-root). The logs directory must be owned by this user:

```bash
# Fix permissions
sudo chown -R 1724:1724 /opt/at-gateway/logs
sudo chmod 755 /opt/at-gateway/logs

# Restart service
sudo systemctl restart at-gateway.service
```

---

### Issue: Network Connectivity Problems

**Symptom:**
```
nc: connect to 10.1.0.4 port 8500 (tcp) failed: Connection refused
```

**Diagnosis:**

```bash
# Verify gateway is listening
sudo netstat -tlnp | grep 8500

# Test local connectivity
nc -zv localhost 8500

# Check NSG rules (from Terraform directory)
cd /aio/work/c/iwcd/6o-mft-on-azure-example/01-AzurePrerequisites/02-ServiceFulfillment
terraform show | grep -A 20 "azurerm_network_security_rule"
```

**Solution:**

Add NSG rule to allow traffic from AKS subnet:

```hcl
security_rule {
  name                       = "AllowGatewayFromAKS"
  priority                   = 120
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_port_range          = "*"
  destination_port_ranges    = ["8500", "8501"]
  source_address_prefix      = "10.1.10.0/24"  # AKS subnet
  destination_address_prefix = "*"
}
```

---

### Issue: Gateway Not Connecting to ActiveTransfer Server

**Symptom:**
```
ActiveTransfer logs show: "Gateway1 connection failed"
Gateway shows as "Disconnected" in Admin UI
```

**Diagnosis:**

```bash
# Check gateway logs
sudo docker logs at-gateway1 | grep -i "connection\|error"

# Verify gateway configuration
cat /opt/at-gateway/config/properties.cnf | grep -i "gateway\|server"

# Check ActiveTransfer secret configuration
kubectl get secret mft-config-json -n mft -o yaml
```

**Solution:**

Verify gateway IPs in the secret template and regenerate secrets:

```bash
cd /aio/work/c/iwcd/6o-mft-on-azure-example/03-TechnologyServices/02-AT/helm

# Check template has correct IPs
grep -A 10 "declareGateways" templates/secret-mft-config.yaml.template

# Regenerate secrets and upgrade
helm upgrade active-transfer . --namespace mft --values ibm_values.yaml
```

---

### Issue: High Memory Usage

**Symptom:**
```
Container using more than 1GB memory
```

**Solution:**

Adjust JVM settings in `docker-compose.yml`:

```yaml
environment:
  - JAVA_MIN_MEM=256m   # Reduce from 512m
  - JAVA_MAX_MEM=768m   # Reduce from 1024m
```

Then restart:
```bash
sudo systemctl restart at-gateway.service
```

---

### Issue: Disk Space Issues

**Symptom:**
```
No space left on device
```

**Solution:**

```bash
# Check disk usage
df -h
sudo docker system df

# Clean Docker resources
sudo docker image prune -a
sudo docker volume prune
sudo docker container prune

# Truncate large log files
sudo truncate -s 0 /var/lib/docker/containers/*/\*-json.log
```

---

### Diagnostic Commands Reference

**Quick Health Check:**
```bash
echo "=== Service Status ==="
sudo systemctl status at-gateway.service

echo "=== Container Status ==="
sudo docker ps | grep at-gateway

echo "=== Port Listening ==="
sudo netstat -tlnp | grep 8500

echo "=== Recent Logs ==="
sudo docker logs at-gateway1 --tail 20

echo "=== Memory Usage ==="
sudo docker stats at-gateway1 --no-stream

echo "=== Disk Usage ==="
df -h /opt/at-gateway
```

**Log Collection for Support:**
```bash
mkdir -p /tmp/gateway-logs
sudo journalctl -u at-gateway.service > /tmp/gateway-logs/service.log
sudo docker logs at-gateway1 > /tmp/gateway-logs/container.log
sudo docker inspect at-gateway1 > /tmp/gateway-logs/inspect.json
cp /opt/at-gateway/docker-compose.yml /tmp/gateway-logs/
cp /opt/at-gateway/config/properties.cnf /tmp/gateway-logs/

tar -czf gateway-logs-$(date +%Y%m%d-%H%M%S).tar.gz -C /tmp gateway-logs
```

---

## Security Considerations

1. **Network Security**:
   - Gateways are in public subnets but protected by NSG rules
   - Only specific ports are exposed
   - Internal communication uses private IPs

2. **Authentication**:
   - VMs use managed identity for ACR access
   - No credentials stored in configuration files
   - SSH access restricted to authorized keys

3. **Container Security**:
   - Containers run as non-root user (UID 1724)
   - Read-only configuration mounts
   - Limited resource allocation

4. **Updates**:
   - Keep container images updated
   - Apply VM security patches regularly
   - Monitor for security advisories

---

## Monitoring

### Key Metrics to Monitor

- Container status (running/stopped)
- Memory usage (should stay under 1GB)
- CPU usage
- Network connectivity to AKS
- Disk space in `/opt/at-gateway`
- Gateway connection status in ActiveTransfer Admin UI

### Azure Monitor Integration

Consider setting up:
- VM metrics collection
- Container insights
- Log Analytics workspace
- Alert rules for critical events

---

## Related Documentation

- [Infrastructure Analysis](/.ai-assist/sessions/2026/05/22/03_add_gateways/agent/infrastructure_analysis.md)
- [Azure Pipeline Setup](../../pipelines/azure/GATEWAYS-PIPELINE-SETUP.md)
- [Helm Upgrade Procedure](../02-AT/HELM-UPGRADE.md)
- [IBM ActiveTransfer Gateway Documentation](https://www.ibm.com/docs/en/webmethods-activetransfer/11.1.0?topic=gateway-understanding-activetransfer)

---

## Support

For issues or questions:
1. Check this troubleshooting section
2. Review container and service logs
3. Verify network connectivity
4. Check Azure resource status in portal
5. Consult session documentation in `.ai-assist/sessions/2026/05/22/03_add_gateways/`