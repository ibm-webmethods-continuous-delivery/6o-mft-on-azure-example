# Azure DevOps Pipelines

This directory contains Azure DevOps pipeline definitions for building and managing container images.

## Available Pipelines

### ActiveTransfer Ingest Pipeline (`ingest-at.yaml`)

Builds and pushes the ActiveTransfer ingest container image to the destination Azure Container Registry.

#### Purpose

This pipeline automates the build process for the ActiveTransfer ingest image, which is based on the IBM WebMethods ActiveTransfer base image with custom configurations for ingestion workflows.

#### Trigger Conditions

The pipeline triggers automatically on:

1. **Push/PR to main or develop branches** when changes are made to:
   - `02-ContainerImages/01-active-transfer-ingest/**`

2. **Scheduled builds**:
   - Monthly on the 3rd of every month at 03:03 UTC
   - Ensures images are rebuilt regularly even without code changes

#### Variables

The pipeline uses the following variables from the `Pipeline-Configuration` variable group:

- `AGENT_POOL_NAME`: Name of the Azure DevOps agent pool (set by Terraform)
- `IBM_WEBMETHODS_CONTAINERS_ACR`: IBM WebMethods container registry URL (default: `ibmwebmethods.azurecr.io`)
- `DESTINATION_ACR`: Destination Azure Container Registry URL (set by Terraform)

Pipeline-specific variables:

- `IBM_ACTIVE_TRANSFER_IMAGE`: Base image name (`ibmwebmethods.azurecr.io/webmethods-activetransfer`)
- `IBM_ACTIVE_TRANSFER_IMAGE_TAG`: Base image tag (e.g., `11.1.0.4`)
- `DEST_IMAGE_NAME`: Destination image name (`active-transfer-ingest`)
- `BUILD_CONTEXT`: Build context path (`02-ContainerImages/01-active-transfer-ingest`)

#### Build Process

1. **Credential Management**
   - Downloads secure files containing registry credentials
   - Logs into IBM WebMethods ACR (source)
   - Logs into Destination ACR (target)

2. **Image Pull Optimization**
   - Pulls the base image early to leverage Docker layer caching
   - Reduces build time for subsequent builds

3. **Image Build**
   - Builds the image with build arguments:
     - `__active_transfer_ibm_image`: Base image name
     - `__active_transfer_ibm_image_tag`: Base image tag
   - Tags with format: `{base_tag}-{YYYYMMDD}-{commit_sha}`
   - Example: `11.1.0.4-20260512-abc123d`

4. **Image Push**
   - Pushes the versioned tag to destination ACR
   - For main branch: Also tags and pushes as `latest`

5. **Artifact Storage**
   - Mounts Azure Storage Account file share
   - Saves build metadata to: `/artifacts/{YYYY}/{MM}/{DD}/ingest-at/{BuildId}-{BuildNumber}/`
   - Stores:
     - `build-info.json`: Complete build metadata
     - `dockerfile-used.txt`: Copy of the Dockerfile used
     - `build-summary.txt`: Human-readable build summary
   - Unmounts storage account (always runs, even on failure)

#### Artifact Storage Structure

```
/artifacts/
└── {YYYY}/
    └── {MM}/
        └── {DD}/
            └── ingest-at/
                └── {BuildId}-{BuildNumber}/
                    ├── build-info.json
                    ├── dockerfile-used.txt
                    └── build-summary.txt
```

#### Required Secure Files

The following secure files must be uploaded via Azure DevOps UI:

1. **ibm-webmethods-acr.env**
   ```
   IBM_WM_CR_USERNAME=your_username
   IBM_WM_CR_PASSWORD=your_password
   ```

2. **destination-acr.env**
   ```
   DEST_CR_USERNAME=admin_username
   DEST_CR_PASSWORD=admin_password
   ```

3. **sa.share.secrets.sh**
   ```
   STORAGE_ACCOUNT_NAME=storage_account_name
   SHARE_NAME=share_name
   STORAGE_ACCOUNT_KEY=storage_account_key
   ```

See [Pipeline Setup Guide](../../docs/pipeline-setup.md) for detailed instructions.

#### Troubleshooting

##### Build Fails: "unauthorized: authentication required"

**Cause**: Invalid or missing registry credentials

**Solution**:
1. Verify secure files are uploaded correctly
2. Check credentials in secure files are valid
3. Ensure secure files are authorized for pipeline use

##### Build Fails: "Error response from daemon: pull access denied"

**Cause**: Cannot pull base image from IBM registry

**Solution**:
1. Verify IBM registry credentials are correct
2. Check network connectivity from build agent
3. Verify base image name and tag are correct

##### Build Fails: "mount error(13): Permission denied"

**Cause**: Cannot mount storage account

**Solution**:
1. Verify storage account credentials in `sa.share.secrets.sh`
2. Check storage account firewall rules allow agent pool subnet
3. Verify storage account key is valid

##### Build Succeeds but No Artifacts Saved

**Cause**: Storage mount succeeded but write failed

**Solution**:
1. Check storage account quota
2. Verify file share permissions
3. Review build logs for specific error messages

##### Pipeline Doesn't Trigger on Code Changes

**Cause**: Path filter not matching changed files

**Solution**:
1. Verify changes are in `02-ContainerImages/01-active-transfer-ingest/`
2. Check branch is `main` or `develop`
3. Review Azure DevOps pipeline trigger settings

#### Local Testing

You can test the build locally using the provided build script:

```bash
cd /aio/work/c/iwcd/6o-mft-on-azure-example/02-ContainerImages/01-active-transfer-ingest

# Set environment variables (optional, defaults are provided)
export IBM_ACTIVE_TRANSFER_IMAGE="ibmwebmethods.azurecr.io/webmethods-activetransfer"
export IBM_ACTIVE_TRANSFER_IMAGE_TAG="11.1.0.4"
export DEST_IMAGE="active-transfer-ingest"

# Run build
./build.sh
```

#### Maintenance

- **Update Base Image Version**: Modify `IBM_ACTIVE_TRANSFER_IMAGE_TAG` variable in pipeline YAML
- **Change Destination Image Name**: Modify `DEST_IMAGE_NAME` variable in pipeline YAML
- **Update Build Context**: Modify `BUILD_CONTEXT` variable and trigger paths

#### Security Considerations

- All credentials are stored in Azure DevOps Secure Files
- Credentials are never logged or exposed in build output
- Storage account is unmounted after artifact storage (always runs)
- Admin credentials for ACR should be rotated regularly

#### Future Enhancements

Planned for future sessions:

- Trivy vulnerability scanning
- Trivy secret scanning
- CycloneDX SBOM generation
- Hadolint Dockerfile linting
- Image signing (cosign/notation)
- Advanced notifications (Teams, Slack)

---

**Last Updated**: 2026-05-12
