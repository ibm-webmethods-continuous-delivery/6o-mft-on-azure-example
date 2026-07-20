#Requires -Version 5.1
<#
.SYNOPSIS
    Validate that all required MFT secrets exist in Azure Key Vault

.DESCRIPTION
    Validates that all required MFT secrets exist in Azure Key Vault

.PARAMETER Environment
    Environment name (optional, defaults from Terraform)

.EXAMPLE
    .\validate-secrets.ps1
    .\validate-secrets.ps1 dev
#>

param(
    [Parameter(Position=0)]
    [string]$Environment
)

$ErrorActionPreference = 'Stop'

# Get script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$TfDir = Join-Path $ScriptDir "..\..\01-AzurePrerequisites\02-ServiceFulfillment"

# Helper functions for colored output
function Write-Info {
    param([string]$Message)
    Write-Host "ℹ $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Error {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

function Write-Warning {
    param([string]$Message)
    Write-Host "⚠ $Message" -ForegroundColor Yellow
}

# Check if Azure CLI is available
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Error "Azure CLI not found. Please install Azure CLI."
    exit 1
}

# Check if logged in
try {
    az account show --output none 2>$null
} catch {
    Write-Error "Not logged in to Azure. Please run: az login"
    exit 1
}

# Get environment from argument or Terraform
if (-not $Environment) {
    if (Test-Path $TfDir) {
        Push-Location $TfDir
        try {
            $tfOutput = terraform output -json 2>$null | ConvertFrom-Json
            $Environment = $tfOutput.environment_name.value
            if (-not $Environment) {
                $Environment = "vanilla"
            }
        } catch {
            $Environment = "vanilla"
        }
        Pop-Location
    } else {
        $Environment = "vanilla"
    }
}

# Get Key Vault name from Terraform
if (Test-Path $TfDir) {
    Push-Location $TfDir
    try {
        $tfOutput = terraform output -json 2>$null | ConvertFrom-Json
        $KvName = $tfOutput.key_vault_name.value
    } catch {
        $KvName = $null
    }
    Pop-Location

    if (-not $KvName) {
        Write-Error "Could not retrieve Key Vault name from Terraform."
        Write-Info "Please ensure Terraform has been applied in: $TfDir"
        exit 1
    }
} else {
    Write-Error "Terraform directory not found: $TfDir"
    exit 1
}

Write-Info "Environment: $Environment"
Write-Info "Key Vault: $KvName"
Write-Host ""

# Define required secrets
$RequiredDbSecrets = @(
    "postgres-server-fqdn",
    "postgres-online-db",
    "postgres-archive-db",
    "postgres-admin-user",
    "postgres-admin-password",
    "postgres-online-user",
    "postgres-online-password",
    "postgres-archive-user",
    "postgres-archive-password"
)

$RequiredAppSecrets = @(
    "admin-password",
    "config-json"
)

$RequiredCertSecrets = @(
    "admin-ui-keystore-password",
    "admin-ui-truststore-password",
    "web-client-keystore-password",
    "web-client-truststore-password",
    "sftp-ssh-private-key"
)

# Validation counters
$script:Total = 0
$script:Found = 0
$script:Missing = 0

function Test-Secret {
    param([string]$SecretName)

    $script:Total++

    try {
        az keyvault secret show --vault-name $KvName --name $SecretName --output none 2>$null
        Write-Success $SecretName
        $script:Found++
        return $true
    } catch {
        Write-Error "$SecretName (MISSING)"
        $script:Missing++
        return $false
    }
}

# Validate database secrets
Write-Host "Validating Database Secrets (mft-db-*):"
Write-Host "=========================================="
foreach ($secret in $RequiredDbSecrets) {
    Test-Secret "$Environment-mft-db-$secret"
}

Write-Host ""
Write-Host "Validating Application Secrets (mft-*):"
Write-Host "=========================================="
foreach ($secret in $RequiredAppSecrets) {
    Test-Secret "$Environment-mft-$secret"
}

Write-Host ""
Write-Host "Validating Certificate Secrets (mft-*):"
Write-Host "=========================================="
foreach ($secret in $RequiredCertSecrets) {
    Test-Secret "$Environment-mft-$secret"
}

# Summary
Write-Host ""
Write-Host "=========================================="
Write-Host "Validation Summary:"
Write-Host "=========================================="
Write-Info "Total secrets checked: $script:Total"
Write-Success "Found: $script:Found"

if ($script:Missing -gt 0) {
    Write-Error "Missing: $script:Missing"
    Write-Host ""
    Write-Warning "Some required secrets are missing!"
    Write-Info "Run Terraform apply to create missing secrets:"
    Write-Info "  cd $TfDir"
    Write-Info "  terraform apply"
    exit 1
} else {
    Write-Host ""
    Write-Success "All required secrets are present!"
    exit 0
}

# Made with Bob
