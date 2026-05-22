#!/usr/bin/env bash
#
# Deploy ActiveTransfer Gateway 2 using Azure VM Run Command
# This script uses Azure CLI to deploy the gateway without requiring SSH access or public IPs
#
# Prerequisites:
# - Azure CLI installed and authenticated (az login)
# - Appropriate permissions to run commands on the VM
# - ACR_LOGIN_SERVER environment variable set
#
# Usage:
#   export ACR_LOGIN_SERVER=<your-acr>.azurecr.io
#   export RESOURCE_GROUP=<your-resource-group>
#   export VM_NAME=<gateway2-vm-name>
#   ./deploy-gateway2-vm-run-command.sh

set -euo pipefail

# Configuration
RESOURCE_GROUP="${RESOURCE_GROUP:-}"
VM_NAME="${VM_NAME:-}"
ACR_LOGIN_SERVER="${ACR_LOGIN_SERVER:-}"

# Validate required variables
if [[ -z "${RESOURCE_GROUP}" ]]; then
    echo "ERROR: RESOURCE_GROUP environment variable is required"
    echo "Usage: export RESOURCE_GROUP=<your-resource-group>"
    exit 1
fi

if [[ -z "${VM_NAME}" ]]; then
    echo "ERROR: VM_NAME environment variable is required"
    echo "Usage: export VM_NAME=<gateway2-vm-name>"
    exit 1
fi

if [[ -z "${ACR_LOGIN_SERVER}" ]]; then
    echo "ERROR: ACR_LOGIN_SERVER environment variable is required"
    echo "Usage: export ACR_LOGIN_SERVER=<your-acr>.azurecr.io"
    exit 1
fi

echo "=========================================="
echo "Deploying ActiveTransfer Gateway 2"
echo "=========================================="
echo "Resource Group: ${RESOURCE_GROUP}"
echo "VM Name: ${VM_NAME}"
echo "ACR: ${ACR_LOGIN_SERVER}"
echo ""

