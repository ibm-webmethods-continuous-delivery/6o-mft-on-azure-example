#!/bin/bash
# Check JGroups initialization in pod logs

NAMESPACE="${NAMESPACE:-default}"
RELEASE_NAME="${RELEASE_NAME:-active-transfer}"

# Get first pod
FIRST_POD=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=active-transfer,app.kubernetes.io/instance=$RELEASE_NAME" -o jsonpath='{.items[0].metadata.name}')

if [ -z "$FIRST_POD" ]; then
    echo "No pods found"
    exit 1
fi

echo "Checking logs for pod: $FIRST_POD"
echo "========================================"
echo ""

echo "1. Checking for JGroups initialization..."
kubectl logs -n "$NAMESPACE" "$FIRST_POD" | grep -i "jgroups\|cluster" | head -50

echo ""
echo "2. Checking for port 7800 binding..."
kubectl logs -n "$NAMESPACE" "$FIRST_POD" | grep -i "7800\|bind"

echo ""
echo "3. Checking for KUBE_PING..."
kubectl logs -n "$NAMESPACE" "$FIRST_POD" | grep -i "kube_ping"

echo ""
echo "4. Checking for MFT cluster sync..."
kubectl logs -n "$NAMESPACE" "$FIRST_POD" | grep -i "mft.cluster.sync"

echo ""
echo "5. Checking for any errors..."
kubectl logs -n "$NAMESPACE" "$FIRST_POD" | grep -i "error\|exception\|failed" | grep -i "jgroups\|cluster" | head -20

echo ""
echo "6. Last 50 lines of logs..."
kubectl logs -n "$NAMESPACE" "$FIRST_POD" --tail=50

# Made with Bob
