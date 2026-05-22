#!/bin/bash
# Verify the actual JGroups configuration in the pod

NAMESPACE="${NAMESPACE:-default}"

POD=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=active-transfer" -o jsonpath='{.items[0].metadata.name}')

echo "Checking JGroups configuration in pod: $POD"
echo "============================================"
echo ""

echo "1. JGroups XML Configuration:"
echo "----------------------------"
kubectl exec -n "$NAMESPACE" "$POD" -- cat /opt/softwareag/IntegrationServer/instances/default/packages/WmMFT/resources/jgroups-properties.xml
echo ""

echo "2. Environment Variables:"
echo "------------------------"
echo "KUBERNETES_NAMESPACE:"
kubectl exec -n "$NAMESPACE" "$POD" -- printenv KUBERNETES_NAMESPACE
echo ""
echo "KUBERNETES_LABELS:"
kubectl exec -n "$NAMESPACE" "$POD" -- printenv KUBERNETES_LABELS
echo ""

echo "3. MFT Properties (cluster sync):"
echo "---------------------------------"
kubectl exec -n "$NAMESPACE" "$POD" -- grep -i "cluster" /opt/softwareag/IntegrationServer/instances/default/packages/WmMFT/config/properties.cnf
echo ""

echo "4. Check if JGroups is actually starting:"
echo "-----------------------------------------"
kubectl logs -n "$NAMESPACE" "$POD" | grep -i "jgroups\|GMS:\|Cloud Sync" | head -20
echo ""

echo "5. Check for any JGroups errors:"
echo "--------------------------------"
kubectl logs -n "$NAMESPACE" "$POD" | grep -i "jgroups.*error\|jgroups.*exception\|kube_ping.*error" | head -10

# Made with Bob
