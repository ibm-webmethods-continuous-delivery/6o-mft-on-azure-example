#!/bin/bash
#
# Database User Initialization Deployment Script
# Uses Azure Key Vault CSI Secrets Store driver for credential management
#

set -e

NAMESPACE="default"
DRY_RUN=false
DELETE_EXISTING=false
FOLLOW_LOGS=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBERNETES_DIR="${SCRIPT_DIR}/kubernetes"
TF_DIR="${SCRIPT_DIR}/../../01-AzurePrerequisites/02-ServiceFulfillment"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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
    cat <<'EOF'
Database User Initialization Deployment Script

Usage:
  ./deploy.sh [OPTIONS]

Options:
  --namespace <name>    Kubernetes namespace (default: default)
  --dry-run             Show what would be deployed without applying
  --delete              Delete existing job before deploying
  --logs                Follow logs after deployment
  --help                Show this help message

Prerequisites:
  1. Terraform applied in ../../01-AzurePrerequisites/02-ServiceFulfillment
  2. AKS cluster with CSI Secrets Store driver enabled
  3. Database credentials populated in Azure Key Vault (via Terraform)
  4. Federated credential for database-user-init-sa created (via Terraform)

This script automatically:
  - Retrieves configuration from Terraform outputs
  - Generates ServiceAccount and SecretProviderClass manifests
  - Deploys all required Kubernetes resources
  - Uses Azure Workload Identity for secure Key Vault access
EOF
    exit 0
}

check_prerequisites() {
    print_info "Checking prerequisites..."

    if ! command -v kubectl >/dev/null 2>&1; then
        print_error "kubectl not found. Please install kubectl."
        exit 1
    fi

    if ! kubectl cluster-info >/dev/null 2>&1; then
        print_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
        exit 1
    fi

    if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
        print_warning "Namespace '${NAMESPACE}' does not exist. It will be created by kubectl apply if manifests include it or after manual creation."
    fi

    # Check if CSI Secrets Store driver is available
    if ! kubectl get csidriver secrets-store.csi.k8s.io >/dev/null 2>&1; then
        print_error "CSI Secrets Store driver not found in cluster."
        print_error "Please ensure the AKS cluster has the CSI driver enabled."
        exit 1
    fi

    print_success "Prerequisites check passed"
}

retrieve_terraform_outputs() {
    print_info "Retrieving Terraform outputs..."

    if [ ! -d "${TF_DIR}" ]; then
        print_error "Terraform directory not found: ${TF_DIR}"
        exit 1
    fi

    cd "${TF_DIR}" || exit 1

    # Check if Terraform state exists
    if ! terraform show >/dev/null 2>&1; then
        print_error "Terraform state not found or invalid."
        print_error "Please run 'terraform apply' in ${TF_DIR}"
        exit 1
    fi

    # Retrieve outputs
    export MFT_IDENTITY_CLIENT_ID=$(terraform output -raw mft_managed_identity_client_id 2>/dev/null)
    export KEY_VAULT_NAME=$(terraform output -raw key_vault_name 2>/dev/null)
    export TENANT_ID=$(terraform output -raw tenant_id 2>/dev/null)
    export ENVIRONMENT=$(terraform output -raw environment_name 2>/dev/null)

    cd "${SCRIPT_DIR}" || exit 1

    # Validate outputs
    if [ -z "${MFT_IDENTITY_CLIENT_ID}" ] || [ -z "${KEY_VAULT_NAME}" ] || \
       [ -z "${TENANT_ID}" ] || [ -z "${ENVIRONMENT}" ]; then
        print_error "Failed to retrieve all required Terraform outputs."
        print_error "Please ensure Terraform has been applied successfully."
        exit 1
    fi

    print_success "Terraform outputs retrieved:"
    print_info "  - Client ID: ${MFT_IDENTITY_CLIENT_ID}"
    print_info "  - Key Vault: ${KEY_VAULT_NAME}"
    print_info "  - Tenant ID: ${TENANT_ID}"
    print_info "  - Environment: ${ENVIRONMENT}"
}

generate_manifests() {
    print_info "Generating Kubernetes manifests from templates..."

    # Generate ServiceAccount
    if [ -f "${KUBERNETES_DIR}/serviceaccount-db-user-init.yaml.template" ]; then
        envsubst < "${KUBERNETES_DIR}/serviceaccount-db-user-init.yaml.template" \
            > "${KUBERNETES_DIR}/serviceaccount-db-user-init.yaml"
        print_success "ServiceAccount manifest generated"
    else
        print_error "ServiceAccount template not found"
        exit 1
    fi

    # Generate SecretProviderClass
    if [ -f "${KUBERNETES_DIR}/secretproviderclass-db-user-init.yaml.template" ]; then
        envsubst < "${KUBERNETES_DIR}/secretproviderclass-db-user-init.yaml.template" \
            > "${KUBERNETES_DIR}/secretproviderclass-db-user-init.yaml"
        print_success "SecretProviderClass manifest generated"
    else
        print_error "SecretProviderClass template not found"
        exit 1
    fi
}

