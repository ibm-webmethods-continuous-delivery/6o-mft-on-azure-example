#!/bin/bash
#
# Database User Initialization Deployment Script
#

set -e

NAMESPACE="default"
DRY_RUN=false
DELETE_EXISTING=false
FOLLOW_LOGS=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBERNETES_DIR="${SCRIPT_DIR}/kubernetes"

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
  1. Decide application credentials (see README.md Step 1)
  2. Generate secret: ./scripts/generate-secret.sh
  3. Apply secret: kubectl apply -f kubernetes/secret-db-user-init-admin-creds.yaml
  4. Run this script
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

    # Check if secret exists
    if ! kubectl get secret db-user-init-admin-credentials -n "${NAMESPACE}" >/dev/null 2>&1; then
        print_error "Secret 'db-user-init-admin-credentials' not found in namespace '${NAMESPACE}'."
        echo ""
        print_info "To create the secret, follow these steps:"
        echo "  1. Set application credentials (see README.md Step 1)"
        echo "  2. Run: ./scripts/generate-secret.sh"
        echo "  3. Apply: kubectl apply -f kubernetes/secret-db-user-init-admin-creds.yaml"
        echo ""
        exit 1
    fi

    print_success "Prerequisites check passed"
}

delete_existing_job() {
    if kubectl get job database-user-init -n "${NAMESPACE}" >/dev/null 2>&1; then
        print_info "Deleting existing job..."
        kubectl delete job database-user-init -n "${NAMESPACE}"
        print_success "Existing job deleted"
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

if [ "${DELETE_EXISTING}" = true ]; then
    delete_existing_job
fi

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
else
    echo ""
    print_info "Dry run completed. No resources were created."
fi