#!/usr/bin/env bash
# ============================================================================
# Gather Private Storage Information Script
# ============================================================================
# This script collects comprehensive information about the private storage
# configuration for troubleshooting purposes.
#
# Usage:
#   ./gather-private-storage-info.sh <namespace> <output-dir>
#
# Example:
#   ./gather-private-storage-info.sh mft ./diagnostics-output
#
# Output:
#   Creates a timestamped directory with all collected information
# ============================================================================

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# Helper Functions
# ============================================================================

print_header() {
    echo ""
    echo -e "${BLUE}============================================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}============================================================================${NC}"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# ============================================================================
# Collection Functions
# ============================================================================

collect_kubernetes_resources() {
    print_header "Collecting Kubernetes Resources"
    
    local output_dir="$1"
    mkdir -p "$output_dir/kubernetes"
    
    # Secret (without sensitive data)
    print_info "Collecting secret metadata..."
    kubectl get secret mft-vfs-private-secret -n "$NAMESPACE" -o yaml 2>/dev/null | \
        sed 's/azurestorageaccountkey:.*/azurestorageaccountkey: <REDACTED>/' \
        > "$output_dir/kubernetes/secret.yaml" || print_error "Failed to get secret"
    
    # PersistentVolume
    print_info "Collecting PersistentVolume..."
    kubectl get pv mft-vfs-private-pv -o yaml > "$output_dir/kubernetes/pv.yaml" 2>/dev/null || \
        print_error "Failed to get PV"
    
    # PersistentVolumeClaim
    print_info "Collecting PersistentVolumeClaim..."
    kubectl get pvc mft-vfs-private-pvc -n "$NAMESPACE" -o yaml > "$output_dir/kubernetes/pvc.yaml" 2>/dev/null || \
        print_error "Failed to get PVC"
    
    # Storage Class (if exists)
    print_info "Collecting StorageClass..."
    kubectl get storageclass azurefile-csi-private -o yaml > "$output_dir/kubernetes/storageclass.yaml" 2>/dev/null || \
        print_info "StorageClass not found (optional)"
    
    # Pods
    print_info "Collecting pod information..."
    kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=active-transfer -o yaml > "$output_dir/kubernetes/pods.yaml" 2>/dev/null || \
        print_error "Failed to get pods"
    
    # Events
    print_info "Collecting events..."
    kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' > "$output_dir/kubernetes/events.txt" 2>/dev/null || \
        print_error "Failed to get events"
    
    print_success "Kubernetes resources collected"
}

collect_resource_descriptions() {
    print_header "Collecting Resource Descriptions"
    
    local output_dir="$1"
    mkdir -p "$output_dir/descriptions"
    
    # PV description
    print_info "Describing PersistentVolume..."
    kubectl describe pv mft-vfs-private-pv > "$output_dir/descriptions/pv-describe.txt" 2>/dev/null || \
        print_error "Failed to describe PV"
    
    # PVC description
    print_info "Describing PersistentVolumeClaim..."
    kubectl describe pvc mft-vfs-private-pvc -n "$NAMESPACE" > "$output_dir/descriptions/pvc-describe.txt" 2>/dev/null || \
        print_error "Failed to describe PVC"
    
    # Pod descriptions
    print_info "Describing pods..."
    local pods
    pods=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=active-transfer -o jsonpath='{.items[*].metadata.name}')
    
    for pod in $pods; do
        kubectl describe pod "$pod" -n "$NAMESPACE" > "$output_dir/descriptions/pod-${pod}-describe.txt" 2>/dev/null || \
            print_error "Failed to describe pod $pod"
    done
    
    print_success "Resource descriptions collected"
}

collect_pod_logs() {
    print_header "Collecting Pod Logs"
    
    local output_dir="$1"
    mkdir -p "$output_dir/logs"
    
    local pods
    pods=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=active-transfer -o jsonpath='{.items[*].metadata.name}')
    
    for pod in $pods; do
        print_info "Collecting logs for pod: $pod"
        
        # Current logs
        kubectl logs "$pod" -n "$NAMESPACE" --tail=1000 > "$output_dir/logs/${pod}-current.log" 2>/dev/null || \
            print_error "Failed to get current logs for $pod"
        
        # Previous logs (if pod restarted)
        kubectl logs "$pod" -n "$NAMESPACE" --previous --tail=1000 > "$output_dir/logs/${pod}-previous.log" 2>/dev/null || \
            print_info "No previous logs for $pod (pod hasn't restarted)"
        
        # Init container logs
        kubectl logs "$pod" -n "$NAMESPACE" -c envsubst-config --tail=1000 > "$output_dir/logs/${pod}-init.log" 2>/dev/null || \
            print_info "No init container logs for $pod"
    done
    
    print_success "Pod logs collected"
}

