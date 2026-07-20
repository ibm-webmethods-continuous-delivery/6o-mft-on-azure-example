# ACR Login Service Setup Guide

## Overview

The `acr-login.service` is a systemd service that automatically authenticates the VM with Azure Container Registry (ACR) using the VM's managed identity. This service is **required** for the ActiveTransfer Gateway deployment to pull container images from ACR.

## Why is this Service Needed?

The ActiveTransfer Gateway runs as a Docker container that needs to be pulled from your private Azure Container Registry. The `acr-login.service`:

- Authenticates the VM with ACR using managed identity (no credentials needed)
- Runs automatically on VM boot
- Ensures Docker can pull images from your private ACR
- Is a dependency for the `at-gateway.service`

## Prerequisites

Before setting up the ACR login service, ensure:

1. **VM has System-Assigned Managed Identity enabled**
2. **VM has AcrPull role assignment on the ACR**
3. **Azure CLI is installed on the VM**
4. **jq (JSON parser) is installed on the VM**

## Checking if ACR Login Service Exists

To check if the service is already installed on your VM:

```bash
# Using Azure VM Run Command
az vm run-command invoke \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${VM_NAME}" \
    --command-id RunShellScript \
    --scripts "systemctl status acr-login.service" \
    --output table

# Or via SSH (if available)
ssh azureuser@<vm-ip>
systemctl status acr-login.service
```

**Expected output if service exists:**
```
● acr-login.service - Login to Azure Container Registry
     Loaded: loaded (/etc/systemd/system/acr-login.service; enabled)
     Active: active (exited) since ...
```

**If service doesn't exist:**
```
Unit acr-login.service could not be found.
```

## Manual Installation

If the `acr-login.service` is not present, follow these steps to install it manually.

### Step 1: Verify Prerequisites

```bash
# Check managed identity is enabled
az vm identity show \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${VM_NAME}"

# Check ACR role assignment
VM_PRINCIPAL_ID=$(az vm identity show -g "${RESOURCE_GROUP}" -n "${VM_NAME}" --query principalId -o tsv)
ACR_ID=$(az acr show -n "${ACR_NAME}" --query id -o tsv)

az role assignment list \
    --assignee "${VM_PRINCIPAL_ID}" \
    --scope "${ACR_ID}" \
    --query "[?roleDefinitionName=='AcrPull']"
```

### Step 2: Install Required Tools

Run this on the VM (via Azure VM Run Command or SSH):

```bash
# Install Azure CLI (if not already installed)
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Install jq for JSON parsing
sudo apt-get update
sudo apt-get install -y jq
```

### Step 3: Create ACR Login Script

Create the login script that will authenticate with ACR:

```bash
sudo tee /usr/local/bin/acr-login.sh > /dev/null << 'EOF'
#!/bin/bash
# ACR Login Script using Managed Identity

# Wait for managed identity to be available
sleep 30

# Get access token using managed identity
TOKEN=$(curl -s 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com/' -H Metadata:true | jq -r .access_token)

if [ -n "$TOKEN" ]; then
    # Login to ACR using managed identity
    az login --identity

    # Replace ACR_NAME with your actual ACR name
    az acr login --name ACR_NAME

    echo "Successfully logged in to ACR: ACR_NAME"
else
    echo "Failed to obtain managed identity token"
    exit 1
fi
EOF

# Make script executable
sudo chmod +x /usr/local/bin/acr-login.sh
```

**Important:** Replace `ACR_NAME` in the script with your actual ACR name (without `.azurecr.io`).

### Step 4: Create Systemd Service

Create the systemd service file:

```bash
sudo tee /etc/systemd/system/acr-login.service > /dev/null << 'EOF'
[Unit]
Description=Login to Azure Container Registry
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/acr-login.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
```

### Step 5: Enable and Start Service

```bash
# Reload systemd to recognize new service
sudo systemctl daemon-reload

# Enable service to start on boot
sudo systemctl enable acr-login.service

# Start service now
sudo systemctl start acr-login.service

# Check service status
sudo systemctl status acr-login.service
```

## Automated Installation via Azure VM Run Command

For convenience, here's a complete script to install the ACR login service using Azure VM Run Command:

```bash
#!/bin/bash
# Install ACR Login Service on Gateway VM

# Set your variables
export RESOURCE_GROUP="rg-mft-dev"
export VM_NAME="vm-mft-gateway1"
export ACR_NAME="acrmftdev"  # Without .azurecr.io

# Create installation script
INSTALL_SCRIPT=$(cat <<'EOF'
#!/bin/bash
set -euo pipefail

ACR_NAME="__ACR_NAME__"

echo "==> Installing Azure CLI..."
curl -sL https://aka.ms/InstallAzureCLIDeb | bash

echo "==> Installing jq..."
apt-get update && apt-get install -y jq

echo "==> Creating ACR login script..."
cat > /usr/local/bin/acr-login.sh << 'SCRIPT_EOF'
#!/bin/bash
sleep 30
TOKEN=$(curl -s 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com/' -H Metadata:true | jq -r .access_token)
if [ -n "$TOKEN" ]; then
    az login --identity
    az acr login --name __ACR_NAME__
    echo "Successfully logged in to ACR: __ACR_NAME__"
else
    echo "Failed to obtain managed identity token"
    exit 1
fi
SCRIPT_EOF

# Replace ACR_NAME placeholder
sed -i "s/__ACR_NAME__/${ACR_NAME}/g" /usr/local/bin/acr-login.sh
chmod +x /usr/local/bin/acr-login.sh

echo "==> Creating systemd service..."
cat > /etc/systemd/system/acr-login.service << 'SERVICE_EOF'
[Unit]
Description=Login to Azure Container Registry
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/acr-login.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE_EOF

echo "==> Enabling and starting service..."
systemctl daemon-reload
systemctl enable acr-login.service
systemctl start acr-login.service

echo "==> Checking service status..."
systemctl status acr-login.service --no-pager

echo "==> ACR login service installation complete!"
EOF
)

# Replace ACR_NAME placeholder
INSTALL_SCRIPT="${INSTALL_SCRIPT//__ACR_NAME__/${ACR_NAME}}"

# Execute on VM
az vm run-command invoke \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${VM_NAME}" \
    --command-id RunShellScript \
    --scripts "${INSTALL_SCRIPT}" \
    --output table
```

