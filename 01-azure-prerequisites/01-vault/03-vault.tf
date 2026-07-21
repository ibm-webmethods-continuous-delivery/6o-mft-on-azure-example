# ============================================================================
# Azure Key Vault for MFT Secrets Management
# ============================================================================

resource "azurerm_key_vault" "main" {
  name                = var.key_vault_name != null ? var.key_vault_name : "${var.prefix}-kv"
  location            = local.rg_location
  resource_group_name = local.rg_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # Network configuration - switchable between public and restricted
  public_network_access_enabled = var.key_vault_public_access_enabled

  # RBAC model (preferred over access policies)
  rbac_authorization_enabled = true

  # Soft delete and purge protection
  soft_delete_retention_days = var.key_vault_soft_delete_retention_days
  purge_protection_enabled   = var.key_vault_purge_protection_enabled

  tags = var.tags
}

# ============================================================================
# Key Vault RBAC — data-plane role assignments
#
# rbac_authorization_enabled = true means subscription-level Owner/Contributor
# has NO implicit data-plane access. Every identity that needs to read or write
# secrets/keys/certificates must have an explicit role assignment scoped to this
# vault (or a parent scope that includes it).
# ============================================================================

locals {
  # Merge the deployer identity with any extra IDs supplied via variable.
  # toset deduplicates in case the deployer OID is also listed explicitly.
  _kv_secrets_officer_ids = toset(concat(
    [data.azurerm_client_config.current.object_id],
    var.key_vault_admin_object_ids
  ))
}

resource "azurerm_role_assignment" "kv_secrets_officer" {
  for_each = local._kv_secrets_officer_ids

  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = each.value
}
