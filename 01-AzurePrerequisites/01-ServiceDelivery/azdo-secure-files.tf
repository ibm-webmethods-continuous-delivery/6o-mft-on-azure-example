# Azure DevOps Secure Files
# Defines secure file placeholders that must be uploaded via Azure DevOps UI

resource "azuredevops_securefile" "ibm_acr_credentials" {
  project_id  = azuredevops_project.main.id
  name        = "ibm-webmethods-acr.env"
  description = "IBM WebMethods ACR credentials - Upload via UI after terraform apply"
}

resource "azuredevops_securefile" "destination_acr_credentials" {
  project_id  = azuredevops_project.main.id
  name        = "destination-acr.env"
  description = "Destination ACR credentials - Upload via UI after terraform apply"
}

resource "azuredevops_securefile" "storage_account_secrets" {
  project_id  = azuredevops_project.main.id
  name        = "sa.share.secrets.sh"
  description = "Storage Account secrets for artifacts share - Upload via UI after terraform apply"
}
