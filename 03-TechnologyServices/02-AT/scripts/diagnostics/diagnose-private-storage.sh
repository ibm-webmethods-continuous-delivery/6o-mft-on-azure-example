#!/usr/bin/env bash
# ============================================================================
# Diagnostic Script for Private Azure Files Storage
# ============================================================================
# This script performs comprehensive post-installation validation of the
# private storage configuration for MFT VFS.
#
# Usage:
#   ./diagnose-private-storage.sh <namespace>
#
# Example:
#   ./diagnose-private-storage.sh mft
#
# Exit Codes:
#   0 - All checks passed
#   1 - One or more checks failed
# ============================================================================

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check counters
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

# ============================================================================
# Helper Functions
# ============================================================================

print_header() {
    echo ""
    echo -e "${BLUE}============================================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}============================================================================${NC}"
}

print_check() {
    echo -e "${BLUE}[CHECK]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓ PASS]${NC} $1"
    ((CHECKS_PASSED++))
}

print_failure() {
    echo -e "${RED}[✗ FAIL]${NC} $1"
    ((CHECKS_FAILED++))
}

print_warning() {
    echo -e "${YELLOW}[⚠ WARN]${NC} $1"
    ((CHECKS_WARNING++))
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# ============================================================================
# Validation Functions
# ============================================================================

check_namespace() {
    print_check "Checking if namespace '$NAMESPACE' exists..."
    if kubectl get namespace "$NAMESPACE" &>/dev/null; then
        print_success "Namespace '$NAMESPACE' exists"
        return 0
    else
        print_failure "Namespace '$NAMESPACE' does not exist"
        return 1
    fi
}

check_secret() {
    print_check "Checking if storage secret exists..."
    
    if ! kubectl get secret mft-vfs-private-secret -n "$NAMESPACE" &>/dev/null; then
        print_failure "Secret 'mft-vfs-private-secret' not found"
        return 1
    fi
    
    print_success "Secret 'mft-vfs-private-secret' exists"
    
    # Validate secret has required keys
    print_check "Validating secret keys..."
    local has_account_name=false
    local has_account_key=false
    
    if kubectl get secret mft-vfs-private-secret -n "$NAMESPACE" -o jsonpath='{.data.azurestorageaccountname}' | base64 -d &>/dev/null; then
        has_account_name=true
    fi
    
    if kubectl get secret mft-vfs-private-secret -n "$NAMESPACE" -o jsonpath='{.data.azurestorageaccountkey}' | base64 -d &>/dev/null; then
        has_account_key=true
    fi
    
    if [[ "$has_account_name" == true ]] && [[ "$has_account_key" == true ]]; then
        print_success "Secret contains required keys (azurestorageaccountname, azurestorageaccountkey)"
        
        # Get storage account name for later use
        STORAGE_ACCOUNT=$(kubectl get secret mft-vfs-private-secret -n "$NAMESPACE" -o jsonpath='{.data.azurestorageaccountname}' | base64 -d)
        print_info "Storage account: $STORAGE_ACCOUNT"
        return 0
    else
        print_failure "Secret is missing required keys"
        return 1
    fi
}

check_pv() {
    print_check "Checking if PersistentVolume exists..."
    
    if ! kubectl get pv mft-vfs-private-pv &>/dev/null; then
        print_failure "PersistentVolume 'mft-vfs-private-pv' not found"
        return 1
    fi
    
    print_success "PersistentVolume 'mft-vfs-private-pv' exists"
    
    # Check PV status
    print_check "Checking PV status..."
    local pv_status
    pv_status=$(kubectl get pv mft-vfs-private-pv -o jsonpath='{.status.phase}')
    
    if [[ "$pv_status" == "Bound" ]]; then
        print_success "PV is Bound"
    elif [[ "$pv_status" == "Available" ]]; then
        print_warning "PV is Available but not Bound (PVC may not exist yet)"
    else
        print_failure "PV status is '$pv_status' (expected: Bound or Available)"
        return 1
    fi
    
    # Check PV capacity
    print_check "Checking PV capacity..."
    local pv_capacity
    pv_capacity=$(kubectl get pv mft-vfs-private-pv -o jsonpath='{.spec.capacity.storage}')
    print_info "PV capacity: $pv_capacity"
    
    # Check storage class
    print_check "Checking PV storage class..."
    local pv_sc
    pv_sc=$(kubectl get pv mft-vfs-private-pv -o jsonpath='{.spec.storageClassName}')
    if [[ -z "$pv_sc" ]]; then
        print_success "PV has empty storageClassName (correct for static provisioning)"
    else
        print_warning "PV has storageClassName '$pv_sc' (expected: empty for static provisioning)"
    fi
    
    return 0
}

check_pvc() {
    print_check "Checking if PersistentVolumeClaim exists..."
    
    if ! kubectl get pvc mft-vfs-private-pvc -n "$NAMESPACE" &>/dev/null; then
        print_failure "PersistentVolumeClaim 'mft-vfs-private-pvc' not found"
        return 1
    fi
    
    print_success "PersistentVolumeClaim 'mft-vfs-private-pvc' exists"
    
    # Check PVC status
    print_check "Checking PVC status..."
    local pvc_status
    pvc_status=$(kubectl get pvc mft-vfs-private-pvc -n "$NAMESPACE" -o jsonpath='{.status.phase}')
    
    if [[ "$pvc_status" == "Bound" ]]; then
        print_success "PVC is Bound"
    else
        print_failure "PVC status is '$pvc_status' (expected: Bound)"
        return 1
    fi
    
    # Check PVC is bound to correct PV
    print_check "Checking PVC binding..."
    local bound_pv
    bound_pv=$(kubectl get pvc mft-vfs-private-pvc -n "$NAMESPACE" -o jsonpath='{.spec.volumeName}')
    
    if [[ "$bound_pv" == "mft-vfs-private-pv" ]]; then
        print_success "PVC is bound to correct PV: $bound_pv"
    else
        print_failure "PVC is bound to wrong PV: $bound_pv (expected: mft-vfs-private-pv)"
        return 1
    fi
    
    return 0
}

check_pod_mounts() {
    print_check "Checking pod volume mounts..."
    
    # Get pods with active-transfer label
    local pods
    pods=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=active-transfer -o jsonpath='{.items[*].metadata.name}')
    
    if [[ -z "$pods" ]]; then
        print_warning "No active-transfer pods found"
        return 0
    fi
    
    print_info "Found pods: $pods"
    
    local all_mounted=true
    for pod in $pods; do
        print_check "Checking pod '$pod'..."
        
        # Check if pod is running
        local pod_status
        pod_status=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
        
        if [[ "$pod_status" != "Running" ]]; then
            print_warning "Pod '$pod' is not Running (status: $pod_status)"
            continue
        fi
        
        # Check if volume is mounted
        if kubectl exec "$pod" -n "$NAMESPACE" -- df -h /opt/IBM/MFT/vfs-private &>/dev/null; then
            print_success "Pod '$pod' has private VFS mounted at /opt/IBM/MFT/vfs-private"
            
            # Get mount details
            local mount_info
            mount_info=$(kubectl exec "$pod" -n "$NAMESPACE" -- df -h /opt/IBM/MFT/vfs-private 2>/dev/null | tail -1)
            print_info "Mount: $mount_info"
        else
            print_failure "Pod '$pod' does not have private VFS mounted"
            all_mounted=false
        fi
    done
    
    if [[ "$all_mounted" == true ]]; then
        return 0
    else
        return 1
    fi
}

