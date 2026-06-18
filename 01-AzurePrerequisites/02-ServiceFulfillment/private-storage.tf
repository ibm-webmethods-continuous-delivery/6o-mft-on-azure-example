# ============================================================================
# Private Storage Account for MFT VFS
# ============================================================================

resource "azurerm_storage_account" "mft_vfs_private" {
  count = var.mft_vfs_private_enabled ? 1 : 0

  name                     = "${var.prefix}mftvfspvt" # Max 24 chars, lowercase
  resource_group_name      = azurerm_resource_group.main.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  # Enable private access only
  ## put temporarily on true when creating, then switch on false
  public_network_access_enabled = false

  # Required for Azure Files
  https_traffic_only_enabled = true
  large_file_share_enabled   = true
  min_tls_version            = "TLS1_2"

  # Network rules - deny all public access
  network_rules {
    ## put temporarily on Allow when creating, then switch on Deny
    default_action             = "Deny"
    bypass                     = ["AzureServices"]
    virtual_network_subnet_ids = [] # No service endpoints, only private endpoint
  }

  # Enable blob versioning for data protection
  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = var.mft_vfs_private_retention_days
    }
  }

  # Enable file share soft delete
  share_properties {
    retention_policy {
      days = var.mft_vfs_private_retention_days
    }
  }

  tags = merge(
    var.tags,
    {
      Purpose = "MFT-VFS-Private"
      Access  = "Private-Endpoint-Only"
    }
  )
}

# Create Azure Files share for MFT VFS
resource "azurerm_storage_share" "mft_vfs_private" {
  count = var.mft_vfs_private_enabled ? 1 : 0

  name                 = "mft-vfs-private"
  storage_account_name = azurerm_storage_account.mft_vfs_private[0].name
  quota                = var.mft_vfs_private_quota_gb

  metadata = {
    # environment = var.environment
    purpose     = "mft-vfs"
  }
}

# ============================================================================
# Private Endpoint for Storage Account
# ============================================================================

resource "azurerm_private_endpoint" "mft_vfs_storage" {
  count = var.mft_vfs_private_enabled ? 1 : 0

  name                = "${var.prefix}-mft-vfs-pe"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_1.id # Adjust to your AKS subnet

  private_service_connection {
    name                           = "${var.prefix}-mft-vfs-psc"
    private_connection_resource_id = azurerm_storage_account.mft_vfs_private[0].id
    subresource_names              = ["file"] # For Azure Files
    is_manual_connection           = false
  }

  # Optional: Private DNS zone group for automatic DNS registration
  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.storage_file[0].id]
  }

  tags = merge(
    var.tags,
    {
      Purpose = "MFT-VFS-Private-Endpoint"
    }
  )
}

# ============================================================================
# Private DNS Zone for Azure Files
# ============================================================================

resource "azurerm_private_dns_zone" "storage_file" {
  count = var.mft_vfs_private_enabled ? 1 : 0

  name                = "privatelink.file.core.windows.net"
  resource_group_name = azurerm_resource_group.main.name

  tags = var.tags
}

# Link DNS zone to VNet
resource "azurerm_private_dns_zone_virtual_network_link" "storage_file" {
  count = var.mft_vfs_private_enabled ? 1 : 0

  name                  = "${var.prefix}-storage-file-dns-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.storage_file[0].name
  virtual_network_id    = azurerm_virtual_network.main.id
  registration_enabled  = false # Manual registration via private endpoint

  tags = var.tags
}

# Note: DNS A record is automatically created by private_dns_zone_group
# in the private endpoint configuration above

# ============================================================================
# RBAC for AKS to access private storage
# ============================================================================

# Grant AKS managed identity access to storage account
resource "azurerm_role_assignment" "aks_storage_contributor" {
  count = var.mft_vfs_private_enabled ? 1 : 0

  scope                = azurerm_storage_account.mft_vfs_private[0].id
  role_definition_name = "Storage Account Contributor"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}

# Grant access to file share data
resource "azurerm_role_assignment" "aks_storage_file_data_smb" {
  count = var.mft_vfs_private_enabled ? 1 : 0

  scope                = azurerm_storage_account.mft_vfs_private[0].id
  role_definition_name = "Storage File Data SMB Share Contributor"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}
