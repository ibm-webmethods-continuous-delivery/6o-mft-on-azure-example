# ============================================================================
# Resource Group Outputs
# ============================================================================

output "resource_group_name" {
  description = "Name of the security resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "ID of the security resource group"
  value       = azurerm_resource_group.main.id
}

output "resource_group_location" {
  description = "Location of the security resource group"
  value       = azurerm_resource_group.main.location
}

# ============================================================================
# Azure Key Vault Outputs
# ============================================================================

output "key_vault_name" {
  description = "Name of the Azure Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_id" {
  description = "ID of the Azure Key Vault"
  value       = azurerm_key_vault.main.id
}

output "key_vault_uri" {
  description = "URI of the Azure Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

output "key_vault_access_mode" {
  description = "Key Vault access mode (public or private)"
  value       = var.key_vault_public_access_enabled ? "public" : "private"
}

output "key_vault_private_endpoint_ip" {
  description = "Private IP address of the Key Vault private endpoint (if enabled)"
  value       = var.key_vault_public_access_enabled ? null : azurerm_private_endpoint.key_vault[0].private_service_connection[0].private_ip_address
}

# ============================================================================
# Managed Identity Outputs
# ============================================================================

output "mft_managed_identity_name" {
  description = "Name of the MFT managed identity"
  value       = azurerm_user_assigned_identity.mft.name
}

output "mft_managed_identity_id" {
  description = "ID of the MFT managed identity"
  value       = azurerm_user_assigned_identity.mft.id
}

output "mft_managed_identity_client_id" {
  description = "Client ID of the MFT managed identity for workload identity"
  value       = azurerm_user_assigned_identity.mft.client_id
}

output "mft_managed_identity_principal_id" {
  description = "Principal ID of the MFT managed identity"
  value       = azurerm_user_assigned_identity.mft.principal_id
}

# ============================================================================
# Federated Identity Credentials Outputs
# ============================================================================

output "federated_credentials" {
  description = "Map of federated identity credentials created"
  value = {
    mft = {
      name      = azurerm_federated_identity_credential.mft.name
      subject   = azurerm_federated_identity_credential.mft.subject
      namespace = var.mft_namespace
    }
    dbc = {
      name      = azurerm_federated_identity_credential.dbc.name
      subject   = azurerm_federated_identity_credential.dbc.subject
      namespace = "default"
    }
    db_user_init = {
      name      = azurerm_federated_identity_credential.db_user_init.name
      subject   = azurerm_federated_identity_credential.db_user_init.subject
      namespace = "default"
    }
    mft_workload = {
      name      = azurerm_federated_identity_credential.mft_workload_identity.name
      subject   = azurerm_federated_identity_credential.mft_workload_identity.subject
      namespace = "mft"
    }
  }
}

# ============================================================================
# AGIC Service Principal Outputs
# ============================================================================

output "agic_application_id" {
  description = "Application (Client) ID of the AGIC Azure AD Application"
  value       = azuread_application.agic.client_id
}

output "agic_service_principal_id" {
  description = "Object ID of the AGIC Service Principal"
  value       = azuread_service_principal.agic.object_id
}

output "agic_service_principal_client_id" {
  description = "Client ID of the AGIC Service Principal"
  value       = azuread_application.agic.client_id
}

output "agic_service_principal_client_secret" {
  description = "Client Secret of the AGIC Service Principal"
  value       = azuread_service_principal_password.agic.value
  sensitive   = true
}

output "agic_service_principal_tenant_id" {
  description = "Tenant ID for the AGIC Service Principal"
  value       = data.azuread_client_config.current.tenant_id
}

# ============================================================================
# Secret Management Outputs
# ============================================================================

output "environment_name" {
  description = "Environment name used for secret naming"
  value       = var.environment_name
}

output "secret_naming_prefix" {
  description = "Prefix used for secret names in Key Vault"
  value       = "${var.environment_name}-mft"
}

output "default_secrets_created" {
  description = "List of default secret names created in Key Vault"
  value       = keys(azurerm_key_vault_secret.defaults)
}

output "database_secrets_created" {
  description = "List of database secret names created in Key Vault"
  value       = keys(azurerm_key_vault_secret.mft_db_credentials)
}

output "certificates_uploaded" {
  description = "Whether certificates were uploaded to Key Vault"
  value       = var.upload_certificates
}

output "certificate_secrets_created" {
  description = "List of certificate secret names created in Key Vault (if upload_certificates is enabled)"
  value       = var.upload_certificates ? keys(azurerm_key_vault_secret.certificates) : []
}

output "certificate_imports_created" {
  description = "List of certificate names imported as Key Vault certificates (if upload_certificates is enabled)"
  value       = var.upload_certificates ? keys(azurerm_key_vault_certificate.imported) : []
}

# ============================================================================
# Azure Context Outputs
# ============================================================================

output "tenant_id" {
  description = "Azure AD tenant ID"
  value       = data.azurerm_client_config.current.tenant_id
}

output "subscription_id" {
  description = "Azure subscription ID"
  value       = data.azurerm_client_config.current.subscription_id
}

# ============================================================================
# Manual Permission Grant Instructions
# ============================================================================

output "manual_permission_grants_required" {
  description = "Instructions for manually granting AGIC permissions when automatic role assignments are disabled"
  value       = var.enable_agic_role_assignments ? "No manual grants required - role assignments were created automatically" : <<-EOT
    MANUAL PERMISSION GRANTS REQUIRED FOR AGIC:

    The following role assignments must be created manually in Azure Portal or via Azure CLI:

    1. Grant 'Contributor' role to AGIC Service Principal on Application Gateway:
       Principal ID: ${azuread_service_principal.agic.object_id}
       Role: Contributor
       Scope: Application Gateway ID (from infrastructure stack)

       Azure CLI command:
       az role assignment create \
         --assignee ${azuread_service_principal.agic.object_id} \
         --role Contributor \
         --scope <APPLICATION_GATEWAY_ID>

    2. Grant 'Reader' role to AGIC Service Principal on Resource Group:
       Principal ID: ${azuread_service_principal.agic.object_id}
       Role: Reader
       Scope: Parent Resource Group ID

       Azure CLI command:
       az role assignment create \
         --assignee ${azuread_service_principal.agic.object_id} \
         --role Reader \
         --scope ${data.azurerm_resource_group.parent.id}

    3. Grant 'Network Contributor' role to AGIC Service Principal on App Gateway subnet:
       Principal ID: ${azuread_service_principal.agic.object_id}
       Role: Network Contributor
       Scope: Application Gateway Subnet ID (from infrastructure stack)

       Azure CLI command:
       az role assignment create \
         --assignee ${azuread_service_principal.agic.object_id} \
         --role "Network Contributor" \
         --scope <APP_GATEWAY_SUBNET_ID>

    After granting these permissions, you can proceed with AGIC installation.
  EOT
}

# ============================================================================
# Summary Information
# ============================================================================

output "stack_summary" {
  description = "Summary of the security stack deployment"
  value = {
    stack_name               = "01-security"
    resource_group           = azurerm_resource_group.main.name
    key_vault_name           = azurerm_key_vault.main.name
    managed_identity_name    = azurerm_user_assigned_identity.mft.name
    agic_sp_client_id        = azuread_application.agic.client_id
    environment              = var.environment_name
    secrets_count            = length(keys(azurerm_key_vault_secret.defaults)) + length(keys(azurerm_key_vault_secret.mft_db_credentials))
    certificates_uploaded    = var.upload_certificates
    private_endpoint_enabled = !var.key_vault_public_access_enabled
  }
}
