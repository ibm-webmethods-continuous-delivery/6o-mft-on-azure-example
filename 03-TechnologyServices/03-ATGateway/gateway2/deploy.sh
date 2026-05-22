#!/bin/bash
# Deploy ActiveTransfer Gateway 2 to Azure VM
# Run this script on the Gateway VM (10.1.1.4)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="/opt/at-gateway"
SERVICE_NAME="at-gateway.service"

echo "=== ActiveTransfer Gateway 2 Deployment ==="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

# Check if docker is installed
if ! command -v docker &> /dev/null; then
    echo "ERROR: Docker is not installed"
    exit 1
fi

# Check if docker-compose is installed
if ! command -v docker compose &> /dev/null; then
    echo "ERROR: docker compose is not installed"
    exit 1
fi

echo "Step 1: Creating deployment directory..."
mkdir -p "$DEPLOY_DIR"
mkdir -p "$DEPLOY_DIR/config"

echo "Step 2: Copying docker-compose.yml..."
cp "$SCRIPT_DIR/docker-compose.yml" "$DEPLOY_DIR/"

echo "Step 3: Copying configuration files..."
cp "$SCRIPT_DIR/config/properties.cnf" "$DEPLOY_DIR/config/"

echo "Step 4: Creating .env file..."
# Get ACR login server from Azure metadata or environment
if [ -z "${ACR_LOGIN_SERVER:-}" ]; then
    echo "WARNING: ACR_LOGIN_SERVER not set in environment"
    echo "Please provide the ACR login server (e.g., myacr.azurecr.io):"
    read -r ACR_LOGIN_SERVER
fi

cat > "$DEPLOY_DIR/.env" << EOF
ACR_LOGIN_SERVER=${ACR_LOGIN_SERVER}
EOF

echo "Step 5: Setting permissions..."
chmod 644 "$DEPLOY_DIR/docker-compose.yml"
chmod 644 "$DEPLOY_DIR/config/properties.cnf"
chmod 600 "$DEPLOY_DIR/.env"

echo "Step 6: Installing systemd service..."
cp "$SCRIPT_DIR/$SERVICE_NAME" "/etc/systemd/system/"
chmod 644 "/etc/systemd/system/$SERVICE_NAME"

echo "Step 7: Reloading systemd..."
systemctl daemon-reload

echo "Step 8: Enabling service..."
systemctl enable "$SERVICE_NAME"

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "To start the gateway:"
echo "  sudo systemctl start $SERVICE_NAME"
echo ""
echo "To check status:"
echo "  sudo systemctl status $SERVICE_NAME"
echo ""
echo "To view logs:"
echo "  sudo docker logs at-gateway2 -f"
echo ""
echo "Gateway will be available on:"
echo "  - Port 8500 (primary)"
echo "  - Port 8501 (secondary)"
echo ""
