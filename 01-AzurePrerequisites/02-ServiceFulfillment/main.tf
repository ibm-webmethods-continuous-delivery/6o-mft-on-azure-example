terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# Use existing resource group
data "azurerm_resource_group" "main" {
  name = var.resource_group_name_existing
}

# New resource group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}


# Reference existing ACR from ServiceDelivery
data "azurerm_container_registry" "main" {
  name                = var.acr_name
  resource_group_name = var.resource_group_name_existing
}

# Local variables for computed names
locals {
  vnet_name             = coalesce(var.vnet_name, "${var.prefix}-vnet")
  public_subnet_1_name  = coalesce(var.public_subnet_1_name, "${var.prefix}-public-subnet-1")
  public_subnet_2_name  = coalesce(var.public_subnet_2_name, "${var.prefix}-public-subnet-2")
  private_subnet_1_name = coalesce(var.private_subnet_1_name, "${var.prefix}-private-subnet-1")
  private_subnet_2_name = coalesce(var.private_subnet_2_name, "${var.prefix}-private-subnet-2")
  sftp_nsg_name         = coalesce(var.sftp_nsg_name, "${var.prefix}-sftp-nsg")
  aks_nsg_name          = coalesce(var.aks_nsg_name, "${var.prefix}-aks-nsg")
  sftp_lb_name          = coalesce(var.sftp_lb_name, "${var.prefix}-sftp-lb")
  sftp_vm_1_name        = coalesce(var.sftp_vm_1_name, "${var.prefix}-sftp-vm-1")
  sftp_vm_2_name        = coalesce(var.sftp_vm_2_name, "${var.prefix}-sftp-vm-2")
  aks_cluster_name      = coalesce(var.aks_cluster_name, "${var.prefix}-aks")
  app_gateway_name      = coalesce(var.app_gateway_name, "${var.prefix}-appgw")
  postgres_server_name  = coalesce(var.postgres_server_name, "${var.prefix}-postgres")
  app_gateway_pip_name  = "${local.app_gateway_name}-pip"
  sftp_lb_pip_name      = "${local.sftp_lb_name}-pip"
}

# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = local.vnet_name
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.vnet_address_space
  tags                = var.tags
}

# Public Subnet 1 (for SFTP VM 1)
resource "azurerm_subnet" "public_1" {
  name                 = local.public_subnet_1_name
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [cidrsubnet(var.vnet_address_space[0], 8, 0)]
}

# Public Subnet 2 (for SFTP VM 2)
resource "azurerm_subnet" "public_2" {
  name                 = local.public_subnet_2_name
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [cidrsubnet(var.vnet_address_space[0], 8, 1)]
}

# Private Subnet 1 (for AKS)
resource "azurerm_subnet" "private_1" {
  name                 = local.private_subnet_1_name
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  # Service endpoints for PostgreSQL access
  service_endpoints = ["Microsoft.Storage", "Microsoft.Sql"]
  address_prefixes  = [cidrsubnet(var.vnet_address_space[0], 8, 10)]
}

