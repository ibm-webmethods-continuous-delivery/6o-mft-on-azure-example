#!/bin/sh

WEB_APP_NAMESPACE="http-test"
HELM_RELEASE_NAME="simple-web"
HELM_CHART_PATH="./helm/simple-web"

echo "=========================================="
echo "Deploying HTTP Test Application via Helm"
echo "=========================================="
echo ""

# Create namespace
echo "Creating namespace: ${WEB_APP_NAMESPACE}"
kubectl create namespace ${WEB_APP_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Deploy using Helm
echo ""
echo "Deploying ${HELM_RELEASE_NAME} Helm chart..."
helm upgrade --install ${HELM_RELEASE_NAME} ${HELM_CHART_PATH} \
  --namespace ${WEB_APP_NAMESPACE} \
  --create-namespace \
  --wait \
  --timeout 5m

echo ""
echo "=========================================="
echo "Deployment Complete"
echo "=========================================="
echo ""
echo "Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app=simple-web -n ${WEB_APP_NAMESPACE} --timeout=120s

echo ""
echo "Checking deployment status:"
kubectl get all -n ${WEB_APP_NAMESPACE}

echo ""
echo "Checking ingress:"
kubectl get ingress -n ${WEB_APP_NAMESPACE}

echo ""
echo "=========================================="
echo "Helm Release Information:"
helm list -n ${WEB_APP_NAMESPACE}

echo ""
echo "=========================================="
echo "To get the Application Gateway public IP:"
echo "  kubectl get ingress ${HELM_RELEASE_NAME} -n ${WEB_APP_NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
echo ""
echo "To check AGIC logs:"
echo "  kubectl logs -n agic -l app=ingress-azure --tail=50 -f"
echo ""
echo "To test the application (once IP is assigned):"
echo "  APP_GW_IP=\$(kubectl get ingress ${HELM_RELEASE_NAME} -n ${WEB_APP_NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
echo "  curl -H 'Host: simple-web.local' http://\${APP_GW_IP}/"
echo ""
echo "To uninstall:"
echo "  helm uninstall ${HELM_RELEASE_NAME} -n ${WEB_APP_NAMESPACE}"
echo "=========================================="

# Made with Bob
