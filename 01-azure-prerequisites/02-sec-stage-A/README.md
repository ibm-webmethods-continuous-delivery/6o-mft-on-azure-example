# Security Stage A - Prerequisites

This Terraform project creates the foundational Azure resources required before the infrastructure team can provision the MFT deployment resources.

## Purpose

The security team uses this project to:

1. **Create Resource Groups**: Two resource groups for organizing infrastructure resources
   - Service Delivery RG: For CI/CD infrastructure (ACR, Key Vault, Azure DevOps agents)
   - Service Fulfillment RG: For MFT runtime infrastructure (AKS, SFTP VMs, PostgreSQL, App Gateway)

2. **Create Infrastructure Team Service Principal**: A service principal with appropriate permissions for the infrastructure team to provision resources using Terraform

3. **Create Azure DevOps Service Principal** (Optional): A service principal for the Stage C service delivery setup to authenticate Azure DevOps service connections against Azure

4. **Create Managed Identities** (Optional): User-assigned managed identities for MFT workloads and AGIC workloads running in AKS

## Resources Created

### Resource Groups

- **`${prefix}-s-delivery`**: Service Delivery resource group
- **`${prefix}-s-fulfillment`**: Service Fulfillment resource group

### Identities

- **Infrastructure Team Service Principal**: `${prefix}-infra-sp`
  - Azure AD Application
  - Service Principal with client secret
  - **Contributor role** on both resource groups (manage resources)
  - **`${prefix}-infra-role-delegator` custom role** on both resource groups (create/delete role assignments — see [Why a custom role?](#why-a-custom-role-instead-of-user-access-administrator) below)
  - **Reader role** on Key Vault resource group (if provided, read Key Vault metadata)
  - Valid for 1 year

- **Azure DevOps Service Principal** (Optional): `${prefix}-azdo-sp`
  - Azure AD Application
  - Service Principal with client secret
  - Contributor role on the Service Delivery resource group
  - Intended for Stage C Azure DevOps service delivery setup
  - Valid for 1 year

- **MFT Workload Identity** (Optional): `${prefix}-mft-identity`
  - User-Assigned Managed Identity
  - Created in the Service Fulfillment resource group
  - Federated credentials to be added later when AKS OIDC issuer is available

- **AGIC Workload Identity** (Optional): `${prefix}-agic-identity`
  - User-Assigned Managed Identity
  - Created in the Service Fulfillment resource group
  - Intended for AGIC workload identity integration in later stages
  - Federated credentials to be added later when AKS OIDC issuer is available

## Why a custom role instead of User Access Administrator?

Stage B needs the infrastructure service principal to create role assignments (e.g. grant `AcrPull` to VMs, `Key Vault Secrets User` to the MFT identity). The natural built-in role for this is **User Access Administrator** (`18d7d88d-d35e-4fb5-a5c3-7773c20a72d9`).

However, IBM enterprise subscriptions apply an **ABAC condition** on the Owner role assignment granted to subscription owners:

```
roleAssignments/write is ALLOWED only when the role being assigned is NOT one of:
  - 8e3af657-a8ff-443c-a75c-2fe8c4bcb635  (Owner)
  - 18d7d88d-d35e-4fb5-a5c3-7773c20a72d9  (User Access Administrator)  ← blocked
  - f58310d9-a9f6-439a-9e8d-f62e7b41a168  (Role Based Access Control Administrator)
```

This means that even a subscription Owner gets a `403 AuthorizationFailed: ABAC condition not fulfilled` when trying to assign UAA to another principal via Terraform or the CLI.

**Solution:** This stage creates a **custom role** (`${prefix}-infra-role-delegator`) that grants only:
- `Microsoft.Authorization/roleAssignments/write`
- `Microsoft.Authorization/roleAssignments/delete`
- `Microsoft.Authorization/roleAssignments/read`

Because the custom role has a new GUID (not in the ABAC blocklist), assigning it succeeds. This is also a **better least-privilege design** than UAA: the infrastructure SP can only create/delete role assignments within its own resource groups, not assign any role at any scope.

## Prerequisites

1. **Azure CLI** installed and authenticated
2. **Terraform** >= 1.0 installed
3. **Permissions**: The user running this Terraform must have:
   - Ability to create resource groups in the subscription
   - Ability to create Azure AD applications and service principals
   - Ability to create custom role definitions in the subscription
   - Ability to assign roles at resource group scope (Contributor or Owner with standard ABAC conditions)
4. **Key Vault** (Optional): If you have an existing Key Vault from `01-vault/`, provide its resource group name to grant the infrastructure team Reader access

## Usage

### 1. Configure Variables

Copy the example variables file and customize it:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
prefix   = "vmazex"  # Your unique prefix (4-10 chars, lowercase)
location = "westeurope"

# Optional: Provide Key Vault resource group for infrastructure team access
# key_vault_resource_group_name = "MIUN-LongTerm"
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Plan the Deployment

```bash
terraform plan
```

Review the planned changes carefully.

### 4. Apply the Configuration

```bash
terraform apply
```

Type `yes` when prompted to confirm.

### 5. Retrieve Service Principal Credentials

After successful deployment, retrieve the service principal credentials:

```bash
# Get the client ID
terraform output infra_sp_application_id

# Get the client secret (sensitive)
terraform output -raw infra_sp_client_secret

# Get the tenant ID
terraform output infra_sp_tenant_id

# Get the subscription ID
terraform output infra_sp_subscription_id

# Get full instructions
terraform output instructions
```

**IMPORTANT**: Save the client secret securely. It will not be shown again after this Terraform state is destroyed.

## Handoff to Infrastructure Team

Provide the infrastructure team with:

1. **Infrastructure Team Service Principal Credentials**:
   - Application (Client) ID
   - Client Secret
   - Tenant ID
   - Subscription ID

2. **Managed Identity Details**:
   - MFT identity IDs (if enabled)
   - AGIC identity IDs (if enabled)

3. **Resource Group Names**:
   - Service Delivery RG: `${prefix}-s-delivery`
   - Service Fulfillment RG: `${prefix}-s-fulfillment`

3. **Authentication Instructions**:

   ```bash
   # Using Azure CLI
   az login --service-principal \
     --username <client-id> \
     --password <client-secret> \
     --tenant <tenant-id>
   
   # Using Terraform environment variables
   export ARM_CLIENT_ID="<client-id>"
   export ARM_CLIENT_SECRET="<client-secret>"
   export ARM_TENANT_ID="<tenant-id>"
   export ARM_SUBSCRIPTION_ID="<subscription-id>"
   ```

## Variables Reference

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `prefix` | Prefix for resource names (4-10 chars, lowercase) | - | Yes |
| `location` | Azure region for resources | `westeurope` | No |
| `delivery_rg_suffix` | Suffix for Service Delivery RG | `s-delivery` | No |
| `fulfillment_rg_suffix` | Suffix for Service Fulfillment RG | `s-fulfillment` | No |
| `infra_sp_name_suffix` | Suffix for infrastructure SP name | `infra-sp` | No |
| `infra_sp_description` | Description for infrastructure SP | See variables.tf | No |
| `create_azdo_sp` | Whether to create Azure DevOps service principal | `true` | No |
| `azdo_sp_name_suffix` | Suffix for Azure DevOps SP name | `azdo-sp` | No |
| `azdo_sp_description` | Description for Azure DevOps SP | See variables.tf | No |
| `create_mft_identity` | Whether to create MFT workload identity | `true` | No |
| `mft_identity_suffix` | Suffix for MFT identity name | `mft-identity` | No |
| `create_agic_identity` | Whether to create AGIC workload identity | `true` | No |
| `agic_identity_suffix` | Suffix for AGIC identity name | `agic-identity` | No |
| `tags` | Tags to apply to resources | See variables.tf | No |

## Outputs Reference

| Output | Description | Sensitive |
|--------|-------------|-----------|
| `delivery_resource_group_name` | Name of Service Delivery RG | No |
| `delivery_resource_group_id` | ID of Service Delivery RG | No |
| `fulfillment_resource_group_name` | Name of Service Fulfillment RG | No |
| `fulfillment_resource_group_id` | ID of Service Fulfillment RG | No |
| `infra_sp_application_id` | Service Principal Client ID | No |
| `infra_sp_object_id` | Service Principal Object ID | No |
| `infra_sp_client_secret` | Service Principal Client Secret | Yes |
| `infra_sp_tenant_id` | Tenant ID | No |
| `infra_sp_subscription_id` | Subscription ID | No |
| `azdo_sp_application_id` | Azure DevOps SP Client ID | No |
| `azdo_sp_object_id` | Azure DevOps SP Object ID | No |
| `azdo_sp_client_secret` | Azure DevOps SP Client Secret | Yes |
| `mft_identity_id` | MFT Identity Resource ID | No |
| `mft_identity_principal_id` | MFT Identity Principal ID | No |
| `mft_identity_client_id` | MFT Identity Client ID | No |
| `agic_identity_id` | AGIC Identity Resource ID | No |
| `agic_identity_principal_id` | AGIC Identity Principal ID | No |
| `agic_identity_client_id` | AGIC Identity Client ID | No |
| `instructions` | Usage instructions for infrastructure team | No |

## Security Considerations

1. **Service Principal Secret Rotation**: The client secret is valid for 1 year. Plan to rotate it before expiration.

2. **State File Security**: The Terraform state file contains sensitive information (client secret). Store it securely:
   - Use remote state backend (Azure Storage with encryption)
   - Restrict access to the state file
   - Enable state locking

3. **Least Privilege**: The service principal has Contributor and the custom `${prefix}-infra-role-delegator` roles scoped to specific resource groups only, not on the entire subscription. The custom role grants only `roleAssignments/write` and `roleAssignments/delete` — unlike User Access Administrator, it cannot be used to assign roles at any other scope or to escalate privileges.

4. **Role Assignment Permissions**: The custom `${prefix}-infra-role-delegator` role allows the infrastructure team to create role assignments within their managed resource groups. This is required for Stage B to grant:
   - `AcrPull` access to SFTP VMs and AKS on the Container Registry
   - AGIC permissions (Application Gateway Contributor, Resource Group Reader, Subnet Network Contributor)
   - Key Vault access for MFT identity (Secrets User, Certificate User)
   - Key Vault Administrator for Terraform to manage secrets

5. **ABAC Compliance**: The custom role design is required by IBM enterprise subscription policy. Attempting to use the built-in User Access Administrator role results in `403 AuthorizationFailed: ABAC condition not fulfilled` even for subscription Owners, because the Owner assignment carries a condition blocking assignment of the three built-in privileged roles (Owner, UAA, RBAC Administrator).

6. **Monitoring**: Consider enabling Azure Activity Log monitoring for role assignment changes to track what access is granted by the infrastructure team service principal.

7. **Audit Trail**: All operations performed by the service principal can be tracked via Azure Activity Logs.

## Troubleshooting

### Service Principal Propagation Issues

If role assignments fail with "Principal not found" errors:

1. The Terraform includes a 30-second wait after SP creation
2. If issues persist, increase the wait time in `main.tf`:
   ```hcl
   resource "time_sleep" "wait_for_sp_propagation" {
     create_duration = "60s"  # Increase to 60 seconds
   }
   ```

### Permission Errors

If you encounter permission errors during `terraform apply`:

1. Verify you have the required Azure AD and RBAC permissions
2. Check you're authenticated to the correct Azure subscription:
   ```bash
   az account show
   ```

### Role Assignment Errors in Stage A (403 ABAC condition not fulfilled)

If you see this error during `terraform apply` in Stage A:

```
Error: AuthorizationFailed: The client has an authorization with ABAC condition
that is not fulfilled to perform action 'Microsoft.Authorization/roleAssignments/write'
```

**Root Cause:** Your Owner role on the subscription has an ABAC condition that blocks assigning the built-in User Access Administrator role (and Owner, RBAC Admin). This is an IBM enterprise subscription policy applied to the `SUB-*_Owner` Entra group.

**This project handles it automatically** by using a custom role instead of UAA. If you are seeing this error, you may be running an older version of this file that still references `role_definition_name = "User Access Administrator"`. Pull the latest version and re-apply.

### Role Assignment Errors in Stage B

If Stage B encounters "AuthorizationFailed" errors when creating role assignments:

**Error Message:**
```
Error: The client does not have authorization to perform action
'Microsoft.Authorization/roleAssignments/write' over scope...
```

**Root Cause:** The infrastructure team service principal needs the `${prefix}-infra-role-delegator` custom role to create role assignments. This is granted by Stage A.

**Solution:** Ensure you've applied the latest version of Stage A before running Stage B:

```bash
# In 02-sec-stage-A directory
terraform plan   # Verify the custom role and its assignments will be created
terraform apply  # Apply the changes
```

**What Gets Fixed:** After applying, the infrastructure SP can create role assignments in Stage B for:
- AcrPull access for SFTP VMs and AKS
- AGIC permissions (Application Gateway, Resource Group, Subnet)
- Key Vault access for MFT identity
- Key Vault Administrator for Terraform

## Next Steps

After completing this stage:

1. **Infrastructure Team** can proceed with the Stage B infrastructure stack using:
   - Infrastructure team service principal credentials
   - Resource group names
   - Managed identity IDs for later federated credential and RBAC configuration

2. **DevOps/Application Team** can later proceed with Stage C using:
   - Azure DevOps service principal credentials
   - Service Delivery resource group details

3. **Security Team** may need to:
   - Add or review additional grants requested by later stages
   - Review secret rotation for both service principals
   - Review managed identity usage and lifecycle

## Cleanup

To destroy all resources created by this project:

```bash
terraform destroy
```

**WARNING**: This will delete the service principal and resource groups. Ensure the infrastructure team is not actively using these resources.

## Conventions

This project follows the conventions documented in `../CONVENTIONS.md`:

- Resource naming uses the `${prefix}` pattern
- First letter of prefix indicates environment type (v=vanilla, d=dev, e=pre-prod, p=prod, t=test)
- All resource names use lowercase letters and hyphens
