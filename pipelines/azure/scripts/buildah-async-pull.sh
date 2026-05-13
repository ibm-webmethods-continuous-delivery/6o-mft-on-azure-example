#!/bin/sh

[ "$#" -eq 1 ] || {
  echo "Usage: $0 <image-ref>" >&2
  exit 2
}

# Only source PU if not already initialized (check for a PU function)
if ! command -v pu_log_i >/dev/null 2>&1; then
  if [ -n "${PU_HOME:-}" ] && [ -f "${PU_HOME}/code/1.init.sh" ]; then
    # shellcheck disable=SC1091
    . "${PU_HOME}/code/1.init.sh"
  fi
fi

__crt_folder=$(pwd)
__timestamp=$(date +%s)
__base_dir=${PU_AUDIT_BASE_DIR:-"/tmp/pu-audit"}
__work_folder="${__base_dir}/buildah-async-pull-$$-$__timestamp"

mkdir -p "$__work_folder"
cd "$__work_folder" || exit 1

pu_log_i "Async launch: buildah pull $1"

nohup buildah pull "$1" >pull.log 2>&1 &
__pid=$!

pu_log_i "Async buildah pull started for $1 with PID ${__pid}"


cd "$__crt_folder" || exit 1

unset __crt_folder __timestamp __base_dir __work_folder
