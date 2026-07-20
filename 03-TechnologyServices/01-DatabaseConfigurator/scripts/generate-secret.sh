#!/bin/sh
# Generate Kubernetes secret for Database Configurator using Terraform outputs and Azure Key Vault

set -e

# Color output helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$1"
}

warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$1"
}

error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1"
}

# Check if required commands are available
if ! command -v envsubst >/dev/null 2>&1; then
    error "envsubst is not installed. Please install gettext package."
    exit 1
fi

if ! command -v az >/dev/null 2>&1; then
    error "Azure CLI (az) is not installed or not in PATH."
    error "Please install Azure CLI: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Navigate to script directory
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
BASE_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
TF_DIR="${BASE_DIR}/../../01-AzurePrerequisites/02-ServiceFulfillment"

info "Retrieving Terraform outputs from ${TF_DIR}..."

# Check if Terraform directory exists
if [ ! -d "${TF_DIR}" ]; then
    error "Terraform directory not found: ${TF_DIR}"
    exit 1
fi

# Source Terraform outputs
cd "${TF_DIR}" || exit 1

if [ ! -f "11-util-source-db-connection-variables.sh" ]; then
    error "Terraform variable sourcing script not found"
    exit 1
fi

# shellcheck source=/dev/null
. ./11-util-source-db-connection-variables.sh

# Get Key Vault name from Terraform
KEY_VAULT_NAME=$(terraform output -raw key_vault_name 2>/dev/null)

cd "${BASE_DIR}" || exit 1

# Validate Terraform outputs
if [ -z "${POSTGRES_SERVER_FQDN}" ] || [ -z "${POSTGRES_ONLINE_DB}" ] || \
   [ -z "${POSTGRES_ARCHIVE_DB}" ]; then
    error "Failed to retrieve all required Terraform outputs"
    error "Please ensure Terraform has been applied successfully"
    info "Current folder is $(pwd)"
    exit 1
fi

if [ -z "${KEY_VAULT_NAME}" ]; then
    error "Failed to retrieve Key Vault name from Terraform outputs"
    error "Please ensure Terraform has been applied successfully"
    exit 1
fi

info "Retrieved Terraform outputs:"
info "  - Server FQDN: ${POSTGRES_SERVER_FQDN}"
info "  - Online DB: ${POSTGRES_ONLINE_DB}"
info "  - Archive DB: ${POSTGRES_ARCHIVE_DB}"
info "  - Key Vault: ${KEY_VAULT_NAME}"

# Fetch application credentials from Azure Key Vault
info "Fetching application credentials from Azure Key Vault..."

# Check for application credentials in environment (for testing/override)
if [ -z "${POSTGRES_USER}" ]; then
    POSTGRES_USER="mft_app_user"
    info "Using default online DB username: ${POSTGRES_USER}"
fi

if [ -z "${POSTGRES_ARCHIVE_USER}" ]; then
    POSTGRES_ARCHIVE_USER="mft_archive_user"
    info "Using default archive DB username: ${POSTGRES_ARCHIVE_USER}"
fi

# Fetch passwords from Key Vault
info "Fetching online DB password from Key Vault..."
POSTGRES_PASSWORD=$(az keyvault secret show \
    --vault-name "${KEY_VAULT_NAME}" \
    --name "dev-mft-secret-db-online-password" \
    --query "value" \
    --output tsv 2>/dev/null)

if [ -z "${POSTGRES_PASSWORD}" ]; then
    error "Failed to fetch online DB password from Key Vault"
    error "Secret name: dev-mft-secret-db-online-password"
    error "Key Vault: ${KEY_VAULT_NAME}"
    error ""
    error "Please ensure:"
    error "  1. You are logged in to Azure CLI (az login)"
    error "  2. The secret exists in Key Vault"
    error "  3. You have permission to read secrets from the Key Vault"
    error ""
    error "To set the secret, run:"
    error "  az keyvault secret set --vault-name ${KEY_VAULT_NAME} \\"
    error "    --name dev-mft-secret-db-online-password \\"
    error "    --value 'YOUR_PASSWORD_HERE'"
    exit 1
fi

info "Fetching archive DB password from Key Vault..."
POSTGRES_ARCHIVE_PASSWORD=$(az keyvault secret show \
    --vault-name "${KEY_VAULT_NAME}" \
    --name "dev-mft-secret-db-archive-password" \
    --query "value" \
    --output tsv 2>/dev/null)

if [ -z "${POSTGRES_ARCHIVE_PASSWORD}" ]; then
    error "Failed to fetch archive DB password from Key Vault"
    error "Secret name: dev-mft-secret-db-archive-password"
    error "Key Vault: ${KEY_VAULT_NAME}"
    error ""
    error "Please ensure:"
    error "  1. You are logged in to Azure CLI (az login)"
    error "  2. The secret exists in Key Vault"
    error "  3. You have permission to read secrets from the Key Vault"
    error ""
    error "To set the secret, run:"
    error "  az keyvault secret set --vault-name ${KEY_VAULT_NAME} \\"
    error "    --name dev-mft-secret-db-archive-password \\"
    error "    --value 'YOUR_PASSWORD_HERE'"
    exit 1
fi

info "Successfully retrieved application credentials from Key Vault"
info "  - Online DB User: ${POSTGRES_USER}"
info "  - Archive DB User: ${POSTGRES_ARCHIVE_USER}"

# Export all variables for envsubst
export POSTGRES_SERVER_FQDN
export POSTGRES_ONLINE_DB
export POSTGRES_ARCHIVE_DB
export POSTGRES_USER
export POSTGRES_PASSWORD
export POSTGRES_ARCHIVE_USER
export POSTGRES_ARCHIVE_PASSWORD

# Generate secret from template
TEMPLATE_FILE="${BASE_DIR}/kubernetes/secret-dbc-creds.yaml.template"
OUTPUT_FILE="${BASE_DIR}/kubernetes/secret-dbc-creds.yaml"

if [ ! -f "${TEMPLATE_FILE}" ]; then
    error "Template file not found: ${TEMPLATE_FILE}"
    exit 1
fi

info "Generating secret manifest..."

# Use envsubst to replace variables
envsubst < "${TEMPLATE_FILE}" > "${OUTPUT_FILE}"

if [ $? -eq 0 ]; then
    info "Secret manifest generated successfully: ${OUTPUT_FILE}"
    info ""
    info "Next steps:"
    info "  1. Review the generated secret (optional): cat ${OUTPUT_FILE}"
    info "  2. Apply the secret: kubectl apply -f ${OUTPUT_FILE}"
    info "  3. Deploy the job: ./deploy.sh"
    info ""
    warn "NOTE: Application credentials were fetched from Azure Key Vault"
    warn "Key Vault: ${KEY_VAULT_NAME}"
else
    error "Failed to generate secret manifest"
    exit 1
fi
