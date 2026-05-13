#!/bin/sh

__crt_folder=$(pwd)
__timestamp=$(date +%s)
__base_dir=${PU_AUDIT_BASE_DIR:-"/tmp/pu-audit"}
__work_folder="${__base_dir}/buildah-async-pull-$$-$__timestamp"

mkdir -p "$__work_folder"
cd "$__work_folder" || exit 1

pu_log_i "Async launch: buildah pull $1"

nohup buildah pull "$1" $

cd "$__crt_folder" || exit 1

unset __crt_folder __timestamp __base_dir __work_folder
