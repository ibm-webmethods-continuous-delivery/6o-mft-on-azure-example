# Optional variables
resource_group_name = "YOUR_AzKV_RG"
# Optional, can contain alphanumeric and dashes
key_vault_name      = "YOUR-zKV-RG-kv"

# Optional: additional AAD object IDs to grant 'Key Vault Secrets Officer'.
# The identity running terraform apply is always included automatically.
# key_vault_admin_object_ids = [
#   "00000000-0000-0000-0000-000000000001",   # another admin user
#   "00000000-0000-0000-0000-000000000002",   # CI/CD service principal
# ]
