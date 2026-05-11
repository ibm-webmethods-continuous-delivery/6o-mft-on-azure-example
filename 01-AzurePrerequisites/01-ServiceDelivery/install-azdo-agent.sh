#!/bin/bash
set -e

# Azure DevOps Agent Installation Script
# This script installs and configures an Azure DevOps agent on Ubuntu

# Parameters (passed via Terraform template)
AZDO_URL="${azdo_url}"
AZDO_PAT="${azdo_pat}"
AZDO_POOL="${azdo_pool}"
AGENT_NAME="${agent_name_prefix}-$(hostname)"

echo "Starting Azure DevOps agent installation..."
echo "Organization URL: $AZDO_URL"
echo "Agent Pool: $AZDO_POOL"
echo "Agent Name: $AGENT_NAME"

# Install dependencies
echo "Installing dependencies..."
apt-get update
apt-get install -y curl jq libicu70 git

# Create agent directory
AGENT_DIR="/opt/azdo-agent"
mkdir -p "$AGENT_DIR"
cd "$AGENT_DIR"

# Download the latest agent
echo "Downloading Azure DevOps agent..."
AGENT_VERSION=$(curl -s https://api.github.com/repos/microsoft/azure-pipelines-agent/releases/latest | jq -r '.tag_name' | sed 's/v//')
AGENT_URL="https://vstsagentpackage.azureedge.net/agent/$${AGENT_VERSION}/vsts-agent-linux-x64-$${AGENT_VERSION}.tar.gz"

curl -L -o agent.tar.gz "$AGENT_URL"
tar xzf agent.tar.gz
rm agent.tar.gz

# Install dependencies for the agent
./bin/installdependencies.sh

# Configure the agent
echo "Configuring Azure DevOps agent..."
./config.sh \
  --unattended \
  --url "$AZDO_URL" \
  --auth pat \
  --token "$AZDO_PAT" \
  --pool "$AZDO_POOL" \
  --agent "$AGENT_NAME" \
  --replace \
  --acceptTeeEula

# Install and start the agent as a service
echo "Installing agent as systemd service..."
./svc.sh install
./svc.sh start

echo "Azure DevOps agent installation completed successfully!"
echo "Agent '$AGENT_NAME' is now running in pool '$AZDO_POOL'"