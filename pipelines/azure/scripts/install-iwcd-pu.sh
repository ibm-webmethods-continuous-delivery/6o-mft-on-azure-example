#!/bin/sh

IWCD_PU_TAG=${IWCD_PU_TAG:-v0.1.5}
IWCD_BASE_URL="${IWCD_BASE_URL:-https://raw.githubusercontent.com/ibm-webmethods-continuous-delivery/2l-posix-shell-utils/refs/tags/${IWCD_PU_TAG}}"

# This variable should be set by the caller, but just in case...
PU_HOME="${PU_HOME:-/tmp/PU_HOME}"
curl "${IWCD_BASE_URL}/code/1.init.sh" -o "${PU_HOME}/code/1.init.sh"
curl "${IWCD_BASE_URL}/code/2.audit.sh" -o "${PU_HOME}/code/2.audit.sh"
curl "${IWCD_BASE_URL}/code/3.ingester.sh" -o "${PU_HOME}/code/3.ingester.sh"
