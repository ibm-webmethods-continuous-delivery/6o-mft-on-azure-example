################################################################################
# Common Variables
################################################################################

variable "prefix" {
  description = "Prefix for all resource names"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]{3,10}$", var.prefix))
    error_message = "Prefix must be 3-10 lowercase alphanumeric characters"
  }
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "westeurope"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "environment_name" {
  description = "Environment name (e.g., dev, test, prod) used for Key Vault secret prefixes"
  type        = string
  default     = "dev"
}

################################################################################
# Stage A Handoff Variables (from Stage A outputs)
################################################################################

variable "delivery_resource_group_name" {
  description = "Name of the Service Delivery resource group (from Stage A)"
  type        = string
}

variable "fulfillment_resource_group_name" {
  description = "Name of the Service Fulfillment resource group (from Stage A)"
  type        = string
}

variable "mft_identity_id" {
  description = "Resource ID of the MFT workload managed identity (from Stage A)"
  type        = string
}

variable "mft_identity_principal_id" {
  description = "Principal ID of the MFT workload managed identity (from Stage A)"
  type        = string
}

variable "mft_identity_client_id" {
  description = "Client ID of the MFT workload managed identity (from Stage A)"
  type        = string
}

variable "agic_identity_id" {
  description = "Resource ID of the AGIC workload managed identity (from Stage A)"
  type        = string
}

variable "agic_identity_principal_id" {
  description = "Principal ID of the AGIC workload managed identity (from Stage A)"
  type        = string
}

variable "agic_identity_client_id" {
  description = "Client ID of the AGIC workload managed identity (from Stage A)"
  type        = string
}

################################################################################
# Key Vault Variables (from 01-vault/)
################################################################################

variable "key_vault_name" {
  description = "Name of the existing Key Vault (from 01-vault/)"
  type        = string
}

variable "key_vault_resource_group_name" {
  description = "Resource group name of the existing Key Vault (from 01-vault/)"
  type        = string
}

################################################################################
# Service Delivery - Network Variables
################################################################################

variable "delivery_vnet_name" {
  description = "Name of the Service Delivery virtual network (optional, defaults to <prefix>-delivery-vnet)"
  type        = string
  default     = null
}

variable "delivery_vnet_address_space" {
  description = "Address space for Service Delivery virtual network"
  type        = list(string)
  default     = ["10.1.0.0/16"]
}

variable "delivery_subnet_name" {
  description = "Name of the Service Delivery subnet (optional, defaults to <prefix>-delivery-subnet)"
  type        = string
  default     = null
}

variable "delivery_nsg_name" {
  description = "Name of the Service Delivery NSG (optional, defaults to <prefix>-delivery-nsg)"
  type        = string
  default     = null
}

################################################################################
# Service Delivery - VMSS Variables
################################################################################

variable "vmss_name" {
  description = "Name of the VMSS for Azure DevOps agents (optional, defaults to <prefix>AgentsVmss)"
  type        = string
  default     = null
}

variable "vmss_sku" {
  description = "SKU/size for VMSS instances"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "vmss_instance_count" {
  description = "Initial number of VMSS instances (typically 0, scaled by Azure DevOps)"
  type        = number
  default     = 0
}

variable "vmss_image" {
  description = "VM image for VMSS in format publisher:offer:sku:version"
  type        = string
  default     = "Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest"
}

variable "ssh_admin_pub_key" {
  description = "SSH public key for VM admin user"
  type        = string
}

################################################################################
# Service Delivery - Storage Variables
################################################################################

variable "storage_account_name" {
  description = "Name of the storage account (optional, defaults to <prefix>imagessa)"
  type        = string
  default     = null
}

variable "storage_share_name" {
  description = "Name of the file share (optional, defaults to <prefix>imagessashare)"
  type        = string
  default     = null
}

variable "storage_share_quota" {
  description = "Quota for file share in GB"
  type        = number
  default     = 5120
}

################################################################################
# Service Delivery - ACR Variables
################################################################################

variable "acr_name" {
  description = "Name of the Azure Container Registry (optional, defaults to <prefix>acr)"
  type        = string
  default     = null
}

variable "acr_sku" {
  description = "SKU for Azure Container Registry"
  type        = string
  default     = "Standard"
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.acr_sku)
    error_message = "ACR SKU must be Basic, Standard, or Premium"
  }
}

################################################################################
# Service Fulfillment - Network Variables
################################################################################

variable "fulfillment_vnet_name" {
  description = "Name of the Service Fulfillment virtual network (optional, defaults to <prefix>-fulfillment-vnet)"
  type        = string
  default     = null
}

variable "fulfillment_vnet_address_space" {
  description = "Address space for Service Fulfillment virtual network"
  type        = list(string)
  default     = ["10.2.0.0/16"]
}

variable "public_subnet_1_name" {
  description = "Name of public subnet 1 for SFTP VM 1 (optional)"
  type        = string
  default     = null
}

variable "public_subnet_2_name" {
  description = "Name of public subnet 2 for SFTP VM 2 (optional)"
  type        = string
  default     = null
}

variable "private_subnet_1_name" {
  description = "Name of private subnet 1 for AKS (optional)"
  type        = string
  default     = null
}

variable "private_subnet_2_name" {
  description = "Name of private subnet 2 for PostgreSQL (optional)"
  type        = string
  default     = null
}

variable "app_gateway_subnet_name" {
  description = "Name of Application Gateway subnet (optional)"
  type        = string
  default     = null
}

