# Resource Group
output "resource_group_name" {
  description = "Name of the resource group"
  value       = data.azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = data.azurerm_resource_group.main.location
}

# Network Security Group
output "nsg_id" {
  description = "ID of the Network Security Group"
  value       = azurerm_network_security_group.main.id
}

output "nsg_name" {
  description = "Name of the Network Security Group"
  value       = azurerm_network_security_group.main.name
}

# Virtual Network
output "vnet_id" {
  description = "ID of the Virtual Network"
  value       = azurerm_virtual_network.main.id
}

output "vnet_name" {
  description = "Name of the Virtual Network"
  value       = azurerm_virtual_network.main.name
}

output "subnet_id" {
  description = "ID of the VM subnet"
  value       = azurerm_subnet.main.id
}

output "subnet_name" {
  description = "Name of the VM subnet"
  value       = azurerm_subnet.main.name
}

# Virtual Machine Scale Set
output "vmss_id" {
  description = "ID of the Virtual Machine Scale Set"
  value       = azurerm_linux_virtual_machine_scale_set.main.id
}

output "vmss_name" {
  description = "Name of the Virtual Machine Scale Set"
  value       = azurerm_linux_virtual_machine_scale_set.main.name
}

# Storage Account
output "storage_account_id" {
  description = "ID of the Storage Account"
  value       = azurerm_storage_account.main.id
}

output "storage_account_name" {
  description = "Name of the Storage Account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_primary_access_key" {
  description = "Primary access key for the Storage Account"
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
}

output "storage_share_name" {
  description = "Name of the file share"
  value       = azurerm_storage_share.main.name
}

output "storage_share_url" {
  description = "URL of the file share"
  value       = azurerm_storage_share.main.url
}

# Key Vault
output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

# Azure Container Registry
output "acr_id" {
  description = "ID of the Azure Container Registry"
  value       = azurerm_container_registry.main.id
}

output "acr_name" {
  description = "Name of the Azure Container Registry"
  value       = azurerm_container_registry.main.name
}

output "acr_login_server" {
  description = "Login server URL for the Azure Container Registry"
  value       = azurerm_container_registry.main.login_server
}

# Azure DevOps Project
output "azdo_project_id" {
  description = "ID of the Azure DevOps project"
  value       = azuredevops_project.main.id
}

output "azdo_project_name" {
  description = "Name of the Azure DevOps project"
  value       = azuredevops_project.main.name
}

output "azdo_project_url" {
  description = "URL of the Azure DevOps project"
  value       = "${var.azdo_org_service_url}/${azuredevops_project.main.name}"
}

# Azure DevOps Agent Pool
output "azdo_agent_pool_id" {
  description = "ID of the Azure DevOps agent pool"
  value       = azuredevops_agent_pool.main.id
}

output "azdo_agent_pool_name" {
  description = "Name of the Azure DevOps agent pool"
  value       = azuredevops_agent_pool.main.name
}

# Azure DevOps Service Endpoint
output "azdo_service_endpoint_id" {
  description = "ID of the Azure RM service endpoint"
  value       = azuredevops_serviceendpoint_azurerm.main.id
}

output "azdo_service_endpoint_name" {
  description = "Name of the Azure RM service endpoint"
  value       = azuredevops_serviceendpoint_azurerm.main.service_endpoint_name
}

# GitHub Service Endpoint Outputs
output "github_service_endpoint_id" {
  description = "ID of the GitHub service endpoint"
  value       = azuredevops_serviceendpoint_github.github.id
}

output "github_service_endpoint_name" {
  description = "Name of the GitHub service endpoint"
  value       = azuredevops_serviceendpoint_github.github.service_endpoint_name
}
