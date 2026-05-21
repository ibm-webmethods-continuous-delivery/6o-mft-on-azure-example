# Resource Group
output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
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

# Subnets
output "public_subnet_1_id" {
  description = "ID of the first public subnet"
  value       = azurerm_subnet.public_1.id
}

output "public_subnet_2_id" {
  description = "ID of the second public subnet"
  value       = azurerm_subnet.public_2.id
}

output "private_subnet_1_id" {
  description = "ID of the first private subnet (AKS)"
  value       = azurerm_subnet.private_1.id
}

output "private_subnet_2_id" {
  description = "ID of the second private subnet (PostgreSQL)"
  value       = azurerm_subnet.private_2.id
}

# Network Security Groups
output "sftp_nsg_id" {
  description = "ID of the SFTP Network Security Group"
  value       = azurerm_network_security_group.sftp.id
}

output "aks_nsg_id" {
  description = "ID of the AKS Network Security Group"
  value       = azurerm_network_security_group.aks.id
}

# SFTP Load Balancer
output "sftp_lb_id" {
  description = "ID of the SFTP Load Balancer"
  value       = azurerm_lb.sftp.id
}

output "sftp_lb_public_ip" {
  description = "Public IP address of the SFTP Load Balancer"
  value       = azurerm_public_ip.sftp_lb.ip_address
}

output "sftp_lb_fqdn" {
  description = "FQDN of the SFTP Load Balancer"
  value       = azurerm_public_ip.sftp_lb.fqdn
}

# SFTP VMs
output "sftp_vm_1_id" {
  description = "ID of the first SFTP VM"
  value       = azurerm_linux_virtual_machine.sftp_vm_1.id
}

output "sftp_vm_1_private_ip" {
  description = "Private IP address of the first SFTP VM"
  value       = azurerm_network_interface.sftp_vm_1.private_ip_address
}

output "sftp_vm_2_id" {
  description = "ID of the second SFTP VM"
  value       = azurerm_linux_virtual_machine.sftp_vm_2.id
}

output "sftp_vm_2_private_ip" {
  description = "Private IP address of the second SFTP VM"
  value       = azurerm_network_interface.sftp_vm_2.private_ip_address
}

# AKS Cluster
output "aks_cluster_id" {
  description = "ID of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.id
}

output "aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.name
}

output "aks_cluster_fqdn" {
  description = "FQDN of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.fqdn
}

output "aks_kube_config" {
  description = "Kubernetes configuration for the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive   = true
}

output "aks_kube_oidc_issuer_url" {
  description = "Kubernetes configuration for the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.oidc_issuer_url
  sensitive   = true
}


output "aks_kubelet_identity" {
  description = "Kubelet identity object ID for ACR access"
  value       = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}

# PostgreSQL
output "postgres_server_id" {
  description = "ID of the PostgreSQL Flexible Server"
  value       = azurerm_postgresql_flexible_server.main.id
}

output "postgres_server_name" {
  description = "Name of the PostgreSQL Flexible Server"
  value       = azurerm_postgresql_flexible_server.main.name
}

output "postgres_server_fqdn" {
  description = "FQDN of the PostgreSQL Flexible Server"
  value       = azurerm_postgresql_flexible_server.main.fqdn
}

output "postgres_admin_username" {
  description = "Administrator username for PostgreSQL Flexible Server"
  value       = var.postgres_admin_username
  sensitive   = true
}

output "postgres_admin_password" {
  description = "Administrator password for PostgreSQL Flexible Server"
  value       = var.postgres_admin_password
  sensitive   = true
}

output "postgres_online_db_name" {
  description = "Name of the online transactions database"
  value       = azurerm_postgresql_flexible_server_database.online.name
}

output "postgres_archive_db_name" {
  description = "Name of the archive database"
  value       = azurerm_postgresql_flexible_server_database.archive.name
}