variable "sftp_nsg_name" {
  description = "Name of SFTP NSG (optional, defaults to <prefix>-sftp-nsg)"
  type        = string
  default     = null
}

variable "aks_nsg_name" {
  description = "Name of AKS NSG (optional, defaults to <prefix>-aks-nsg)"
  type        = string
  default     = null
}

variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access SFTP VMs"
  type        = list(string)
  default     = []
}

################################################################################
# Service Fulfillment - SFTP Variables
################################################################################

variable "sftp_lb_name" {
  description = "Name of SFTP load balancer (optional, defaults to <prefix>-sftp-lb)"
  type        = string
  default     = null
}

variable "sftp_vm_1_name" {
  description = "Name of SFTP VM 1 (optional, defaults to <prefix>-sftp-vm-1)"
  type        = string
  default     = null
}

variable "sftp_vm_2_name" {
  description = "Name of SFTP VM 2 (optional, defaults to <prefix>-sftp-vm-2)"
  type        = string
  default     = null
}

variable "sftp_vm_size" {
  description = "VM size for SFTP VMs"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "enable_sftp_vm_acr_role" {
  description = "Enable ACR Pull role assignment for SFTP VMs"
  type        = bool
  default     = true
}

################################################################################
# Service Fulfillment - AKS Variables
################################################################################

variable "aks_cluster_name" {
  description = "Name of the AKS cluster (optional, defaults to <prefix>-aks)"
  type        = string
  default     = null
}

variable "aks_node_count" {
  description = "Number of nodes in the AKS default node pool"
  type        = number
  default     = 3
}

variable "aks_node_size" {
  description = "VM size for AKS nodes"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "enable_aks_acr_role" {
  description = "Enable ACR Pull role assignment for AKS"
  type        = bool
  default     = true
}

variable "mft_namespace" {
  description = "Kubernetes namespace for MFT workload"
  type        = string
  default     = "mft"
}

variable "mft_service_account_name" {
  description = "Kubernetes service account name for MFT workload"
  type        = string
  default     = "mft-service-account"
}

################################################################################
# Service Fulfillment - PostgreSQL Variables
################################################################################

variable "postgres_server_name" {
  description = "Name of PostgreSQL Flexible Server (optional, defaults to <prefix>-postgres)"
  type        = string
  default     = null
}

variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "16"
}

variable "postgres_sku_name" {
  description = "SKU name for PostgreSQL Flexible Server"
  type        = string
  default     = "B_Standard_B2s"
}

variable "postgres_storage_mb" {
  description = "Storage size in MB for PostgreSQL"
  type        = number
  default     = 32768
}

variable "postgres_admin_username" {
  description = "Administrator username for PostgreSQL"
  type        = string
  default     = "psqladmin"
}

variable "postgres_admin_password" {
  description = "Administrator password for PostgreSQL"
  type        = string
  sensitive   = true
}

variable "postgres_online_db_name" {
  description = "Name of the online transactions database"
  type        = string
  default     = "mft_online"
}

variable "postgres_archive_db_name" {
  description = "Name of the archive database"
  type        = string
  default     = "mft_archive"
}

variable "postgres_dbc_user" {
  description = "PostgreSQL user for MFT Database Configurator (online)"
  type        = string
  default     = "mft_dbc_user"
}

variable "postgres_dbc_password" {
  description = "PostgreSQL password for MFT Database Configurator (online)"
  type        = string
  sensitive   = true
}

variable "postgres_dbc_archive_user" {
  description = "PostgreSQL user for MFT Database Configurator (archive)"
  type        = string
  default     = "mft_dbc_archive_user"
}

variable "postgres_dbc_archive_password" {
  description = "PostgreSQL password for MFT Database Configurator (archive)"
  type        = string
  sensitive   = true
}

################################################################################
# Service Fulfillment - Application Gateway Variables
################################################################################

variable "app_gateway_name" {
  description = "Name of Application Gateway (optional, defaults to <prefix>-appgw)"
  type        = string
  default     = null
}

variable "app_gateway_sku_name" {
  description = "SKU name for Application Gateway"
  type        = string
  default     = "Standard_v2"
}

variable "app_gateway_sku_tier" {
  description = "SKU tier for Application Gateway"
  type        = string
  default     = "Standard_v2"
}

variable "app_gateway_capacity" {
  description = "Capacity (instance count) for Application Gateway"
  type        = number
  default     = 2
}

################################################################################
# Key Vault Integration Variables
################################################################################

variable "secret_expiration_date" {
  description = "Expiration date for Key Vault secrets (ISO 8601 format)"
  type        = string
  default     = "2027-12-31T23:59:59Z"
}

variable "upload_certificates" {
  description = "Whether to upload certificates to Key Vault"
  type        = bool
  default     = false
}

variable "certificates_base_path" {
  description = "Base path for certificate files (when upload_certificates is true)"
  type        = string
  default     = ""
}

variable "certificate_password" {
  description = "Password for PKCS12 certificate files"
  type        = string
  sensitive   = true
  default     = ""
}

################################################################################
# Optional Private Storage Variables
################################################################################

variable "create_private_storage" {
  description = "Whether to create private storage account for MFT VFS"
  type        = bool
  default     = false
}

variable "private_storage_account_name" {
  description = "Name of private storage account for MFT VFS (optional)"
  type        = string
  default     = null
}

variable "private_storage_share_name" {
  description = "Name of private file share for MFT VFS (optional)"
  type        = string
  default     = null
}

variable "private_storage_share_quota" {
  description = "Quota for private file share in GB"
  type        = number
  default     = 1024
}
