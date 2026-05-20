#!/bin/sh

export KUBECONFIG="${KUBECONFIG:-~/.kube/config-mft}"

export AGIC_NAMESPACE="${AGIC_NAMESPACE:-agic}"
export AGIC_SERVICE_ACCOUNT_NAME="${AGIC_SERVICE_ACCOUNT_NAME:-agic-sa}"

