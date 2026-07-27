################################################################################
# Key Vault Integration - Certificate Upload (Optional)
################################################################################

locals {
  certificate_files = var.upload_certificates ? {
    "${local.environment}-mft-cert-admin-ui-keystore-pkcs12" = {
      file_path   = "${var.certificates_base_path}/02-admin-ui/out/rsa/full.chain.key.store.p12"
      description = "PKCS12 keystore for administration UI HTTPS"
    }
    "${local.environment}-mft-cert-admin-ui-keystore-jks" = {
      file_path   = "${var.certificates_base_path}/02-admin-ui/out/rsa/full.chain.key.store.jks"
      description = "JKS keystore for administration UI HTTPS"
    }
    "${local.environment}-mft-cert-web-client-keystore-pkcs12" = {
      file_path   = "${var.certificates_base_path}/03-web-client/out/rsa/full.chain.key.store.p12"
      description = "PKCS12 keystore for web client HTTPS"
    }
    "${local.environment}-mft-cert-web-client-keystore-jks" = {
      file_path   = "${var.certificates_base_path}/03-web-client/out/rsa/full.chain.key.store.jks"
      description = "JKS keystore for web client HTTPS"
    }
    "${local.environment}-mft-cert-truststore-pkcs12" = {
      file_path   = "${var.certificates_base_path}/02-admin-ui/out/rsa/public.trust.store.p12"
      description = "Global PKCS12 truststore for MFT"
    }
    "${local.environment}-mft-cert-truststore-jks" = {
      file_path   = "${var.certificates_base_path}/out/global.public.trust.store.jks"
      description = "Global JKS truststore for MFT"
    }
    "${local.environment}-mft-cert-ca-bundle-pem" = {
      file_path   = "${var.certificates_base_path}/out/all_certs.pem"
      description = "CA bundle in PEM format"
    }
  } : {}

  sftp_ssh_key_file = var.upload_certificates ? "${var.certificates_base_path}/04-sftp-server/out/id_rsa" : null
}

# Upload certificate files to Key Vault as base64-encoded secrets
resource "azurerm_key_vault_secret" "certificates" {
  for_each = local.certificate_files

  name            = each.key
  value           = filebase64(each.value.file_path)
  key_vault_id    = data.azurerm_key_vault.main.id
  content_type    = "application/octet-stream"
  expiration_date = var.secret_expiration_date

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

# Update SFTP SSH private key
resource "azurerm_key_vault_secret" "sftp_ssh_key" {
  count = var.upload_certificates ? 1 : 0

  name            = "${local.environment}-mft-sftp-ssh-private-key-loaded"
  value           = file(local.sftp_ssh_key_file)
  key_vault_id    = data.azurerm_key_vault.main.id
  content_type    = "text/plain"
  expiration_date = var.secret_expiration_date

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

################################################################################
# Key Vault Integration - Certificate Import (Optional)
################################################################################

locals {
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
  key_vault_id = data.azurerm_key_vault.main.id

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

################################################################################
# Optional Private Storage for MFT VFS
################################################################################

# Private Storage Account for MFT VFS (optional)
resource "azurerm_storage_account" "private" {
  count = var.create_private_storage ? 1 : 0

  name                       = local.private_storage_account_name
  resource_group_name        = data.azurerm_resource_group.fulfillment.name
  location                   = var.location
  account_tier               = "Standard"
  account_replication_type   = "LRS"
  https_traffic_only_enabled = true
  large_file_share_enabled   = true
  tags                       = var.tags
}

# Private File Share for MFT VFS (optional)
resource "azurerm_storage_share" "private" {
  count = var.create_private_storage ? 1 : 0

  name               = local.private_storage_share_name
  storage_account_id = azurerm_storage_account.private[0].id
  access_tier        = "TransactionOptimized"
  quota              = var.private_storage_share_quota
}
