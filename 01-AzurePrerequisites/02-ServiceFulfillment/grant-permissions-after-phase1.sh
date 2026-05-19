#!/bin/bash
# ============================================================================
# Grant Permissions After Phase 1
# ============================================================================
# This script grants the necessary role assignments that require elevated
# permissions (User Access Administrator or Owner). Run this in Azure Cloud
# Shell after Phase 1 Terraform deployment completes.
#
# Prerequisites:
# - Phase 1 Terraform deployment completed successfully
# - You have User Access Administrator or Owner permissions on the subscription
# - Azure CLI is authenticated (automatic in Cloud Shell)
#
# Usage:
#   ./grant-permissions-after-phase1.sh

set -euo pipefail

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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
print_info "Checking prerequisites..."

if ! command_exists az; then
    print_error "Azure CLI (az) is not installed or not in PATH"
    exit 1
fi

if ! command_exists jq; then
    print_error "jq is not installed. Please install it: sudo apt-get install jq"
    exit 1
fi

# Check if we're authenticated
if ! az account show >/dev/null 2>&1; then
    print_error "Not authenticated to Azure. Please run 'az login' first."
    exit 1
fi

print_success "Prerequisites check passed"

# Extract values from Terraform outputs
print_info "Extracting resource IDs from Terraform outputs..."

if [ ! -f "terraform.tfstate" ]; then
    print_error "terraform.tfstate not found. Please run this script from the Terraform directory."
    exit 1
fi

# Extract AGIC identity details
AGIC_IDENTITY_ID=$(terraform output -raw agic_identity_id 2>/dev/null || echo "")
AGIC_PRINCIPAL_ID=$(terraform output -raw agic_identity_principal_id 2>/dev/null || echo "")

# Extract Application Gateway ID
APP_GATEWAY_ID=$(terraform output -raw app_gateway_id 2>/dev/null || echo "")

# Extract Resource Group ID
RESOURCE_GROUP_ID=$(terraform output -raw resource_group_id 2>/dev/null || echo "")

# Extract AKS kubelet identity
AKS_KUBELET_OBJECT_ID=$(terraform output -raw aks_kubelet_identity_object_id 2>/dev/null || echo "")

# Extract ACR ID
ACR_ID=$(terraform output -raw acr_id 2>/dev/null || echo "")

# Extract AKS identity
AKS_IDENTITY_PRINCIPAL_ID=$(terraform output -raw aks_identity_principal_id 2>/dev/null || echo "")

# Extract SFTP VM identities
SFTP_VM_1_PRINCIPAL_ID=$(terraform output -raw sftp_vm_1_identity_principal_id 2>/dev/null || echo "")
SFTP_VM_2_PRINCIPAL_ID=$(terraform output -raw sftp_vm_2_identity_principal_id 2>/dev/null || echo "")

# Validate required values
print_info "Validating extracted values..."

if [ -z "$AGIC_IDENTITY_ID" ] || [ -z "$AGIC_PRINCIPAL_ID" ]; then
    print_error "Failed to extract AGIC identity information from Terraform outputs"
    exit 1
fi

if [ -z "$APP_GATEWAY_ID" ]; then
    print_error "Failed to extract Application Gateway ID from Terraform outputs"
    exit 1
fi

if [ -z "$RESOURCE_GROUP_ID" ]; then
    print_error "Failed to extract Resource Group ID from Terraform outputs"
    exit 1
fi

if [ -z "$AKS_KUBELET_OBJECT_ID" ]; then
    print_error "Failed to extract AKS kubelet identity from Terraform outputs"
    exit 1
fi

print_success "All required values extracted successfully"

# Display what will be done
echo ""
print_info "The following role assignments will be created:"
echo "  1. AGIC Identity -> Contributor on Application Gateway"
echo "  2. AGIC Identity -> Reader on Resource Group"
echo "  3. AKS Kubelet Identity -> Managed Identity Operator on AGIC Identity"

if [ -n "$ACR_ID" ] && [ -n "$AKS_IDENTITY_PRINCIPAL_ID" ]; then
    echo "  4. AKS Identity -> AcrPull on Container Registry"
fi