collect_csi_driver_logs() {
    print_header "Collecting CSI Driver Logs"
    
    local output_dir="$1"
    mkdir -p "$output_dir/csi-driver"
    
    # Get CSI driver pods
    print_info "Collecting CSI driver pod logs..."
    local csi_pods
    csi_pods=$(kubectl get pods -n kube-system -l app=csi-azurefile-node -o jsonpath='{.items[*].metadata.name}')
    
    for pod in $csi_pods; do
        print_info "Collecting logs for CSI pod: $pod"
        kubectl logs "$pod" -n kube-system -c azurefile --tail=500 > "$output_dir/csi-driver/${pod}.log" 2>/dev/null || \
            print_error "Failed to get CSI driver logs for $pod"
    done
    
    print_success "CSI driver logs collected"
}

collect_network_diagnostics() {
    print_header "Collecting Network Diagnostics"
    
    local output_dir="$1"
    mkdir -p "$output_dir/network"
    
    # Get first running pod
    local pod
    pod=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=active-transfer -o jsonpath='{.items[0].metadata.name}')
    
    if [[ -z "$pod" ]]; then
        print_error "No pods found for network diagnostics"
        return
    fi
    
    print_info "Using pod: $pod"
    
    # Get storage account name
    local storage_account
    storage_account=$(kubectl get secret mft-vfs-private-secret -n "$NAMESPACE" -o jsonpath='{.data.azurestorageaccountname}' | base64 -d 2>/dev/null)
    
    if [[ -n "$storage_account" ]]; then
        local fqdn="${storage_account}.file.core.windows.net"
        
        # DNS resolution
        print_info "Testing DNS resolution..."
        kubectl exec "$pod" -n "$NAMESPACE" -- nslookup "$fqdn" > "$output_dir/network/dns-resolution.txt" 2>&1 || \
            print_error "DNS resolution failed"
        
        # Ping test (may not work due to ICMP blocking)
        print_info "Testing connectivity (ping)..."
        kubectl exec "$pod" -n "$NAMESPACE" -- ping -c 3 "$fqdn" > "$output_dir/network/ping-test.txt" 2>&1 || \
            print_info "Ping test failed (ICMP may be blocked)"
        
        # Port connectivity test
        print_info "Testing SMB port connectivity..."
        kubectl exec "$pod" -n "$NAMESPACE" -- nc -zv "$fqdn" 445 > "$output_dir/network/port-445-test.txt" 2>&1 || \
            print_info "Port 445 test failed (nc may not be available)"
    else
        print_error "Storage account name not found"
    fi
    
    print_success "Network diagnostics collected"
}

collect_mount_information() {
    print_header "Collecting Mount Information"
    
    local output_dir="$1"
    mkdir -p "$output_dir/mounts"
    
    local pods
    pods=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=active-transfer -o jsonpath='{.items[*].metadata.name}')
    
    for pod in $pods; do
        print_info "Collecting mount info for pod: $pod"
        
        # df output
        kubectl exec "$pod" -n "$NAMESPACE" -- df -h > "$output_dir/mounts/${pod}-df.txt" 2>/dev/null || \
            print_error "Failed to get df output for $pod"
        
        # mount output
        kubectl exec "$pod" -n "$NAMESPACE" -- mount > "$output_dir/mounts/${pod}-mount.txt" 2>/dev/null || \
            print_error "Failed to get mount output for $pod"
        
        # VFS directory listing
        kubectl exec "$pod" -n "$NAMESPACE" -- ls -la /opt/IBM/MFT/vfs-private > "$output_dir/mounts/${pod}-vfs-ls.txt" 2>/dev/null || \
            print_error "Failed to list VFS directory for $pod"
    done
    
    print_success "Mount information collected"
}

