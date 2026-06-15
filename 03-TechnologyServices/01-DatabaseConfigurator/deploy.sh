#!/bin/bash
#
# Database Configurator Deployment Script
#
# This script deploys the Database Configurator Kubernetes Job to initialize
# webMethods database schemas in Azure PostgreSQL Flexible Server.
#
# Prerequisites:
# - kubectl configured with access to target AKS cluster
# - Azure PostgreSQL Flexible Server provisioned and accessible
# - Terraform outputs available from prerequisites deployment
#
# Usage:
#   ./deploy.sh [OPTIONS]
#
# Options:
#   --namespace <name>    Kubernetes namespace (default: default)
#   --dry-run            Show what would be deployed without applying
#   --delete             Delete existing job before deploying
#   --logs               Follow logs after deployment
#   --help               Show this help message
#

set -e

# Default values
NAMESPACE="default"
DRY_RUN=false
DELETE_EXISTING=false
FOLLOW_LOGS=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBERNETES_DIR="${SCRIPT_DIR}/kubernetes"
TF_DIR="${SCRIPT_DIR}/../../01-AzurePrerequisites/02-ServiceFulfillment"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

show_help() {
    grep '^#' "$0" | grep -v '#!/bin/bash' | sed 's/^# //' | sed 's/^#//'
    exit 0
}

get_terraform_outputs() {
    print_info "Retrieving configuration from Terraform..."

    # Check if Terraform directory exists
    if [ ! -d "${TF_DIR}" ]; then
        print_error "Terraform directory not found: ${TF_DIR}"
        print_error "Please ensure Terraform has been applied in the prerequisites directory."
        exit 1
    fi

    # Navigate to Terraform directory
    cd "${TF_DIR}" || exit 1

    if ! command -v terraform &> /dev/null; then
        print_error "terraform not found. Please install Terraform."
        exit 1
    fi

    # Get all required outputs
    ACR_LOGIN_SERVER=$(terraform output -raw acr_login_server 2>/dev/null)
    MFT_IDENTITY_CLIENT_ID=$(terraform output -raw mft_managed_identity_client_id 2>/dev/null)
    KEY_VAULT_NAME=$(terraform output -raw key_vault_name 2>/dev/null)
    TENANT_ID=$(terraform output -raw tenant_id 2>/dev/null)
    ENVIRONMENT_NAME=$(terraform output -raw environment_name 2>/dev/null)

    cd "${SCRIPT_DIR}" || exit 1

    # Validate outputs
    if [ -z "${ACR_LOGIN_SERVER}" ] || [ "${ACR_LOGIN_SERVER}" = "null" ]; then
        print_error "Failed to retrieve ACR login server from Terraform outputs."
        exit 1
    fi

    if [ -z "${MFT_IDENTITY_CLIENT_ID}" ] || [ "${MFT_IDENTITY_CLIENT_ID}" = "null" ]; then
        print_error "Failed to retrieve managed identity client ID from Terraform outputs."
        exit 1
    fi

    if [ -z "${KEY_VAULT_NAME}" ] || [ "${KEY_VAULT_NAME}" = "null" ]; then
        print_error "Failed to retrieve Key Vault name from Terraform outputs."
        exit 1
    fi

    if [ -z "${TENANT_ID}" ] || [ "${TENANT_ID}" = "null" ]; then
        print_error "Failed to retrieve tenant ID from Terraform outputs."
        exit 1
    fi

    if [ -z "${ENVIRONMENT_NAME}" ] || [ "${ENVIRONMENT_NAME}" = "null" ]; then
        print_error "Failed to retrieve environment name from Terraform outputs."
        exit 1
    fi

    # Export for use in templates
    export ACR_LOGIN_SERVER
    export MFT_IDENTITY_CLIENT_ID
    export KEY_VAULT_NAME
    export TENANT_ID
    export ENVIRONMENT_NAME

    print_success "ACR login server: ${ACR_LOGIN_SERVER}"
    print_success "Managed identity client ID: ${MFT_IDENTITY_CLIENT_ID}"
    print_success "Key Vault name: ${KEY_VAULT_NAME}"
    print_success "Tenant ID: ${TENANT_ID}"
    print_success "Environment: ${ENVIRONMENT_NAME}"
}

