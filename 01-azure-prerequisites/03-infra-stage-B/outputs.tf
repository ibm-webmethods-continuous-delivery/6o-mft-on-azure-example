################################################################################
# Service Delivery Outputs
################################################################################

output "delivery_vnet_name" {
  description = "Name of the Service Delivery virtual network"
  value       = azurerm_virtual_network.delivery.name
}

output "delivery_vnet_id" {
  description = "ID of the Service Delivery virtual network"
  value       = azurerm_virtual_network.delivery.id
}

output "delivery_subnet_id" {
  description = "ID of the Service Delivery subnet"
  value       = azurerm_subnet.delivery.id
}

output "vmss_name" {
  description = "Name of the VMSS for Azure DevOps agents"
  value       = azurerm_linux_virtual_machine_scale_set.agents.name
}

output "vmss_id" {
  description = "ID of the VMSS for Azure DevOps agents"
  value       = azurerm_linux_virtual_machine_scale_set.agents.id
}

output "storage_account_name" {
  description = "Name of the Service Delivery storage account"
  value       = azurerm_storage_account.delivery.name
}

output "storage_account_id" {
  description = "ID of the Service Delivery storage account"
  value       = azurerm_storage_account.delivery.id
}

output "storage_share_name" {
  description = "Name of the Service Delivery file share"
  value       = azurerm_storage_share.delivery.name
}

output "acr_name" {
  description = "Name of the Azure Container Registry"
  value       = azurerm_container_registry.main.name
}

output "acr_id" {
  description = "ID of the Azure Container Registry"
  value       = azurerm_container_registry.main.id
}

output "acr_login_server" {
  description = "Login server URL for the Azure Container Registry"
  value       = azurerm_container_registry.main.login_server
}

################################################################################
# Service Fulfillment - Network Outputs
################################################################################

output "fulfillment_vnet_name" {
  description = "Name of the Service Fulfillment virtual network"
  value       = azurerm_virtual_network.fulfillment.name
}

output "fulfillment_vnet_id" {
  description = "ID of the Service Fulfillment virtual network"
  value       = azurerm_virtual_network.fulfillment.id
}

output "public_subnet_1_id" {
  description = "ID of public subnet 1 (SFTP VM 1)"
  value       = azurerm_subnet.public_1.id
}

output "public_subnet_2_id" {
  description = "ID of public subnet 2 (SFTP VM 2)"
  value       = azurerm_subnet.public_2.id
}

output "private_subnet_1_id" {
  description = "ID of private subnet 1 (AKS)"
  value       = azurerm_subnet.private_1.id
}

output "private_subnet_2_id" {
  description = "ID of private subnet 2 (PostgreSQL)"
  value       = azurerm_subnet.private_2.id
}

output "app_gateway_subnet_id" {
  description = "ID of Application Gateway subnet"
  value       = azurerm_subnet.app_gateway.id
}

################################################################################
# Service Fulfillment - SFTP Outputs
################################################################################

output "sftp_lb_name" {
  description = "Name of the SFTP load balancer"
  value       = azurerm_lb.sftp.name
}

output "sftp_lb_public_ip" {
  description = "Public IP address of the SFTP load balancer"
  value       = azurerm_public_ip.sftp_lb.ip_address
}

output "sftp_vm_1_name" {
  description = "Name of SFTP VM 1"
  value       = azurerm_linux_virtual_machine.sftp_vm_1.name
}

output "sftp_vm_1_private_ip" {
  description = "Private IP address of SFTP VM 1"
  value       = azurerm_network_interface.sftp_vm_1.private_ip_address
}

output "sftp_vm_2_name" {
  description = "Name of SFTP VM 2"
  value       = azurerm_linux_virtual_machine.sftp_vm_2.name
}

output "sftp_vm_2_private_ip" {
  description = "Private IP address of SFTP VM 2"
  value       = azurerm_network_interface.sftp_vm_2.private_ip_address
}

################################################################################
# Service Fulfillment - AKS Outputs
################################################################################

output "aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.name
}

output "aks_cluster_id" {
  description = "ID of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.id
}

output "aks_cluster_fqdn" {
  description = "FQDN of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.fqdn
}

output "aks_oidc_issuer_url" {
  description = "OIDC issuer URL for AKS workload identity"
  value       = azurerm_kubernetes_cluster.main.oidc_issuer_url
}

output "aks_kubelet_identity_object_id" {
  description = "Object ID of the AKS kubelet managed identity"
  value       = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}

################################################################################
# Service Fulfillment - PostgreSQL Outputs
################################################################################

output "postgres_server_name" {
  description = "Name of the PostgreSQL Flexible Server"
  value       = azurerm_postgresql_flexible_server.main.name
}

output "postgres_server_fqdn" {
  description = "FQDN of the PostgreSQL Flexible Server"
  value       = azurerm_postgresql_flexible_server.main.fqdn
}

output "postgres_online_db_name" {
  description = "Name of the PostgreSQL online database"
  value       = azurerm_postgresql_flexible_server_database.online.name
}

output "postgres_archive_db_name" {
  description = "Name of the PostgreSQL archive database"
  value       = azurerm_postgresql_flexible_server_database.archive.name
}

