#!/usr/bin/env bash
# ============================================================================
# Deploy Active Transfer to Azure AKS
# ============================================================================
# This script deploys the Active Transfer Helm chart to Azure Kubernetes Service.
#
# Prerequisites:
#   - kubectl configured with access to target AKS cluster
#   - helm installed (v3+)
#   - Secrets created (run generate-secrets.sh first)
#   - Database initialized (00-DatabaseUserInit and 01-DatabaseConfigurator)
#   - values.yaml updated with environment-specific values
#
# Usage:
#   ./deploy.sh [OPTIONS]
#
# Options:
#   --namespace <name>    Kubernetes namespace (default: mft)
#   --release <name>      Helm release name (default: active-transfer)
#   --values <file>       Additional values file (default: values.yaml)
#   --dry-run            Perform a dry run without installing
#   --upgrade            Upgrade existing release
#   --uninstall          Uninstall the release
#   --help               Show this help message
# ============================================================================

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELM_DIR="${SCRIPT_DIR}/../helm"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Default values
NAMESPACE="mft"
RELEASE_NAME="active-transfer"
VALUES_FILE="${HELM_DIR}/values.yaml"
DRY_RUN=false
UPGRADE=false
UNINSTALL=false
ADDITIONAL_VALUES=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --release)
            RELEASE_NAME="$2"
            shift 2
            ;;
        --values)
            ADDITIONAL_VALUES="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --upgrade)
            UPGRADE=true
            shift
            ;;
        --uninstall)
            UNINSTALL=true
            shift
            ;;
        --help)
            grep '^#' "$0" | grep -v '#!/usr/bin/env' | sed 's/^# //' | sed 's/^#//'
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# ============================================================================
# Helper Functions
# ============================================================================

print_header() {
    echo ""
    echo "============================================================================"
    echo "$1"
    echo "============================================================================"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        print_error "$1 is not installed. Please install $1."
        exit 1
    fi
}

# ============================================================================
# Uninstall
# ============================================================================

if [[ "$UNINSTALL" == "true" ]]; then
    print_header "Uninstalling Active Transfer"
    
    print_info "Release: $RELEASE_NAME"
    print_info "Namespace: $NAMESPACE"
    echo ""
    
    if helm list -n "$NAMESPACE" | grep -q "$RELEASE_NAME"; then
        helm uninstall "$RELEASE_NAME" -n "$NAMESPACE"
        print_success "Release uninstalled successfully"
    else
        print_warning "Release $RELEASE_NAME not found in namespace $NAMESPACE"
    fi
    
    exit 0
fi

# ============================================================================
# Pre-flight Checks
# ============================================================================

print_header "Active Transfer Deployment - Pre-flight Checks"

# Check required commands
print_info "Checking required commands..."
check_command kubectl
check_command helm
print_success "All required commands are available"

# Check kubectl connectivity
print_info "Checking Kubernetes cluster connectivity..."
if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster. Please configure kubectl."
    exit 1
fi
print_success "Connected to Kubernetes cluster"

# Get cluster info
CLUSTER_NAME=$(kubectl config current-context)
print_info "Current cluster: $CLUSTER_NAME"

# Check if namespace exists, create if not
print_info "Checking namespace: $NAMESPACE"
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    print_warning "Namespace $NAMESPACE does not exist. Creating..."
    kubectl create namespace "$NAMESPACE"
    print_success "Namespace created"
else
    print_success "Namespace exists"
fi

# Check if secrets exist
print_info "Checking required secrets..."
REQUIRED_SECRETS=(
    "mft-db-credentials"
    "mft-admin-ui-certs"
    "mft-web-client-certs"
    "mft-sftp-ssh-keys"
    "mft-admin-credentials"
)

MISSING_SECRETS=()
for secret in "${REQUIRED_SECRETS[@]}"; do
    if ! kubectl get secret "$secret" -n "$NAMESPACE" &> /dev/null; then
        MISSING_SECRETS+=("$secret")
    fi
done

