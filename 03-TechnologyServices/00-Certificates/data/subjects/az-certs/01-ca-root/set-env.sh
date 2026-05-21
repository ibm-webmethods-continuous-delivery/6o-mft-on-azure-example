#!/bin/sh
#
# Copyright IBM Corp. 2026 - 2026
# SPDX-License-Identifier: Apache-2.0
#
# Root CA for MFT Example Environment

export CRTMGR_SUBJECT_TYPE="RootCA"
export CRTMGR_SUBJ_PARAM="/CN=MFT\ Example\ Root\ CA/O=IWCD\ Test/C=XX"
export CRTMGR_KEY_STORE_ENTRY_NAME="mft-test-root-ca"
export CRTMGR_CERTIFICATE_VALIDITY_DAYS=3650

# Passphrase: resolved from the harness-level TEST_PK_SECRET env var.
# TEST_PK_SECRET is set in docker-compose for unattended CI/CD operation.
# In production, do not use a shared env var; use a proper secrets manager.
export CRTMGR_PK_PASS="${TEST_PK_SECRET}"
