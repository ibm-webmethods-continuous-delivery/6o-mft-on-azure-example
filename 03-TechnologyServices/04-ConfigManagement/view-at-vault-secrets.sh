#!/bin/sh
# View MFT secrets in Azure Key Vault with descriptions
# Usage: ./view-at-vault-secrets.sh [environment] [--show-values]

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
MAGENTA='\033[0;35m'
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

print_secret_name() {
    printf "${MAGENTA}%s${NC}\n" "$1"
}

# Parse arguments
SHOW_VALUES=false
ENVIRONMENT=""

for arg in "$@"; do
    case "$arg" in
        --show-values)
            SHOW_VALUES=true
            ;;
        *)
            if [ -z "$ENVIRONMENT" ]; then
                ENVIRONMENT="$arg"
            fi
            ;;
    esac
done

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

print_info "Environment: $ENVIRONMENT"
print_info "Key Vault: $KV_NAME"
if [ "$SHOW_VALUES" = true ]; then
    print_warning "Secret values will be displayed (use with caution!)"
fi
echo ""

# Function to display secret details
display_secret() {
    SECRET_NAME="$1"
    
    # Get secret details
    SECRET_JSON=$(az keyvault secret show --vault-name "$KV_NAME" --name "$SECRET_NAME" 2>/dev/null)
    
    if [ -z "$SECRET_JSON" ]; then
        print_error "Failed to retrieve secret: $SECRET_NAME"
        return 1
    fi
    
    # Extract fields
    ENABLED=$(echo "$SECRET_JSON" | grep -o '"enabled": *[^,]*' | sed 's/.*: *//' | tr -d ' ')
    CONTENT_TYPE=$(echo "$SECRET_JSON" | grep -o '"contentType": *"[^"]*"' | sed 's/.*: *"//' | tr -d '"')
    EXPIRES=$(echo "$SECRET_JSON" | grep -o '"expires": *"[^"]*"' | sed 's/.*: *"//' | tr -d '"')
    DESCRIPTION=$(echo "$SECRET_JSON" | grep -o '"Description": *"[^"]*"' | sed 's/.*: *"//' | tr -d '"')
    
    # Display secret name
    print_secret_name "  $SECRET_NAME"
    
    # Display type
    if [ -n "$CONTENT_TYPE" ]; then
        printf "    ${CYAN}Type:${NC} %s\n" "$CONTENT_TYPE"
    else
        printf "    ${CYAN}Type:${NC} text/plain\n"
    fi
    
    # Display description
    if [ -n "$DESCRIPTION" ]; then
        printf "    ${CYAN}Description:${NC} %s\n" "$DESCRIPTION"
    else
        printf "    ${CYAN}Description:${NC} (none)\n"
    fi
    
    # Display enabled status
    printf "    ${CYAN}Enabled:${NC} %s\n" "$ENABLED"
    
    # Display expiration
    if [ -n "$EXPIRES" ] && [ "$EXPIRES" != "null" ]; then
        printf "    ${CYAN}Expires:${NC} %s\n" "$EXPIRES"
    fi
    
    # Display value if requested
    if [ "$SHOW_VALUES" = true ]; then
        VALUE=$(echo "$SECRET_JSON" | grep -o '"value": *"[^"]*"' | sed 's/.*: *"//' | tr -d '"')
        if [ -n "$VALUE" ]; then
            # Truncate long values (e.g., certificates)
            VALUE_LENGTH=${#VALUE}
            if [ "$VALUE_LENGTH" -gt 100 ]; then
                printf "    ${CYAN}Value:${NC} %s... (truncated, length: %d)\n" "$(echo "$VALUE" | cut -c1-100)" "$VALUE_LENGTH"
            else
                printf "    ${CYAN}Value:${NC} %s\n" "$VALUE"
            fi
        fi
    fi
    
    echo ""
}

# Get all MFT secrets for the environment
print_header "═══════════════════════════════════════════════════════════════"
print_header "MFT Secrets for Environment: $ENVIRONMENT"
print_header "═══════════════════════════════════════════════════════════════"
echo ""

# Database secrets
print_header "Database Secrets (mft-db-*)"
print_header "───────────────────────────────────────────────────────────────"
DB_SECRETS=$(az keyvault secret list --vault-name "$KV_NAME" \
    --query "[?starts_with(name, '${ENVIRONMENT}-mft-db-')].name" \
    -o tsv 2>/dev/null)

if [ -n "$DB_SECRETS" ]; then
    echo "$DB_SECRETS" | while IFS= read -r secret; do
        display_secret "$secret"
    done
else
    print_warning "No database secrets found"
    echo ""
fi

# Application secrets (excluding db and cert)
print_header "Application Secrets (mft-*)"
print_header "───────────────────────────────────────────────────────────────"
APP_SECRETS=$(az keyvault secret list --vault-name "$KV_NAME" \
    --query "[?starts_with(name, '${ENVIRONMENT}-mft-') && !starts_with(name, '${ENVIRONMENT}-mft-db-') && !starts_with(name, '${ENVIRONMENT}-mft-cert-')].name" \
    -o tsv 2>/dev/null)

if [ -n "$APP_SECRETS" ]; then
    echo "$APP_SECRETS" | while IFS= read -r secret; do
        display_secret "$secret"
    done
else
    print_warning "No application secrets found"
    echo ""
fi

# Certificate secrets
print_header "Certificate Secrets (mft-cert-*)"
print_header "───────────────────────────────────────────────────────────────"
CERT_SECRETS=$(az keyvault secret list --vault-name "$KV_NAME" \
    --query "[?starts_with(name, '${ENVIRONMENT}-mft-cert-')].name" \
    -o tsv 2>/dev/null)

if [ -n "$CERT_SECRETS" ]; then
    echo "$CERT_SECRETS" | while IFS= read -r secret; do
        display_secret "$secret"
    done
else
    print_warning "No certificate secrets found"
    echo ""
fi

# Certificate objects (Key Vault certificates, not secrets)
print_header "Certificate Objects"
print_header "───────────────────────────────────────────────────────────────"
CERT_OBJECTS=$(az keyvault certificate list --vault-name "$KV_NAME" \
    --query "[?starts_with(name, '${ENVIRONMENT}-mft-')].name" \
    -o tsv 2>/dev/null)

if [ -n "$CERT_OBJECTS" ]; then
    echo "$CERT_OBJECTS" | while IFS= read -r cert; do
        CERT_JSON=$(az keyvault certificate show --vault-name "$KV_NAME" --name "$cert" 2>/dev/null)
        
        if [ -n "$CERT_JSON" ]; then
            print_secret_name "  $cert"
            
            ENABLED=$(echo "$CERT_JSON" | grep -o '"enabled": *[^,]*' | sed 's/.*: *//' | tr -d ' ')
            EXPIRES=$(echo "$CERT_JSON" | grep -o '"expires": *"[^"]*"' | sed 's/.*: *"//' | tr -d '"')
            
            printf "    ${CYAN}Type:${NC} Certificate\n"
            printf "    ${CYAN}Enabled:${NC} %s\n" "$ENABLED"
            
            if [ -n "$EXPIRES" ] && [ "$EXPIRES" != "null" ]; then
                printf "    ${CYAN}Expires:${NC} %s\n" "$EXPIRES"
            fi
            
            echo ""
        fi
    done
else
    print_warning "No certificate objects found"
    echo ""
fi

print_header "═══════════════════════════════════════════════════════════════"
print_success "Secret listing complete"

if [ "$SHOW_VALUES" = false ]; then
    echo ""
    print_info "To display secret values, run with: --show-values"
    print_warning "Warning: This will display sensitive information!"
fi