# Private Subnet 2 (for PostgreSQL and other private services)
resource "azurerm_subnet" "private_2" {
  name                 = local.private_subnet_2_name
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [cidrsubnet(var.vnet_address_space[0], 8, 11)]

  delegation {
    name = "postgres-delegation"
    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

# Application Gateway Subnet
resource "azurerm_subnet" "app_gateway" {
  name                 = "${var.prefix}-appgw-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [cidrsubnet(var.vnet_address_space[0], 8, 2)]
}

# Network Security Group for SFTP VMs (Public Subnets)
resource "azurerm_network_security_group" "sftp" {
  name                = local.sftp_nsg_name
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  # Allow SFTP from whitelisted IPs
  security_rule {
    name                       = "AllowSFTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "55022"
    source_address_prefixes    = var.allowed_ip_ranges
    destination_address_prefix = "*"
  }

  # Allow SSH from whitelisted IPs for management
  security_rule {
    name                       = "AllowSSH"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefixes    = var.allowed_ip_ranges
    destination_address_prefix = "*"
  }

  # Allow outbound to ACR
  security_rule {
    name                       = "AllowACR"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "AzureContainerRegistry"
  }

  # Add to main.tf in azurerm_network_security_group.sftp resource:
  security_rule {
    name                       = "AllowGatewayFromAKS"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["8500", "8501"]
    source_address_prefix      = azurerm_subnet.private_1.address_prefixes[0] # AKS subnet
    destination_address_prefix = "*"
  }
}

# Network Security Group for AKS (Private Subnet)
resource "azurerm_network_security_group" "aks" {
  name                = local.aks_nsg_name
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  # Allow traffic from Application Gateway
  security_rule {
    name                       = "AllowAppGateway"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
    source_address_prefix      = cidrsubnet(var.vnet_address_space[0], 8, 2)
    destination_address_prefix = "*"
  }

  # Allow outbound to ACR
  security_rule {
    name                       = "AllowACR"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "AzureContainerRegistry"
  }
}

# Associate NSG with Public Subnet 1
resource "azurerm_subnet_network_security_group_association" "public_1" {
  subnet_id                 = azurerm_subnet.public_1.id
  network_security_group_id = azurerm_network_security_group.sftp.id
}

# Associate NSG with Public Subnet 2
resource "azurerm_subnet_network_security_group_association" "public_2" {
  subnet_id                 = azurerm_subnet.public_2.id
  network_security_group_id = azurerm_network_security_group.sftp.id
}

# Associate NSG with Private Subnet 1 (AKS)
resource "azurerm_subnet_network_security_group_association" "private_1" {
  subnet_id                 = azurerm_subnet.private_1.id
  network_security_group_id = azurerm_network_security_group.aks.id
}

# Public IP for Load Balancer
resource "azurerm_public_ip" "sftp_lb" {
  name                = local.sftp_lb_pip_name
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# Load Balancer for SFTP VMs
resource "azurerm_lb" "sftp" {
  name                = local.sftp_lb_name
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard"
  tags                = var.tags

  frontend_ip_configuration {
    name                 = "sftp-frontend"
    public_ip_address_id = azurerm_public_ip.sftp_lb.id
  }
}

# Backend Address Pool for Load Balancer
resource "azurerm_lb_backend_address_pool" "sftp" {
  loadbalancer_id = azurerm_lb.sftp.id
  name            = "sftp-backend-pool"
}

# Health Probe for SFTP
resource "azurerm_lb_probe" "sftp" {
  loadbalancer_id = azurerm_lb.sftp.id
  name            = "sftp-health-probe"
  protocol        = "Tcp"
  port            = 55022
}

# Load Balancer Rule for SFTP
resource "azurerm_lb_rule" "sftp" {
  loadbalancer_id                = azurerm_lb.sftp.id
  name                           = "sftp-rule"
  protocol                       = "Tcp"
  frontend_port                  = 55022
  backend_port                   = 55022
  frontend_ip_configuration_name = "sftp-frontend"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.sftp.id]
  probe_id                       = azurerm_lb_probe.sftp.id
}

# Network Interface for SFTP VM 1
resource "azurerm_network_interface" "sftp_vm_1" {
  name                = "${local.sftp_vm_1_name}-nic"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.public_1.id
    private_ip_address_allocation = "Dynamic"
  }
}

# Network Interface for SFTP VM 2
resource "azurerm_network_interface" "sftp_vm_2" {
  name                = "${local.sftp_vm_2_name}-nic"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.public_2.id
    private_ip_address_allocation = "Dynamic"
  }
}

# Associate NIC 1 with Backend Pool
resource "azurerm_network_interface_backend_address_pool_association" "sftp_vm_1" {
  network_interface_id    = azurerm_network_interface.sftp_vm_1.id
  ip_configuration_name   = "internal"
  backend_address_pool_id = azurerm_lb_backend_address_pool.sftp.id
}