collect_azure_resources() {
    print_header "Collecting Azure Resource Information"
    
    local output_dir="$1"
    mkdir -p "$output_dir/azure"
    
    # Check if Azure CLI is available
    if ! command -v az &>/dev/null; then
        print_info "Azure CLI not available, skipping Azure resource collection"
        return
    fi
    
    # Get storage account name
    local storage_account
    storage_account=$(kubectl get secret mft-vfs-private-secret -n "$NAMESPACE" -o jsonpath='{.data.azurestorageaccountname}' | base64 -d 2>/dev/null)
    
    if [[ -z "$storage_account" ]]; then
        print_error "Storage account name not found"
        return
    fi
    
    print_info "Collecting Azure storage account information..."
    
    # Storage account details
    az storage account show --name "$storage_account" --query "{name:name, location:location, publicAccess:publicNetworkAccess, privateEndpoints:privateEndpointConnections}" -o json > "$output_dir/azure/storage-account.json" 2>/dev/null || \
        print_error "Failed to get storage account details (check Azure CLI authentication)"
    
    # File share details
    az storage share list --account-name "$storage_account" -o json > "$output_dir/azure/file-shares.json" 2>/dev/null || \
        print_error "Failed to get file share details"
    
    print_success "Azure resource information collected"
}

create_summary() {
    print_header "Creating Summary Report"
    
    local output_dir="$1"
    local summary_file="$output_dir/SUMMARY.txt"
    
    {
        echo "============================================================================"
        echo "Private Storage Diagnostic Information Summary"
        echo "============================================================================"
        echo ""
        echo "Collection Date: $(date)"
        echo "Namespace: $NAMESPACE"
        echo ""
        echo "============================================================================"
        echo "Collected Information"
        echo "============================================================================"
        echo ""
        echo "Kubernetes Resources:"
        echo "  - Secret metadata (credentials redacted)"
        echo "  - PersistentVolume YAML"
        echo "  - PersistentVolumeClaim YAML"
        echo "  - StorageClass YAML (if exists)"
        echo "  - Pod YAML"
        echo "  - Events"
        echo ""
        echo "Resource Descriptions:"
        echo "  - PV description"
        echo "  - PVC description"
        echo "  - Pod descriptions"
        echo ""
        echo "Logs:"
        echo "  - Pod logs (current and previous)"
        echo "  - Init container logs"
        echo "  - CSI driver logs"
        echo ""
        echo "Network Diagnostics:"
        echo "  - DNS resolution"
        echo "  - Connectivity tests"
        echo ""
        echo "Mount Information:"
        echo "  - df output"
        echo "  - mount output"
        echo "  - VFS directory listings"
        echo ""
        echo "Azure Resources:"
        echo "  - Storage account details (if Azure CLI available)"
        echo "  - File share details (if Azure CLI available)"
        echo ""
        echo "============================================================================"
        echo "Next Steps"
        echo "============================================================================"
        echo ""
        echo "1. Review the collected information in the output directory"
        echo "2. Check for errors in pod logs and CSI driver logs"
        echo "3. Verify DNS resolution points to private IP"
        echo "4. Ensure PV and PVC are bound correctly"
        echo "5. Check Azure portal for private endpoint status"
        echo ""
        echo "For support, provide this entire directory to your support team."
        echo ""
    } > "$summary_file"
    
    print_success "Summary report created: $summary_file"
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    # Check arguments
    if [[ $# -lt 2 ]]; then
        echo "Usage: $0 <namespace> <output-dir>"
        echo "Example: $0 mft ./diagnostics-output"
        exit 1
    fi
    
    NAMESPACE="$1"
    OUTPUT_BASE="$2"
    
    # Create timestamped output directory
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    OUTPUT_DIR="${OUTPUT_BASE}/private-storage-diagnostics-${TIMESTAMP}"
    
    print_header "Private Storage Information Gathering"
    echo "Namespace: $NAMESPACE"
    echo "Output Directory: $OUTPUT_DIR"
    echo ""
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    # Collect all information
    collect_kubernetes_resources "$OUTPUT_DIR"
    collect_resource_descriptions "$OUTPUT_DIR"
    collect_pod_logs "$OUTPUT_DIR"
    collect_csi_driver_logs "$OUTPUT_DIR"
    collect_network_diagnostics "$OUTPUT_DIR"
    collect_mount_information "$OUTPUT_DIR"
    collect_azure_resources "$OUTPUT_DIR"
    create_summary "$OUTPUT_DIR"
    
    # Print completion message
    print_header "Collection Complete"
    echo -e "${GREEN}✓ All information collected successfully${NC}"
    echo ""
    echo "Output directory: $OUTPUT_DIR"
    echo ""
    echo "To create a tarball for sharing:"
    echo "  tar -czf private-storage-diagnostics-${TIMESTAMP}.tar.gz -C ${OUTPUT_BASE} private-storage-diagnostics-${TIMESTAMP}"
    echo ""
}

# Run main function
main "$@"
