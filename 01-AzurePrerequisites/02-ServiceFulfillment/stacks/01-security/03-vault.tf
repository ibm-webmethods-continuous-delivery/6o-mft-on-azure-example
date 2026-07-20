# ============================================================================
# Azure Key Vault for MFT Secrets Management
# ============================================================================

resource "azurerm_key_vault" "main" {
  name                = "${var.prefix}-kv"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # Network configuration - switchable between public and private
  public_network_access_enabled = var.key_vault_public_access_enabled

  # RBAC model (preferred over access policies)
  rbac_authorization_enabled = true

  # Soft delete and purge protection
  soft_delete_retention_days = var.key_vault_soft_delete_retention_days
  purge_protection_enabled   = var.key_vault_purge_protection_enabled

  tags = var.tags
}

# ============================================================================
# Private Endpoint for Key Vault (when private access is enabled)
# ============================================================================

resource "azurerm_private_endpoint" "key_vault" {
  count               = var.key_vault_public_access_enabled ? 0 : 1
  name                = "${var.prefix}-kv-pe"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = var.private_subnet_id

  private_service_connection {
    name                           = "${var.prefix}-kv-psc"
    private_connection_resource_id = azurerm_key_vault.main.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  tags = var.tags
}

# Private DNS zone for Key Vault
resource "azurerm_private_dns_zone" "key_vault" {
  count               = var.key_vault_public_access_enabled ? 0 : 1
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

# Link Private DNS zone to VNet
resource "azurerm_private_dns_zone_virtual_network_link" "key_vault" {
  count                 = var.key_vault_public_access_enabled ? 0 : 1
  name                  = "${var.prefix}-kv-dns-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.key_vault[0].name
  virtual_network_id    = var.vnet_id
  tags                  = var.tags
}

# Private DNS A record for Key Vault
resource "azurerm_private_dns_a_record" "key_vault" {
  count               = var.key_vault_public_access_enabled ? 0 : 1
  name                = azurerm_key_vault.main.name
  zone_name           = azurerm_private_dns_zone.key_vault[0].name
  resource_group_name = azurerm_resource_group.main.name
  ttl                 = 300
  records             = [azurerm_private_endpoint.key_vault[0].private_service_connection[0].private_ip_address]
}

# ============================================================================
# User-Assigned Managed Identity for MFT Workload
# ============================================================================

resource "azurerm_user_assigned_identity" "mft" {
  name                = "${var.prefix}-mft-identity"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

# ============================================================================
# Federated Identity Credentials for Workload Identity (AKS OIDC)
# ============================================================================

# Federated credential for MFT service account
resource "azurerm_federated_identity_credential" "mft" {
  name                = "${var.prefix}-mft-federated-credential"
  resource_group_name = azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.mft.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.aks_oidc_issuer_url
  subject             = "system:serviceaccount:${var.mft_namespace}:${var.mft_service_account_name}"
}

# Federated credential for Database Configurator service account
resource "azurerm_federated_identity_credential" "dbc" {
  name                = "${var.prefix}-dbc-federated-credential"
  resource_group_name = azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.mft.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.aks_oidc_issuer_url
  subject             = "system:serviceaccount:default:database-configurator-sa"
}

# Federated credential for Database User Init service account
resource "azurerm_federated_identity_credential" "db_user_init" {
  name                = "${var.prefix}-db-user-init-federated-credential"
  resource_group_name = azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.mft.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.aks_oidc_issuer_url
  subject             = "system:serviceaccount:default:database-user-init-sa"
}

# Federated credential for active transfer - mft service
resource "azurerm_federated_identity_credential" "mft_workload_identity" {
  name                = "${var.prefix}-mft-service-federated-credential"
  resource_group_name = azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.mft.id
  issuer              = var.aks_oidc_issuer_url
  subject             = "system:serviceaccount:mft:mft-service-account"
  audience            = ["api://AzureADTokenExchange"]
}

# ============================================================================
# Key Vault Role Assignments
# ============================================================================

# Grant Key Vault Secrets User role to MFT user assigned identity
resource "azurerm_role_assignment" "mft_kv_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.mft.principal_id
}

# Grant Key Vault Certificate User role to MFT user assigned identity
resource "azurerm_role_assignment" "mft_kv_certificates_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Certificate User"
  principal_id         = azurerm_user_assigned_identity.mft.principal_id
}

# Grant current identity running Terraform Key Vault Administrator role (for secret creation)
resource "azurerm_role_assignment" "terraform_kv_admin" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ============================================================================
# Default MFT Secrets in Key Vault
# ============================================================================

locals {
  environment = var.environment_name

  default_secrets = {
    "${local.environment}-mft-admin-password" = {
      value       = "ChangeMe123!"
      description = "MFT administrator password for admin UI and management operations"
    }
    "${local.environment}-mft-admin-ui-jks-keystore-password" = {
      value       = "ChangeMe123!"
      description = "Password for MFT Admin UI JKS keystore"
    }
    "${local.environment}-mft-admin-ui-pkcs12-keystore-password" = {
      value       = "ChangeMe123!"
      description = "Password for MFT Admin UI PKCS12 keystore"
    }
    "${local.environment}-mft-admin-ui-jks-truststore-password" = {
      value       = "ChangeMe123!"
      description = "Password for MFT Admin UI JKS truststore"
    }
    "${local.environment}-mft-admin-ui-pkcs12-truststore-password" = {
      value       = "ChangeMe123!"
      description = "Password for MFT Admin UI PKCS12 truststore"
    }
    "${local.environment}-mft-web-client-jks-keystore-password" = {
      value       = "ChangeMe123!"
      description = "Password for MFT Web Client JKS keystore"
    }
    "${local.environment}-mft-web-client-pkcs12-keystore-password" = {
      value       = "ChangeMe123!"
      description = "Password for MFT Web Client PKCS12 keystore"
    }
    "${local.environment}-mft-web-client-jks-truststore-password" = {
      value       = "ChangeMe123!"
      description = "Password for MFT Web Client JKS truststore"
    }
    "${local.environment}-mft-web-client-pkcs12-truststore-password" = {
      value       = "ChangeMe123!"
      description = "Password for MFT Web Client PKCS12 truststore"
    }
    "${local.environment}-mft-cert-jks-truststore-password" = {
      value       = "ChangeMe123!"
      description = "Password for global MFT JKS truststore"
    }
    "${local.environment}-mft-cert-pkcs12-truststore-password" = {
      value       = "ChangeMe123!"
      description = "Password for global MFT PKCS12 truststore"
    }
    "${local.environment}-mft-sftp-ssh-private-key" = {
      value       = "placeholder-ssh-key"
      description = "SSH private key for SFTP server authentication (placeholder, replace with actual key)"
    }
    "${local.environment}-mft-metering-config-xml-file" = {
      value       = "<metering>Change this to a valid file you download from https://ibm.biz/metering</metering>"
      description = "IBM webMethods metering configuration XML file mounted into the Active Transfer runtime when metering is enabled"
    }
  }
}

# Create default secrets in Key Vault with descriptions
resource "azurerm_key_vault_secret" "defaults" {
  for_each = local.default_secrets

  name         = each.key
  value        = each.value.value
  key_vault_id = azurerm_key_vault.main.id

  # Content type for documentation
  content_type = "text/plain"

  # Set expiration
  expiration_date = var.secret_expiration_date

  tags = merge(var.tags, {
    ManagedBy   = "Terraform"
    Purpose     = "MFT-Example"
    Environment = local.environment
    Warning     = "DEFAULT-VALUE-CHANGE-IMMEDIATELY"
    Description = each.value.description
  })

  depends_on = [
    azurerm_role_assignment.terraform_kv_admin
  ]

  lifecycle {
    ignore_changes = [value, expiration_date]
  }
}

# ============================================================================
# MFT Database Credentials in Key Vault
# ============================================================================

locals {
  # Database credentials for MFT components (Database Configurator, etc.)
  mft_db_credentials = {
    "postgres-server-fqdn" = {
      value       = var.postgres_server_fqdn
      description = "PostgreSQL Flexible Server FQDN for MFT database connections"
    }
    "postgres-online-db" = {
      value       = var.postgres_online_db_name
      description = "PostgreSQL database name for MFT online transactions"
    }
    "postgres-archive-db" = {
      value       = var.postgres_archive_db_name
      description = "PostgreSQL database name for MFT archiving"
    }
    "postgres-admin-user" = {
      value       = var.postgres_admin_username
      description = "PostgreSQL administrator username for database bootstrap and maintenance"
    }
    "postgres-admin-password" = {
      value       = var.postgres_admin_password
      description = "PostgreSQL administrator password for database bootstrap and maintenance"
    }
    "postgres-online-user" = {
      value       = var.postgres_dbc_user
      description = "PostgreSQL user for MFT online database operations (shared by MFT tools)"
    }
    "postgres-online-password" = {
      value       = var.postgres_dbc_password
      description = "PostgreSQL password for MFT online database operations (shared by MFT tools)"
    }
    "postgres-archive-user" = {
      value       = var.postgres_dbc_archive_user
      description = "PostgreSQL user for MFT archive database operations"
    }
    "postgres-archive-password" = {
      value       = var.postgres_dbc_archive_password
      description = "PostgreSQL password for MFT archive database operations"
    }
  }
}

# Create MFT database secrets in Key Vault with descriptions
resource "azurerm_key_vault_secret" "mft_db_credentials" {
  for_each = local.mft_db_credentials

  name         = "${local.environment}-mft-db-${each.key}"
  value        = each.value.value
  key_vault_id = azurerm_key_vault.main.id

  # Set expiration
  expiration_date = var.secret_expiration_date

  # Content type for documentation
  content_type = "text/plain"

  tags = merge(var.tags, {
    ManagedBy   = "Terraform"
    Purpose     = "MFT-Database"
    Environment = local.environment
    Component   = "MFT-DB"
    Description = each.value.description
  })

  depends_on = [
    azurerm_role_assignment.terraform_kv_admin
  ]

  lifecycle {
    ignore_changes = [value, expiration_date]
  }
}

# ============================================================================
# Certificate Upload to Key Vault
# ============================================================================

locals {
  # Certificate files mapping (only when upload_certificates is enabled)
  certificate_files = var.upload_certificates ? {
    "${local.environment}-mft-cert-admin-ui-keystore-pkcs12" = {
      file_path   = "${var.certificates_base_path}/02-admin-ui/out/rsa/full.chain.key.store.p12"
      description = "PKCS12 keystore, encrypted to open HTTPS ports for administration UI. Password is provided in the secret with name ${local.environment}-mft-admin-ui-pkcs12-keystore-password"
    }
    "${local.environment}-mft-cert-admin-ui-keystore-jks" = {
      file_path   = "${var.certificates_base_path}/02-admin-ui/out/rsa/full.chain.key.store.jks"
      description = "JKS formatted keystore, encrypted to open HTTPS ports for administration UI. Password is provided in the secret with name ${local.environment}-mft-admin-ui-jks-keystore-password"
    }
    "${local.environment}-mft-cert-web-client-keystore-pkcs12" = {
      file_path   = "${var.certificates_base_path}/03-web-client/out/rsa/full.chain.key.store.p12"
      description = "Keystore for web client HTTPS port, in PKCS12 format, password in ${local.environment}-mft-web-client-pkcs12-keystore-password"
    }
    "${local.environment}-mft-cert-web-client-keystore-jks" = {
      file_path   = "${var.certificates_base_path}/03-web-client/out/rsa/full.chain.key.store.jks"
      description = "Keystore for web client HTTPS port, in JKS format, password in ${local.environment}-mft-web-client-jks-keystore-password"
    }
    "${local.environment}-mft-cert-truststore-pkcs12" = {
      file_path   = "${var.certificates_base_path}/02-admin-ui/out/rsa/public.trust.store.p12"
      description = "Global truststore for MFT, in PKCS12 format, encrypted. Password is taken from the keyvault secret with name ${local.environment}-mft-cert-pkcs12-truststore-password"
    }
    "${local.environment}-mft-cert-truststore-jks" = {
      file_path   = "${var.certificates_base_path}/out/global.public.trust.store.jks"
      description = "Global truststore for MFT, in JKS format, encrypted. Password is taken from the keyvault secret with name ${local.environment}-mft-cert-jks-truststore-password"
    }
    "${local.environment}-mft-cert-ca-bundle-pem" = {
      file_path   = "${var.certificates_base_path}/out/all_certs.pem"
      description = "Bundle of certificates, in PEM format, without encryption"
    }
  } : {}

  # SSH private key (updates existing placeholder)
  sftp_ssh_key_file = var.upload_certificates ? "${var.certificates_base_path}/04-sftp-server/out/id_rsa" : null
}

# Upload certificate files to Key Vault as base64-encoded secrets
resource "azurerm_key_vault_secret" "certificates" {
  for_each = local.certificate_files

  name         = each.key
  value        = filebase64(each.value.file_path)
  key_vault_id = azurerm_key_vault.main.id

  # Set expiration
  expiration_date = var.secret_expiration_date

  # Content type for documentation
  content_type = "application/octet-stream"

  tags = merge(var.tags, {
    ManagedBy    = "Terraform"
    Purpose      = "MFT-Certificates"
    Environment  = local.environment
    CertType     = "KeyStore-TrustStore"
    UploadedFrom = basename(each.value.file_path)
    Description  = each.value.description
  })

  depends_on = [
    azurerm_role_assignment.terraform_kv_admin
  ]

  lifecycle {
    ignore_changes = [value, expiration_date]
  }
}

# Update SFTP SSH private key (replaces placeholder)
resource "azurerm_key_vault_secret" "sftp_ssh_key" {
  count = var.upload_certificates ? 1 : 0

  name         = "${local.environment}-mft-sftp-ssh-private-key-loaded"
  value        = file(local.sftp_ssh_key_file)
  key_vault_id = azurerm_key_vault.main.id

  # Set expiration
  expiration_date = var.secret_expiration_date

  # Content type for documentation
  content_type = "text/plain"

  tags = merge(var.tags, {
    ManagedBy    = "Terraform"
    Purpose      = "MFT-SFTP-SSH"
    Environment  = local.environment
    KeyType      = "SSH-PrivateKey"
    UploadedFrom = basename(local.sftp_ssh_key_file)
  })

  depends_on = [
    azurerm_role_assignment.terraform_kv_admin,
    azurerm_key_vault_secret.defaults
  ]

  lifecycle {
    ignore_changes = [value, expiration_date]
  }
}

# ============================================================================
# Certificate Import to Key Vault (as Certificates, not just Secrets)
# ============================================================================

locals {
  # Certificate files for import as Key Vault certificates
  certificate_imports = var.upload_certificates ? {
    "${local.environment}-mft-admin-ui-cert-with-chain" = {
      file_path   = "${var.certificates_base_path}/02-admin-ui/out/rsa/full.chain.key.store.p12"
      description = "Admin UI certificate with full chain"
    }
    "${local.environment}-mft-admin-ui-cert-no-chain" = {
      file_path   = "${var.certificates_base_path}/02-admin-ui/out/rsa/private.key.store.p12"
      description = "Admin UI certificate without chain"
    }
    "${local.environment}-mft-web-client-cert-with-chain" = {
      file_path   = "${var.certificates_base_path}/03-web-client/out/rsa/full.chain.key.store.p12"
      description = "Web Client certificate with full chain"
    }
    "${local.environment}-mft-web-client-cert-no-chain" = {
      file_path   = "${var.certificates_base_path}/03-web-client/out/rsa/private.key.store.p12"
      description = "Web Client certificate without chain"
    }
  } : {}
}

# Import PKCS12 certificates into Key Vault as certificates
resource "azurerm_key_vault_certificate" "imported" {
  for_each = local.certificate_imports

  name         = each.key
  key_vault_id = azurerm_key_vault.main.id

  certificate {
    contents = filebase64(each.value.file_path)
    password = var.certificate_password
  }

  certificate_policy {
    issuer_parameters {
      name = "Unknown"
    }

    key_properties {
      exportable = true
      key_size   = 2048
      key_type   = "RSA"
      reuse_key  = false
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }

    x509_certificate_properties {
      key_usage = [
        "digitalSignature",
        "keyEncipherment",
      ]

      subject            = "CN=Imported Certificate"
      validity_in_months = 12
    }
  }

  tags = merge(var.tags, {
    ManagedBy    = "Terraform"
    Purpose      = "MFT-Certificates"
    Environment  = local.environment
    CertType     = "Imported-PKCS12"
    Description  = each.value.description
    UploadedFrom = basename(each.value.file_path)
  })

  depends_on = [
    azurerm_role_assignment.terraform_kv_admin
  ]
}

# ============================================================================
# AGIC (Application Gateway Ingress Controller) Service Principal
# ============================================================================

# Create Azure AD Application for AGIC
resource "azuread_application" "agic" {
  display_name = "${var.prefix}-agic-sp"
  owners       = [data.azuread_client_config.current.object_id]
}

# Create Service Principal for the AGIC Application
resource "azuread_service_principal" "agic" {
  client_id = azuread_application.agic.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

# Create a password/secret for the Service Principal
resource "azuread_service_principal_password" "agic" {
  service_principal_id = azuread_service_principal.agic.id
}

# Grant AGIC Service Principal Contributor access to Application Gateway
resource "azurerm_role_assignment" "agic_appgw_contributor" {
  count                = var.enable_agic_role_assignments && var.app_gateway_id != "" ? 1 : 0
  scope                = var.app_gateway_id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.agic.object_id
}

# Grant AGIC Service Principal Reader access to Application Gateway resource group
resource "azurerm_role_assignment" "agic_rg_reader" {
  count                = var.enable_agic_role_assignments ? 1 : 0
  scope                = data.azurerm_resource_group.parent.id
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.agic.object_id
}

# Grant AGIC Service Principal Network Contributor access to App Gateway subnet
resource "azurerm_role_assignment" "agic_subnet_network_contributor" {
  count                = var.enable_agic_role_assignments && var.app_gateway_subnet_id != "" ? 1 : 0
  scope                = var.app_gateway_subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azuread_service_principal.agic.object_id
}
