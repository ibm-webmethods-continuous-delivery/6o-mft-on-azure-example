#!/bin/sh
# Check completeness of MFT secrets required by Helm chart in Azure Key Vault
# This validates that all secrets referenced in the Helm chart are present in Key Vault
# Usage: ./check-at-helm-secrets-presence.sh [environment]

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="${SCRIPT_DIR}/../../01-AzurePrerequisites/02-ServiceFulfillment"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

print_header() {
    printf "${CYAN}%s${NC}\n" "$1"
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

# Define required secrets based on Helm chart SecretProviderClass
# These are the secrets that MUST exist for the Helm chart to work

# Core application secrets
REQUIRED_APP_SECRETS="
mft-admin-password
mft-sftp-ssh-private-key
"

# Database secrets
REQUIRED_DB_SECRETS="
mft-db-postgres-server-fqdn
mft-db-postgres-online-db
mft-db-postgres-archive-db
mft-db-postgres-admin-user
mft-db-postgres-admin-password
mft-db-postgres-online-user
mft-db-postgres-online-password
mft-db-postgres-archive-user
mft-db-postgres-archive-password
"

# Certificate password secrets - JKS format
REQUIRED_JKS_PASSWORD_SECRETS="
mft-admin-ui-jks-keystore-password
mft-admin-ui-jks-truststore-password
mft-web-client-jks-keystore-password
mft-web-client-jks-truststore-password
mft-cert-jks-truststore-password
"

# Certificate password secrets - PKCS12 format
REQUIRED_PKCS12_PASSWORD_SECRETS="
mft-admin-ui-pkcs12-keystore-password
mft-admin-ui-pkcs12-truststore-password
mft-web-client-pkcs12-keystore-password
mft-web-client-pkcs12-truststore-password
mft-cert-pkcs12-truststore-password
"

# Certificate file secrets - JKS format
REQUIRED_JKS_CERT_SECRETS="
mft-cert-admin-ui-keystore-jks
mft-cert-web-client-keystore-jks
mft-cert-truststore-jks
"

# Certificate file secrets - PKCS12 format
REQUIRED_PKCS12_CERT_SECRETS="
mft-cert-admin-ui-keystore-pkcs12
mft-cert-web-client-keystore-pkcs12
mft-cert-truststore-pkcs12
"

# Optional secrets (warn if missing but don't fail)
OPTIONAL_SECRETS="
mft-metering-config-xml-file
mft-sftp-ssh-private-key-loaded
mft-cert-ca-bundle-pem
"

# Validation counters
TOTAL_REQUIRED=0
FOUND_REQUIRED=0
MISSING_REQUIRED=0
TOTAL_OPTIONAL=0
FOUND_OPTIONAL=0
MISSING_OPTIONAL=0

# Function to check if a secret exists
check_secret() {
    SECRET_SUFFIX="$1"
    IS_OPTIONAL="${2:-false}"
    
    FULL_SECRET_NAME="${ENVIRONMENT}-${SECRET_SUFFIX}"
    
    if [ "$IS_OPTIONAL" = "false" ]; then
        TOTAL_REQUIRED=$((TOTAL_REQUIRED + 1))
    else
        TOTAL_OPTIONAL=$((TOTAL_OPTIONAL + 1))
    fi
    
    if az keyvault secret show --vault-name "$KV_NAME" --name "$FULL_SECRET_NAME" >/dev/null 2>&1; then
        print_success "$FULL_SECRET_NAME"
        if [ "$IS_OPTIONAL" = "false" ]; then
            FOUND_REQUIRED=$((FOUND_REQUIRED + 1))
        else
            FOUND_OPTIONAL=$((FOUND_OPTIONAL + 1))
        fi
        return 0
    else
        if [ "$IS_OPTIONAL" = "false" ]; then
            print_error "$FULL_SECRET_NAME (MISSING - REQUIRED)"
            MISSING_REQUIRED=$((MISSING_REQUIRED + 1))
        else
            print_warning "$FULL_SECRET_NAME (MISSING - OPTIONAL)"
            MISSING_OPTIONAL=$((MISSING_OPTIONAL + 1))
        fi
        return 1
    fi
}

# Check all required secrets
print_header "═══════════════════════════════════════════════════════════════"
print_header "Checking Required Secrets for Helm Chart Deployment"
print_header "═══════════════════════════════════════════════════════════════"
echo ""

print_header "Application Secrets"
print_header "───────────────────────────────────────────────────────────────"
for secret in $REQUIRED_APP_SECRETS; do
    check_secret "$secret" false
done

echo ""
print_header "Database Secrets"
print_header "───────────────────────────────────────────────────────────────"
for secret in $REQUIRED_DB_SECRETS; do
    check_secret "$secret" false
done

echo ""
print_header "Certificate Password Secrets - JKS Format"
print_header "───────────────────────────────────────────────────────────────"
for secret in $REQUIRED_JKS_PASSWORD_SECRETS; do
    check_secret "$secret" false
done

echo ""
print_header "Certificate Password Secrets - PKCS12 Format"
print_header "───────────────────────────────────────────────────────────────"
for secret in $REQUIRED_PKCS12_PASSWORD_SECRETS; do
    check_secret "$secret" false
done

echo ""
print_header "Certificate File Secrets - JKS Format"
print_header "───────────────────────────────────────────────────────────────"
for secret in $REQUIRED_JKS_CERT_SECRETS; do
    check_secret "$secret" false
done

echo ""
print_header "Certificate File Secrets - PKCS12 Format"
print_header "───────────────────────────────────────────────────────────────"
for secret in $REQUIRED_PKCS12_CERT_SECRETS; do
    check_secret "$secret" false
done

echo ""
print_header "Optional Secrets"
print_header "───────────────────────────────────────────────────────────────"
for secret in $OPTIONAL_SECRETS; do
    check_secret "$secret" true
done

# Summary
echo ""
print_header "═══════════════════════════════════════════════════════════════"
print_header "Validation Summary"
print_header "═══════════════════════════════════════════════════════════════"
echo ""

print_info "Required Secrets:"
printf "  Total:   %d\n" "$TOTAL_REQUIRED"
printf "  ${GREEN}Found:   %d${NC}\n" "$FOUND_REQUIRED"
if [ "$MISSING_REQUIRED" -gt 0 ]; then
    printf "  ${RED}Missing: %d${NC}\n" "$MISSING_REQUIRED"
else
    printf "  Missing: %d\n" "$MISSING_REQUIRED"
fi

echo ""
print_info "Optional Secrets:"
printf "  Total:   %d\n" "$TOTAL_OPTIONAL"
printf "  ${GREEN}Found:   %d${NC}\n" "$FOUND_OPTIONAL"
if [ "$MISSING_OPTIONAL" -gt 0 ]; then
    printf "  ${YELLOW}Missing: %d${NC}\n" "$MISSING_OPTIONAL"
else
    printf "  Missing: %d\n" "$MISSING_OPTIONAL"
fi

echo ""
print_header "═══════════════════════════════════════════════════════════════"

# Exit status and recommendations
if [ "$MISSING_REQUIRED" -gt 0 ]; then
    echo ""
    print_error "VALIDATION FAILED: $MISSING_REQUIRED required secret(s) missing!"
    echo ""
    print_info "Recommended Actions:"
    echo ""
    echo "  1. Run Terraform to create missing secrets:"
    echo "     cd $TF_DIR"
    echo "     terraform apply"
    echo ""
    echo "  2. For certificate secrets, ensure upload_certificates is enabled:"
    echo "     Check terraform.tfvars: upload_certificates = true"
    echo ""
    echo "  3. Manually set secrets using:"
    echo "     cd $SCRIPT_DIR"
    echo "     ./set-at-helm-secret.sh <secret-suffix> <value>"
    echo ""
    echo "  4. View all secrets:"
    echo "     ./view-at-vault-secrets.sh $ENVIRONMENT"
    echo ""
    exit 1
else
    echo ""
    print_success "VALIDATION PASSED: All required secrets are present!"
    
    if [ "$MISSING_OPTIONAL" -gt 0 ]; then
        echo ""
        print_warning "Note: $MISSING_OPTIONAL optional secret(s) missing"
        print_info "These are not required for basic deployment but may be needed for:"
        echo "  - IBM license metering (mft-metering-config-xml-file)"
        echo "  - Alternative SSH key format (mft-sftp-ssh-private-key-loaded)"
        echo "  - CA bundle in PEM format (mft-cert-ca-bundle-pem)"
    fi
    
    echo ""
    print_info "Next Steps:"
    echo "  1. Verify secret values are correct (not default placeholders):"
    echo "     ./view-at-vault-secrets.sh $ENVIRONMENT --show-values"
    echo ""
    echo "  2. Deploy Helm chart:"
    echo "     cd ${SCRIPT_DIR}/../02-AT/helm"
    echo "     helm upgrade --install active-transfer . -f values.yaml"
    echo ""
    echo "  3. Monitor deployment:"
    echo "     kubectl get pods -n <namespace> -w"
    echo ""
    exit 0
fi
