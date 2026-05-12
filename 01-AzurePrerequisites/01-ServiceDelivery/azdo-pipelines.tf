# Azure DevOps Pipeline Definitions
# Defines build pipelines for container images

resource "azuredevops_build_definition" "ingest_at" {
  project_id = azuredevops_project.main.id
  name       = "ActiveTransfer-Ingest"
  path       = "\\Container Images"

  ci_trigger {
    use_yaml = true
  }

  repository {
    repo_type   = "TfsGit"
    repo_id     = azuredevops_git_repository.main.id
    branch_name = azuredevops_git_repository.main.default_branch
    yml_path    = "pipelines/azure/ingest-at.yaml"
  }
}
