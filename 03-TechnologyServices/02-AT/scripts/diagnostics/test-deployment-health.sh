#!/bin/bash
# Test script for Active Transfer Helm deployment health
# This script verifies:
# 1. Pod status and readiness
# 2. JGroups clustering connectivity
# 3. Service endpoints
# 4. Health check endpoints

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default namespace
NAMESPACE="${NAMESPACE:-default}"
RELEASE_NAME="${RELEASE_NAME:-active-transfer}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Active Transfer Deployment Health Check${NC}"
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
    else
        echo -e "${RED}✗${NC} $message"
    fi
}

# Test 1: Check if pods exist and are running
echo -e "${BLUE}[1/6] Checking Pod Status...${NC}"
PODS=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=active-transfer,app.kubernetes.io/instance=$RELEASE_NAME" -o json)
POD_COUNT=$(echo "$PODS" | jq -r '.items | length')

if [ "$POD_COUNT" -eq 0 ]; then
    print_status "FAIL" "No pods found for release '$RELEASE_NAME' in namespace '$NAMESPACE'"
    exit 1
fi

print_status "OK" "Found $POD_COUNT pod(s)"

# Check each pod status
ALL_RUNNING=true
echo "$PODS" | jq -r '.items[] | "\(.metadata.name) \(.status.phase) \(.status.conditions[] | select(.type=="Ready") | .status)"' | while read -r POD_NAME PHASE READY; do
    if [ "$PHASE" = "Running" ] && [ "$READY" = "True" ]; then
        print_status "OK" "Pod $POD_NAME is Running and Ready"
    else
        print_status "FAIL" "Pod $POD_NAME is $PHASE (Ready: $READY)"
        ALL_RUNNING=false
    fi
done

# Test 2: Check pod IPs and network
echo ""
echo -e "${BLUE}[2/6] Checking Pod Network...${NC}"
POD_IPS=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=active-transfer,app.kubernetes.io/instance=$RELEASE_NAME" -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.podIP}{"\n"}{end}')

if [ -z "$POD_IPS" ]; then
    print_status "FAIL" "No pod IPs found"
else
    print_status "OK" "Pod IPs assigned:"
    echo "$POD_IPS" | while read -r POD_NAME POD_IP; do
        echo "  - $POD_NAME: $POD_IP"
    done
fi

# Test 3: Check JGroups port connectivity (if multiple pods)
echo ""
echo -e "${BLUE}[3/6] Checking JGroups Connectivity (Port 7800)...${NC}"

if [ "$POD_COUNT" -lt 2 ]; then
    print_status "WARN" "Only 1 pod found - skipping JGroups connectivity test (requires 2+ pods)"
