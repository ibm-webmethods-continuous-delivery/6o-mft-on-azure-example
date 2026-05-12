terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azuredevops = {
      source  = "microsoft/azuredevops"
      version = "~> 1.0"
    }
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = true
    }
  }
}

provider "azuredevops" {
  # Authentication via AZDO_PERSONAL_ACCESS_TOKEN environment variable
  # Set before running terraform: export AZDO_PERSONAL_ACCESS_TOKEN="your-pat"
  org_service_url = var.azdo_org_service_url
}

# Use existing resource group (must be created beforehand)
data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

# Get current client configuration for Key Vault access
data "azurerm_client_config" "current" {}

# Local variables for computed names
locals {
  nsg_name             = coalesce(var.nsg_name, "${var.prefix}AgentsNSG")
  vnet_name            = coalesce(var.vnet_name, "${var.prefix}AgentsNSGVnet")
  subnet_name          = coalesce(var.subnet_name, "${var.prefix}AgentsSubnet")
  vmss_name            = coalesce(var.vmss_name, "${var.prefix}AgentsVmss")
  storage_account_name = coalesce(var.storage_account_name, "${var.prefix}imagessa")
  storage_share_name   = coalesce(var.storage_share_name, "${var.prefix}imagessashare")
  key_vault_name       = coalesce(var.key_vault_name, "${var.prefix}vault")
  acr_name             = coalesce(var.acr_name, "${var.prefix}acr")
}

# Network Security Group
resource "azurerm_network_security_group" "main" {
  name                = local.nsg_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main.name
  tags                = var.tags
}

# Virtual Network with subnet
resource "azurerm_virtual_network" "main" {
  name                = local.vnet_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main.name
  address_space       = var.vnet_address_space
  tags                = var.tags

  depends_on = [azurerm_network_security_group.main]
}

# Subnet for VMs
resource "azurerm_subnet" "main" {
  name                 = local.subnet_name
  resource_group_name  = data.azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [cidrsubnet(var.vnet_address_space[0], 8, 0)]
}

# Associate NSG with subnet
resource "azurerm_subnet_network_security_group_association" "main" {
  subnet_id                 = azurerm_subnet.main.id
  network_security_group_id = azurerm_network_security_group.main.id
}

# Parse VM image components
locals {
  image_parts = split(":", var.vmss_image)
  publisher   = local.image_parts[0]
  offer       = local.image_parts[1]
  sku         = local.image_parts[2]
  version     = local.image_parts[3]
}

# Virtual Machine Scale Set (uniform orchestration, 0 instances)
resource "azurerm_linux_virtual_machine_scale_set" "main" {
  name                            = local.vmss_name
  location                        = var.location
  resource_group_name             = data.azurerm_resource_group.main.name
  sku                             = var.vmss_sku
  instances                       = var.vmss_instance_count
  admin_username                  = "azureuser"
  disable_password_authentication = true
  overprovision                   = false
  upgrade_mode                    = "Manual"
  single_placement_group          = false
  platform_fault_domain_count     = 1
  tags                            = var.tags

  admin_ssh_key {
    username = "azureuser"
    # public_key = file("~/.ssh/id_rsa.pub")
    public_key = var.ssh_admin_pub_key
  }

  source_image_reference {
    publisher = local.publisher
    offer     = local.offer
    sku       = local.sku
    version   = local.version
  }

  os_disk {
    storage_account_type = "StandardSSD_LRS"
    caching              = "ReadWrite"
  }

  network_interface {
    name    = "primary"
    primary = true

    ip_configuration {
      name      = "internal"
      primary   = true
      subnet_id = azurerm_subnet.main.id
    }
  }

  # Custom script extension to install Azure DevOps agent
  extension {
    name                       = "InstallAzDoAgent"
    publisher                  = "Microsoft.Azure.Extensions"
    type                       = "CustomScript"
    type_handler_version       = "2.1"
    auto_upgrade_minor_version = true

    protected_settings = jsonencode({
      script = base64encode(templatefile("${path.module}/install-azdo-agent.sh", {
        azdo_url          = var.azdo_org_service_url
        azdo_pat          = var.azdo_pat
        azdo_pool         = var.azdo_agent_pool_name
        agent_name_prefix = local.vmss_name
      }))
    })
  }

  depends_on = [
    azurerm_subnet_network_security_group_association.main,
    azuredevops_agent_pool.main
  ]
}