generate_manifests() {
    print_info "Generating Kubernetes manifests from templates..."

    # Check if envsubst is available
    if ! command -v envsubst &> /dev/null; then
        print_error "envsubst not found. Please install gettext package."
        exit 1
    fi

    # Generate ServiceAccount
    TEMPLATE_FILE="${KUBERNETES_DIR}/serviceaccount-dbc.yaml.template"
    OUTPUT_FILE="${KUBERNETES_DIR}/serviceaccount-dbc.yaml"

    if [ ! -f "${TEMPLATE_FILE}" ]; then
        print_error "Template file not found: ${TEMPLATE_FILE}"
        exit 1
    fi

    sed "s|<mft_managed_identity_client_id>|${MFT_IDENTITY_CLIENT_ID}|g" \
        "${TEMPLATE_FILE}" > "${OUTPUT_FILE}"

    if [ $? -eq 0 ]; then
        print_success "ServiceAccount manifest generated: ${OUTPUT_FILE}"
    else
        print_error "Failed to generate ServiceAccount manifest"
        exit 1
    fi

    # Generate SecretProviderClass
    TEMPLATE_FILE="${KUBERNETES_DIR}/secretproviderclass-dbc.yaml.template"
    OUTPUT_FILE="${KUBERNETES_DIR}/secretproviderclass-dbc.yaml"

    if [ ! -f "${TEMPLATE_FILE}" ]; then
        print_error "Template file not found: ${TEMPLATE_FILE}"
        exit 1
    fi

    sed -e "s|<mft_managed_identity_client_id>|${MFT_IDENTITY_CLIENT_ID}|g" \
        -e "s|<key_vault_name>|${KEY_VAULT_NAME}|g" \
        -e "s|<tenant_id>|${TENANT_ID}|g" \
        -e "s|<environment_name>|${ENVIRONMENT_NAME}|g" \
        "${TEMPLATE_FILE}" > "${OUTPUT_FILE}"

    if [ $? -eq 0 ]; then
        print_success "SecretProviderClass manifest generated: ${OUTPUT_FILE}"
    else
        print_error "Failed to generate SecretProviderClass manifest"
        exit 1
    fi

    # Generate Job
    TEMPLATE_FILE="${KUBERNETES_DIR}/job-dbc.yaml.template"
    OUTPUT_FILE="${KUBERNETES_DIR}/job-dbc.yaml"

    if [ ! -f "${TEMPLATE_FILE}" ]; then
        print_error "Template file not found: ${TEMPLATE_FILE}"
        exit 1
    fi

    envsubst < "${TEMPLATE_FILE}" > "${OUTPUT_FILE}"

    if [ $? -eq 0 ]; then
        print_success "Job manifest generated: ${OUTPUT_FILE}"
    else
        print_error "Failed to generate Job manifest"
        exit 1
    fi
}

check_prerequisites() {
    print_info "Checking prerequisites..."

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl not found. Please install kubectl."
        exit 1
    fi

    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
        exit 1
    fi

    # Check if namespace exists
    if ! kubectl get namespace "${NAMESPACE}" &> /dev/null; then
        print_warning "Namespace '${NAMESPACE}' does not exist. It will be created."
    fi

    # Check if CSI Secrets Store driver is installed
    if ! kubectl get csidriver secrets-store.csi.k8s.io &> /dev/null; then
        print_warning "CSI Secrets Store driver not found. Key Vault integration may not work."
        print_warning "The driver should be enabled on the AKS cluster."
    fi

    # Note: We don't check for the secret here as it will be created by the CSI driver
    # when the pod starts. The SecretProviderClass will handle the secret synchronization.

    print_success "Prerequisites check passed"
}

delete_existing_job() {
    if kubectl get job database-configurator -n "${NAMESPACE}" &> /dev/null; then
        print_info "Deleting existing job..."
        kubectl delete job database-configurator -n "${NAMESPACE}"
        # Wait a moment for the job to be fully deleted
        sleep 2
        print_success "Existing job deleted"
    fi
}

