#!/bin/sh
# Validate that all required MFT secrets exist in Azure Key Vault
# Usage: ./validate-secrets.sh [environment]

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

# Define required secrets
REQUIRED_DB_SECRETS="
postgres-server-fqdn
postgres-online-db
postgres-archive-db
postgres-admin-user
postgres-admin-password
postgres-online-user
postgres-online-password
postgres-archive-user
postgres-archive-password
"

REQUIRED_APP_SECRETS="
admin-password
config-json
"

REQUIRED_CERT_SECRETS="
admin-ui-keystore-password
admin-ui-truststore-password
web-client-keystore-password
web-client-truststore-password
sftp-ssh-private-key
"

# Validation counters
TOTAL=0
FOUND=0
MISSING=0

check_secret() {
    SECRET_NAME="$1"
    TOTAL=$((TOTAL + 1))
    
    if az keyvault secret show --vault-name "$KV_NAME" --name "$SECRET_NAME" >/dev/null 2>&1; then
        print_success "$SECRET_NAME"
        FOUND=$((FOUND + 1))
        return 0
    else
        print_error "$SECRET_NAME (MISSING)"
        MISSING=$((MISSING + 1))
        return 1
    fi
}

# Validate database secrets
echo "Validating Database Secrets (mft-db-*):"
echo "=========================================="
for secret in $REQUIRED_DB_SECRETS; do
    check_secret "${ENVIRONMENT}-mft-db-${secret}"
done

echo ""
echo "Validating Application Secrets (mft-*):"
echo "=========================================="
for secret in $REQUIRED_APP_SECRETS; do
    check_secret "${ENVIRONMENT}-mft-${secret}"
done

echo ""
echo "Validating Certificate Secrets (mft-*):"
echo "=========================================="
for secret in $REQUIRED_CERT_SECRETS; do
    check_secret "${ENVIRONMENT}-mft-${secret}"
done

# Summary
echo ""
echo "=========================================="
echo "Validation Summary:"
echo "=========================================="
print_info "Total secrets checked: $TOTAL"
print_success "Found: $FOUND"

if [ "$MISSING" -gt 0 ]; then
    print_error "Missing: $MISSING"
    echo ""
    print_warning "Some required secrets are missing!"
    print_info "Run Terraform apply to create missing secrets:"
    print_info "  cd $TF_DIR"
    print_info "  terraform apply"
    exit 1
else
    echo ""
    print_success "All required secrets are present!"
    exit 0
fi
