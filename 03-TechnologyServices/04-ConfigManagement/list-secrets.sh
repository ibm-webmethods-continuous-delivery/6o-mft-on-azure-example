#!/bin/sh
# List MFT secrets in Azure Key Vault
# Usage: ./list-secrets.sh [environment]

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="${SCRIPT_DIR}/../../01-AzurePrerequisites/02-ServiceFulfillment"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    printf "${BLUE}ℹ${NC} %s\n" "$1"
}

print_success() {
    printf "${GREEN}✓${NC} %s\n" "$1"
}

print_error() {
    printf "${RED}✗${NC} %s\n" "$1"
}

print_warning() {
    printf "${YELLOW}⚠${NC} %s\n" "$1"
}

# Check if Azure CLI is available
if ! command -v az >/dev/null 2>&1; then
    print_error "Azure CLI not found. Please install Azure CLI."
    exit 1
fi

# Check if logged in
if ! az account show >/dev/null 2>&1; then
    print_error "Not logged in to Azure. Please run: az login"
    exit 1
fi

# Get environment from argument or Terraform
if [ -n "$1" ]; then
    ENVIRONMENT="$1"
else
    if [ -d "$TF_DIR" ]; then
        cd "$TF_DIR" || exit 1
        ENVIRONMENT=$(terraform output -raw environment_name 2>/dev/null || echo "vanilla")
        cd - >/dev/null || exit 1
    else
        ENVIRONMENT="vanilla"
    fi
fi

# Get Key Vault name from Terraform
if [ -d "$TF_DIR" ]; then
    cd "$TF_DIR" || exit 1
    KV_NAME=$(terraform output -raw key_vault_name 2>/dev/null)
    cd - >/dev/null || exit 1
    
    if [ -z "$KV_NAME" ]; then
        print_error "Could not retrieve Key Vault name from Terraform."
        print_info "Please ensure Terraform has been applied in: $TF_DIR"
        exit 1
    fi
else
    print_error "Terraform directory not found: $TF_DIR"
    exit 1
fi

print_info "Environment: $ENVIRONMENT"
print_info "Key Vault: $KV_NAME"
echo ""

# List all MFT secrets for the environment
print_info "Listing MFT secrets for environment: $ENVIRONMENT"
echo "=========================================="

# Database secrets
echo ""
print_info "Database Secrets (mft-db-*):"
az keyvault secret list --vault-name "$KV_NAME" \
    --query "[?starts_with(name, '${ENVIRONMENT}-mft-db-')].{Name:name, Enabled:attributes.enabled, Expires:attributes.expires}" \
    -o table 2>/dev/null || print_warning "No database secrets found"

# Application secrets
echo ""
print_info "Application Secrets (mft-*):"
az keyvault secret list --vault-name "$KV_NAME" \
    --query "[?starts_with(name, '${ENVIRONMENT}-mft-') && !starts_with(name, '${ENVIRONMENT}-mft-db-') && !starts_with(name, '${ENVIRONMENT}-mft-cert-')].{Name:name, Enabled:attributes.enabled, Expires:attributes.expires}" \
    -o table 2>/dev/null || print_warning "No application secrets found"

# Certificate secrets
echo ""
print_info "Certificate Secrets (mft-cert-*):"
az keyvault secret list --vault-name "$KV_NAME" \
    --query "[?starts_with(name, '${ENVIRONMENT}-mft-cert-')].{Name:name, Enabled:attributes.enabled, Expires:attributes.expires}" \
    -o table 2>/dev/null || print_warning "No certificate secrets found"

# Certificate objects
echo ""
print_info "Certificate Objects:"
az keyvault certificate list --vault-name "$KV_NAME" \
    --query "[?starts_with(name, '${ENVIRONMENT}-mft-')].{Name:name, Enabled:attributes.enabled, Expires:attributes.expires}" \
    -o table 2>/dev/null || print_warning "No certificate objects found"

echo ""
print_success "Secret listing complete"
