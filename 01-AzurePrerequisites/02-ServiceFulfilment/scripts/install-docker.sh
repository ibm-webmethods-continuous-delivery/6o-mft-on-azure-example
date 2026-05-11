#!/bin/bash
set -e

# Update system packages
apt-get update
apt-get upgrade -y

# Install prerequisites
apt-get install -y \
    apt-transport-https \
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
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Start and enable Docker service
systemctl start docker
systemctl enable docker

# Add azureuser to docker group
usermod -aG docker azureuser

# Install Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Login to ACR using managed identity
# This will be executed after the VM is fully provisioned and identity is assigned
cat > /usr/local/bin/acr-login.sh << 'EOF'
#!/bin/bash
# Wait for managed identity to be available
sleep 30

# Get access token using managed identity
TOKEN=$(curl -s 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com/' -H Metadata:true | jq -r .access_token)

if [ -n "$TOKEN" ]; then
    # Login to ACR using managed identity
    az login --identity
    az acr login --name ${acr_name}
    echo "Successfully logged in to ACR: ${acr_name}"
else
    echo "Failed to obtain managed identity token"
    exit 1
fi
EOF

chmod +x /usr/local/bin/acr-login.sh

# Create systemd service to run ACR login on boot
cat > /etc/systemd/system/acr-login.service << 'EOF'
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

# Enable the service
systemctl daemon-reload
systemctl enable acr-login.service

# Install jq for JSON parsing
apt-get install -y jq

# Create directory for docker compose files
mkdir -p /opt/sftp
chown azureuser:azureuser /opt/sftp

# Create a sample docker-compose.yml for SFTP service
cat > /opt/sftp/docker-compose.yml << 'EOF'
version: '3.8'

services:
  sftp:
    image: atmoz/sftp:latest
    ports:
      - "55022:22"
    volumes:
      - sftp-data:/home
    command: user:pass:1001
    restart: unless-stopped

volumes:
  sftp-data:
EOF

chown azureuser:azureuser /opt/sftp/docker-compose.yml

# Create a systemd service to start SFTP container on boot
cat > /etc/systemd/system/sftp-service.service << 'EOF'
[Unit]
Description=SFTP Docker Compose Service
Requires=docker.service acr-login.service
After=docker.service acr-login.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/sftp
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Enable the SFTP service
systemctl daemon-reload
systemctl enable sftp-service.service

# Log completion
echo "Docker and Docker Compose installation completed successfully" | tee /var/log/docker-install.log
echo "ACR login service configured for: ${acr_name}" | tee -a /var/log/docker-install.log
