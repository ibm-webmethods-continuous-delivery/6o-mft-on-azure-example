#!/usr/bin/env bash
#
# extract-terraform-values.sh
# Extracts values from Terraform state/output and generates a values override file
# for the Active Transfer Helm chart deployment.
#
# Usage:
#   ./extract-terraform-values.sh [--terraform-dir <path>] [--output <file>]
#
# Options:
#   --terraform-dir <path>  Path to Terraform directory (default: ../../01-Infrastructure)
#   --output <file>         Output file path (default: ../helm/terraform-values.yaml)
#   --help                  Show this help message
#
# Prerequisites:
#   - Terraform must be installed and available in PATH
#   - Terraform state must exist in the specified directory
#   - User must have access to run 'terraform output' command
#
# Note: This script should be run in an environment with Terraform installed,
#       not in the Bob Shell sandbox where Terraform is not available.

set -euo pipefail

# Default values
TERRAFORM_DIR="../../../01-AzurePrerequisites/02-ServiceFulfillment/"
OUTPUT_FILE="../helm/terraform-values.yaml"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print functions
print_error() {
    echo -e "${RED}✗ $1${NC}" >&2
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Show usage
show_usage() {
    grep '^#' "$0" | grep -v '#!/usr/bin/env' | sed 's/^# \?//'
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --terraform-dir)
            TERRAFORM_DIR="$2"
            shift 2
            ;;
        --output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --help)
            show_usage
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            ;;
    esac
done

# Resolve paths
TERRAFORM_DIR="$(cd "$SCRIPT_DIR" && cd "$TERRAFORM_DIR" && pwd)"
OUTPUT_FILE="$(cd "$SCRIPT_DIR" && cd "$(dirname "$OUTPUT_FILE")" && pwd)/$(basename "$OUTPUT_FILE")"

echo "============================================================================"
echo "Extract Terraform Values for Active Transfer Helm Chart"
echo "============================================================================"
echo ""

# Check if terraform is available
print_info "Checking for Terraform..."
if ! command -v terraform &> /dev/null; then
    print_error "Terraform is not installed or not in PATH"
    print_info "This script must be run in an environment with Terraform installed"
    print_info "Example: Run in Azure CLI container or local machine with Terraform"
    exit 1
fi
print_success "Terraform is available"

# Check if Terraform directory exists
print_info "Checking Terraform directory: $TERRAFORM_DIR"
if [[ ! -d "$TERRAFORM_DIR" ]]; then
    print_error "Terraform directory not found: $TERRAFORM_DIR"
    exit 1
fi
print_success "Terraform directory exists"

# Check if Terraform state exists
print_info "Checking Terraform state..."
if [[ ! -f "$TERRAFORM_DIR/terraform.tfstate" ]] && [[ ! -f "$TERRAFORM_DIR/.terraform/terraform.tfstate" ]]; then
    print_error "Terraform state not found in: $TERRAFORM_DIR"
    print_info "Run 'terraform init' and 'terraform apply' first"
    exit 1
fi
print_success "Terraform state exists"

# Extract Terraform outputs
print_info "Extracting Terraform outputs..."
cd "$TERRAFORM_DIR"

# Function to get Terraform output value
get_tf_output() {
    local output_name="$1"
    local value
    value=$(terraform output -raw "$output_name" 2>/dev/null || echo "")
    echo "$value"
}

# Extract required values
ACR_LOGIN_SERVER=$(get_tf_output "acr_login_server")
POSTGRES_SERVER_FQDN=$(get_tf_output "postgres_server_fqdn")
POSTGRES_ONLINE_DB_NAME=$(get_tf_output "postgres_online_db_name")
POSTGRES_ARCHIVE_DB_NAME=$(get_tf_output "postgres_archive_db_name")
POSTGRES_DB_ONLINE_USER=$(get_tf_output "postgres_mft_db_online_user")
POSTGRES_DB_ARCHIVE_USER=$(get_tf_output "postgres_mft_db_archive_user")
SFTP_VM_1_PRIVATE_IP=$(get_tf_output "sftp_vm_1_private_ip")
SFTP_VM_2_PRIVATE_IP=$(get_tf_output "sftp_vm_2_private_ip")
APP_GATEWAY_PUBLIC_IP=$(get_tf_output "application_gateway_public_ip")
KEY_VAULT_NAME=$(get_tf_output "key_vault_name")
TENANT_ID=$(get_tf_output "tenant_id")
MFT_MANAGED_IDENTITY_CLIENT_ID=$(get_tf_output "mft_managed_identity_client_id")
ENVIRONMENT_NAME=$(get_tf_output "environment_name")

# Validate required outputs
MISSING_OUTPUTS=()
[[ -z "$ACR_LOGIN_SERVER" ]] && MISSING_OUTPUTS+=("acr_login_server")
[[ -z "$POSTGRES_SERVER_FQDN" ]] && MISSING_OUTPUTS+=("postgres_server_fqdn")
[[ -z "$POSTGRES_ONLINE_DB_NAME" ]] && MISSING_OUTPUTS+=("postgres_online_db_name")
[[ -z "$POSTGRES_ARCHIVE_DB_NAME" ]] && MISSING_OUTPUTS+=("postgres_archive_db_name")
[[ -z "$POSTGRES_DB_ONLINE_USER" ]] && MISSING_OUTPUTS+=("POSTGRES_DB_ONLINE_USER")
[[ -z "$POSTGRES_DB_ARCHIVE_USER" ]] && MISSING_OUTPUTS+=("POSTGRES_DB_ARCHIVE_USER")