################################################################################
# Service Fulfillment - Application Gateway Outputs
################################################################################

output "app_gateway_name" {
  description = "Name of the Application Gateway"
  value       = azurerm_application_gateway.main.name
}

output "app_gateway_id" {
  description = "ID of the Application Gateway"
  value       = azurerm_application_gateway.main.id
}

output "app_gateway_public_ip" {
  description = "Public IP address of the Application Gateway"
  value       = azurerm_public_ip.app_gateway.ip_address
}

################################################################################
# Key Vault Outputs
################################################################################

output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = data.azurerm_key_vault.main.name
}

output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = data.azurerm_key_vault.main.id
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = data.azurerm_key_vault.main.vault_uri
}

################################################################################
# Workload Identity Outputs
################################################################################

output "mft_identity_client_id" {
  description = "Client ID of the MFT workload managed identity"
  value       = var.mft_identity_client_id
}

output "agic_identity_client_id" {
  description = "Client ID of the AGIC workload managed identity"
  value       = var.agic_identity_client_id
}

################################################################################
# Optional Private Storage Outputs
################################################################################

output "private_storage_account_name" {
  description = "Name of the private storage account for MFT VFS (if created)"
  value       = var.create_private_storage ? azurerm_storage_account.private[0].name : null
}

output "private_storage_share_name" {
  description = "Name of the private file share for MFT VFS (if created)"
  value       = var.create_private_storage ? azurerm_storage_share.private[0].name : null
}

################################################################################
# Handoff Instructions for Stage C
################################################################################

output "stage_c_handoff" {
  description = "Information needed for Stage C (Azure DevOps setup)"
  value = {
    vmss_name                = azurerm_linux_virtual_machine_scale_set.agents.name
    vmss_resource_group_name = data.azurerm_resource_group.delivery.name
    acr_name                 = azurerm_container_registry.main.name
    acr_login_server         = azurerm_container_registry.main.login_server
    key_vault_name           = data.azurerm_key_vault.main.name
    key_vault_uri            = data.azurerm_key_vault.main.vault_uri
  }
}

################################################################################
# Summary Instructions
################################################################################

output "instructions" {
  description = "Instructions for next steps after Stage B deployment"
  value       = <<-EOT
    
    ========================================
    Stage B Infrastructure Deployment Complete
    ========================================
    
    Service Delivery Resources:
    - Virtual Network: ${azurerm_virtual_network.delivery.name}
    - VMSS for Azure DevOps Agents: ${azurerm_linux_virtual_machine_scale_set.agents.name}
    - Storage Account: ${azurerm_storage_account.delivery.name}
    - Azure Container Registry: ${azurerm_container_registry.main.name}
    
    Service Fulfillment Resources:
    - Virtual Network: ${azurerm_virtual_network.fulfillment.name}
    - AKS Cluster: ${azurerm_kubernetes_cluster.main.name}
    - PostgreSQL Server: ${azurerm_postgresql_flexible_server.main.name}
    - Application Gateway: ${azurerm_application_gateway.main.name}
    - SFTP Load Balancer: ${azurerm_lb.sftp.name} (Public IP: ${azurerm_public_ip.sftp_lb.ip_address})
    
    Workload Identities Configured:
    - MFT Identity: Federated credentials created for MFT service accounts
    - AGIC Identity: Federated credential and RBAC roles configured
    
    Key Vault Integration:
    - Default secrets created in: ${data.azurerm_key_vault.main.name}
    - Database credentials stored
    - MFT identity has Secrets User and Certificate User roles
    
    Next Steps:
    
    1. Configure kubectl access to AKS:
       az aks get-credentials --resource-group ${data.azurerm_resource_group.fulfillment.name} --name ${azurerm_kubernetes_cluster.main.name}
    
    2. Verify AKS workload identity is enabled:
       kubectl get serviceaccount -A
    
    3. Deploy AGIC to AKS (if not already deployed):
       helm install ingress-azure application-gateway-kubernetes-ingress/ingress-azure \
         --set appgw.applicationGatewayID=${azurerm_application_gateway.main.id} \
         --set armAuth.type=workloadIdentity \
         --set armAuth.identityClientID=${var.agic_identity_client_id}
    
    4. Proceed to Stage C for Azure DevOps setup:
       - Use outputs from Stage A for Azure DevOps service principal
       - Use VMSS name: ${azurerm_linux_virtual_machine_scale_set.agents.name}
       - Use ACR name: ${azurerm_container_registry.main.name}
    
    5. Access Key Vault secrets:
       az keyvault secret list --vault-name ${data.azurerm_key_vault.main.name}
    
    6. Connect to PostgreSQL:
       Server: ${azurerm_postgresql_flexible_server.main.fqdn}
       Online DB: ${azurerm_postgresql_flexible_server_database.online.name}
       Archive DB: ${azurerm_postgresql_flexible_server_database.archive.name}
    
    7. Access SFTP service:
       SFTP Endpoint: ${azurerm_public_ip.sftp_lb.ip_address}:55022
    
    ========================================
  EOT
}
