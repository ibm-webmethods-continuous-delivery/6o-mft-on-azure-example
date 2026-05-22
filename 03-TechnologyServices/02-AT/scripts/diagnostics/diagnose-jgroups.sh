#!/bin/bash
# Diagnostic script for JGroups clustering issues
# This script checks JGroups configuration, port status, and logs

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default namespace
NAMESPACE="${NAMESPACE:-default}"
RELEASE_NAME="${RELEASE_NAME:-active-transfer}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}JGroups Clustering Diagnostic${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Namespace: $NAMESPACE"
echo "Release: $RELEASE_NAME"
echo ""

# Function to print status
print_status() {
    local status=$1
    local message=$2
    if [ "$status" = "OK" ]; then
        echo -e "${GREEN}✓${NC} $message"
    elif [ "$status" = "WARN" ]; then
        echo -e "${YELLOW}⚠${NC} $message"
    elif [ "$status" = "INFO" ]; then
        echo -e "${CYAN}ℹ${NC} $message"
    else
        echo -e "${RED}✗${NC} $message"
    fi
}

# Get first pod
FIRST_POD=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=active-transfer,app.kubernetes.io/instance=$RELEASE_NAME" -o jsonpath='{.items[0].metadata.name}')

if [ -z "$FIRST_POD" ]; then
    print_status "FAIL" "No pods found for release '$RELEASE_NAME' in namespace '$NAMESPACE'"
    exit 1
fi

print_status "INFO" "Using pod: $FIRST_POD"
echo ""

# Test 1: Check if JGroups config file exists
echo -e "${BLUE}[1/8] Checking JGroups Configuration File...${NC}"
JGROUPS_CONFIG_PATH="/opt/softwareag/IntegrationServer/instances/default/packages/WmMFT/resources/jgroups-properties.xml"

if kubectl exec -n "$NAMESPACE" "$FIRST_POD" -- test -f "$JGROUPS_CONFIG_PATH" 2>/dev/null; then
    print_status "OK" "JGroups config file exists: $JGROUPS_CONFIG_PATH"

    # Show file details
    FILE_INFO=$(kubectl exec -n "$NAMESPACE" "$FIRST_POD" -- ls -lh "$JGROUPS_CONFIG_PATH" 2>/dev/null)
    echo "  $FILE_INFO"

    # Show first few lines
    echo ""
    echo "  First 10 lines of config:"
    kubectl exec -n "$NAMESPACE" "$FIRST_POD" -- head -10 "$JGROUPS_CONFIG_PATH" 2>/dev/null | sed 's/^/    /'
else
    print_status "FAIL" "JGroups config file NOT found: $JGROUPS_CONFIG_PATH"
fi

# Test 2: Check MFT properties.cnf for cluster settings
echo ""
echo -e "${BLUE}[2/8] Checking MFT Properties (properties.cnf)...${NC}"
MFT_PROPS_PATH="/opt/softwareag/IntegrationServer/instances/default/packages/WmMFT/config/properties.cnf"

if kubectl exec -n "$NAMESPACE" "$FIRST_POD" -- test -f "$MFT_PROPS_PATH" 2>/dev/null; then
    print_status "OK" "MFT properties file exists"

    # Check for cluster-related properties
    CLUSTER_PROPS=$(kubectl exec -n "$NAMESPACE" "$FIRST_POD" -- grep -i "cluster" "$MFT_PROPS_PATH" 2>/dev/null || echo "")

    if [ -n "$CLUSTER_PROPS" ]; then
        print_status "OK" "Found cluster configuration:"
        echo "$CLUSTER_PROPS" | sed 's/^/    /'
    else
        print_status "FAIL" "No cluster configuration found in properties.cnf"
        print_status "INFO" "Expected: mft.cluster.sync.enabled=true"
    fi
else
    print_status "FAIL" "MFT properties file NOT found: $MFT_PROPS_PATH"
    print_status "INFO" "This file is required for JGroups clustering"
fi

# Test 3: Check environment variables
echo ""
echo -e "${BLUE}[3/8] Checking Environment Variables...${NC}"

KUBE_NAMESPACE=$(kubectl exec -n "$NAMESPACE" "$FIRST_POD" -- printenv KUBERNETES_NAMESPACE 2>/dev/null || echo "")
KUBE_LABELS=$(kubectl exec -n "$NAMESPACE" "$FIRST_POD" -- printenv KUBERNETES_LABELS 2>/dev/null || echo "")

if [ -n "$KUBE_NAMESPACE" ]; then
    print_status "OK" "KUBERNETES_NAMESPACE: $KUBE_NAMESPACE"
else
    print_status "FAIL" "KUBERNETES_NAMESPACE not set"
fi

if [ -n "$KUBE_LABELS" ]; then
    print_status "OK" "KUBERNETES_LABELS: $KUBE_LABELS"
else
    print_status "FAIL" "KUBERNETES_LABELS not set"
fi

# Test 4: Check if port 7800 is listening
echo ""
echo -e "${BLUE}[4/8] Checking Port 7800 Status...${NC}"

# Try netstat first
PORT_LISTEN=$(kubectl exec -n "$NAMESPACE" "$FIRST_POD" -- netstat -tuln 2>/dev/null | grep ":7800" || echo "")

if [ -z "$PORT_LISTEN" ]; then
    # Try ss if netstat not available
    PORT_LISTEN=$(kubectl exec -n "$NAMESPACE" "$FIRST_POD" -- ss -tuln 2>/dev/null | grep ":7800" || echo "")
