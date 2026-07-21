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


## Secure File Permissions

### Manual Process Required

**Important**: Secure file permissions **CANNOT** be automated with Terraform due to Azure DevOps provider limitations.

### Upload Secure Files (One-Time)

1. Navigate to: **Azure DevOps → Project → Pipelines → Library → Secure files**
2. Upload the required files (see `secure_files_instructions` output for content format):
   - `ibm-webmethods-acr.env` - IBM WebMethods ACR credentials
   - `destination-acr.env` - Destination ACR credentials
   - `sa.share.secrets.sh` - Storage Account secrets for artifacts share

### Grant Pipeline Permissions (Per Pipeline)

For each pipeline that needs secure file access:

1. Navigate to: **Azure DevOps → Project → Pipelines → Library → Secure files**
2. Click on each secure file (e.g., `ibm-webmethods-acr.env`)
3. Go to **"Pipeline permissions"** tab
4. Click **"+"** button
5. Select the pipeline (e.g., `ActiveTransfer-Ingest`, `ActiveTransfer-Enhance`)
6. Click **"Save"**
7. Repeat for all secure files (3 files per pipeline)

### Checklist for New Pipelines

When adding a new pipeline:
- [ ] Add pipeline definition in `azdo-pipelines.tf`
- [ ] Run `terraform apply -var-file=terraform.tfvars`
- [ ] Grant secure file permissions manually via Azure DevOps UI:
  - [ ] `ibm-webmethods-acr.env`
  - [ ] `destination-acr.env`
  - [ ] `sa.share.secrets.sh`
- [ ] Test pipeline run

### Why Manual?

The Azure DevOps Terraform provider does not support:
- `azuredevops_securefile` data source (cannot look up secure files)
- `azuredevops_resource_authorization` for secure files (requires data source)

This is a known provider limitation. Permissions must be granted via the Azure DevOps UI or REST API.


## Architecture: GitHub Integration

This configuration creates a **service connection** to GitHub, allowing Azure Pipelines to access your GitHub repositories directly:



## Agent Pool Configuration Strategy

### Overview

This Terraform configuration supports a flexible agent pool architecture that separates **pool creation** from **pipeline execution**:

1. **Terraform-Created Pool**: Standard agent pool created by Terraform
2. **VMSS-Backed Pool**: Manually created pool with VMSS integration (Terraform limitation)
3. **Pipeline-Specific Pools**: Each pipeline can use a different pool

### Why Two Agent Pool Concepts?

**The Challenge**: Azure DevOps Terraform provider cannot create agent pools that are backed by Virtual Machine Scale Sets (VMSS). This requires manual configuration or Azure CLI.

**The Solution**: Separate pool creation from pool usage:

```
┌─────────────────────────────────────────────────────────────┐
│ Terraform Creates (Standard Pool)                           │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ Agent Pool: EniPMftDemoVmssAgents                       │ │
│ │ - Created by: azuredevops_agent_pool.main               │ │
│ │ - Variable: azdo_agent_pool_name                        │ │
│ │ - Purpose: Pool object for VMSS association             │ │
│ └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Manual Exception Creates (VMSS-Backed Pool)                 │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ Agent Pool: EniPDemoAgentsPool                          │ │
│ │ - Created: Manually or via Azure CLI                    │ │
│ │ - Variables: ingest_pipeline_agent_pool_name            │ │
│ │              enhance_pipeline_agent_pool_name           │ │
│ │ - Purpose: Actual pool used by pipelines                │ │
│ └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### Configuration Variables

#### Pool Creation
```hcl
# Creates the agent pool object (for VMSS association)
azdo_agent_pool_name = "EniPMftDemoVmssAgents"
```

#### Pipeline Execution
```hcl
# Pool used by ingest pipeline (defaults to azdo_agent_pool_name if not set)
ingest_pipeline_agent_pool_name = "EniPDemoAgentsPool"

# Pool used by enhance pipeline (defaults to ingest pool, then azdo_agent_pool_name)
enhance_pipeline_agent_pool_name = "EniPDemoAgentsPool"  # or different pool
```

### Variable Resolution Flow

The configuration uses a fallback chain for pipeline agent pools:

```
enhance_pipeline_agent_pool_name (if set)
  ↓ (if null)
ingest_pipeline_agent_pool_name (if set)
  ↓ (if null)
azdo_agent_pool_name (always set)
```

This allows:
- **Simple Setup**: Omit pipeline-specific variables to use the Terraform-created pool
- **VMSS Integration**: Set pipeline variables to use manually-created VMSS-backed pools
- **Per-Pipeline Pools**: Use different pools for different pipelines if needed

### Variable Group Mapping

The Terraform configuration creates these variables in the `Pipeline-Configuration` variable group:

| Variable Group Variable | Source | Purpose |
|------------------------|--------|---------|
| `AGENT_POOL_NAME` | `azdo_agent_pool_name` | Terraform-created pool (for reference) |
| `INGEST_PIPELINE_AGENT_POOL` | `ingest_pipeline_agent_pool_name` | Pool for ingest pipeline |
| `ENHANCE_PIPELINE_AGENT_POOL` | `enhance_pipeline_agent_pool_name` | Pool for enhance pipeline |

### Pipeline YAML Usage

Pipelines reference the appropriate variable:

```yaml
# ingest-at.yaml
pool:
  name: $(INGEST_PIPELINE_AGENT_POOL)

# enhance-at.yaml
pool:
  name: $(ENHANCE_PIPELINE_AGENT_POOL)
```

### Manual VMSS-Backed Pool Creation

After Terraform deployment, create the VMSS-backed pool manually:

```bash
# Using Azure CLI (requires Azure DevOps extension)
az devops configure --defaults organization=https://dev.azure.com/yourorg project=YourProject

# Create VMSS-backed agent pool
az pipelines pool create \
  --name "EniPDemoAgentsPool" \
  --pool-type vmss \
  --vmss-resource-id "/subscriptions/.../resourceGroups/.../providers/Microsoft.Compute/virtualMachineScaleSets/..." \
  --service-endpoint-id "..."
```

Or use the Azure DevOps web UI:
1. Navigate to Project Settings → Agent pools
2. Click "Add pool"
3. Select "Azure virtual machine scale set"
4. Configure VMSS integration

### Example Configuration

**Scenario**: Use VMSS-backed pool for all pipelines

```hcl
# terraform.tfvars
azdo_agent_pool_name            = "EniPMftDemoVmssAgents"  # Terraform creates this
ingest_pipeline_agent_pool_name = "EniPDemoAgentsPool"     # Manually created VMSS pool
# enhance_pipeline_agent_pool_name not set, will use ingest pool
```

**Result**:
- Terraform creates standard pool: `EniPMftDemoVmssAgents`
- You manually create VMSS pool: `EniPDemoAgentsPool`
- Both pipelines use: `EniPDemoAgentsPool`


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
