#!/usr/bin/env bash
# ============================================================================
# Test Private Storage Operations Script
# ============================================================================
# This script performs comprehensive testing of file operations on the
# private storage to validate functionality and performance.
#
# Usage:
#   ./test-private-storage-operations.sh <namespace>
#
# Example:
#   ./test-private-storage-operations.sh mft
#
# Exit Codes:
#   0 - All tests passed
#   1 - One or more tests failed
# ============================================================================

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

# Test directory
TEST_DIR="/opt/IBM/MFT/vfs-private/.test-operations"

# ============================================================================
# Helper Functions
# ============================================================================

print_header() {
    echo ""
    echo -e "${BLUE}============================================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}============================================================================${NC}"
}

print_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓ PASS]${NC} $1"
    ((TESTS_PASSED++))
}

print_failure() {
    echo -e "${RED}[✗ FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# ============================================================================
# Test Functions
# ============================================================================

setup_test_environment() {
    print_header "Setting Up Test Environment"
    
    # Get first running pod
    POD=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=active-transfer -o jsonpath='{.items[0].metadata.name}')
    
    if [[ -z "$POD" ]]; then
        print_failure "No active-transfer pods found"
        exit 1
    fi
    
    local pod_status
    pod_status=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
    
    if [[ "$pod_status" != "Running" ]]; then
        print_failure "Pod '$POD' is not Running (status: $pod_status)"
        exit 1
    fi
    
    print_info "Using pod: $POD"
    
    # Create test directory
    print_test "Creating test directory..."
    if kubectl exec "$POD" -n "$NAMESPACE" -- mkdir -p "$TEST_DIR" &>/dev/null; then
        print_success "Test directory created: $TEST_DIR"
    else
        print_failure "Failed to create test directory"
        exit 1
    fi
}

cleanup_test_environment() {
    print_header "Cleaning Up Test Environment"
    
    print_test "Removing test directory..."
    if kubectl exec "$POD" -n "$NAMESPACE" -- rm -rf "$TEST_DIR" &>/dev/null; then
        print_success "Test directory removed"
    else
        print_failure "Failed to remove test directory"
    fi
}

test_create_file() {
    print_test "Test: Create file"
    
    local test_file="${TEST_DIR}/create-test.txt"
    local test_content="Test content $(date +%s)"
    
    if kubectl exec "$POD" -n "$NAMESPACE" -- sh -c "echo '$test_content' > $test_file" &>/dev/null; then
        print_success "File created successfully"
        return 0
    else
        print_failure "Failed to create file"
        return 1
    fi
}

test_read_file() {
    print_test "Test: Read file"
    
    local test_file="${TEST_DIR}/create-test.txt"
    
    if kubectl exec "$POD" -n "$NAMESPACE" -- cat "$test_file" &>/dev/null; then
        print_success "File read successfully"
        return 0
    else
        print_failure "Failed to read file"
        return 1
    fi
}

test_update_file() {
    print_test "Test: Update file"
    
    local test_file="${TEST_DIR}/create-test.txt"
    local new_content="Updated content $(date +%s)"
    
    if kubectl exec "$POD" -n "$NAMESPACE" -- sh -c "echo '$new_content' >> $test_file" &>/dev/null; then
        print_success "File updated successfully"
        return 0
    else
        print_failure "Failed to update file"
        return 1
    fi
}

test_delete_file() {
    print_test "Test: Delete file"
    
    local test_file="${TEST_DIR}/create-test.txt"
    
    if kubectl exec "$POD" -n "$NAMESPACE" -- rm "$test_file" &>/dev/null; then
        print_success "File deleted successfully"
        return 0
    else
        print_failure "Failed to delete file"
        return 1
    fi
}

test_create_directory() {
    print_test "Test: Create directory"
    
    local test_subdir="${TEST_DIR}/subdir"
    
    if kubectl exec "$POD" -n "$NAMESPACE" -- mkdir -p "$test_subdir" &>/dev/null; then
        print_success "Directory created successfully"
        return 0
    else
        print_failure "Failed to create directory"
        return 1
    fi
}