Save this as `install-acr-login-service.sh` and run it for each gateway VM.

## Verification

After installation, verify the service is working:

```bash
# Check service status
az vm run-command invoke \
    -g "${RESOURCE_GROUP}" \
    -n "${VM_NAME}" \
    --command-id RunShellScript \
    --scripts "systemctl status acr-login.service" \
    --output table

# Check service logs
az vm run-command invoke \
    -g "${RESOURCE_GROUP}" \
    -n "${VM_NAME}" \
    --command-id RunShellScript \
    --scripts "journalctl -u acr-login.service -n 50" \
    --output table

# Test Docker can pull from ACR
az vm run-command invoke \
    -g "${RESOURCE_GROUP}" \
    -n "${VM_NAME}" \
    --command-id RunShellScript \
    --scripts "docker pull ${ACR_LOGIN_SERVER}/active-transfer-enhance:latest" \
    --output table
```

## Troubleshooting

### Issue: Service Fails to Start

**Symptoms:**
```
acr-login.service: Failed with result 'exit-code'
```

**Solutions:**

1. **Check managed identity is assigned:**
   ```bash
   az vm identity show -g "${RESOURCE_GROUP}" -n "${VM_NAME}"
   ```

2. **Verify ACR role assignment:**
   ```bash
   VM_PRINCIPAL_ID=$(az vm identity show -g "${RESOURCE_GROUP}" -n "${VM_NAME}" --query principalId -o tsv)
   az role assignment list --assignee "${VM_PRINCIPAL_ID}"
   ```

3. **Check service logs:**
   ```bash
   az vm run-command invoke \
       -g "${RESOURCE_GROUP}" \
       -n "${VM_NAME}" \
       --command-id RunShellScript \
       --scripts "journalctl -u acr-login.service -n 100" \
       --output table
   ```

### Issue: "Failed to obtain managed identity token"

**Cause:** Managed identity not properly configured or not yet available.

**Solutions:**

1. **Wait longer for identity to be available:**
   Edit `/usr/local/bin/acr-login.sh` and increase sleep time:
   ```bash
   sleep 60  # Increase from 30 to 60 seconds
   ```

2. **Manually test identity endpoint:**
   ```bash
   curl -s 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com/' -H Metadata:true
   ```

### Issue: "az acr login" fails

**Symptoms:**
```
You may not have access to the container registry
```

**Solutions:**

1. **Assign AcrPull role to VM:**
   ```bash
   VM_PRINCIPAL_ID=$(az vm identity show -g "${RESOURCE_GROUP}" -n "${VM_NAME}" --query principalId -o tsv)
   ACR_ID=$(az acr show -n "${ACR_NAME}" --query id -o tsv)

   az role assignment create \
       --assignee "${VM_PRINCIPAL_ID}" \
       --role "AcrPull" \
       --scope "${ACR_ID}"
   ```

2. **Wait a few minutes for role assignment to propagate**, then restart service:
   ```bash
   az vm run-command invoke \
       -g "${RESOURCE_GROUP}" \
       -n "${VM_NAME}" \
       --command-id RunShellScript \
       --scripts "systemctl restart acr-login.service" \
       --output table
   ```

## Integration with Gateway Deployment

The `at-gateway.service` depends on `acr-login.service`:

```systemd
[Unit]
Description=ActiveTransfer Gateway Service
After=docker.service acr-login.service
Requires=docker.service
Wants=acr-login.service
```

This ensures:
- ACR authentication happens before gateway starts
- Gateway can pull container images successfully
- Proper startup order is maintained

## Automatic Setup via Terraform

The ACR login service is automatically installed when VMs are provisioned via Terraform using the `install-docker.sh` cloud-init script. This happens when:

1. VM is created with `enable_sftp_vm_acr_role = true` in Terraform
2. Cloud-init script runs during VM provisioning
3. Service is automatically enabled and started

**Location:** `01-AzurePrerequisites/02-ServiceFulfillment/scripts/install-docker.sh`

If you're deploying VMs via Terraform, the service should already be present. Only manual installation is needed if:
- VMs were created without the cloud-init script
- Service was accidentally removed
- You're troubleshooting authentication issues

## Related Documentation

- [Gateway Deployment README](./README.md)
- [VM Run Command Deployment Guide](./DEPLOYMENT-VM-RUN-COMMAND.md)
- [Troubleshooting Guide](./TROUBLESHOOTING.md)
- [Terraform Infrastructure](../../01-AzurePrerequisites/02-ServiceFulfillment/)

## Summary

The `acr-login.service` is a critical component that:
- ✅ Authenticates VMs with ACR using managed identity
- ✅ Runs automatically on boot
- ✅ Enables Docker to pull private container images
- ✅ Is required for gateway deployment

If the service is missing, use the automated installation script provided in this guide to deploy it quickly via Azure VM Run Command.