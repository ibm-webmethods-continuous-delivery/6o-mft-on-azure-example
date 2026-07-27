################################################################################
# Data Sources
################################################################################

# Get current Azure client configuration
data "azurerm_client_config" "current" {}

# Reference existing resource groups from Stage A
data "azurerm_resource_group" "delivery" {
  name = var.delivery_resource_group_name
}

data "azurerm_resource_group" "fulfillment" {
  name = var.fulfillment_resource_group_name
}

# Reference existing Key Vault from 01-vault/
data "azurerm_key_vault" "main" {
  name                = var.key_vault_name
  resource_group_name = var.key_vault_resource_group_name
}

# Reference existing MFT managed identity from Stage A
data "azurerm_user_assigned_identity" "mft" {
  name                = split("/", var.mft_identity_id)[8]
  resource_group_name = data.azurerm_resource_group.fulfillment.name
}

# Reference existing AGIC managed identity from Stage A
data "azurerm_user_assigned_identity" "agic" {
  name                = split("/", var.agic_identity_id)[8]
  resource_group_name = data.azurerm_resource_group.fulfillment.name
}

################################################################################
# Local Variables
################################################################################

locals {
  # Service Delivery resource names
  delivery_vnet_name   = coalesce(var.delivery_vnet_name, "${var.prefix}-delivery-vnet")
  delivery_subnet_name = coalesce(var.delivery_subnet_name, "${var.prefix}-delivery-subnet")
  delivery_nsg_name    = coalesce(var.delivery_nsg_name, "${var.prefix}-delivery-nsg")
  vmss_name            = coalesce(var.vmss_name, "${var.prefix}AgentsVmss")
  storage_account_name = coalesce(var.storage_account_name, "${var.prefix}imagessa")
  storage_share_name   = coalesce(var.storage_share_name, "${var.prefix}imagessashare")
  acr_name             = coalesce(var.acr_name, "${var.prefix}acr")

  # Service Fulfillment resource names
  fulfillment_vnet_name   = coalesce(var.fulfillment_vnet_name, "${var.prefix}-fulfillment-vnet")
  public_subnet_1_name    = coalesce(var.public_subnet_1_name, "${var.prefix}-public-subnet-1")
  public_subnet_2_name    = coalesce(var.public_subnet_2_name, "${var.prefix}-public-subnet-2")
  private_subnet_1_name   = coalesce(var.private_subnet_1_name, "${var.prefix}-private-subnet-1")
  private_subnet_2_name   = coalesce(var.private_subnet_2_name, "${var.prefix}-private-subnet-2")
  app_gateway_subnet_name = coalesce(var.app_gateway_subnet_name, "${var.prefix}-appgw-subnet")
  sftp_nsg_name           = coalesce(var.sftp_nsg_name, "${var.prefix}-sftp-nsg")
  aks_nsg_name            = coalesce(var.aks_nsg_name, "${var.prefix}-aks-nsg")
  sftp_lb_name            = coalesce(var.sftp_lb_name, "${var.prefix}-sftp-lb")
  sftp_vm_1_name          = coalesce(var.sftp_vm_1_name, "${var.prefix}-sftp-vm-1")
  sftp_vm_2_name          = coalesce(var.sftp_vm_2_name, "${var.prefix}-sftp-vm-2")
  aks_cluster_name        = coalesce(var.aks_cluster_name, "${var.prefix}-aks")
  postgres_server_name    = coalesce(var.postgres_server_name, "${var.prefix}-postgres")
  app_gateway_name        = coalesce(var.app_gateway_name, "${var.prefix}-appgw")
  app_gateway_pip_name    = "${local.app_gateway_name}-pip"
  sftp_lb_pip_name        = "${local.sftp_lb_name}-pip"

  # Private storage names (optional)
  private_storage_account_name = var.create_private_storage ? coalesce(var.private_storage_account_name, "${var.prefix}mftvfs") : null
  private_storage_share_name   = var.create_private_storage ? coalesce(var.private_storage_share_name, "${var.prefix}mftvfsshare") : null

  # Environment for Key Vault secrets
  environment = var.environment_name

  # Parse VMSS image
  vmss_image_parts = split(":", var.vmss_image)
  vmss_publisher   = local.vmss_image_parts[0]
  vmss_offer       = local.vmss_image_parts[1]
  vmss_sku         = local.vmss_image_parts[2]
  vmss_version     = local.vmss_image_parts[3]
}

