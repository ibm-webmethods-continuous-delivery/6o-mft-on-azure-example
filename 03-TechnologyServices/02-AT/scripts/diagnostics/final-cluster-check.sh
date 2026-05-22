#!/bin/bash
# Final check for JGroups cluster formation

NAMESPACE="${NAMESPACE:-default}"

echo "Final JGroups Cluster Check"
echo "============================"
echo ""

PODS=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=active-transfer" -o jsonpath='{.items[*].metadata.name}')

for POD in $PODS; do
    echo "Pod: $POD"
    echo "-------------------"

    # Check for successful config loading
    echo "1. Config loading:"
    kubectl exec -n "$NAMESPACE" "$POD" -- grep -i "Loaded KUBE_PING" /opt/softwareag/IntegrationServer/instances/default/logs/ActiveTransfer.log 2>/dev/null | tail -1

    # Check for clustering enabled
    echo ""
    echo "2. Clustering status:"
    kubectl exec -n "$NAMESPACE" "$POD" -- grep -i "clustering enabled" /opt/softwareag/IntegrationServer/instances/default/logs/ActiveTransfer.log 2>/dev/null | tail -1

    # Check for GMS address
    echo ""
    echo "3. GMS address:"
    kubectl exec -n "$NAMESPACE" "$POD" -- grep "GMS:" /opt/softwareag/IntegrationServer/instances/default/logs/ActiveTransfer.log 2>/dev/null | tail -1

    # Check for any jgroup errors
    echo ""
    echo "4. JGroup errors (if any):"
    ERRORS=$(kubectl exec -n "$NAMESPACE" "$POD" -- grep -i "jgroup.*error\|jgroup.*exception\|jgroup.*warn" /opt/softwareag/IntegrationServer/instances/default/logs/ActiveTransfer.log 2>/dev/null | tail -5)
    if [ -n "$ERRORS" ]; then
        echo "$ERRORS"
    else
        echo "   No errors found!"
    fi

    # Check for cluster view
    echo ""
    echo "5. Cluster view:"
    kubectl exec -n "$NAMESPACE" "$POD" -- grep -i "view.*\[" /opt/softwareag/IntegrationServer/instances/default/logs/ActiveTransfer.log 2>/dev/null | tail -3

    echo ""
    echo "================================"
    echo ""
done

echo ""
echo "Testing pod-to-pod connectivity on port 7800..."
./test-pod-to-pod.sh | grep -A 10 "Testing connectivity"

# Made with Bob
