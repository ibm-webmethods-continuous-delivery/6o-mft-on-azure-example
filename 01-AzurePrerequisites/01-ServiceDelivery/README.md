# Azure DevOps Service Delivery - Quick Start

## Prerequisites

1. Azure service principal with Contributor access
2. Azure DevOps Personal Access Token (PAT) with scopes:
   - Agent Pools: Read & manage
   - Project and Team: Read, write, & manage
   - Service Connections: Read, query, & manage
3. GitHub Personal Access Token (PAT) with scopes:
   - `repo` - Full control of private repositories (required for importing)

## Quick Start

### 1. Configure Variables

```sh
# Copy example and edit with your values
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your organization details
```

### 2. Set Credentials (No History)

Make a temporary file and source these variables, this way they will not remain in the history:

```sh
# Azure credentials
export ARM_CLIENT_ID="your-sp-id"
export ARM_CLIENT_SECRET="your-sp-secret"
export ARM_SUBSCRIPTION_ID="your-sub-id"
export ARM_TENANT_ID="your-tenant-id"

# Azure DevOps credentials (BOTH required)
export AZDO_PERSONAL_ACCESS_TOKEN="your-pat-token"
export TF_VAR_azdo_pat="your-pat-token"
export TF_VAR_azdo_service_principal_id="$ARM_CLIENT_ID"
export TF_VAR_azdo_service_principal_key="$ARM_CLIENT_SECRET"

# GitHub credentials
export TF_VAR_github_pat="your-github-pat-token"
```

### 3. Deploy

```sh
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

### 4. Scale VMSS (After Deployment, az cli example)

```sh
# Scale to desired capacity to register agents
az vmss scale \
  --name <vmss-name-from-output> \
  --resource-group <your-rg-name> \
  --new-capacity 2
```

### 5. Clean Up Credentials

```sh
# Unset all sensitive variables
unset ARM_CLIENT_ID ARM_CLIENT_SECRET ARM_SUBSCRIPTION_ID ARM_TENANT_ID
unset AZDO_PERSONAL_ACCESS_TOKEN TF_VAR_azdo_pat
unset TF_VAR_azdo_service_principal_id TF_VAR_azdo_service_principal_key
unset TF_VAR_github_pat

# Clear recent history (bash)
history -d $(history 1)
```

## Troubleshooting

**Error: "You are not authorized to access Azure DevOps Organization"**
- Ensure `AZDO_PERSONAL_ACCESS_TOKEN` is set (not just `TF_VAR_azdo_pat`)
- Verify PAT has organization-level access and correct scopes

**Agents not appearing in pool**
- Wait 5-10 minutes after scaling VMSS
- Check VMSS extension logs: `/var/log/azure/custom-script/handler.log`

## Resources Created

- Azure DevOps project with Git, pipelines, boards, artifacts
- Azure DevOps agent pool (self-hosted)
- Azure DevOps service connection (Azure RM)
- Azure DevOps service connection (GitHub)
- Git repository imported from GitHub
- VMSS with auto-configured agents
- Virtual network, subnet, NSG
- Storage account with file share
- Key Vault
- Azure Container Registry

## GitHub Integration

The Terraform configuration now includes automatic GitHub repository import:

- **GitHub Service Endpoint**: Creates a service connection to GitHub using your PAT
- **Repository Import**: Imports the specified GitHub repository into the Azure DevOps project
- **Configuration**: Set `github_repo_url` in `terraform.tfvars` to your GitHub repository URL

This ensures the Azure DevOps project Git repository is synchronized with your GitHub repository.
