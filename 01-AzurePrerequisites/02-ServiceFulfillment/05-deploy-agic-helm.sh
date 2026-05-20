#!/bin/sh

. ./03-get-tf-output-for-agic-installation.sh
. ./04-set-kube-params.sh

__timestamp=$(date +%s)
__tmp_folder="/tmp/kube_provisioning_${__timestamp}"

mkdir -p "${__tmp_folder}"

envsubst < ./05-agic-helm-values.yml > "${__tmp_folder}/agic-helm-values.yml"

echo "Values file for helm: ${__tmp_folder}/agic-helm-values.yml"

# Check if already installed
if helm list -n ${AGIC_NAMESPACE} | grep -q ingress-azure; then
    echo "AGIC already installed, upgrading..."
    helm upgrade ingress-azure \
      oci://mcr.microsoft.com/azure-application-gateway/charts/ingress-azure \
      --version 1.7.5 \
      --namespace ${AGIC_NAMESPACE} \
      --values ${__tmp_folder}/agic-helm-values.yml
else
    echo "Installing AGIC..."
    helm install ingress-azure \
      oci://mcr.microsoft.com/azure-application-gateway/charts/ingress-azure \
      --version 1.7.5 \
      --namespace ${AGIC_NAMESPACE} \
      --values ${__tmp_folder}/agic-helm-values.yml
fi