output "postgres_connection_string_online" {
  description = "Connection string for the online database"
  value       = "postgresql://${var.postgres_admin_username}@${azurerm_postgresql_flexible_server.main.name}:${var.postgres_admin_password}@${azurerm_postgresql_flexible_server.main.fqdn}:5432/${azurerm_postgresql_flexible_server_database.online.name}?sslmode=require"
  sensitive   = true
}

output "postgres_connection_string_archive" {
  description = "Connection string for the archive database"
  value       = "postgresql://${var.postgres_admin_username}@${azurerm_postgresql_flexible_server.main.name}:${var.postgres_admin_password}@${azurerm_postgresql_flexible_server.main.fqdn}:5432/${azurerm_postgresql_flexible_server_database.archive.name}?sslmode=require"
  sensitive   = true
}

# Application Gateway
output "app_gateway_id" {
  description = "ID of the Application Gateway"
  value       = azurerm_application_gateway.main.id
}

output "app_gateway_name" {
  description = "Name of the Application Gateway"
  value       = azurerm_application_gateway.main.name
}

output "app_gateway_public_ip" {
  description = "Public IP address of the Application Gateway"
  value       = azurerm_public_ip.app_gateway.ip_address
}

output "app_gateway_fqdn" {
  description = "FQDN of the Application Gateway"
  value       = azurerm_public_ip.app_gateway.fqdn
}

# ACR Reference
output "acr_name" {
  description = "Name of the Azure Container Registry"
  value       = data.azurerm_container_registry.main.name
}

output "acr_login_server" {
  description = "Login server URL for the Azure Container Registry"
  value       = data.azurerm_container_registry.main.login_server
}

# AGIC Service Principal
output "agic_service_principal_client_id" {
  description = "Client ID (Application ID) of the AGIC Service Principal"
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

output "agic_service_principal_object_id" {
  description = "Object ID of the AGIC Service Principal"
  value       = azuread_service_principal.agic.object_id
}

# Summary Information
output "sftp_endpoint" {
  description = "SFTP endpoint for connecting (use port 55022)"
  value       = "sftp://${azurerm_public_ip.sftp_lb.ip_address}:55022"
}


# Manual Permission Grant Instructions (when enable_agic_role_assignments = false)
output "manual_permission_grants_required" {
  description = "Instructions for manually granting AGIC permissions when automatic role assignments are disabled"
  value       = var.enable_agic_role_assignments ? "No manual grants required - role assignments were created automatically" : <<-EOT
    MANUAL PERMISSION GRANTS REQUIRED:

    The following role assignments must be created manually in Azure Portal or via Azure CLI:

    1. Grant 'Contributor' role to AGIC Service Principal on Application Gateway:
       Scope: ${azurerm_application_gateway.main.id}
       Principal ID: ${azuread_service_principal.agic.object_id}
       Role: Contributor

       Azure CLI command:
       az role assignment create \
         --assignee ${azuread_service_principal.agic.object_id} \
         --role Contributor \
         --scope ${azurerm_application_gateway.main.id}

    2. Grant 'Reader' role to AGIC Service Principal on Resource Group:
       Scope: ${azurerm_resource_group.main.id}
       Principal ID: ${azuread_service_principal.agic.object_id}
       Role: Reader

       Azure CLI command:
       az role assignment create \
         --assignee ${azuread_service_principal.agic.object_id} \
         --role Reader \
         --scope ${azurerm_resource_group.main.id}

    3. Grant 'Network Contributor' role to AGIC Service Principal on App Gateway subnet:
       Scope: ${azurerm_subnet.app_gateway.id}
       Principal ID: ${azuread_service_principal.agic.object_id}
       Role: Network Contributor

       Azure CLI command:
       az role assignment create \
         --assignee ${azuread_service_principal.agic.object_id} \
         --role "Network Contributor" \
         --scope ${azurerm_subnet.app_gateway.id}

    After granting these permissions, you can proceed with AGIC installation.
    See AGIC-INSTALLATION.md for detailed instructions.
  EOT
}

output "web_endpoint" {
  description = "Web endpoint for accessing the application"
  value       = "http://${azurerm_public_ip.app_gateway.ip_address}"
}