test_list_directory() {
    print_test "Test: List directory"
    
    if kubectl exec "$POD" -n "$NAMESPACE" -- ls -la "$TEST_DIR" &>/dev/null; then
        print_success "Directory listed successfully"
        return 0
    else
        print_failure "Failed to list directory"
        return 1
    fi
}

test_rename_file() {
    print_test "Test: Rename file"
    
    local old_file="${TEST_DIR}/rename-test-old.txt"
    local new_file="${TEST_DIR}/rename-test-new.txt"
    
    # Create file
    kubectl exec "$POD" -n "$NAMESPACE" -- sh -c "echo 'test' > $old_file" &>/dev/null
    
    # Rename
    if kubectl exec "$POD" -n "$NAMESPACE" -- mv "$old_file" "$new_file" &>/dev/null; then
        print_success "File renamed successfully"
        # Cleanup
        kubectl exec "$POD" -n "$NAMESPACE" -- rm "$new_file" &>/dev/null
        return 0
    else
        print_failure "Failed to rename file"
        return 1
    fi
}

test_copy_file() {
    print_test "Test: Copy file"
    
    local source_file="${TEST_DIR}/copy-source.txt"
    local dest_file="${TEST_DIR}/copy-dest.txt"
    
    # Create source file
    kubectl exec "$POD" -n "$NAMESPACE" -- sh -c "echo 'test' > $source_file" &>/dev/null
    
    # Copy
    if kubectl exec "$POD" -n "$NAMESPACE" -- cp "$source_file" "$dest_file" &>/dev/null; then
        print_success "File copied successfully"
        # Cleanup
        kubectl exec "$POD" -n "$NAMESPACE" -- rm "$source_file" "$dest_file" &>/dev/null
        return 0
    else
        print_failure "Failed to copy file"
        return 1
    fi
}

test_file_permissions() {
    print_test "Test: File permissions"
    
    local test_file="${TEST_DIR}/permissions-test.txt"
    
    # Create file
    kubectl exec "$POD" -n "$NAMESPACE" -- sh -c "echo 'test' > $test_file" &>/dev/null
    
    # Change permissions
    if kubectl exec "$POD" -n "$NAMESPACE" -- chmod 644 "$test_file" &>/dev/null; then
        print_success "File permissions changed successfully"
        # Cleanup
        kubectl exec "$POD" -n "$NAMESPACE" -- rm "$test_file" &>/dev/null
        return 0
    else
        print_failure "Failed to change file permissions"
        return 1
    fi
}

test_large_file() {
    print_test "Test: Large file (10MB)"
    
    local test_file="${TEST_DIR}/large-file.bin"
    local start_time
    local end_time
    local duration
    
    start_time=$(date +%s)
    
    # Create 10MB file
    if kubectl exec "$POD" -n "$NAMESPACE" -- dd if=/dev/zero of="$test_file" bs=1M count=10 &>/dev/null; then
        end_time=$(date +%s)
        duration=$((end_time - start_time))
        print_success "Large file created successfully (${duration}s)"
        
        # Cleanup
        kubectl exec "$POD" -n "$NAMESPACE" -- rm "$test_file" &>/dev/null
        return 0
    else
        print_failure "Failed to create large file"
        return 1
    fi
}

test_concurrent_writes() {
    print_test "Test: Concurrent writes (5 files)"
    
    local success=true
    
    # Create 5 files concurrently
    for i in {1..5}; do
        local test_file="${TEST_DIR}/concurrent-${i}.txt"
        kubectl exec "$POD" -n "$NAMESPACE" -- sh -c "echo 'concurrent test $i' > $test_file" &>/dev/null &
    done
    
    # Wait for all background jobs
    wait
    
    # Verify all files were created
    for i in {1..5}; do
        local test_file="${TEST_DIR}/concurrent-${i}.txt"
        if ! kubectl exec "$POD" -n "$NAMESPACE" -- test -f "$test_file" &>/dev/null; then
            success=false
            break
        fi
    done
    
    if [[ "$success" == true ]]; then
        print_success "Concurrent writes successful"
        # Cleanup
        kubectl exec "$POD" -n "$NAMESPACE" -- rm "${TEST_DIR}/concurrent-"*.txt &>/dev/null
        return 0
    else
        print_failure "Concurrent writes failed"
        return 1
    fi
}

