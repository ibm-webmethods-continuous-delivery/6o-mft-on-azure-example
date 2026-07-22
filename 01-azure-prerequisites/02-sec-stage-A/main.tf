# Get current client configuration
data "azurerm_client_config" "current" {}

# Local variables for computed names
locals {
  delivery_rg_name    = "${var.prefix}-${var.delivery_rg_suffix}"
  fulfillment_rg_name = "${var.prefix}-${var.fulfillment_rg_suffix}"
  infra_sp_name       = "${var.prefix}-${var.infra_sp_name_suffix}"
  azdo_sp_name        = "${var.prefix}-${var.azdo_sp_name_suffix}"
  mft_identity_name   = "${var.prefix}-${var.mft_identity_suffix}"
  agic_identity_name  = "${var.prefix}-${var.agic_identity_suffix}"
}

################################################################################
# Resource Groups
################################################################################

# Service Delivery Resource Group
# Purpose: CI/CD infrastructure (Azure DevOps agents, ACR, Key Vault, etc.)
resource "azurerm_resource_group" "delivery" {
  name     = local.delivery_rg_name
  location = var.location
  tags     = var.tags
}

# Service Fulfillment Resource Group
# Purpose: MFT runtime infrastructure (AKS, SFTP VMs, PostgreSQL, App Gateway, etc.)
resource "azurerm_resource_group" "fulfillment" {
  name     = local.fulfillment_rg_name
  location = var.location
  tags     = var.tags
}

################################################################################
# Infrastructure Team Service Principal
################################################################################

# Azure AD Application for Infrastructure Team
resource "azuread_application" "infra" {
  display_name = local.infra_sp_name
  description  = var.infra_sp_description
  owners       = [data.azurerm_client_config.current.object_id]
}

# Service Principal for the Application
resource "azuread_service_principal" "infra" {
  client_id = azuread_application.infra.client_id
  owners    = [data.azurerm_client_config.current.object_id]

  description = var.infra_sp_description
}

# Client Secret for the Service Principal
resource "azuread_application_password" "infra" {
  application_id = azuread_application.infra.id
  display_name   = "Terraform-managed secret"
  end_date       = timeadd(timestamp(), "8760h") # 1 year from now

  lifecycle {
    ignore_changes = [end_date]
  }
}

# Wait for service principal to propagate in Azure AD
resource "time_sleep" "wait_for_sp_propagation" {
  depends_on = [azuread_service_principal.infra]

  create_duration = "30s"
}

################################################################################
# Azure DevOps Service Principal (Optional)
################################################################################

# Azure AD Application for Azure DevOps operations
resource "azuread_application" "azdo" {
  count = var.create_azdo_sp ? 1 : 0

  display_name = local.azdo_sp_name
  description  = var.azdo_sp_description
  owners       = [data.azurerm_client_config.current.object_id]
}

# Service Principal for the Azure DevOps Application
resource "azuread_service_principal" "azdo" {
  count = var.create_azdo_sp ? 1 : 0

  client_id = azuread_application.azdo[0].client_id
  owners    = [data.azurerm_client_config.current.object_id]

  description = var.azdo_sp_description
}

# Client Secret for the Azure DevOps Service Principal
resource "azuread_application_password" "azdo" {
  count = var.create_azdo_sp ? 1 : 0

  application_id = azuread_application.azdo[0].id
  display_name   = "Terraform-managed secret"
  end_date       = timeadd(timestamp(), "8760h") # 1 year from now

  lifecycle {
    ignore_changes = [end_date]
  }
}

# Wait for Azure DevOps service principal to propagate in Azure AD
resource "time_sleep" "wait_for_azdo_sp_propagation" {
  count = var.create_azdo_sp ? 1 : 0

  depends_on = [azuread_service_principal.azdo]

  create_duration = "30s"
}

################################################################################
# Role Assignments for Infrastructure Team Service Principal
################################################################################

# Contributor role on Service Delivery Resource Group
resource "azurerm_role_assignment" "infra_delivery_contributor" {
  scope                = azurerm_resource_group.delivery.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.infra.object_id

  depends_on = [time_sleep.wait_for_sp_propagation]
}

# Contributor role on Service Fulfillment Resource Group
resource "azurerm_role_assignment" "infra_fulfillment_contributor" {
  scope                = azurerm_resource_group.fulfillment.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.infra.object_id

  depends_on = [time_sleep.wait_for_sp_propagation]
}

# Contributor role on Service Delivery Resource Group for Azure DevOps Service Principal
resource "azurerm_role_assignment" "azdo_delivery_contributor" {
  count = var.create_azdo_sp ? 1 : 0

  scope                = azurerm_resource_group.delivery.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.azdo[0].object_id

  depends_on = [time_sleep.wait_for_azdo_sp_propagation]
}

################################################################################
# MFT Workload User-Assigned Managed Identity (Optional)
################################################################################

# User-Assigned Managed Identity for MFT workloads
# This identity will be used by MFT pods running in AKS to access Key Vault
# Federated credentials will be added later when AKS OIDC issuer URL is known
resource "azurerm_user_assigned_identity" "mft" {
  count = var.create_mft_identity ? 1 : 0

  name                = local.mft_identity_name
  location            = var.location
  resource_group_name = azurerm_resource_group.fulfillment.name
  tags                = var.tags
}

# User-Assigned Managed Identity for AGIC workloads
# This identity will be used by AGIC running in AKS to manage Application Gateway
# Federated credentials will be added later when AKS OIDC issuer URL is known
resource "azurerm_user_assigned_identity" "agic" {
  count = var.create_agic_identity ? 1 : 0

  name                = local.agic_identity_name
  location            = var.location
  resource_group_name = azurerm_resource_group.fulfillment.name
  tags                = var.tags
}
