# Azure DevOps Service Delivery - Quick Start

## Prerequisites

1. Azure service principal with Contributor access
2. Azure DevOps Personal Access Token (PAT) with scopes:
   - Agent Pools: Read & manage
   - Project and Team: Read, write, & manage
   - Service Connections: Read, query, & manage
3. GitHub Personal Access Token (PAT) with **required** scopes:
   - `repo` - Full control of private repositories (read/write access to code, commit statuses, deployments, etc.)
   - `admin:repo_hook` - Full control of repository hooks (required for webhook management by Azure Pipelines)

   **Note**: These scopes allow Azure Pipelines to:
   - Clone and access repository content during pipeline runs
   - Update commit statuses (e.g., build success/failure)
   - Create and manage webhooks for CI/CD triggers
   - Access repository metadata

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
```

## Resources Created

- Azure DevOps project with Git, pipelines, boards, artifacts
- Azure DevOps agent pool (self-hosted)
- Azure DevOps service connection (Azure RM)
- Azure DevOps service connection (GitHub)
- VMSS with auto-configured agents
- Virtual network, subnet, NSG
- Storage account with file share
- Key Vault
- Azure Container Registry

## Architecture: GitHub Integration

This configuration creates a **service connection** to GitHub, allowing Azure Pipelines to access your GitHub repositories directly:

- **GitHub Service Endpoint**: Creates a service connection to GitHub using your PAT
- **No Repository Cloning**: The GitHub repository is NOT imported or cloned into Azure DevOps
- **Source of Truth**: GitHub remains the single source of truth for your code
- **Pipeline Integration**: Azure Pipelines will reference the GitHub repository directly via the service connection
- **Webhook Support**: The service connection enables Azure DevOps to create webhooks in GitHub for CI/CD triggers

### How It Works

1. **Service Connection**: The `azuredevops_serviceendpoint_github` resource creates a connection to GitHub
2. **Pipeline Configuration**: When you create Azure Pipelines (YAML or Classic), you'll reference your GitHub repository using this service connection
3. **Triggers**: Pipelines can be triggered by GitHub events (push, pull request, etc.) via webhooks
4. **No Duplication**: Your code stays in GitHub; Azure DevOps only accesses it when pipelines run

### Azure DevOps Project Configuration

- **Version Control**: The project is configured with `version_control = "Git"` but **no repositories are created**
- **Purpose**: The project is used solely for:
  - Running CI/CD pipelines that reference GitHub repositories
  - Managing VMSS-based self-hosted agents
  - Storing pipeline definitions (if not stored in GitHub)
  - Managing work items, boards, and artifacts

### Next Steps After Deployment

1. Create Azure Pipelines (YAML or Classic) that reference your GitHub repository
2. Configure pipeline triggers (push, PR, scheduled, manual)
3. Use path filters to trigger specific pipelines based on changed folders (e.g., Dockerfiles, Helm charts)
4. Keep Terraform operations manual as a prerequisite assurance convenience