# Associate NIC 2 with Backend Pool
resource "azurerm_network_interface_backend_address_pool_association" "sftp_vm_2" {
  network_interface_id    = azurerm_network_interface.sftp_vm_2.id
  ip_configuration_name   = "internal"
  backend_address_pool_id = azurerm_lb_backend_address_pool.sftp.id
}

# SFTP VM 1
resource "azurerm_linux_virtual_machine" "sftp_vm_1" {
  name                            = local.sftp_vm_1_name
  location                        = var.location
  resource_group_name             = azurerm_resource_group.main.name
  size                            = var.sftp_vm_size
  admin_username                  = "azureuser"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.sftp_vm_1.id]
  tags                            = var.tags

  admin_ssh_key {
    username   = "azureuser"
    public_key = var.ssh_admin_pub_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }

  # ignore patch_assessment_mode changed a-postriori
  lifecycle {
    ignore_changes = [
      patch_assessment_mode
    ]
  }

  custom_data = base64encode(templatefile("${path.module}/scripts/install-docker.sh", {
    acr_name = data.azurerm_container_registry.main.name
  }))
}

# SFTP VM 2
resource "azurerm_linux_virtual_machine" "sftp_vm_2" {
  name                            = local.sftp_vm_2_name
  location                        = var.location
  resource_group_name             = azurerm_resource_group.main.name
  size                            = var.sftp_vm_size
  admin_username                  = "azureuser"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.sftp_vm_2.id]
  tags                            = var.tags

  admin_ssh_key {
    username   = "azureuser"
    public_key = var.ssh_admin_pub_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }

  # ignore patch_assessment_mode changed a-postriori
  lifecycle {
    ignore_changes = [
      patch_assessment_mode
    ]
  }

  custom_data = base64encode(templatefile("${path.module}/scripts/install-docker.sh", {
    acr_name = data.azurerm_container_registry.main.name
  }))
}

# Grant ACR Pull access to SFTP VM 1 (optional, controlled by variable)
resource "azurerm_role_assignment" "sftp_vm_1_acr" {
  count                = var.enable_sftp_vm_acr_role ? 1 : 0
  scope                = data.azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_virtual_machine.sftp_vm_1.identity[0].principal_id
}

# Grant ACR Pull access to SFTP VM 2 (optional, controlled by variable)
resource "azurerm_role_assignment" "sftp_vm_2_acr" {
  count                = var.enable_sftp_vm_acr_role ? 1 : 0
  scope                = data.azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_virtual_machine.sftp_vm_2.identity[0].principal_id
}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "main" {
  name                      = local.aks_cluster_name
  location                  = var.location
  resource_group_name       = azurerm_resource_group.main.name
  dns_prefix                = "${var.prefix}-aks"
  oidc_issuer_enabled       = true
  workload_identity_enabled = true
  tags                      = var.tags

  default_node_pool {
    name                        = "default"
    node_count                  = var.aks_node_count
    vm_size                     = var.aks_node_size
    vnet_subnet_id              = azurerm_subnet.private_1.id
    zones                       = ["1", "2", "3"] # Distribute nodes across availability zones
    temporary_name_for_rotation = "defaulttmp"
  }

  lifecycle {
    ignore_changes = [
      default_node_pool[0].upgrade_settings,
      microsoft_defender
    ]
  }

  identity {
    type = "SystemAssigned"
  }

  # seems mandatory in our case
  azure_policy_enabled = true

  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
  }

  # Enable Key Vault Secrets Provider (CSI Driver)
  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }
}

# Grant ACR Pull access to AKS (optional, controlled by variable)
resource "azurerm_role_assignment" "aks_acr" {
  count                = var.enable_aks_acr_role ? 1 : 0
  scope                = data.azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}

# ============================================================================
# Azure Key Vault for MFT Secrets Management
# ============================================================================

# Get current Azure client configuration
data "azurerm_client_config" "current" {}

# Azure Key Vault
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
  soft_delete_retention_days = 90
  purge_protection_enabled   = true

  tags = var.tags
}