################################################################################
# Service Delivery - Network Resources
################################################################################

# Virtual Network for Service Delivery
resource "azurerm_virtual_network" "delivery" {
  name                = local.delivery_vnet_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.delivery.name
  address_space       = var.delivery_vnet_address_space
  tags                = var.tags
}

# Subnet for VMSS agents
resource "azurerm_subnet" "delivery" {
  name                 = local.delivery_subnet_name
  resource_group_name  = data.azurerm_resource_group.delivery.name
  virtual_network_name = azurerm_virtual_network.delivery.name
  address_prefixes     = [cidrsubnet(var.delivery_vnet_address_space[0], 8, 0)]
}

# Network Security Group for Service Delivery
resource "azurerm_network_security_group" "delivery" {
  name                = local.delivery_nsg_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.delivery.name
  tags                = var.tags
}

# Associate NSG with subnet
resource "azurerm_subnet_network_security_group_association" "delivery" {
  subnet_id                 = azurerm_subnet.delivery.id
  network_security_group_id = azurerm_network_security_group.delivery.id
}

################################################################################
# Service Delivery - VMSS for Azure DevOps Agents
################################################################################

# Virtual Machine Scale Set (uniform orchestration, 0 instances by default)
resource "azurerm_linux_virtual_machine_scale_set" "agents" {
  name                            = local.vmss_name
  location                        = var.location
  resource_group_name             = data.azurerm_resource_group.delivery.name
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
    username   = "azureuser"
    public_key = var.ssh_admin_pub_key
  }

  source_image_reference {
    publisher = local.vmss_publisher
    offer     = local.vmss_offer
    sku       = local.vmss_sku
    version   = local.vmss_version
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
      subnet_id = azurerm_subnet.delivery.id
    }
  }

  depends_on = [
    azurerm_subnet_network_security_group_association.delivery
  ]
}

################################################################################
# Service Delivery - Storage Account and File Share
################################################################################

# Storage Account with large file share support
resource "azurerm_storage_account" "delivery" {
  name                       = local.storage_account_name
  resource_group_name        = data.azurerm_resource_group.delivery.name
  location                   = var.location
  account_tier               = "Standard"
  account_replication_type   = "LRS"
  https_traffic_only_enabled = true
  large_file_share_enabled   = true
  tags                       = var.tags
}

# File Share in Storage Account
resource "azurerm_storage_share" "delivery" {
  name               = local.storage_share_name
  storage_account_id = azurerm_storage_account.delivery.id
  access_tier        = "TransactionOptimized"
  quota              = var.storage_share_quota
}

################################################################################
# Service Delivery - Azure Container Registry
################################################################################

# Azure Container Registry
resource "azurerm_container_registry" "main" {
  name                = local.acr_name
  resource_group_name = data.azurerm_resource_group.delivery.name
  location            = var.location
  sku                 = var.acr_sku
  admin_enabled       = false
  tags                = var.tags
}

################################################################################
# Service Fulfillment - Network Resources
################################################################################

# Virtual Network for Service Fulfillment
resource "azurerm_virtual_network" "fulfillment" {
  name                = local.fulfillment_vnet_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.fulfillment.name
  address_space       = var.fulfillment_vnet_address_space
  tags                = var.tags
}

# Public Subnet 1 (for SFTP VM 1)
resource "azurerm_subnet" "public_1" {
  name                 = local.public_subnet_1_name
  resource_group_name  = data.azurerm_resource_group.fulfillment.name
  virtual_network_name = azurerm_virtual_network.fulfillment.name
  address_prefixes     = [cidrsubnet(var.fulfillment_vnet_address_space[0], 8, 0)]
}

