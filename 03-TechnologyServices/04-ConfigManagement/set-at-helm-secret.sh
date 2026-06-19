#!/bin/sh
# Set or update an MFT secret in Azure Key Vault
# Usage: ./set-at-helm-secret.sh <secret-suffix> <value> [environment]
#
# Examples:
#   ./set-at-helm-secret.sh admin-password "MySecurePassword123!"
#   ./set-at-helm-secret.sh db-postgres-online-password "DbPassword456" dev
#   ./set-at-helm-secret.sh sftp-ssh-private-key "$(cat ~/.ssh/id_rsa)"

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

print_usage() {
    cat <<EOF
${CYAN}Usage:${NC}
  $0 <secret-suffix> <value> [environment]

${CYAN}Arguments:${NC}
  secret-suffix    Secret name suffix (without environment prefix)
                   Examples: admin-password, db-postgres-online-password
  value           Secret value to set
  environment     Environment name (optional, defaults from Terraform)

${CYAN}Common Secret Suffixes:${NC}
  ${GREEN}Application Secrets:${NC}
    mft-admin-password
    mft-metering-config-xml-file
    mft-sftp-ssh-private-key
    mft-sftp-ssh-private-key-loaded

  ${GREEN}Database Secrets:${NC}
    mft-db-postgres-server-fqdn
    mft-db-postgres-online-db
    mft-db-postgres-archive-db
    mft-db-postgres-admin-user
    mft-db-postgres-admin-password
    mft-db-postgres-online-user
    mft-db-postgres-online-password
    mft-db-postgres-archive-user
    mft-db-postgres-archive-password

  ${GREEN}Certificate Passwords:${NC}
    mft-admin-ui-jks-keystore-password
    mft-admin-ui-jks-truststore-password
    mft-admin-ui-pkcs12-keystore-password
    mft-admin-ui-pkcs12-truststore-password
    mft-web-client-jks-keystore-password
    mft-web-client-jks-truststore-password
    mft-web-client-pkcs12-keystore-password
    mft-web-client-pkcs12-truststore-password
    mft-cert-jks-truststore-password
    mft-cert-pkcs12-truststore-password

${CYAN}Examples:${NC}
  # Set admin password
  $0 mft-admin-password "MySecurePassword123!"

  # Set database password for specific environment
  $0 mft-db-postgres-online-password "DbPassword456" dev

  # Set SSH private key from file
  $0 mft-sftp-ssh-private-key "\$(cat ~/.ssh/id_rsa)"

  # Set metering config XML from file
  $0 mft-metering-config-xml-file "\$(cat metering.xml)"

${CYAN}Notes:${NC}
  - Secret names are automatically prefixed with environment name
  - Existing secrets will be updated (previous versions are retained)
  - Use quotes around values containing special characters
  - For binary files (certificates), use base64 encoding first

EOF
}

# Check arguments
if [ $# -lt 2 ]; then
    print_error "Missing required arguments"
    echo ""
    print_usage
    exit 1
fi

SECRET_SUFFIX="$1"
SECRET_VALUE="$2"
ENVIRONMENT="${3:-}"

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

# Get environment from Terraform if not provided
if [ -z "$ENVIRONMENT" ]; then
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

# Construct full secret name
# Remove any leading "mft-" or environment prefix if user provided it
SECRET_SUFFIX=$(echo "$SECRET_SUFFIX" | sed "s/^${ENVIRONMENT}-//; s/^mft-//")

# Ensure it starts with "mft-" for consistency
if ! echo "$SECRET_SUFFIX" | grep -q "^mft-"; then
    SECRET_SUFFIX="mft-${SECRET_SUFFIX}"
fi

FULL_SECRET_NAME="${ENVIRONMENT}-${SECRET_SUFFIX}"

print_info "Environment: $ENVIRONMENT"
print_info "Key Vault: $KV_NAME"
print_info "Secret Name: $FULL_SECRET_NAME"
echo ""

# Check if secret already exists
if az keyvault secret show --vault-name "$KV_NAME" --name "$FULL_SECRET_NAME" >/dev/null 2>&1; then
    print_warning "Secret already exists and will be updated"
    print_info "Previous versions will be retained in Key Vault history"
    echo ""
fi

# Validate secret value is not empty
if [ -z "$SECRET_VALUE" ]; then
    print_error "Secret value cannot be empty"
    exit 1
fi

# Determine content type based on secret suffix
CONTENT_TYPE="text/plain"
case "$SECRET_SUFFIX" in
    *-config-json)
        CONTENT_TYPE="application/json"
        # Validate JSON if it looks like JSON
        if echo "$SECRET_VALUE" | grep -q "^{"; then
            if ! echo "$SECRET_VALUE" | python3 -m json.tool >/dev/null 2>&1; then
                print_warning "Value does not appear to be valid JSON"
                read -p "Continue anyway? (y/N): " -r
                if [ "$REPLY" != "y" ] && [ "$REPLY" != "Y" ]; then
                    print_info "Operation cancelled"
                    exit 0
                fi
            fi
        fi
        ;;
    *-xml-file)
        CONTENT_TYPE="application/xml"
        ;;
    *-cert-*|*-keystore-*|*-truststore-*)
        CONTENT_TYPE="application/octet-stream"
        ;;
esac

# Set the secret
print_info "Setting secret in Key Vault..."

if az keyvault secret set \
    --vault-name "$KV_NAME" \
    --name "$FULL_SECRET_NAME" \
    --value "$SECRET_VALUE" \
    --content-type "$CONTENT_TYPE" \
    --output none 2>/dev/null; then
    
    print_success "Secret set successfully: $FULL_SECRET_NAME"
    echo ""
    
    # Display secret info (without value)
    print_info "Secret Details:"
    az keyvault secret show \
        --vault-name "$KV_NAME" \
        --name "$FULL_SECRET_NAME" \
        --query "{Name:name, ContentType:contentType, Enabled:attributes.enabled, Updated:attributes.updated}" \
        -o table 2>/dev/null
    
    echo ""
    print_info "Next Steps:"
    echo "  1. Verify the secret was set correctly:"
    echo "     ./view-at-vault-secrets.sh $ENVIRONMENT --show-values | grep -A 10 '$FULL_SECRET_NAME'"
    echo ""
    echo "  2. If this secret is used by the Helm chart, restart pods to pick up changes:"
    echo "     kubectl rollout restart deployment/active-transfer -n <namespace>"
    echo ""
    echo "  3. Monitor secret rotation (if enabled):"
    echo "     kubectl logs -f deployment/active-transfer -n <namespace> | grep -i secret"
    
else
    print_error "Failed to set secret: $FULL_SECRET_NAME"
    print_info "Check Azure CLI permissions and Key Vault access policies"
    exit 1
fi
