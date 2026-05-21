#!/bin/sh
#
# Copyright IBM Corp. 2026 - 2026
# SPDX-License-Identifier: Apache-2.0
#
# Certificate Manager Entrypoint Script
#
# Generates:
#   1. Server TLS certificates (RSA + ED25519) via cert-manager
#   2. Client SSH key pairs (RSA + ED25519) for SFTP key-based auth

echo "Starting certificate manager..."

# Guard: TEST_PK_SECRET must be set for unattended operation.
# Each subject's set-env.sh resolves CRTMGR_PK_PASS from this variable.
# Without it, the cert-manager function library falls back to pu_read_secret_from_user
# (interactive terminal prompt), which blocks unattended CI/CD execution.
if [ -z "${TEST_PK_SECRET}" ]; then
  echo "[FATAL] TEST_PK_SECRET is not set. Set it in docker-compose environment for unattended operation." >&2
  exit 1
fi

# Source initialization scripts, packaged in the image
# shellcheck disable=SC1091
. /opt/cert-mgr/util/PU_HOME/code/1.init.sh
# shellcheck disable=SC1091
. /opt/cert-mgr/cert-mgmt-functions.sh

# ─── Step 1: Server TLS certificates ─────────────────────────────────────────

mkdir -p /mnt/data/certmgr/az-certs/out
rm -f \
  /mnt/data/certmgr/az-certs/out/all_certs.pem \
  /mnt/data/certmgr/az-certs/out/global.public.trust.store.jks \
  /mnt/data/certmgr/az-certs/out/global.public.trust.store.p12

echo "Generating server TLS certificates..."
cert_mgr_manage_subject /mnt/data/certmgr/az-certs 01-ca-root
cert_mgr_manage_subject /mnt/data/certmgr/az-certs 02-admin-ui
cert_mgr_manage_subject /mnt/data/certmgr/az-certs 03-web-client

# ─── Step 2: Server SFTP RSA keys    ─────────────────────────────────────────

_CLIENT_KEYS_DIR="/mnt/data/certmgr/az-certs/04-sftp-server/out"

echo "Generating client SSH key pairs..."

mkdir -p "${_CLIENT_KEYS_DIR}"
# Always regenerate to ensure consistency (test environment, idempotency)
rm -f "${_CLIENT_KEYS_DIR}/id_rsa" "${_CLIENT_KEYS_DIR}/id_rsa.pub"
ssh-keygen -t rsa -b 2048 -f "${_CLIENT_KEYS_DIR}/id_rsa" -N '' -q -C "mft-example-stfp-server-rsa"
echo "  RSA client key generated: ${_CLIENT_KEYS_DIR}/id_rsa"

echo "Certificate and key generation complete."