# Public Subnet 2 (for SFTP VM 2)
resource "azurerm_subnet" "public_2" {
  name                 = local.public_subnet_2_name
  resource_group_name  = data.azurerm_resource_group.fulfillment.name
  virtual_network_name = azurerm_virtual_network.fulfillment.name
  address_prefixes     = [cidrsubnet(var.fulfillment_vnet_address_space[0], 8, 1)]
}

# Private Subnet 1 (for AKS)
resource "azurerm_subnet" "private_1" {
  name                 = local.private_subnet_1_name
  resource_group_name  = data.azurerm_resource_group.fulfillment.name
  virtual_network_name = azurerm_virtual_network.fulfillment.name
  service_endpoints    = ["Microsoft.Storage", "Microsoft.Sql"]
  address_prefixes     = [cidrsubnet(var.fulfillment_vnet_address_space[0], 8, 10)]
}

# Private Subnet 2 (for PostgreSQL)
resource "azurerm_subnet" "private_2" {
  name                 = local.private_subnet_2_name
  resource_group_name  = data.azurerm_resource_group.fulfillment.name
  virtual_network_name = azurerm_virtual_network.fulfillment.name
  address_prefixes     = [cidrsubnet(var.fulfillment_vnet_address_space[0], 8, 11)]

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
  name                 = local.app_gateway_subnet_name
  resource_group_name  = data.azurerm_resource_group.fulfillment.name
  virtual_network_name = azurerm_virtual_network.fulfillment.name
  address_prefixes     = [cidrsubnet(var.fulfillment_vnet_address_space[0], 8, 2)]
}

# Network Security Group for SFTP VMs (Public Subnets)
resource "azurerm_network_security_group" "sftp" {
  name                = local.sftp_nsg_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.fulfillment.name
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

  # Allow Gateway traffic from AKS
  security_rule {
    name                       = "AllowGatewayFromAKS"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["8500", "8501"]
    source_address_prefix      = cidrsubnet(var.fulfillment_vnet_address_space[0], 8, 10)
    destination_address_prefix = "*"
  }
}

# Network Security Group for AKS (Private Subnet)
resource "azurerm_network_security_group" "aks" {
  name                = local.aks_nsg_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.fulfillment.name
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
    source_address_prefix      = cidrsubnet(var.fulfillment_vnet_address_space[0], 8, 2)
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

################################################################################
# Service Fulfillment - SFTP Load Balancer and VMs
################################################################################

# Public IP for Load Balancer
resource "azurerm_public_ip" "sftp_lb" {
  name                = local.sftp_lb_pip_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.fulfillment.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# Load Balancer for SFTP VMs
resource "azurerm_lb" "sftp" {
  name                = local.sftp_lb_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.fulfillment.name
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
  resource_group_name = data.azurerm_resource_group.fulfillment.name
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
  resource_group_name = data.azurerm_resource_group.fulfillment.name
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
  resource_group_name             = data.azurerm_resource_group.fulfillment.name
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

  lifecycle {
    ignore_changes = [
      patch_assessment_mode
    ]
  }

  custom_data = base64encode(templatefile("${path.module}/scripts/install-docker.sh", {
    acr_name = azurerm_container_registry.main.name
  }))
}

# SFTP VM 2
resource "azurerm_linux_virtual_machine" "sftp_vm_2" {
  name                            = local.sftp_vm_2_name
  location                        = var.location
  resource_group_name             = data.azurerm_resource_group.fulfillment.name
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

  lifecycle {
    ignore_changes = [
      patch_assessment_mode
    ]
  }

  custom_data = base64encode(templatefile("${path.module}/scripts/install-docker.sh", {
    acr_name = azurerm_container_registry.main.name
  }))
}

# Grant ACR Pull access to SFTP VM 1
resource "azurerm_role_assignment" "sftp_vm_1_acr" {
  count                = var.enable_sftp_vm_acr_role ? 1 : 0
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_virtual_machine.sftp_vm_1.identity[0].principal_id
}

# Grant ACR Pull access to SFTP VM 2
resource "azurerm_role_assignment" "sftp_vm_2_acr" {
  count                = var.enable_sftp_vm_acr_role ? 1 : 0
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_virtual_machine.sftp_vm_2.identity[0].principal_id
}

################################################################################
# Service Fulfillment - AKS Cluster
################################################################################

# AKS Cluster
resource "azurerm_kubernetes_cluster" "main" {
  name                      = local.aks_cluster_name
  location                  = var.location
  resource_group_name       = data.azurerm_resource_group.fulfillment.name
  dns_prefix                = "${var.prefix}-aks"
  oidc_issuer_enabled       = true
  workload_identity_enabled = true
  tags                      = var.tags

  default_node_pool {
    name                        = "default"
    node_count                  = var.aks_node_count
    vm_size                     = var.aks_node_size
    vnet_subnet_id              = azurerm_subnet.private_1.id
    zones                       = ["1", "2", "3"]
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

  azure_policy_enabled = true

  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
  }

  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }
}

# Grant ACR Pull access to AKS
resource "azurerm_role_assignment" "aks_acr" {
  count                = var.enable_aks_acr_role ? 1 : 0
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}

################################################################################
# Service Fulfillment - PostgreSQL Flexible Server
################################################################################

# Private DNS Zone for PostgreSQL
resource "azurerm_private_dns_zone" "postgres" {
  name                = "${var.prefix}-postgres.private.postgres.database.azure.com"
  resource_group_name = data.azurerm_resource_group.fulfillment.name
  tags                = var.tags

  lifecycle {
    ignore_changes = [tags["Ephemeral Resource"]]
  }
}

# Link Private DNS Zone to VNet
resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "${var.prefix}-postgres-vnet-link"
  resource_group_name   = data.azurerm_resource_group.fulfillment.name
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = azurerm_virtual_network.fulfillment.id
  tags                  = var.tags

  lifecycle {
    ignore_changes = [tags["Ephemeral Resource"]]
  }
}