test_disk_space() {
    print_test "Test: Check disk space"
    
    local df_output
    df_output=$(kubectl exec "$POD" -n "$NAMESPACE" -- df -h /opt/IBM/MFT/vfs-private 2>/dev/null | tail -1)
    
    if [[ -n "$df_output" ]]; then
        print_success "Disk space check successful"
        print_info "Disk usage: $df_output"
        return 0
    else
        print_failure "Failed to check disk space"
        return 1
    fi
}

# ============================================================================
# Performance Tests
# ============================================================================

test_write_performance() {
    print_header "Performance Tests"
    print_test "Test: Write performance (100 x 1KB files)"
    
    local start_time
    local end_time
    local duration
    local files_per_second
    
    start_time=$(date +%s%3N)  # milliseconds
    
    # Write 100 small files
    for i in {1..100}; do
        local test_file="${TEST_DIR}/perf-write-${i}.txt"
        kubectl exec "$POD" -n "$NAMESPACE" -- sh -c "echo 'performance test' > $test_file" &>/dev/null
    done
    
    end_time=$(date +%s%3N)
    duration=$((end_time - start_time))
    files_per_second=$(echo "scale=2; 100000 / $duration" | bc)
    
    print_success "Write performance: ${files_per_second} files/second (${duration}ms total)"
    
    # Cleanup
    kubectl exec "$POD" -n "$NAMESPACE" -- rm "${TEST_DIR}/perf-write-"*.txt &>/dev/null
}

test_read_performance() {
    print_test "Test: Read performance (100 x 1KB files)"
    
    # Create test files
    for i in {1..100}; do
        local test_file="${TEST_DIR}/perf-read-${i}.txt"
        kubectl exec "$POD" -n "$NAMESPACE" -- sh -c "echo 'performance test' > $test_file" &>/dev/null
    done
    
    local start_time
    local end_time
    local duration
    local files_per_second
    
    start_time=$(date +%s%3N)
    
    # Read 100 files
    for i in {1..100}; do
        local test_file="${TEST_DIR}/perf-read-${i}.txt"
        kubectl exec "$POD" -n "$NAMESPACE" -- cat "$test_file" &>/dev/null
    done
    
    end_time=$(date +%s%3N)
    duration=$((end_time - start_time))
    files_per_second=$(echo "scale=2; 100000 / $duration" | bc)
    
    print_success "Read performance: ${files_per_second} files/second (${duration}ms total)"
    
    # Cleanup
    kubectl exec "$POD" -n "$NAMESPACE" -- rm "${TEST_DIR}/perf-read-"*.txt &>/dev/null
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
    POD=""
    
    print_header "Private Storage Operations Test Suite"
    echo "Namespace: $NAMESPACE"
    echo "Date: $(date)"
    echo ""
    
    # Setup
    setup_test_environment
    
    # Run basic operation tests
    print_header "Basic Operations Tests"
    test_create_file || true
    test_read_file || true
    test_update_file || true
    test_delete_file || true
    test_create_directory || true
    test_list_directory || true
    test_rename_file || true
    test_copy_file || true
    test_file_permissions || true
    
    # Run advanced tests
    print_header "Advanced Tests"
    test_large_file || true
    test_concurrent_writes || true
    test_disk_space || true
    
    # Run performance tests
    test_write_performance || true
    test_read_performance || true
    
    # Cleanup
    cleanup_test_environment
    
    # Print summary
    print_header "Test Summary"
    echo -e "${GREEN}Tests Passed:${NC} $TESTS_PASSED"
    echo -e "${RED}Tests Failed:${NC} $TESTS_FAILED"
    echo ""
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✓ All tests passed!${NC}"
        echo ""
        exit 0
    else
        echo -e "${RED}✗ Some tests failed. Please review the output above.${NC}"
        echo ""
        exit 1
    fi
}

# Run main function
main "$@"