fi

if [ -n "$PORT_LISTEN" ]; then
    print_status "OK" "Port 7800 is listening:"
    echo "$PORT_LISTEN" | sed 's/^/    /'
else
    print_status "FAIL" "Port 7800 is NOT listening"
    print_status "INFO" "This means JGroups is not starting or binding to the port"
fi

# Test 5: Check all listening ports
echo ""
echo -e "${BLUE}[5/8] Checking All Listening Ports...${NC}"

ALL_PORTS=$(kubectl exec -n "$NAMESPACE" "$FIRST_POD" -- netstat -tuln 2>/dev/null || kubectl exec -n "$NAMESPACE" "$FIRST_POD" -- ss -tuln 2>/dev/null || echo "")

if [ -n "$ALL_PORTS" ]; then
    print_status "INFO" "All listening TCP ports:"
    echo "$ALL_PORTS" | grep LISTEN | sed 's/^/    /'
else
    print_status "WARN" "Could not retrieve listening ports"
fi

# Test 6: Check JGroups in logs
echo ""
echo -e "${BLUE}[6/8] Checking Logs for JGroups Messages...${NC}"

JGROUPS_LOGS=$(kubectl logs -n "$NAMESPACE" "$FIRST_POD" --tail=1000 2>/dev/null | grep -i "jgroups" || echo "")

if [ -n "$JGROUPS_LOGS" ]; then
    print_status "OK" "Found JGroups messages in logs:"
    echo "$JGROUPS_LOGS" | head -20 | sed 's/^/    /'

    LINE_COUNT=$(echo "$JGROUPS_LOGS" | wc -l)
    if [ "$LINE_COUNT" -gt 20 ]; then
        echo "    ... (showing first 20 of $LINE_COUNT lines)"
    fi
else
    print_status "FAIL" "No JGroups messages found in logs"
    print_status "INFO" "This suggests JGroups is not initializing"
fi

# Test 7: Check for cluster-related logs
echo ""
echo -e "${BLUE}[7/8] Checking Logs for Cluster Messages...${NC}"

CLUSTER_LOGS=$(kubectl logs -n "$NAMESPACE" "$FIRST_POD" --tail=1000 2>/dev/null | grep -i "cluster\|kube_ping" || echo "")

if [ -n "$CLUSTER_LOGS" ]; then
    print_status "OK" "Found cluster-related messages:"
    echo "$CLUSTER_LOGS" | head -20 | sed 's/^/    /'

    LINE_COUNT=$(echo "$CLUSTER_LOGS" | wc -l)
    if [ "$LINE_COUNT" -gt 20 ]; then
        echo "    ... (showing first 20 of $LINE_COUNT lines)"
    fi
else
    print_status "WARN" "No cluster messages found in logs"
fi

# Test 8: Check for errors related to port 7800
echo ""
echo -e "${BLUE}[8/8] Checking for Port 7800 Errors...${NC}"

PORT_ERRORS=$(kubectl logs -n "$NAMESPACE" "$FIRST_POD" --tail=1000 2>/dev/null | grep -i "7800\|bind.*error\|address.*use" || echo "")

if [ -n "$PORT_ERRORS" ]; then
    print_status "WARN" "Found potential port-related errors:"
    echo "$PORT_ERRORS" | sed 's/^/    /'
else
    print_status "OK" "No port-related errors found"
fi

# Summary and recommendations
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Diagnostic Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Determine likely issue
if [ -z "$JGROUPS_LOGS" ]; then
    echo -e "${RED}ISSUE: JGroups is not initializing${NC}"
    echo ""
    echo "Possible causes:"
    echo "  1. mft.cluster.sync.enabled property not set to 'true' in properties.cnf"
    echo "  2. properties.cnf file not mounted correctly"
    echo "  3. JGroups configuration file not being loaded by the application"
    echo ""
    echo "Recommended actions:"
    echo "  1. Verify mft.cluster.sync.enabled=true in properties.cnf"
    echo "  2. Check if properties.cnf is mounted at the correct path"
    echo "  3. Verify jgroups-properties.xml path is correct in properties.cnf"
    echo "  4. Check startup logs for configuration loading errors"
elif [ -z "$PORT_LISTEN" ]; then
    echo -e "${RED}ISSUE: JGroups is configured but port 7800 is not listening${NC}"
    echo ""
    echo "Possible causes:"
    echo "  1. JGroups failed to bind to port 7800"
    echo "  2. Port conflict with another process"
    echo "  3. Network policy blocking the port"
    echo ""
    echo "Recommended actions:"
    echo "  1. Check full logs for JGroups binding errors"
    echo "  2. Verify no other process is using port 7800"
    echo "  3. Check network policies in the namespace"
else
    echo -e "${GREEN}JGroups appears to be configured and running${NC}"
    echo ""
    echo "If pods still can't communicate:"
    echo "  1. Check network policies between pods"
    echo "  2. Verify RBAC permissions for pod discovery"
    echo "  3. Check if pods are in the same namespace"
fi

echo ""
echo "To view full logs:"
echo "  kubectl logs -n $NAMESPACE $FIRST_POD | less"
echo ""
echo "To check RBAC permissions:"
echo "  kubectl auth can-i list pods --as=system:serviceaccount:$NAMESPACE:mft-service-account -n $NAMESPACE"
echo ""

# Made with Bob
