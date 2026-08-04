# Pipeline Setup Guide

This guide walks you through setting up the Azure DevOps pipelines for building container images.

## Prerequisites

Before setting up the pipelines, ensure you have:

1. **Azure Subscription** with appropriate permissions
2. **Azure DevOps Organization** with project admin access
3. **IBM WebMethods Container Registry Credentials**
4. **Terraform** installed (v1.0+)
5. **Azure CLI** installed and authenticated
6. **Git** repository access

## Setup Steps

### Step 1: Deploy Infrastructure with Terraform

Navigate to the Terraform project directory:

```bash
cd /aio/work/c/iwcd/6o-mft-on-azure-example/01-AzurePrerequisites/01-ServiceDelivery
```

#### 1.1: Create `terraform.tfvars`

Create a `terraform.tfvars` file with your configuration:

```hcl
# Core Azure Configuration
resource_group_name = "rg-mft-example"
location            = "eastus"
prefix              = "mftex"

# Azure DevOps Configuration
azdo_org_service_url = "https://dev.azure.com/your-org"
azdo_project_name    = "MFT-on-Azure"
azdo_agent_pool_name = "MFT-Agents"
azdo_pat             = "your-azdo-pat-token"

# Service Principal for Azure Connection
azdo_service_principal_id  = "your-sp-app-id"
azdo_service_principal_key = "your-sp-secret"
azdo_subscription_name     = "Your Azure Subscription Name"

# GitHub Configuration
github_pat = "your-github-pat-token"

# Optional: IBM WebMethods ACR URL (defaults to ibmwebmethods.azurecr.io)
# ibm_webmethods_acr_url = "ibmwebmethods.azurecr.io"

# Optional: Key Vault allowed IPs
# key_vault_allowed_ips = ["93.46.33.151"]
```

#### 1.2: Initialize and Apply Terraform

```bash
# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply the configuration
terraform apply
```

#### 1.3: Save Important Outputs

After successful apply, save these outputs for later use:

```bash
# Save ACR admin password
terraform output -raw acr_admin_password > acr-password.txt

# Save storage account key
terraform output -raw images_storage_account_key > storage-key.txt

# Display setup instructions
terraform output secure_files_instructions
```

### Step 2: Upload Secure Files to Azure DevOps

Navigate to your Azure DevOps project:

```
https://dev.azure.com/{your-org}/{project-name}/_settings/adminservices
```

Then go to: **Pipelines → Secure files**

#### 2.1: Upload `ibm-webmethods-acr.env`

Create a file named `ibm-webmethods-acr.env` with your IBM credentials:

```bash
IBM_WM_CR_USERNAME=your_ibm_username
IBM_WM_CR_PASSWORD=your_ibm_password
```

Upload this file and **enable "Authorize for use in all pipelines"**.

#### 2.2: Upload `destination-acr.env`

Create a file named `destination-acr.env`:

```bash
# Get username from Terraform
terraform output -raw acr_admin_username

# Get password from saved file or Terraform
cat acr-password.txt
# OR
terraform output -raw acr_admin_password
```

Create the file:

```bash
DEST_CR_USERNAME=<username-from-above>
DEST_CR_PASSWORD=<password-from-above>
```

Upload this file and **enable "Authorize for use in all pipelines"**.

#### 2.3: Upload `sa.share.secrets.sh`

Create a file named `sa.share.secrets.sh`:

```bash
# Get values from Terraform
terraform output images_storage_account_name
terraform output images_storage_share_name

# Get key from saved file or Terraform
cat storage-key.txt
# OR
terraform output -raw images_storage_account_key
```

Create the file:

```bash
STORAGE_ACCOUNT_NAME=<storage-account-name>
SHARE_NAME=<share-name>
STORAGE_ACCOUNT_KEY=<storage-account-key>
```

Upload this file and **enable "Authorize for use in all pipelines"**.

### Step 3: Verify Pipeline Configuration

#### 3.1: Check Variable Group

Navigate to: **Pipelines → Library → Variable groups**

Verify the `Pipeline-Configuration` variable group exists with:
- `AGENT_POOL_NAME`
- `IBM_WEBMETHODS_CONTAINERS_ACR`
- `DESTINATION_ACR`

#### 3.2: Check Pipeline Definition

Navigate to: **Pipelines → Pipelines**

You should see the `ActiveTransfer-Ingest` pipeline under the "Container Images" folder.

### Step 4: Run First Pipeline Build

#### 4.1: Manual Trigger

1. Navigate to the `ActiveTransfer-Ingest` pipeline
2. Click "Run pipeline"
3. Select branch: `main` or `develop`
4. Click "Run"

#### 4.2: Monitor Build

Watch the build progress and check for:
- ✅ Successful login to both registries
- ✅ Base image pull completes
- ✅ Image build succeeds
- ✅ Image push succeeds
- ✅ Artifacts saved to storage account

#### 4.3: Verify Artifacts

