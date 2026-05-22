#!/bin/bash
# Check if JGroups cluster has multiple members

NAMESPACE="${NAMESPACE:-default}"

echo "Checking JGroups Cluster Membership"
echo "===================================="
echo ""

PODS=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=active-transfer" -o jsonpath='{.items[*].metadata.name}')

for POD in $PODS; do
    echo "Pod: $POD"
    echo "-------------------"

    # Look for cluster view messages
    echo "Cluster view messages:"
    kubectl logs -n "$NAMESPACE" "$POD" | grep -i "view.*\[" | tail -5

    # Look for member count
    echo ""
    echo "GMS messages:"
    kubectl logs -n "$NAMESPACE" "$POD" | grep "GMS:" | tail -3

    # Look for received view
    echo ""
    echo "Received view messages:"
    kubectl logs -n "$NAMESPACE" "$POD" | grep -i "received.*view" | tail -3

    echo ""
    echo "================================"
    echo ""
done

echo "Summary:"
echo "--------"
echo "If you see 'view: [member1, member2]' with 2 members, clustering is working!"
echo "If you only see 1 member in the view, pods haven't discovered each other yet."
echo ""
echo "To test configuration synchronization:"
echo "1. Make a change in the Admin UI of one pod"
echo "2. Check if the change appears in the other pod"

# Made with Bob
