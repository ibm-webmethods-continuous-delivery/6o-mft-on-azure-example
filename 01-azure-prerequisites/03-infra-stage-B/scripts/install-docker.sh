#!/bin/bash
# Script to install Docker on Ubuntu and configure ACR access
# This script is executed via cloud-init on SFTP VMs

set -e

ACR_NAME="${acr_name}"

# Update package list
apt-get update

# Install prerequisites
apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# Add Docker's official GPG key
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Set up Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Start and enable Docker service
systemctl start docker
systemctl enable docker

# Add azureuser to docker group
usermod -aG docker azureuser

# Configure ACR authentication using managed identity
# The VM's system-assigned managed identity will be used for ACR pull
# This requires the AcrPull role assignment to be configured in Terraform

# Create a script to login to ACR using managed identity
cat > /usr/local/bin/acr-login.sh << EOF
#!/bin/bash
# Login to ACR using managed identity
az acr login --name $ACR_NAME --identity
EOF

chmod +x /usr/local/bin/acr-login.sh

# Install Azure CLI for ACR authentication
curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Note: The actual ACR login will be performed when needed
# The managed identity must have AcrPull role on the ACR

echo "Docker installation complete. ACR: $ACR_NAME"
