#!/bin/sh

# Get the Application Gateway IP
APP_GW_IP=$(kubectl get ingress simple-web -n http-test -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "Testing Application Gateway at IP: ${APP_GW_IP}"

# Test with Host header (as configured in values.yaml: simple-web.local)
curl -H 'Host: simple-web.local' http://${APP_GW_IP}/
