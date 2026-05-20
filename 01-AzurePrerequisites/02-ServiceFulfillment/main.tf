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
  address_prefixes     = [cidrsubnet(var.vnet_address_space[0], 8, 10)]
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
    name           = "default"
    node_count     = var.aks_node_count
    vm_size        = var.aks_node_size
    vnet_subnet_id = azurerm_subnet.private_1.id
  }

  lifecycle {
    ignore_changes = [
      default_node_pool
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
}

# Grant ACR Pull access to AKS (optional, controlled by variable)
resource "azurerm_role_assignment" "aks_acr" {
  count                = var.enable_aks_acr_role ? 1 : 0
  scope                = data.azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}

# ============================================================================
# AGIC (Application Gateway for Containers / Ingress integration) Prerequisites
# ============================================================================

# User-assigned managed identity for AGIC
resource "azurerm_user_assigned_identity" "agic" {
  name                = "${var.prefix}-agic-identity"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

# Grant AGIC identity Contributor access to Application Gateway
resource "azurerm_role_assignment" "agic_appgw_contributor" {
  count                = var.enable_agic_role_assignments ? 1 : 0
  scope                = azurerm_application_gateway.main.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.agic.principal_id
}

# Grant AGIC identity Reader access to Application Gateway resource group
resource "azurerm_role_assignment" "agic_rg_reader" {
  count                = var.enable_agic_role_assignments ? 1 : 0
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.agic.principal_id
}

# Grant AKS kubelet identity permission to use the AGIC managed identity
resource "azurerm_role_assignment" "agic_identity_operator" {
  count                = var.enable_agic_role_assignments ? 1 : 0
  scope                = azurerm_user_assigned_identity.agic.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}


# Private DNS Zone for PostgreSQL
resource "azurerm_private_dns_zone" "postgres" {
  name                = "${var.prefix}-postgres.private.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

# Link Private DNS Zone to VNet
resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "${var.prefix}-postgres-vnet-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = azurerm_virtual_network.main.id
  tags                  = var.tags
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
}
