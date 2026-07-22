################################################################################
# Resource Group Outputs
################################################################################

output "delivery_resource_group_name" {
  description = "Name of the Service Delivery resource group"
  value       = azurerm_resource_group.delivery.name
}

output "delivery_resource_group_id" {
  description = "ID of the Service Delivery resource group"
  value       = azurerm_resource_group.delivery.id
}

output "fulfillment_resource_group_name" {
  description = "Name of the Service Fulfillment resource group"
  value       = azurerm_resource_group.fulfillment.name
}

output "fulfillment_resource_group_id" {
  description = "ID of the Service Fulfillment resource group"
  value       = azurerm_resource_group.fulfillment.id
}

################################################################################
# Infrastructure Team Service Principal Outputs
################################################################################

output "infra_sp_application_id" {
  description = "Application (Client) ID of the infrastructure team service principal"
  value       = azuread_application.infra.client_id
}

output "infra_sp_object_id" {
  description = "Object ID of the infrastructure team service principal"
  value       = azuread_service_principal.infra.object_id
}

output "infra_sp_client_secret" {
  description = "Client secret for the infrastructure team service principal (sensitive)"
  value       = azuread_application_password.infra.value
  sensitive   = true
}

output "infra_sp_tenant_id" {
  description = "Tenant ID for the infrastructure team service principal"
  value       = data.azurerm_client_config.current.tenant_id
}

output "infra_sp_subscription_id" {
  description = "Subscription ID where resources are deployed"
  value       = data.azurerm_client_config.current.subscription_id
}

################################################################################
# MFT Workload Identity Outputs
################################################################################

output "mft_identity_id" {
  description = "Resource ID of the MFT workload user-assigned managed identity"
  value       = var.create_mft_identity ? azurerm_user_assigned_identity.mft[0].id : null
}

output "mft_identity_principal_id" {
  description = "Principal (Object) ID of the MFT workload user-assigned managed identity"
  value       = var.create_mft_identity ? azurerm_user_assigned_identity.mft[0].principal_id : null
}

output "mft_identity_client_id" {
  description = "Client ID of the MFT workload user-assigned managed identity"
  value       = var.create_mft_identity ? azurerm_user_assigned_identity.mft[0].client_id : null
}

################################################################################
# Instructions for Infrastructure Team
################################################################################

output "instructions" {
  description = "Instructions for the infrastructure team to use the service principal"
  value       = <<-EOT
    
    ========================================
    Infrastructure Team Service Principal
    ========================================
    
    To authenticate with this service principal, use:
    
    az login --service-principal \
      --username ${azuread_application.infra.client_id} \
      --password <client-secret> \
      --tenant ${data.azurerm_client_config.current.tenant_id}
    
    Or set these environment variables for Terraform:
    
    export ARM_CLIENT_ID="${azuread_application.infra.client_id}"
    export ARM_CLIENT_SECRET="<client-secret>"
    export ARM_TENANT_ID="${data.azurerm_client_config.current.tenant_id}"
    export ARM_SUBSCRIPTION_ID="${data.azurerm_client_config.current.subscription_id}"
    
    The client secret can be retrieved with:
    terraform output -raw infra_sp_client_secret
    
    This service principal has Contributor role on:
    - ${azurerm_resource_group.delivery.name}
    - ${azurerm_resource_group.fulfillment.name}
    
    ========================================
  EOT
}
