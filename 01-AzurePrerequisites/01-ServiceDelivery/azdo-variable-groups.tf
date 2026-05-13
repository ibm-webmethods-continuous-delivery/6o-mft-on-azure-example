# Azure DevOps Variable Groups
# Provides common pipeline configuration variables

resource "azuredevops_variable_group" "pipeline_configuration" {
  project_id   = azuredevops_project.main.id
  name         = "Pipeline-Configuration"
  description  = "Common pipeline configuration variables for container image builds"
  allow_access = true

  variable {
    name  = "AGENT_POOL_NAME"
    value = azuredevops_agent_pool.main.name
  }

  variable {
    name  = "INGEST_PIPELINE_AGENT_POOL"
    value = local.ingest_pipeline_agent_pool_name
  }

  variable {
    name  = "ENHANCE_PIPELINE_AGENT_POOL"
    value = local.enhance_pipeline_agent_pool_name
  }

  variable {
    name  = "IBM_WEBMETHODS_CONTAINERS_ACR"
    value = var.ibm_webmethods_acr_url
  }

  variable {
    name  = "DESTINATION_ACR"
    value = azurerm_container_registry.main.login_server
  }
}