# Private endpoint for Key Vault (when private access is enabled)
resource "azurerm_private_endpoint" "key_vault" {
  count               = var.key_vault_public_access_enabled ? 0 : 1
  name                = "${var.prefix}-kv-pe"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_1.id

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
  virtual_network_id    = azurerm_virtual_network.main.id
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

# User-assigned managed identity for MFT workload
resource "azurerm_user_assigned_identity" "mft" {
  name                = "${var.prefix}-mft-identity"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

# Federated credential for workload identity (AKS OIDC) - MFT service account
resource "azurerm_federated_identity_credential" "mft" {
  name      = "${var.prefix}-mft-federated-credential"
  parent_id = azurerm_user_assigned_identity.mft.id
  audience  = ["api://AzureADTokenExchange"]
  issuer    = azurerm_kubernetes_cluster.main.oidc_issuer_url
  subject   = "system:serviceaccount:${var.mft_namespace}:${var.mft_service_account_name}"
}

# Federated credential for Database Configurator service account
resource "azurerm_federated_identity_credential" "dbc" {
  name      = "${var.prefix}-dbc-federated-credential"
  parent_id = azurerm_user_assigned_identity.mft.id
  audience  = ["api://AzureADTokenExchange"]
  issuer    = azurerm_kubernetes_cluster.main.oidc_issuer_url
  subject   = "system:serviceaccount:default:database-configurator-sa"
}

# Federated credential for Database User Init service account
resource "azurerm_federated_identity_credential" "db_user_init" {
  name      = "${var.prefix}-db-user-init-federated-credential"
  parent_id = azurerm_user_assigned_identity.mft.id
  audience  = ["api://AzureADTokenExchange"]
  issuer    = azurerm_kubernetes_cluster.main.oidc_issuer_url
  subject   = "system:serviceaccount:default:database-user-init-sa"
}

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

# Local variables for default secrets with descriptions
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
    "${local.environment}-mft-config-json" = {
      value       = "{}"
      description = "MFT configuration JSON for runtime configuration management"
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

# Local variables for MFT database credentials with descriptions
locals {
  # Database credentials for MFT components (Database Configurator, etc.)
  mft_db_credentials = {
    "postgres-server-fqdn" = {
      value       = azurerm_postgresql_flexible_server.main.fqdn
      description = "PostgreSQL Flexible Server FQDN for MFT database connections"
    }
    "postgres-online-db" = {
      value       = azurerm_postgresql_flexible_server_database.online.name
      description = "PostgreSQL database name for MFT online transactions"
    }
    "postgres-archive-db" = {
      value       = azurerm_postgresql_flexible_server_database.archive.name
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
    azurerm_role_assignment.terraform_kv_admin,
    azurerm_postgresql_flexible_server.main,
    azurerm_postgresql_flexible_server_database.online,
    azurerm_postgresql_flexible_server_database.archive
  ]

  lifecycle {
    ignore_changes = [value, expiration_date]
  }
}



# ============================================================================
# Certificate Upload to Key Vault
# ============================================================================

# Local variables for certificate file paths
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
# TODO: understand why this was in conflict with ${local.environment}-mft-sftp-ssh-private-key and if we want both. For now keep both
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

# Local variables for certificate imports (PKCS12 files only)
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

# Get current Azure AD client configuration
data "azuread_client_config" "current" {}

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
  count                = var.enable_agic_role_assignments ? 1 : 0
  scope                = azurerm_application_gateway.main.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.agic.object_id
}

# Grant AGIC Service Principal Reader access to Application Gateway resource group
resource "azurerm_role_assignment" "agic_rg_reader" {
  count                = var.enable_agic_role_assignments ? 1 : 0
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.agic.object_id
}

# Grant AGIC Service Principal Network Contributor access to App Gateway subnet
resource "azurerm_role_assignment" "agic_subnet_network_contributor" {
  count                = var.enable_agic_role_assignments ? 1 : 0
  scope                = azurerm_subnet.app_gateway.id
  role_definition_name = "Network Contributor"
  principal_id         = azuread_service_principal.agic.object_id
}


# Private DNS Zone for PostgreSQL
resource "azurerm_private_dns_zone" "postgres" {
  name                = "${var.prefix}-postgres.private.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  # Known issue, TODO: check for tags having spaces
  lifecycle {
    ignore_changes = [tags["Ephemeral Resource"]]
  }
}

# Link Private DNS Zone to VNet
resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "${var.prefix}-postgres-vnet-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = azurerm_virtual_network.main.id
  tags                  = var.tags
  # Known issue, TODO: check for tags having spaces
  lifecycle {
    ignore_changes = [tags["Ephemeral Resource"]]
  }
}

# PostgreSQL Flexible Server
resource "azurerm_postgresql_flexible_server" "main" {
  name                   = local.postgres_server_name
  location               = var.location
  resource_group_name    = azurerm_resource_group.main.name
  version                = var.postgres_version
  delegated_subnet_id    = azurerm_subnet.private_2.id
  private_dns_zone_id    = azurerm_private_dns_zone.postgres.id
  administrator_login    = var.postgres_admin_username
  administrator_password = var.postgres_admin_password
  # zone                          = "2"
  lifecycle {
    ignore_changes = [
      zone
    ]
  }
  storage_mb                    = var.postgres_storage_mb
  sku_name                      = var.postgres_sku_name
  public_network_access_enabled = false
  tags                          = var.tags


  # Authentication configuration
  authentication {
    active_directory_auth_enabled = false
    password_auth_enabled         = true
  }
  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]
}

# PostgreSQL Database for Online Transactions
resource "azurerm_postgresql_flexible_server_database" "online" {
  name      = var.postgres_online_db_name
  server_id = azurerm_postgresql_flexible_server.main.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# PostgreSQL Database for Archiving
resource "azurerm_postgresql_flexible_server_database" "archive" {
  name      = var.postgres_archive_db_name
  server_id = azurerm_postgresql_flexible_server.main.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# PostgreSQL Configuration - Disable require_secure_transport
resource "azurerm_postgresql_flexible_server_configuration" "require_secure_transport" {
  name      = "require_secure_transport"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = "off"
}

# PostgreSQL Configuration - Increase max_connections
resource "azurerm_postgresql_flexible_server_configuration" "max_connections" {
  name      = "max_connections"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = "200"
}

# Public IP for Application Gateway
resource "azurerm_public_ip" "app_gateway" {
  name                = local.app_gateway_pip_name
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# Application Gateway
resource "azurerm_application_gateway" "main" {
  name                = local.app_gateway_name
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  sku {
    name     = var.app_gateway_sku_name
    tier     = var.app_gateway_sku_tier
    capacity = var.app_gateway_capacity
  }

  ssl_policy {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101"
  }

  gateway_ip_configuration {
    name      = "appgw-ip-config"
    subnet_id = azurerm_subnet.app_gateway.id
  }

  frontend_port {
    name = "http-port"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "appgw-frontend-ip"
    public_ip_address_id = azurerm_public_ip.app_gateway.id
  }

  backend_address_pool {
    name = "aks-backend-pool"
  }

  backend_http_settings {
    name                  = "http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
  }

  http_listener {
    name                           = "http-listener"
    frontend_ip_configuration_name = "appgw-frontend-ip"
    frontend_port_name             = "http-port"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "http-routing-rule"
    rule_type                  = "Basic"
    http_listener_name         = "http-listener"
    backend_address_pool_name  = "aks-backend-pool"
    backend_http_settings_name = "http-settings"
    priority                   = 100
  }

  # Lifecycle block to ignore changes made by AGIC and Kubernetes-managed tags
  lifecycle {
    ignore_changes = [
      backend_address_pool,
      backend_http_settings,
      frontend_port,
      http_listener,
      probe,
      request_routing_rule,
      url_path_map,
      ssl_certificate,
      redirect_configuration,
      tags["ingress-for-aks-cluster-id"],
      tags["managed-by-k8s-ingress"]
    ]
  }
}
