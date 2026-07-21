# Azure DevOps Secure Files
# NOTE: The azuredevops_securefile resource type is not supported by the Azure DevOps provider.
# Secure files must be uploaded manually via the Azure DevOps UI.
#
# After running terraform apply, navigate to:
# Azure DevOps Project → Pipelines → Library → Secure files
#
# Upload the following files manually:
# 1. ibm-webmethods-acr.env - IBM WebMethods ACR credentials
# 2. destination-acr.env - Destination ACR credentials
# 3. sa.share.secrets.sh - Storage Account secrets for artifacts share
#
# See the 'secure_files_instructions' output for detailed content format.
