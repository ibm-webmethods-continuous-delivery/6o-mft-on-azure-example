#!/bin/sh
# Generate Kubernetes secret from template using Terraform outputs and user-provided app credentials

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

# Check if envsubst is available
if ! command -v envsubst >/dev/null 2>&1; then
    error "envsubst is not installed. Please install gettext package."
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

cd "${BASE_DIR}" || exit 1

# Validate Terraform outputs
if [ -z "${POSTGRES_SERVER_FQDN}" ] || [ -z "${POSTGRES_ADMIN_USER}" ] || \
   [ -z "${POSTGRES_ADMIN_PASSWORD}" ] || [ -z "${POSTGRES_ONLINE_DB}" ] || \
   [ -z "${POSTGRES_ARCHIVE_DB}" ]; then
    error "Failed to retrieve all required Terraform outputs"
    error "Please ensure Terraform has been applied successfully"
    info "Crt folder is $(pwd)"
    info "Env is "
    env | sort
    exit 1
fi

info "Retrieved Terraform outputs:"
info "  - Server FQDN: ${POSTGRES_SERVER_FQDN}"
info "  - Admin User: ${POSTGRES_ADMIN_USER}"
info "  - Online DB: ${POSTGRES_ONLINE_DB}"
info "  - Archive DB: ${POSTGRES_ARCHIVE_DB}"

# Check for application credentials in environment
if [ -z "${POSTGRES_USER}" ] || [ -z "${POSTGRES_PASSWORD}" ] || \
   [ -z "${POSTGRES_ARCHIVE_USER}" ] || [ -z "${POSTGRES_ARCHIVE_PASSWORD}" ]; then
    warn "Application credentials not found in environment"
    info "Please provide the following application credentials:"
    info "(These will be created by the init job and used by DBC and Active Transfer)"
    echo ""

    # Prompt for credentials
    printf "Online DB application username [mft_app_user]: "
    read -r POSTGRES_USER
    POSTGRES_USER=${POSTGRES_USER:-mft_app_user}

    printf "Online DB application password: "
    read -r POSTGRES_PASSWORD

    printf "Archive DB application username [mft_archive_user]: "
    read -r POSTGRES_ARCHIVE_USER
    POSTGRES_ARCHIVE_USER=${POSTGRES_ARCHIVE_USER:-mft_archive_user}

    printf "Archive DB application password: "
    read -r POSTGRES_ARCHIVE_PASSWORD

    echo ""
fi

# Validate application credentials
if [ -z "${POSTGRES_USER}" ] || [ -z "${POSTGRES_PASSWORD}" ] || \
   [ -z "${POSTGRES_ARCHIVE_USER}" ] || [ -z "${POSTGRES_ARCHIVE_PASSWORD}" ]; then
    error "All application credentials are required"
    exit 1
fi

info "Using application credentials:"
info "  - Online DB User: ${POSTGRES_USER}"
info "  - Archive DB User: ${POSTGRES_ARCHIVE_USER}"

# Export all variables for envsubst
export POSTGRES_SERVER_FQDN
export POSTGRES_ADMIN_USER
export POSTGRES_ADMIN_PASSWORD
export POSTGRES_ONLINE_DB
export POSTGRES_ARCHIVE_DB
export POSTGRES_USER
export POSTGRES_PASSWORD
export POSTGRES_ARCHIVE_USER
export POSTGRES_ARCHIVE_PASSWORD

# Generate secret from template
TEMPLATE_FILE="${BASE_DIR}/kubernetes/secret-db-user-init-admin-creds.yaml.template"
OUTPUT_FILE="${BASE_DIR}/kubernetes/secret-db-user-init-admin-creds.yaml"

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
    warn "IMPORTANT: Save these application credentials securely!"
    warn "You will need them for Database Configurator and Active Transfer deployment."
else
    error "Failed to generate secret manifest"
    exit 1
fi
