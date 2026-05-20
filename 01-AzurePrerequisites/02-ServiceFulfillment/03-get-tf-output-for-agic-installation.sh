#!/bin/sh

# Subscription ID where we provisioned
AGIC_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
export AGIC_SUBSCRIPTION_ID

# Resource Group Name where we provisioned
AGIC_RESOURCE_GROUP=$(terraform output -raw resource_group_name)
export AGIC_RESOURCE_GROUP

# Name of APP Gateway we provisioned
AGIC_APP_GATEWAY_NAME=$(terraform output -raw app_gateway_name)
export AGIC_APP_GATEWAY_NAME

# Service Principal credentials for AGIC
AGIC_SP_CLIENT_ID=$(terraform output -raw agic_service_principal_client_id)
export AGIC_SP_CLIENT_ID

AGIC_SP_CLIENT_SECRET=$(terraform output -raw agic_service_principal_client_secret)
export AGIC_SP_CLIENT_SECRET

AGIC_SP_TENANT_ID=$(terraform output -raw agic_service_principal_tenant_id)
export AGIC_SP_TENANT_ID

# Create the Service Principal secret JSON for AGIC Helm chart (base64 encoded)
AGIC_SERVICE_PRINCIPAL_SECRET_JSON=$(cat <<EOF | base64 -w 0
{
  "clientId": "${AGIC_SP_CLIENT_ID}",
  "clientSecret": "${AGIC_SP_CLIENT_SECRET}",
  "subscriptionId": "${AGIC_SUBSCRIPTION_ID}",
  "tenantId": "${AGIC_SP_TENANT_ID}",
  "activeDirectoryEndpointUrl": "https://login.microsoftonline.com",
  "resourceManagerEndpointUrl": "https://management.azure.com/",
  "activeDirectoryGraphResourceId": "https://graph.windows.net/",
  "sqlManagementEndpointUrl": "https://management.core.windows.net:8443/",
  "galleryEndpointUrl": "https://gallery.azure.com/",
  "managementEndpointUrl": "https://management.core.windows.net/"
}
EOF
)
export AGIC_SERVICE_PRINCIPAL_SECRET_JSON

# Cluster Name of AKS Cluster we provisioned
AGIC_AKS_CLUSTER_NAME=$(terraform output -raw aks_cluster_name)
export AGIC_AKS_CLUSTER_NAME

# OIDC issuer URL of AKS Cluster we provisioned
AGIC_AKS_OIDC_ISSUER=$(terraform output -raw aks_kube_oidc_issuer_url)
export AGIC_AKS_OIDC_ISSUER

# Made with Bob