# PostgreSQL Flexible Server
resource "azurerm_postgresql_flexible_server" "main" {
  name                          = local.postgres_server_name
  location                      = var.location
  resource_group_name           = data.azurerm_resource_group.fulfillment.name
  version                       = var.postgres_version
  delegated_subnet_id           = azurerm_subnet.private_2.id
  private_dns_zone_id           = azurerm_private_dns_zone.postgres.id
  administrator_login           = var.postgres_admin_username
  administrator_password        = var.postgres_admin_password
  storage_mb                    = var.postgres_storage_mb
  sku_name                      = var.postgres_sku_name
  public_network_access_enabled = false
  tags                          = var.tags

  lifecycle {
    ignore_changes = [zone]
  }

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

################################################################################
# Service Fulfillment - Application Gateway
################################################################################

# Public IP for Application Gateway
resource "azurerm_public_ip" "app_gateway" {
  name                = local.app_gateway_pip_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.fulfillment.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# Application Gateway
resource "azurerm_application_gateway" "main" {
  name                = local.app_gateway_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.fulfillment.name
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

################################################################################
# Workload Identity - MFT Federated Credentials
################################################################################

# Federated credential for MFT service account
resource "azurerm_federated_identity_credential" "mft" {
  name      = "${var.prefix}-mft-federated-credential"
  parent_id = data.azurerm_user_assigned_identity.mft.id
  audience  = ["api://AzureADTokenExchange"]
  issuer    = azurerm_kubernetes_cluster.main.oidc_issuer_url
  subject   = "system:serviceaccount:${var.mft_namespace}:${var.mft_service_account_name}"
}

# Federated credential for Database Configurator service account
resource "azurerm_federated_identity_credential" "dbc" {
  name      = "${var.prefix}-dbc-federated-credential"
  parent_id = data.azurerm_user_assigned_identity.mft.id
  audience  = ["api://AzureADTokenExchange"]
  issuer    = azurerm_kubernetes_cluster.main.oidc_issuer_url
  subject   = "system:serviceaccount:default:database-configurator-sa"
}

# Federated credential for Database User Init service account
resource "azurerm_federated_identity_credential" "db_user_init" {
  name      = "${var.prefix}-db-user-init-federated-credential"
  parent_id = data.azurerm_user_assigned_identity.mft.id
  audience  = ["api://AzureADTokenExchange"]
  issuer    = azurerm_kubernetes_cluster.main.oidc_issuer_url
  subject   = "system:serviceaccount:default:database-user-init-sa"
}

# Federated credential for MFT service (active transfer)
resource "azurerm_federated_identity_credential" "mft_service" {
  name      = "${var.prefix}-mft-service-federated-credential"
  parent_id = data.azurerm_user_assigned_identity.mft.id
  audience  = ["api://AzureADTokenExchange"]
  issuer    = azurerm_kubernetes_cluster.main.oidc_issuer_url
  subject   = "system:serviceaccount:mft:mft-service-account"
}

################################################################################
# Workload Identity - AGIC Federated Credential and RBAC
################################################################################

# Federated credential for AGIC service account
resource "azurerm_federated_identity_credential" "agic" {
  name      = "${var.prefix}-agic-federated-credential"
  parent_id = data.azurerm_user_assigned_identity.agic.id
  audience  = ["api://AzureADTokenExchange"]
  issuer    = azurerm_kubernetes_cluster.main.oidc_issuer_url
  subject   = "system:serviceaccount:default:ingress-azure"
}

# Grant AGIC Contributor access to Application Gateway
resource "azurerm_role_assignment" "agic_appgw_contributor" {
  scope                = azurerm_application_gateway.main.id
  role_definition_name = "Contributor"
  principal_id         = var.agic_identity_principal_id
}

# Grant AGIC Reader access to Application Gateway resource group
resource "azurerm_role_assignment" "agic_rg_reader" {
  scope                = data.azurerm_resource_group.fulfillment.id
  role_definition_name = "Reader"
  principal_id         = var.agic_identity_principal_id
}

# Grant AGIC Network Contributor access to App Gateway subnet
resource "azurerm_role_assignment" "agic_subnet_network_contributor" {
  scope                = azurerm_subnet.app_gateway.id
  role_definition_name = "Network Contributor"
  principal_id         = var.agic_identity_principal_id
}

################################################################################
# Key Vault Integration - RBAC Role Assignments
################################################################################

# Grant Key Vault Secrets User role to MFT managed identity
resource "azurerm_role_assignment" "mft_kv_secrets_user" {
  scope                = data.azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.mft_identity_principal_id
}

# Grant Key Vault Certificate User role to MFT managed identity
resource "azurerm_role_assignment" "mft_kv_certificates_user" {
  scope                = data.azurerm_key_vault.main.id
  role_definition_name = "Key Vault Certificate User"
  principal_id         = var.mft_identity_principal_id
}

# Grant current identity Key Vault Administrator role (for secret creation)
resource "azurerm_role_assignment" "terraform_kv_admin" {
  scope                = data.azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

################################################################################
# Key Vault Integration - Default Secrets
################################################################################

locals {
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
      description = "IBM webMethods metering configuration XML file"
    }
  }
}

# Create default secrets in Key Vault
resource "azurerm_key_vault_secret" "defaults" {
  for_each = local.default_secrets

  name         = each.key
  value        = each.value.value
  key_vault_id = data.azurerm_key_vault.main.id
  content_type = "text/plain"

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

################################################################################
# Key Vault Integration - MFT Database Credentials
################################################################################

locals {
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
      description = "PostgreSQL administrator username"
    }
    "postgres-admin-password" = {
      value       = var.postgres_admin_password
      description = "PostgreSQL administrator password"
    }
    "postgres-online-user" = {
      value       = var.postgres_dbc_user
      description = "PostgreSQL user for MFT online database operations"
    }
    "postgres-online-password" = {
      value       = var.postgres_dbc_password
      description = "PostgreSQL password for MFT online database operations"
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

# Create MFT database secrets in Key Vault
resource "azurerm_key_vault_secret" "mft_db_credentials" {
  for_each = local.mft_db_credentials

  name            = "${local.environment}-mft-db-${each.key}"
  value           = each.value.value
  key_vault_id    = data.azurerm_key_vault.main.id
  expiration_date = var.secret_expiration_date
  content_type    = "text/plain"

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