check_file_operations() {
    print_check "Testing file operations on private VFS..."
    
    # Get first running pod
    local pod
    pod=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=active-transfer -o jsonpath='{.items[0].metadata.name}')
    
    if [[ -z "$pod" ]]; then
        print_warning "No active-transfer pods found, skipping file operations test"
        return 0
    fi
    
    local pod_status
    pod_status=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
    
    if [[ "$pod_status" != "Running" ]]; then
        print_warning "Pod '$pod' is not Running, skipping file operations test"
        return 0
    fi
    
    print_info "Using pod: $pod"
    
    # Test write
    print_check "Testing write operation..."
    if kubectl exec "$pod" -n "$NAMESPACE" -- sh -c "echo 'test-$(date +%s)' > /opt/IBM/MFT/vfs-private/.diagnostic-test" &>/dev/null; then
        print_success "Write operation successful"
    else
        print_failure "Write operation failed"
        return 1
    fi
    
    # Test read
    print_check "Testing read operation..."
    if kubectl exec "$pod" -n "$NAMESPACE" -- cat /opt/IBM/MFT/vfs-private/.diagnostic-test &>/dev/null; then
        print_success "Read operation successful"
    else
        print_failure "Read operation failed"
        return 1
    fi
    
    # Test delete
    print_check "Testing delete operation..."
    if kubectl exec "$pod" -n "$NAMESPACE" -- rm /opt/IBM/MFT/vfs-private/.diagnostic-test &>/dev/null; then
        print_success "Delete operation successful"
    else
        print_failure "Delete operation failed"
        return 1
    fi
    
    return 0
}