deploy_serviceaccount() {
    print_info "Deploying ServiceAccount..."

    if [ "${DRY_RUN}" = true ]; then
        kubectl apply -f "${KUBERNETES_DIR}/serviceaccount-dbc.yaml" -n "${NAMESPACE}" --dry-run=client
    else
        kubectl apply -f "${KUBERNETES_DIR}/serviceaccount-dbc.yaml" -n "${NAMESPACE}"
        print_success "ServiceAccount deployed"
    fi
}

deploy_secretproviderclass() {
    print_info "Deploying SecretProviderClass..."

    if [ "${DRY_RUN}" = true ]; then
        kubectl apply -f "${KUBERNETES_DIR}/secretproviderclass-dbc.yaml" -n "${NAMESPACE}" --dry-run=client
    else
        kubectl apply -f "${KUBERNETES_DIR}/secretproviderclass-dbc.yaml" -n "${NAMESPACE}"
        print_success "SecretProviderClass deployed"
    fi
}

deploy_configmap() {
    print_info "Deploying ConfigMap..."

    if [ "${DRY_RUN}" = true ]; then
        kubectl apply -f "${KUBERNETES_DIR}/configmap-dbc-script.yaml" -n "${NAMESPACE}" --dry-run=client
    else
        kubectl apply -f "${KUBERNETES_DIR}/configmap-dbc-script.yaml" -n "${NAMESPACE}"
        print_success "ConfigMap deployed"
    fi
}

deploy_job() {
    print_info "Deploying Database Configurator Job..."

    if [ "${DRY_RUN}" = true ]; then
        kubectl apply -f "${KUBERNETES_DIR}/job-dbc.yaml" -n "${NAMESPACE}" --dry-run=client
    else
        kubectl apply -f "${KUBERNETES_DIR}/job-dbc.yaml" -n "${NAMESPACE}"
        print_success "Job deployed"
    fi
}

wait_for_job() {
    print_info "Waiting for job to complete..."

    # Wait for job to start
    sleep 2

    # Get pod name
    POD_NAME=$(kubectl get pods -n "${NAMESPACE}" -l app=database-configurator -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [ -z "${POD_NAME}" ]; then
        print_warning "Pod not found yet. Job may still be starting."
        return
    fi

    print_info "Pod: ${POD_NAME}"

    if [ "${FOLLOW_LOGS}" = true ]; then
        print_info "Following logs (Ctrl+C to stop)..."
        kubectl logs -n "${NAMESPACE}" -f "${POD_NAME}" || true
    fi
}

show_status() {
    print_info "Job status:"
    kubectl get job database-configurator -n "${NAMESPACE}" 2>/dev/null || print_warning "Job not found"

    print_info "Pod status:"
    kubectl get pods -n "${NAMESPACE}" -l app=database-configurator 2>/dev/null || print_warning "No pods found"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --delete)
            DELETE_EXISTING=true
            shift
            ;;
        --logs)
            FOLLOW_LOGS=true
            shift
            ;;
        --help)
            show_help
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            ;;
    esac
done

# Main execution
echo "=========================================="
echo "Database Configurator Deployment"
echo "=========================================="
echo "Namespace: ${NAMESPACE}"
echo "Dry Run: ${DRY_RUN}"
echo "Delete Existing: ${DELETE_EXISTING}"
echo "Follow Logs: ${FOLLOW_LOGS}"
echo "=========================================="
echo ""

# Check prerequisites
check_prerequisites

# Get all required values from Terraform
get_terraform_outputs

# Generate all manifests from templates
generate_manifests

# Delete existing job if requested
if [ "${DELETE_EXISTING}" = true ]; then
    delete_existing_job
fi

# Deploy resources in order
deploy_serviceaccount
deploy_secretproviderclass
deploy_configmap
deploy_job

if [ "${DRY_RUN}" = false ]; then
    echo ""
    print_success "Deployment completed"
    echo ""

    # Wait and show status
    wait_for_job

    echo ""
    show_status

    echo ""
    print_info "To view logs:"
    echo "  kubectl logs -n ${NAMESPACE} -l app=database-configurator -f"

    print_info "To check job status:"
    echo "  kubectl get job database-configurator -n ${NAMESPACE}"

    print_info "To delete the job:"
    echo "  kubectl delete job database-configurator -n ${NAMESPACE}"
else
    echo ""
    print_info "Dry run completed. No resources were created."
fi