# Storage Account with large file share support
resource "azurerm_storage_account" "main" {
  name                       = local.storage_account_name
  resource_group_name        = data.azurerm_resource_group.main.name
  location                   = var.location
  account_tier               = "Standard"
  account_replication_type   = "LRS"
  https_traffic_only_enabled = true
  large_file_share_enabled   = true
  tags                       = var.tags
}

# File Share in Storage Account
resource "azurerm_storage_share" "main" {
  name                 = local.storage_share_name
  storage_account_name = azurerm_storage_account.main.name
  access_tier          = "TransactionOptimized"
  quota                = var.storage_share_quota
}

# Key Vault with network restrictions
resource "azurerm_key_vault" "main" {
  name                       = local.key_vault_name
  location                   = var.location
  resource_group_name        = data.azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  tags                       = var.tags

  # Network ACLs: deny by default, allow Azure services and specified IPs
  network_acls {
    bypass         = "AzureServices"
    default_action = "Deny"
    ip_rules       = var.key_vault_allowed_ips
  }

  # Grant access to the service principal running Terraform
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [
      "Get",
      "List",
      "Set",
      "Delete",
      "Purge",
      "Recover"
    ]
  }
}

# Test secret in Key Vault
resource "azurerm_key_vault_secret" "test" {
  name         = "Test"
  value        = "test"
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault.main]
}

# Azure Container Registry
resource "azurerm_container_registry" "main" {
  name                = local.acr_name
  resource_group_name = data.azurerm_resource_group.main.name
  location            = var.location
  sku                 = var.acr_sku
  admin_enabled       = false
  tags                = var.tags
}

# Azure DevOps Project
resource "azuredevops_project" "main" {
  name               = var.azdo_project_name
  description        = var.azdo_project_description
  visibility         = var.azdo_project_visibility
  version_control    = "Git"
  work_item_template = "Agile"

  features = {
    "boards"       = "enabled"
    "repositories" = "enabled"
    "pipelines"    = "enabled"
    "testplans"    = "disabled"
    "artifacts"    = "enabled"
  }
}


# Azure DevOps Service Endpoint for GitHub
resource "azuredevops_serviceendpoint_github" "github" {
  project_id            = azuredevops_project.main.id
  service_endpoint_name = var.azdo_github_service_endpoint_name
  description           = "GitHub service connection for ${var.azdo_project_name}"

  auth_personal {
    personal_access_token = var.github_pat
  }
}

# GitHub Service Endpoint is configured above (azuredevops_serviceendpoint_github.github)
# This allows Azure Pipelines to access the GitHub repository without importing/cloning it
# Pipelines will reference the GitHub repo directly via the service connection

# Azure DevOps Agent Pool
resource "azuredevops_agent_pool" "main" {
  name           = var.azdo_agent_pool_name
  auto_provision = false
  auto_update    = true
}

# Grant project access to the agent pool
resource "azuredevops_agent_queue" "main" {
  project_id    = azuredevops_project.main.id
  agent_pool_id = azuredevops_agent_pool.main.id
}

# Azure DevOps Service Endpoint for Azure RM
resource "azuredevops_serviceendpoint_azurerm" "main" {
  project_id            = azuredevops_project.main.id
  service_endpoint_name = var.azdo_service_endpoint_name
  description           = "Azure Resource Manager service connection for ${var.azdo_project_name}"

  credentials {
    serviceprincipalid  = var.azdo_service_principal_id
    serviceprincipalkey = var.azdo_service_principal_key
  }

  azurerm_spn_tenantid      = data.azurerm_client_config.current.tenant_id
  azurerm_subscription_id   = data.azurerm_client_config.current.subscription_id
  azurerm_subscription_name = var.azdo_subscription_name
}
