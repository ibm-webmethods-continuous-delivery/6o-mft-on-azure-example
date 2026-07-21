# Vault - Optional

This example is based on the principle that all secrets are managed using Azure Key Vault.

We are thus assuming the organization has at least a key vault, provisioned and managed by the security team. The rest of the teams may provision objects that are explicitly allowed to read from the vault on specific entries.

This stack is optional, provision a vault if none is available, but we expect the vault to be already present for real production deployments.