Check the storage account for build artifacts:

```bash
# Using Azure CLI
az storage file list \
  --account-name <storage-account-name> \
  --share-name <share-name> \
  --path "artifacts/$(date +%Y)/$(date +%m)/$(date +%d)/ingest-at" \
  --account-key <storage-account-key>
```

Or mount the share locally:

```bash
# Linux/macOS
sudo mkdir -p /mnt/artifacts
sudo mount -t cifs //<storage-account-name>.file.core.windows.net/<share-name> /mnt/artifacts \
  -o vers=3.0,username=<storage-account-name>,password=<storage-account-key>,dir_mode=0777,file_mode=0777

# Navigate to today's artifacts
cd /mnt/artifacts/artifacts/$(date +%Y)/$(date +%m)/$(date +%d)/ingest-at

# Unmount when done
sudo umount /mnt/artifacts
```

### Step 5: Verify Image in ACR

Check that the image was pushed successfully:

```bash
# Get ACR login server
terraform output acr_login_server

# Login to ACR
az acr login --name <acr-name>

# List images
az acr repository list --name <acr-name>

# List tags for active-transfer-ingest
az acr repository show-tags --name <acr-name> --repository active-transfer-ingest
```

You should see:
- A versioned tag: `11.1.0.4-YYYYMMDD-{commit-sha}`
- A `latest` tag (if built from main branch)

## Troubleshooting

### Issue: Terraform Apply Fails

**Error**: "Error creating Azure DevOps project"

**Solution**:
1. Verify Azure DevOps PAT has correct permissions:
   - Project: Read, write, & manage
   - Agent Pools: Read & manage
   - Build: Read & execute
   - Service Connections: Read, query, & manage
2. Check PAT is not expired
3. Verify organization URL is correct

### Issue: Secure File Upload Fails

**Error**: "File already exists"

**Solution**:
1. Delete existing file in Azure DevOps UI
2. Re-upload with correct content
3. Ensure "Authorize for use in all pipelines" is enabled

### Issue: Pipeline Fails at Login Step

**Error**: "unauthorized: authentication required"

**Solution**:
1. Verify secure file content is correct (no extra spaces, newlines)
2. Check credentials are valid
3. Ensure secure file is authorized for pipeline use
4. Verify variable group values are correct

### Issue: Storage Mount Fails

**Error**: "mount error(13): Permission denied"

**Solution**:
1. Verify storage account key is correct
2. Check storage account firewall rules
3. Ensure agent pool subnet has access
4. Verify SMB 3.0 is supported on agent

### Issue: Image Build Fails

**Error**: "failed to solve with frontend dockerfile.v0"

**Solution**:
1. Check Dockerfile syntax
2. Verify build arguments are passed correctly
3. Ensure base image exists and is accessible
4. Review build logs for specific error

## Maintenance

### Updating Base Image Version

To update the IBM ActiveTransfer base image version:

1. Edit `pipelines/azure/ingest-at.yaml`
2. Update `IBM_ACTIVE_TRANSFER_IMAGE_TAG` variable
3. Commit and push changes
4. Pipeline will trigger automatically

### Rotating Credentials

#### ACR Credentials

```bash
# Regenerate ACR admin password
az acr credential renew --name <acr-name> --password-name password

# Get new password
az acr credential show --name <acr-name>

# Update destination-acr.env in Azure DevOps Secure Files
```

#### Storage Account Key

```bash
# Regenerate storage account key
az storage account keys renew \
  --account-name <storage-account-name> \
  --key primary

# Get new key
az storage account keys list \
  --account-name <storage-account-name>

# Update sa.share.secrets.sh in Azure DevOps Secure Files
```

### Adding New Pipelines

To add additional container image pipelines:

1. Create new pipeline YAML in `pipelines/azure/`
2. Add pipeline definition in Terraform (`azdo-pipelines.tf`)
3. Run `terraform apply`
4. Upload any required secure files
5. Test the new pipeline

## Security Best Practices

1. **Rotate credentials regularly** (every 90 days recommended)
2. **Use separate credentials** for each environment (dev/staging/prod)
3. **Enable Azure DevOps audit logging**
4. **Restrict agent pool access** to specific projects
5. **Use managed identities** where possible (future enhancement)
6. **Review pipeline permissions** regularly
7. **Enable branch protection** on main branch
8. **Require pull request reviews** before merging

## Next Steps

After successful setup:

1. **Configure branch policies** for main branch
2. **Set up additional pipelines** for other container images
3. **Implement vulnerability scanning** (Trivy)
4. **Add image signing** (cosign/notation)
5. **Configure notifications** (Teams/Slack)
6. **Document custom configurations** in your Dockerfile

## Support

For issues or questions:

1. Check [Pipeline README](../pipelines/azure/README.md)
2. Review Azure DevOps pipeline logs
3. Check Terraform state and outputs
4. Consult Azure DevOps documentation

---

**Last Updated**: 2026-05-12
