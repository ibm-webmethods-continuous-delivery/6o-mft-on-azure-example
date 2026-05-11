#!/bin/bash

################################################################################
# Azure Prerequisites Setup Script
#
# This script creates the necessary Azure resources for MFT deployment:
# 1. Resource Group in specified region
# 2. Service Principal with client secret
# 3. Contributor role assignment for SP on the Resource Group
#
# Usage:
#   ./setup-azure-prerequisites.sh
#
# The script will prompt for required parameters or you can set them as
# environment variables before running.
################################################################################

set -e  # Exit on error
set -u  # Exit on undefined variable

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to prompt for input with default value
prompt_with_default() {
    local prompt_message=$1
    local default_value=$2
    local var_name=$3

    read -p "$(echo -e ${BLUE}${prompt_message}${NC} [${default_value}]: )" input_value
    eval ${var_name}="${input_value:-$default_value}"
}

# Banner
echo "================================================================================"
echo "  Azure Prerequisites Setup for MFT Deployment"
echo "================================================================================"
echo ""

# Check if Azure CLI is available
if ! command -v az &> /dev/null; then
    print_error "Azure CLI is not installed or not in PATH"
    exit 1
fi

# Check if logged in to Azure
print_info "Checking Azure login status..."
if ! az account show &> /dev/null; then
    print_error "Not logged in to Azure. Please run 'az login' first."
    exit 1
fi

# Get current subscription
CURRENT_SUBSCRIPTION=$(az account show --query name -o tsv)
CURRENT_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
print_success "Logged in to Azure subscription: ${CURRENT_SUBSCRIPTION} (${CURRENT_SUBSCRIPTION_ID})"
echo ""

# Prompt for parameters
print_info "Please provide the following information:"
echo ""

# Resource Group Name
prompt_with_default "Resource Group Name" "rg-mft-prod" "RESOURCE_GROUP_NAME"

# Region/Location
prompt_with_default "Azure Region" "westeurope" "LOCATION"

# Service Principal Name
prompt_with_default "Service Principal Name" "sp-mft-deployment" "SP_NAME"

# Service Principal Display Name (optional, defaults to SP_NAME)
SP_DISPLAY_NAME="${SP_NAME}"

echo ""
print_info "Configuration Summary:"
echo "  Resource Group: ${RESOURCE_GROUP_NAME}"
echo "  Location: ${LOCATION}"
echo "  Service Principal: ${SP_NAME}"
echo "  Subscription: ${CURRENT_SUBSCRIPTION}"
echo ""

# Confirm before proceeding
read -p "$(echo -e ${YELLOW}Do you want to proceed? [y/N]:${NC} )" -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Operation cancelled by user"
    exit 0
fi

echo ""
print_info "Starting Azure resource creation..."
echo ""

################################################################################
# Step 1: Create Resource Group
################################################################################
print_info "Step 1/3: Creating Resource Group '${RESOURCE_GROUP_NAME}' in '${LOCATION}'..."

if az group show --name "${RESOURCE_GROUP_NAME}" &> /dev/null; then
    print_warning "Resource Group '${RESOURCE_GROUP_NAME}' already exists"
else
    az group create \
        --name "${RESOURCE_GROUP_NAME}" \
        --location "${LOCATION}" \
        --output none

    print_success "Resource Group '${RESOURCE_GROUP_NAME}' created successfully"
fi

# Get Resource Group ID
RG_ID=$(az group show --name "${RESOURCE_GROUP_NAME}" --query id -o tsv)
print_info "Resource Group ID: ${RG_ID}"
echo ""

################################################################################
# Step 2: Create Service Principal
################################################################################
print_info "Step 2/3: Creating Service Principal '${SP_NAME}'..."

# Check if SP already exists
EXISTING_SP=$(az ad sp list --display-name "${SP_DISPLAY_NAME}" --query "[0].appId" -o tsv 2>/dev/null || echo "")

if [ -n "${EXISTING_SP}" ]; then
    print_warning "Service Principal '${SP_NAME}' already exists with App ID: ${EXISTING_SP}"
    print_warning "Using existing Service Principal. If you need a new secret, you'll need to create it manually."
    SP_APP_ID="${EXISTING_SP}"
    SP_PASSWORD="<existing-secret-not-retrieved>"
else
    # Create Service Principal with secret
    print_info "Creating new Service Principal..."

    SP_OUTPUT=$(az ad sp create-for-rbac \
        --name "${SP_NAME}" \
        --skip-assignment \
        --output json)

    SP_APP_ID=$(echo "${SP_OUTPUT}" | jq -r '.appId')
    SP_PASSWORD=$(echo "${SP_OUTPUT}" | jq -r '.password')
    SP_TENANT=$(echo "${SP_OUTPUT}" | jq -r '.tenant')

    print_success "Service Principal created successfully"
    print_info "App ID (Client ID): ${SP_APP_ID}"
    print_info "Tenant ID: ${SP_TENANT}"
fi

echo ""

################################################################################
# Step 3: Assign Contributor Role
################################################################################
print_info "Step 3/3: Assigning Contributor role to Service Principal on Resource Group..."

# Wait a bit for SP to propagate in Azure AD
print_info "Waiting for Service Principal to propagate in Azure AD (15 seconds)..."
sleep 15

# Assign Contributor role
MAX_RETRIES=3
RETRY_COUNT=0

while [ ${RETRY_COUNT} -lt ${MAX_RETRIES} ]; do
    if az role assignment create \
        --assignee "${SP_APP_ID}" \
        --role "Contributor" \
        --scope "${RG_ID}" \
        --output none 2>/dev/null; then
        print_success "Contributor role assigned successfully"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ ${RETRY_COUNT} -lt ${MAX_RETRIES} ]; then
            print_warning "Role assignment failed, retrying in 10 seconds... (Attempt ${RETRY_COUNT}/${MAX_RETRIES})"
            sleep 10
        else
            print_error "Failed to assign role after ${MAX_RETRIES} attempts"
            print_warning "You may need to assign the role manually using:"
            echo "  az role assignment create --assignee ${SP_APP_ID} --role Contributor --scope ${RG_ID}"
        fi
    fi
done

echo ""
echo "================================================================================"
print_success "Azure Prerequisites Setup Complete!"
echo "================================================================================"
echo ""
print_info "Resource Details:"
echo "  Subscription ID:    ${CURRENT_SUBSCRIPTION_ID}"
echo "  Resource Group:     ${RESOURCE_GROUP_NAME}"
echo "  Location:           ${LOCATION}"
echo "  Resource Group ID:  ${RG_ID}"
echo ""
print_info "Service Principal Details:"
echo "  Display Name:       ${SP_DISPLAY_NAME}"
echo "  Application ID:     ${SP_APP_ID}"
echo "  Tenant ID:          ${SP_TENANT:-$(az account show --query tenantId -o tsv)}"

if [ "${SP_PASSWORD}" != "<existing-secret-not-retrieved>" ]; then
    echo ""
    print_warning "IMPORTANT: Save the following secret securely!"
    echo "  Client Secret:      ${SP_PASSWORD}"
    echo ""
    print_warning "This secret will not be shown again!"
fi

echo ""
print_info "You can verify the role assignment with:"
echo "  az role assignment list --assignee ${SP_APP_ID} --scope ${RG_ID} --output table"
echo ""
print_info "To use this Service Principal for authentication:"
echo "  az login --service-principal -u ${SP_APP_ID} -p <secret> --tenant ${SP_TENANT:-$(az account show --query tenantId -o tsv)}"
echo ""
echo "================================================================================"

# Made with Bob