if [[ ${#MISSING_SECRETS[@]} -gt 0 ]]; then
    print_error "Missing required secrets:"
    for secret in "${MISSING_SECRETS[@]}"; do
        echo "  - $secret"
    done
    echo ""
    print_info "Run generate-secrets.sh to create secrets:"
    echo "  cd scripts && ./generate-secrets.sh --apply"
    exit 1
fi
print_success "All required secrets exist"

# Check if values file exists
print_info "Checking values file: $VALUES_FILE"
if [[ ! -f "$VALUES_FILE" ]]; then
    print_error "Values file not found: $VALUES_FILE"
    exit 1
fi
print_success "Values file exists"

# Validate Helm chart
print_info "Validating Helm chart..."
if ! helm lint "$HELM_DIR" &> /dev/null; then
    print_error "Helm chart validation failed"
    helm lint "$HELM_DIR"
    exit 1
fi
print_success "Helm chart is valid"

# ============================================================================
# Deployment
# ============================================================================

print_header "Deploying Active Transfer"

print_info "Release: $RELEASE_NAME"
print_info "Namespace: $NAMESPACE"
print_info "Chart: $HELM_DIR"
print_info "Values: $VALUES_FILE"
if [[ -n "$ADDITIONAL_VALUES" ]]; then
    print_info "Additional values: $ADDITIONAL_VALUES"
fi
echo ""

# Build helm command
HELM_CMD="helm"
if [[ "$UPGRADE" == "true" ]]; then
    HELM_CMD="$HELM_CMD upgrade --install"
else
    HELM_CMD="$HELM_CMD install"
fi

HELM_CMD="$HELM_CMD $RELEASE_NAME $HELM_DIR"
HELM_CMD="$HELM_CMD --namespace $NAMESPACE"
HELM_CMD="$HELM_CMD --values $VALUES_FILE"

if [[ -n "$ADDITIONAL_VALUES" ]]; then
    HELM_CMD="$HELM_CMD --values $ADDITIONAL_VALUES"
fi

if [[ "$DRY_RUN" == "true" ]]; then
    HELM_CMD="$HELM_CMD --dry-run --debug"
fi

# Execute deployment
print_info "Executing: $HELM_CMD"
echo ""

if eval "$HELM_CMD"; then
    if [[ "$DRY_RUN" == "true" ]]; then
        print_success "Dry run completed successfully"
    else
        print_success "Deployment completed successfully"
    fi
else
    print_error "Deployment failed"
    exit 1
fi

# ============================================================================
# Post-deployment Information
# ============================================================================

if [[ "$DRY_RUN" == "false" ]]; then
    print_header "Post-deployment Information"
    
    # Wait for pods to be ready
    print_info "Waiting for pods to be ready (this may take a few minutes)..."
    kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/name=active-transfer \
        -n "$NAMESPACE" \
        --timeout=600s || true
    
    # Get deployment status
    echo ""
    print_info "Deployment status:"
    kubectl get deployment -l app.kubernetes.io/name=active-transfer -n "$NAMESPACE"
    
    echo ""
    print_info "Pod status:"
    kubectl get pods -l app.kubernetes.io/name=active-transfer -n "$NAMESPACE"
    
    echo ""
    print_info "Service status:"
    kubectl get svc -l app.kubernetes.io/name=active-transfer -n "$NAMESPACE"
    
    echo ""
    print_info "Ingress status:"
    kubectl get ingress -l app.kubernetes.io/name=active-transfer -n "$NAMESPACE"
    
    echo ""
    print_info "PVC status:"
    kubectl get pvc -l app.kubernetes.io/name=active-transfer -n "$NAMESPACE"
    
    # ============================================================================
    # Helpful Commands
    # ============================================================================
    
    print_header "Helpful Commands"
    
    echo "View logs:"
    echo "  kubectl logs -l app.kubernetes.io/name=active-transfer -n $NAMESPACE -f"
    echo ""
    
    echo "Get pod details:"
    echo "  kubectl describe pod -l app.kubernetes.io/name=active-transfer -n $NAMESPACE"
    echo ""
    
    echo "Execute shell in pod:"
    echo "  kubectl exec -it -n $NAMESPACE \$(kubectl get pod -l app.kubernetes.io/name=active-transfer -n $NAMESPACE -o jsonpath='{.items[0].metadata.name}') -- /bin/bash"
    echo ""
    
    echo "Port forward to admin UI:"
    echo "  kubectl port-forward -n $NAMESPACE svc/$RELEASE_NAME 5555:5555"
    echo "  Then access: http://localhost:5555"
    echo ""
    
    echo "View Helm release:"
    echo "  helm list -n $NAMESPACE"
    echo "  helm status $RELEASE_NAME -n $NAMESPACE"
    echo ""
    
    echo "Upgrade release:"
    echo "  ./deploy.sh --upgrade"
    echo ""
    
    echo "Uninstall release:"
    echo "  ./deploy.sh --uninstall"
    echo ""
fi

print_header "Deployment Complete"