if [ -n "$ACR_ID" ] && [ -n "$SFTP_VM_1_PRINCIPAL_ID" ]; then
    echo "  5. SFTP VM 1 Identity -> AcrPull on Container Registry"
fi

if [ -n "$ACR_ID" ] && [ -n "$SFTP_VM_2_PRINCIPAL_ID" ]; then
    echo "  6. SFTP VM 2 Identity -> AcrPull on Container Registry"
fi

echo ""
read -p "Do you want to proceed? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    print_warning "Operation cancelled by user"
    exit 0
fi

# Function to create role assignment with retry
create_role_assignment() {
    local scope=$1
    local role=$2
    local principal_id=$3
    local description=$4
    local max_retries=3
    local retry_count=0

    print_info "Creating role assignment: $description"

    while [ $retry_count -lt $max_retries ]; do
        if az role assignment create \
            --role "$role" \
            --assignee-object-id "$principal_id" \
            --assignee-principal-type ServicePrincipal \
            --scope "$scope" \
            --output none 2>/dev/null; then
            print_success "$description - Role assignment created"
            return 0
        else
            # Check if assignment already exists
            if az role assignment list \
                --assignee "$principal_id" \
                --scope "$scope" \
                --role "$role" \
                --output json | jq -e 'length > 0' >/dev/null 2>&1; then
                print_warning "$description - Role assignment already exists"
                return 0
            fi

            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                print_warning "$description - Attempt $retry_count failed, retrying in 5 seconds..."
                sleep 5
            fi
        fi
    done

    print_error "$description - Failed after $max_retries attempts"
    return 1
}

# Create role assignments
echo ""
print_info "Creating role assignments..."

# 1. AGIC Identity -> Contributor on Application Gateway
create_role_assignment \
    "$APP_GATEWAY_ID" \
    "Contributor" \
    "$AGIC_PRINCIPAL_ID" \
    "AGIC Identity -> Contributor on Application Gateway"

# 2. AGIC Identity -> Reader on Resource Group
create_role_assignment \
    "$RESOURCE_GROUP_ID" \
    "Reader" \
    "$AGIC_PRINCIPAL_ID" \
    "AGIC Identity -> Reader on Resource Group"

# 3. AKS Kubelet Identity -> Managed Identity Operator on AGIC Identity
create_role_assignment \
    "$AGIC_IDENTITY_ID" \
    "Managed Identity Operator" \
    "$AKS_KUBELET_OBJECT_ID" \
    "AKS Kubelet Identity -> Managed Identity Operator on AGIC Identity"

# 4. AKS Identity -> AcrPull on Container Registry (if ACR exists)
if [ -n "$ACR_ID" ] && [ -n "$AKS_IDENTITY_PRINCIPAL_ID" ]; then
    create_role_assignment \
        "$ACR_ID" \
        "AcrPull" \
        "$AKS_IDENTITY_PRINCIPAL_ID" \
        "AKS Identity -> AcrPull on Container Registry"
fi

# 5. SFTP VM 1 Identity -> AcrPull on Container Registry (if ACR exists)
if [ -n "$ACR_ID" ] && [ -n "$SFTP_VM_1_PRINCIPAL_ID" ]; then
    create_role_assignment \
        "$ACR_ID" \
        "AcrPull" \
        "$SFTP_VM_1_PRINCIPAL_ID" \
        "SFTP VM 1 Identity -> AcrPull on Container Registry"
fi

# 6. SFTP VM 2 Identity -> AcrPull on Container Registry (if ACR exists)
if [ -n "$ACR_ID" ] && [ -n "$SFTP_VM_2_PRINCIPAL_ID" ]; then
    create_role_assignment \
        "$ACR_ID" \
        "AcrPull" \
        "$SFTP_VM_2_PRINCIPAL_ID" \
        "SFTP VM 2 Identity -> AcrPull on Container Registry"
fi

echo ""
print_success "All role assignments completed successfully!"
echo ""
print_info "Next steps:"
echo "  1. Wait 2-3 minutes for role assignments to propagate"
echo "  2. Run Phase 2 Terraform deployment:"
echo "     terraform apply -var-file=common.tfvars -var-file=phase2.tfvars"
echo ""