# Create deployment script that will run on the VM
DEPLOYMENT_SCRIPT=$(cat <<'EOF'
#!/bin/bash
set -euo pipefail

ACR_LOGIN_SERVER="__ACR_LOGIN_SERVER__"
DEPLOY_DIR="/opt/at-gateway"
SERVICE_NAME="at-gateway"

echo "==> Creating deployment directory..."
mkdir -p "${DEPLOY_DIR}"/{config,data,logs}

echo "==> Creating docker-compose.yml..."
cat > "${DEPLOY_DIR}/docker-compose.yml" <<'COMPOSE_EOF'
version: '3.8'

services:
  at-gateway2:
    image: ${ACR_LOGIN_SERVER}/active-transfer-enhance:latest
    container_name: at-gateway2
    hostname: gateway2
    restart: unless-stopped
    ports:
      - "8500:8500"
      - "8501:8501"
    volumes:
      - ./config/properties.cnf:/opt/softwareag/IntegrationServer/instances/default/packages/WmMFT/config/properties.cnf:ro
      - ./logs:/opt/softwareag/IntegrationServer/instances/default/logs
    environment:
      - MFT_SERVER_RUNTIME_MODE=Gateway
      - JAVA_MIN_MEM=512m
      - JAVA_MAX_MEM=1024m
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8500/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
COMPOSE_EOF

echo "==> Creating gateway configuration..."
cat > "${DEPLOY_DIR}/config/properties.cnf" <<'CONFIG_EOF'
# ActiveTransfer Gateway Configuration
# Gateway 2 - Azure Deployment

# REQUIRED: Set runtime mode to Gateway
mft.server.runtime.mode=Gateway

# Gateway server port (default: 8500)
# The next port (8501) is also used automatically
mft.gatewayServer.port=8500

# Server identification
mft.server.id=Gateway2-Azure
mft.server.name=Gateway2-Azure

# Accept connections from any IP (internal network only via NSG)
mft.gatewayServer.accept.ip.list=

# Logging configuration
mft.server.log.level=INFO
mft.server.log.dir=/opt/softwareag/IntegrationServer/instances/default/logs

# Performance tuning
mft.server.thread.pool.size=50
mft.server.connection.timeout=300000

# Health check endpoint
mft.server.health.check.enabled=true
CONFIG_EOF

echo "==> Creating .env file..."
cat > "${DEPLOY_DIR}/.env" <<ENV_EOF
ACR_LOGIN_SERVER=${ACR_LOGIN_SERVER}
ENV_EOF

echo "==> Setting permissions..."
chown -R root:root "${DEPLOY_DIR}"
chmod 755 "${DEPLOY_DIR}"
chmod 644 "${DEPLOY_DIR}/docker-compose.yml"
chmod 644 "${DEPLOY_DIR}/config/properties.cnf"
chmod 644 "${DEPLOY_DIR}/.env"

# Set ownership of logs directory to container user (UID 1724)
# This allows the Integration Server running inside the container to write logs
chown -R 1724:1724 "${DEPLOY_DIR}/logs"
chmod 755 "${DEPLOY_DIR}/logs"

echo "==> Creating systemd service..."
cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<'SERVICE_EOF'
[Unit]
Description=ActiveTransfer Gateway Service
After=docker.service acr-login.service
Requires=docker.service
Wants=acr-login.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/at-gateway
EnvironmentFile=/opt/at-gateway/.env

# Pull latest image before starting
ExecStartPre=/usr/bin/docker compose pull

# Start the service
ExecStart=/usr/bin/docker compose up -d

# Stop the service
ExecStop=/usr/bin/docker compose down

# Reload configuration
ExecReload=/usr/bin/docker compose restart

[Install]
WantedBy=multi-user.target
SERVICE_EOF

echo "==> Reloading systemd..."
systemctl daemon-reload

echo "==> Enabling service..."
systemctl enable "${SERVICE_NAME}.service"

echo "==> Starting service..."
systemctl start "${SERVICE_NAME}.service"

echo "==> Waiting for service to start..."
sleep 10

echo "==> Checking service status..."
systemctl status "${SERVICE_NAME}.service" --no-pager || true

echo "==> Checking container status..."
docker ps | grep at-gateway2 || true

echo "==> Checking container logs (last 20 lines)..."
docker logs at-gateway2 --tail 20 || true

echo ""
echo "=========================================="
echo "Gateway 2 deployment completed!"
echo "=========================================="
echo ""
echo "To check status:"
echo "  systemctl status ${SERVICE_NAME}.service"
echo ""
echo "To view logs:"
echo "  docker logs at-gateway2 -f"
echo ""
echo "To restart:"
echo "  systemctl restart ${SERVICE_NAME}.service"
echo ""
EOF
)

# Replace placeholder with actual ACR value
DEPLOYMENT_SCRIPT="${DEPLOYMENT_SCRIPT//__ACR_LOGIN_SERVER__/${ACR_LOGIN_SERVER}}"

echo "==> Running deployment script on VM..."
echo ""

# Execute the script on the VM using Azure VM Run Command
az vm run-command invoke \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${VM_NAME}" \
    --command-id RunShellScript \
    --scripts "${DEPLOYMENT_SCRIPT}" \
    --output table

echo ""
echo "=========================================="
echo "Deployment command sent successfully!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Verify gateway is running:"
echo "   az vm run-command invoke -g ${RESOURCE_GROUP} -n ${VM_NAME} --command-id RunShellScript --scripts 'systemctl status at-gateway.service'"
echo ""
echo "2. Check container logs:"
echo "   az vm run-command invoke -g ${RESOURCE_GROUP} -n ${VM_NAME} --command-id RunShellScript --scripts 'docker logs at-gateway2 --tail 50'"
echo ""
echo "3. Test connectivity from AKS:"
echo "   kubectl run test-gateway --image=busybox --rm -it --restart=Never -n mft -- nc -zv 10.1.1.4 8500"
echo ""