delete_existing_job() {
    if kubectl get job database-user-init -n "${NAMESPACE}" >/dev/null 2>&1; then
        print_info "Deleting existing job..."
        kubectl delete job database-user-init -n "${NAMESPACE}"
        print_success "Existing job deleted"
    fi
}

deploy_serviceaccount() {
    print_info "Deploying ServiceAccount..."

    if [ "${DRY_RUN}" = true ]; then
        kubectl apply -f "${KUBERNETES_DIR}/serviceaccount-db-user-init.yaml" -n "${NAMESPACE}" --dry-run=client
    else
        kubectl apply -f "${KUBERNETES_DIR}/serviceaccount-db-user-init.yaml" -n "${NAMESPACE}"
        print_success "ServiceAccount deployed"
    fi
}

deploy_secretproviderclass() {
    print_info "Deploying SecretProviderClass..."

    if [ "${DRY_RUN}" = true ]; then
        kubectl apply -f "${KUBERNETES_DIR}/secretproviderclass-db-user-init.yaml" -n "${NAMESPACE}" --dry-run=client
    else
        kubectl apply -f "${KUBERNETES_DIR}/secretproviderclass-db-user-init.yaml" -n "${NAMESPACE}"
        print_success "SecretProviderClass deployed"
    fi
}

deploy_configmap() {
    print_info "Deploying ConfigMap..."

    if [ "${DRY_RUN}" = true ]; then
        kubectl apply -f "${KUBERNETES_DIR}/configmap-db-user-init-script.yaml" -n "${NAMESPACE}" --dry-run=client
    else
        kubectl apply -f "${KUBERNETES_DIR}/configmap-db-user-init-script.yaml" -n "${NAMESPACE}"
        print_success "ConfigMap deployed"
    fi
}

deploy_job() {
    print_info "Deploying Job..."

    if [ "${DRY_RUN}" = true ]; then
        kubectl apply -f "${KUBERNETES_DIR}/job-db-user-init.yaml" -n "${NAMESPACE}" --dry-run=client
    else
        kubectl apply -f "${KUBERNETES_DIR}/job-db-user-init.yaml" -n "${NAMESPACE}"
        print_success "Job deployed"
    fi
}

wait_for_job() {
    print_info "Waiting for job to start..."
    sleep 2

    POD_NAME="$(kubectl get pods -n "${NAMESPACE}" -l app=database-user-init -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")"

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
    kubectl get job database-user-init -n "${NAMESPACE}" 2>/dev/null || print_warning "Job not found"

    print_info "Pod status:"
    kubectl get pods -n "${NAMESPACE}" -l app=database-user-init 2>/dev/null || print_warning "No pods found"

    print_info "SecretProviderClass status:"
    kubectl get secretproviderclass db-user-init-azure-kv-secrets -n "${NAMESPACE}" 2>/dev/null || print_warning "SecretProviderClass not found"

    print_info "Synced secret status:"
    kubectl get secret db-user-init-credentials-synced -n "${NAMESPACE}" 2>/dev/null || print_warning "Synced secret not found (will be created when pod starts)"
}

while [ $# -gt 0 ]; do
    case "$1" in
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

echo "=========================================="
echo "Database User Initialization Deployment"
echo "=========================================="
echo "Namespace: ${NAMESPACE}"
echo "Dry Run: ${DRY_RUN}"
echo "Delete Existing: ${DELETE_EXISTING}"
echo "Follow Logs: ${FOLLOW_LOGS}"
echo "=========================================="
echo ""

check_prerequisites
retrieve_terraform_outputs
generate_manifests

if [ "${DELETE_EXISTING}" = true ]; then
    delete_existing_job
fi

deploy_serviceaccount
deploy_secretproviderclass
deploy_configmap
deploy_job

if [ "${DRY_RUN}" = false ]; then
    echo ""
    print_success "Deployment completed"
    echo ""
    wait_for_job
    echo ""
    show_status
    echo ""
    print_info "To view logs: kubectl logs -l app=database-user-init -n ${NAMESPACE}"
    print_info "To check secret mount: kubectl describe pod -l app=database-user-init -n ${NAMESPACE}"
else
    echo ""
    print_info "Dry run completed. No resources were created."
fi
