#!/bin/bash
# Check RBAC permissions for JGroups KUBE_PING

NAMESPACE="${NAMESPACE:-default}"
SERVICE_ACCOUNT="mft-service-account"

echo "Checking RBAC permissions for JGroups KUBE_PING discovery"
echo "=========================================="
echo ""

echo "1. Check if Role exists..."
kubectl get role -n "$NAMESPACE" active-transfer-jgroups -o yaml 2>/dev/null || echo "Role NOT found"

echo ""
echo "2. Check if RoleBinding exists..."
kubectl get rolebinding -n "$NAMESPACE" active-transfer-jgroups -o yaml 2>/dev/null || echo "RoleBinding NOT found"

echo ""
echo "3. Check if ServiceAccount exists..."
kubectl get serviceaccount -n "$NAMESPACE" "$SERVICE_ACCOUNT" -o yaml 2>/dev/null || echo "ServiceAccount NOT found"

echo ""
echo "4. Test if ServiceAccount can list pods..."
kubectl auth can-i list pods \
  --as="system:serviceaccount:$NAMESPACE:$SERVICE_ACCOUNT" \
  -n "$NAMESPACE"

echo ""
echo "5. Test if ServiceAccount can get pods..."
kubectl auth can-i get pods \
  --as="system:serviceaccount:$NAMESPACE:$SERVICE_ACCOUNT" \
  -n "$NAMESPACE"

echo ""
echo "6. Check what pods the ServiceAccount can see..."
echo "   (This simulates what KUBE_PING sees)"
kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=active-transfer" \
  --as="system:serviceaccount:$NAMESPACE:$SERVICE_ACCOUNT" 2>&1

echo ""
echo "7. Check environment variables in pod..."
POD=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=active-transfer" -o jsonpath='{.items[0].metadata.name}')
if [ -n "$POD" ]; then
    echo "   Pod: $POD"
    echo "   KUBERNETES_NAMESPACE:"
    kubectl exec -n "$NAMESPACE" "$POD" -- printenv KUBERNETES_NAMESPACE 2>/dev/null || echo "   NOT SET"
    echo "   KUBERNETES_LABELS:"
    kubectl exec -n "$NAMESPACE" "$POD" -- printenv KUBERNETES_LABELS 2>/dev/null || echo "   NOT SET"
fi

# Made with Bob
