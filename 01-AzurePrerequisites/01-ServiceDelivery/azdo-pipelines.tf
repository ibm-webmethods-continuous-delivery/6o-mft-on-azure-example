# Azure DevOps Pipeline Definitions
# Defines build pipelines for container images from external GitHub repository

resource "azuredevops_build_definition" "ingest_at" {
  project_id = azuredevops_project.main.id
  name       = "ActiveTransfer-Ingest"
  path       = "\\Container Images"

  ci_trigger {
    use_yaml = true
  }

  repository {
    repo_type             = "GitHub"
    repo_id               = var.github_repository
    branch_name           = "refs/heads/${var.github_branch}"
    yml_path              = "pipelines/azure/ingest-at.yaml"
    service_connection_id = azuredevops_serviceendpoint_github.github.id
  }
}

resource "azuredevops_build_definition" "enhance_at" {
  project_id = azuredevops_project.main.id
  name       = "ActiveTransfer-Enhance"
  path       = "\\Container Images"

  ci_trigger {
    use_yaml = true
  }

  repository {
    repo_type             = "GitHub"
    repo_id               = var.github_repository
    branch_name           = "refs/heads/${var.github_branch}"
    yml_path              = "pipelines/azure/enhance-at.yaml"
    service_connection_id = azuredevops_serviceendpoint_github.github.id
  }
}