check_dns_resolution() {
    print_check "Testing DNS resolution to private IP..."
    
    if [[ -z "$STORAGE_ACCOUNT" ]]; then
        print_warning "Storage account name not available, skipping DNS test"
        return 0
    fi
    
    # Get first running pod
    local pod
    pod=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=active-transfer -o jsonpath='{.items[0].metadata.name}')
    
    if [[ -z "$pod" ]]; then
        print_warning "No active-transfer pods found, skipping DNS test"
        return 0
    fi
    
    local fqdn="${STORAGE_ACCOUNT}.file.core.windows.net"
    print_info "Testing DNS for: $fqdn"
    
    # Try to resolve DNS
    local resolved_ip
    resolved_ip=$(kubectl exec "$pod" -n "$NAMESPACE" -- nslookup "$fqdn" 2>/dev/null | grep -A1 "Name:" | tail -1 | awk '{print $2}')
    
    if [[ -n "$resolved_ip" ]]; then
        print_info "Resolved to: $resolved_ip"
        
        # Check if it's a private IP (10.x.x.x, 172.16-31.x.x, 192.168.x.x)
        if [[ "$resolved_ip" =~ ^10\. ]] || [[ "$resolved_ip" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] || [[ "$resolved_ip" =~ ^192\.168\. ]]; then
            print_success "DNS resolves to private IP: $resolved_ip"
            return 0
        else
            print_warning "DNS resolves to public IP: $resolved_ip (expected: private IP)"
            return 0
        fi
    else
        print_failure "DNS resolution failed for $fqdn"
        return 1
    fi
}

check_storage_class() {
    print_check "Checking if custom storage class exists (optional)..."
    
    if kubectl get storageclass azurefile-csi-private &>/dev/null; then
        print_success "Storage class 'azurefile-csi-private' exists"
        
        # Check provisioner
        local provisioner
        provisioner=$(kubectl get storageclass azurefile-csi-private -o jsonpath='{.provisioner}')
        print_info "Provisioner: $provisioner"
        
        return 0
    else
        print_info "Storage class 'azurefile-csi-private' not found (this is optional)"
        return 0
    fi
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    # Check arguments
    if [[ $# -lt 1 ]]; then
        echo "Usage: $0 <namespace>"
        echo "Example: $0 mft"
        exit 1
    fi
    
    NAMESPACE="$1"
    STORAGE_ACCOUNT=""
    
    print_header "Private Storage Diagnostic Report"
    echo "Namespace: $NAMESPACE"
    echo "Date: $(date)"
    echo ""
    
    # Run all checks
    check_namespace || true
    check_secret || true
    check_pv || true
    check_pvc || true
    check_storage_class || true
    check_pod_mounts || true
    check_file_operations || true
    check_dns_resolution || true
    
    # Print summary
    print_header "Summary"
    echo -e "${GREEN}Checks Passed:${NC} $CHECKS_PASSED"
    echo -e "${YELLOW}Warnings:${NC} $CHECKS_WARNING"
    echo -e "${RED}Checks Failed:${NC} $CHECKS_FAILED"
    echo ""
    
    if [[ $CHECKS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✓ All critical checks passed!${NC}"
        echo ""
        exit 0
    else
        echo -e "${RED}✗ Some checks failed. Please review the output above.${NC}"
        echo ""
        exit 1
    fi
}

# Run main function
main "$@"