else
    # Get pod names and IPs
    POD_ARRAY=($(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=active-transfer,app.kubernetes.io/instance=$RELEASE_NAME" -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.podIP}{"\n"}{end}'))

    # Test connectivity from first pod to all others
    SOURCE_POD="${POD_ARRAY[0]}"
    SOURCE_IP="${POD_ARRAY[1]}"

    print_status "OK" "Testing from pod: $SOURCE_POD ($SOURCE_IP)"

    for ((i=2; i<${#POD_ARRAY[@]}; i+=2)); do
        TARGET_POD="${POD_ARRAY[$i]}"
        TARGET_IP="${POD_ARRAY[$i+1]}"

        # Test TCP connectivity to port 7800
        if kubectl exec -n "$NAMESPACE" "$SOURCE_POD" -- bash -c "(echo > /dev/tcp/$TARGET_IP/7800) >/dev/null 2>&1"; then
            print_status "OK" "Port 7800 is open: $SOURCE_POD -> $TARGET_POD ($TARGET_IP)"
        else
            print_status "FAIL" "Port 7800 is closed: $SOURCE_POD -> $TARGET_POD ($TARGET_IP)"
        fi
    done
fi

# Test 4: Check service endpoints
echo ""
echo -e "${BLUE}[4/6] Checking Service Endpoints...${NC}"
SERVICE_NAME="$RELEASE_NAME"
SERVICE_EXISTS=$(kubectl get service -n "$NAMESPACE" "$SERVICE_NAME" -o json 2>/dev/null || echo "")

if [ -z "$SERVICE_EXISTS" ]; then
    print_status "FAIL" "Service '$SERVICE_NAME' not found"
else
    print_status "OK" "Service '$SERVICE_NAME' exists"

    # Check endpoints
    ENDPOINTS=$(kubectl get endpoints -n "$NAMESPACE" "$SERVICE_NAME" -o jsonpath='{.subsets[*].addresses[*].ip}')
    if [ -z "$ENDPOINTS" ]; then
        print_status "WARN" "No endpoints registered for service"
    else
        ENDPOINT_COUNT=$(echo "$ENDPOINTS" | wc -w)
        print_status "OK" "Service has $ENDPOINT_COUNT endpoint(s): $ENDPOINTS"
    fi
fi

# Test 5: Check health endpoints
echo ""
echo -e "${BLUE}[5/6] Checking Health Endpoints...${NC}"

# Get first pod for health check
FIRST_POD=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=active-transfer,app.kubernetes.io/instance=$RELEASE_NAME" -o jsonpath='{.items[0].metadata.name}')

if [ -n "$FIRST_POD" ]; then
    # Test liveness endpoint
    if kubectl exec -n "$NAMESPACE" "$FIRST_POD" -- curl -sf http://localhost:5555/health/liveness >/dev/null 2>&1; then
        print_status "OK" "Liveness endpoint responding on $FIRST_POD"
    else
        print_status "FAIL" "Liveness endpoint not responding on $FIRST_POD"
    fi

    # Test readiness endpoint
    if kubectl exec -n "$NAMESPACE" "$FIRST_POD" -- curl -sf http://localhost:5555/health/readiness >/dev/null 2>&1; then
        print_status "OK" "Readiness endpoint responding on $FIRST_POD"
    else
        print_status "FAIL" "Readiness endpoint not responding on $FIRST_POD"
    fi
fi

# Test 6: Check JGroups cluster view in logs
echo ""
echo -e "${BLUE}[6/6] Checking JGroups Cluster Formation...${NC}"

if [ "$POD_COUNT" -lt 2 ]; then
    print_status "WARN" "Only 1 pod - skipping cluster formation check"
else
    FIRST_POD=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=active-transfer,app.kubernetes.io/instance=$RELEASE_NAME" -o jsonpath='{.items[0].metadata.name}')

    # Check for JGroups cluster view in logs
    CLUSTER_VIEW=$(kubectl logs -n "$NAMESPACE" "$FIRST_POD" --tail=500 2>/dev/null | grep -i "view" | grep -i "jgroups\|cluster" | tail -1 || echo "")

    if [ -n "$CLUSTER_VIEW" ]; then
        print_status "OK" "JGroups cluster view found in logs"
        echo "  Latest view: $CLUSTER_VIEW"
    else
        print_status "WARN" "No JGroups cluster view found in recent logs"
    fi

    # Check for KUBE_PING discovery
    KUBE_PING=$(kubectl logs -n "$NAMESPACE" "$FIRST_POD" --tail=500 2>/dev/null | grep -i "KUBE_PING" | tail -1 || echo "")

    if [ -n "$KUBE_PING" ]; then
        print_status "OK" "KUBE_PING discovery active"
        echo "  $KUBE_PING"
    else
        print_status "WARN" "No KUBE_PING messages found in recent logs"
    fi
fi

# Summary
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Health Check Complete${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "To view detailed logs:"
echo "  kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=active-transfer --tail=100"
echo ""
echo "To check JGroups configuration:"
echo "  kubectl exec -n $NAMESPACE $FIRST_POD -- cat /opt/softwareag/IntegrationServer/instances/default/packages/WmMFT/resources/jgroups-properties.xml"
echo ""

# Made with Bob
