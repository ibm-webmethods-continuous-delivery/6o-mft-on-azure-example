#!/bin/sh

. ./03-get-tf-output-for-agic-installation.sh
. ./04-set-kube-params.sh

__timestamp=$(date +%s)
__tmp_folder="/tmp/kube_provisioning_${__timestamp}"

mkdir -p "${__tmp_folder}"

envsubst < ./04-kube-prerequisites.yml > "${__tmp_folder}/kube-prerequisites.yml"

kubectl apply -f "${__tmp_folder}/kube-prerequisites.yml"

echo "applied file ${__tmp_folder}/kube-prerequisites.yml"
