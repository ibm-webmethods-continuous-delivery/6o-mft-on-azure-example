# Security Stage A - Prerequisites

This Terraform project creates the foundational Azure resources required before the infrastructure team can provision the MFT deployment resources.

## Purpose

The security team uses this project to:

1. **Create Resource Groups**: Two resource groups for organizing infrastructure resources
   - Service Delivery RG: For CI/CD infrastructure (ACR, Key Vault, Azure DevOps agents)
   - Service Fulfillment RG: For MFT runtime infrastructure (AKS, SFTP VMs, PostgreSQL, App Gateway)

2. **Create Infrastructure Team Service Principal**: A service principal with appropriate permissions for the infrastructure team to provision resources using Terraform

3. **Create MFT Workload Identity** (Optional): A user-assigned managed identity for MFT workloads running in AKS

## Resources Created

### Resource Groups

- **`${prefix}-s-delivery`**: Service Delivery resource group
- **`${prefix}-s-fulfillment`**: Service Fulfillment resource group

### Identities

- **Infrastructure Team Service Principal**: `${prefix}-infra-sp`
  - Azure AD Application
  - Service Principal with client secret
  - Contributor role on both resource groups
  - Valid for 1 year

- **MFT Workload Identity** (Optional): `${prefix}-mft-identity`
  - User-Assigned Managed Identity
  - Created in the Service Fulfillment resource group
  - Federated credentials to be added later when AKS OIDC issuer is available

## Prerequisites

1. **Azure CLI** installed and authenticated
2. **Terraform** >= 1.0 installed
3. **Permissions**: The user running this Terraform must have:
   - Ability to create resource groups in the subscription
   - Ability to create Azure AD applications and service principals
   - Ability to assign roles (User Access Administrator or Owner)

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

1. **Service Principal Credentials**:
   - Application (Client) ID
   - Client Secret
   - Tenant ID
   - Subscription ID

2. **Resource Group Names**:
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
| `create_mft_identity` | Whether to create MFT workload identity | `true` | No |
| `mft_identity_suffix` | Suffix for MFT identity name | `mft-identity` | No |
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
| `mft_identity_id` | MFT Identity Resource ID | No |
| `mft_identity_principal_id` | MFT Identity Principal ID | No |
| `mft_identity_client_id` | MFT Identity Client ID | No |
| `instructions` | Usage instructions for infrastructure team | No |

## Security Considerations

1. **Service Principal Secret Rotation**: The client secret is valid for 1 year. Plan to rotate it before expiration.

2. **State File Security**: The Terraform state file contains sensitive information (client secret). Store it securely:
   - Use remote state backend (Azure Storage with encryption)
   - Restrict access to the state file
   - Enable state locking

3. **Least Privilege**: The service principal has Contributor role on the two resource groups only, not on the entire subscription.

4. **Audit Trail**: All operations performed by the service principal can be tracked via Azure Activity Logs.

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

## Next Steps

After completing this stage:

1. **Infrastructure Team** can proceed with:
   - `01-azure-prerequisites/03-infra-stage-delivery/` - Service Delivery infrastructure
   - `01-azure-prerequisites/04-infra-stage-fulfillment/` - Service Fulfillment infrastructure

2. **Security Team** may need to:
   - Add federated credentials to MFT identity after AKS is created
   - Assign Key Vault permissions to MFT identity
   - Review and approve any additional permission requests

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
