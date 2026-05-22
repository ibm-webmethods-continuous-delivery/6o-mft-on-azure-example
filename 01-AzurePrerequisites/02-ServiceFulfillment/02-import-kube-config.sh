#!/bin/sh

export KUBECONFIG=~/.kube/config-mft

if [ ! -f ${KUBECONFIG} ]; then
  mkdir -p ~/.kube
  terraform output -raw aks_kube_config > ~/.kube/config-mft
else
  echo "KUBECONFIG file already exists, using exiting one @ ${KUBECONFIG}"
fi