if [[ ${#MISSING_OUTPUTS[@]} -gt 0 ]]; then
    print_error "Missing required Terraform outputs:"
    for output in "${MISSING_OUTPUTS[@]}"; do
        echo "  - $output"
    done
    print_info "Ensure these outputs are defined in your Terraform configuration"
    exit 1
fi

print_success "All required Terraform outputs extracted"

# Generate nip.io hostname from Application Gateway public IP
INGRESS_HOSTNAME=""
if [[ -n "$APP_GATEWAY_PUBLIC_IP" ]]; then
    INGRESS_HOSTNAME="${APP_GATEWAY_PUBLIC_IP}.nip.io"
    print_info "Generated ingress hostname: $INGRESS_HOSTNAME"
else
    print_warning "Application Gateway public IP not found - ingress hostname will be empty"
fi

# Generate values override file
print_info "Generating values override file: $OUTPUT_FILE"

cat > "$OUTPUT_FILE" << EOF
# Terraform-generated values for Active Transfer Helm chart
# Generated on: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Terraform directory: $TERRAFORM_DIR
#
# This file contains values extracted from Terraform state/output.
# Use this file as an additional values file during Helm deployment:
#   helm install active-transfer ./helm \\
#     --values ./helm/vanilla-values.yaml \\
#     --values ./helm/terraform-values.yaml

# Container image configuration
image:
  repository: "${ACR_LOGIN_SERVER}/active-transfer-enhance"
  tag: "latest"

# Database configuration
database:
  serverFqdn: "${POSTGRES_SERVER_FQDN}"
  onlineDbName: "${POSTGRES_ONLINE_DB_NAME}"
  archiveDbName: "${POSTGRES_ARCHIVE_DB_NAME}"
  onlineDbUser: "${POSTGRES_DB_ONLINE_USER}"
  archiveDbUser: "${POSTGRES_DB_ARCHIVE_USER}"
  sslMode: "require"

# MFT gateway configuration
mftConfig:
  gateways:
EOF

# Add gateway configurations if IPs are available
if [[ -n "$SFTP_VM_1_PRIVATE_IP" ]]; then
    cat >> "$OUTPUT_FILE" << EOF
    - instanceName: "Gateway1"
      host: "${SFTP_VM_1_PRIVATE_IP}"
      port: 8500
      active: true
      autoConnect: true
EOF
fi

if [[ -n "$SFTP_VM_2_PRIVATE_IP" ]]; then
    cat >> "$OUTPUT_FILE" << EOF
    - instanceName: "Gateway2"
      host: "${SFTP_VM_2_PRIVATE_IP}"
      port: 8500
      active: true
      autoConnect: true
EOF
fi

# Add ingress configuration if hostname is available
if [[ -n "$INGRESS_HOSTNAME" ]]; then
    cat >> "$OUTPUT_FILE" << EOF

# Ingress configuration (using nip.io for DNS-less access)
ingress:
  enabled: true
  hosts:
    - host: "${INGRESS_HOSTNAME}"
      paths:
        - path: /
          pathType: Prefix
          port: 5555
  tls:
    - secretName: mft-admin-tls
      hosts:
        - ${INGRESS_HOSTNAME}
EOF
fi

# Add Azure Key Vault configuration if values are available
if [[ -n "$KEY_VAULT_NAME" ]] && [[ -n "$TENANT_ID" ]] && [[ -n "$MFT_MANAGED_IDENTITY_CLIENT_ID" ]]; then
    cat >> "$OUTPUT_FILE" << EOF

# Azure Key Vault configuration (for azureKeyVault secret provider mode)
azureKeyVault:
  name: "${KEY_VAULT_NAME}"
  tenantId: "${TENANT_ID}"
  clientId: "${MFT_MANAGED_IDENTITY_CLIENT_ID}"
  environment: "${ENVIRONMENT_NAME:-vanilla}"
EOF
fi

print_success "Values override file generated successfully"
echo ""
print_info "Summary of extracted values:"
echo "  - ACR Login Server: $ACR_LOGIN_SERVER"
echo "  - PostgreSQL Server: $POSTGRES_SERVER_FQDN"
echo "  - Online Database: $POSTGRES_ONLINE_DB_NAME (user: $POSTGRES_DB_ONLINE_USER)"
echo "  - Archive Database: $POSTGRES_ARCHIVE_DB_NAME (user: $POSTGRES_DB_ARCHIVE_USER)"
[[ -n "$SFTP_VM_1_PRIVATE_IP" ]] && echo "  - Gateway 1 IP: $SFTP_VM_1_PRIVATE_IP"
[[ -n "$SFTP_VM_2_PRIVATE_IP" ]] && echo "  - Gateway 2 IP: $SFTP_VM_2_PRIVATE_IP"
[[ -n "$INGRESS_HOSTNAME" ]] && echo "  - Ingress Hostname: $INGRESS_HOSTNAME"
[[ -n "$KEY_VAULT_NAME" ]] && echo "  - Key Vault: $KEY_VAULT_NAME"
echo ""
print_success "Done! Use this file with: helm install ... --values $OUTPUT_FILE"
