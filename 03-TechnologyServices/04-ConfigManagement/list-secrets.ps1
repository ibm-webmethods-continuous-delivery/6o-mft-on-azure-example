#Requires -Version 5.1
<#
.SYNOPSIS
    List MFT secrets in Azure Key Vault

.DESCRIPTION
    Lists all MFT secrets in Azure Key Vault organized by category

.PARAMETER Environment
    Environment name (optional, defaults from Terraform)

.EXAMPLE
    .\list-secrets.ps1
    .\list-secrets.ps1 dev
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

# List all MFT secrets for the environment
Write-Info "Listing MFT secrets for environment: $Environment"
Write-Host "=========================================="

# Database secrets
Write-Host ""
Write-Info "Database Secrets (mft-db-*):"
try {
    $dbSecrets = az keyvault secret list --vault-name $KvName --query "[?starts_with(name, '$Environment-mft-db-')].{Name:name, Enabled:attributes.enabled, Expires:attributes.expires}" -o json 2>$null | ConvertFrom-Json
    if ($dbSecrets) {
        $dbSecrets | Format-Table -AutoSize
    } else {
        Write-Warning "No database secrets found"
    }
} catch {
    Write-Warning "No database secrets found"
}

# Application secrets
Write-Host ""
Write-Info "Application Secrets (mft-*):"
try {
    $appSecrets = az keyvault secret list --vault-name $KvName --query "[?starts_with(name, '$Environment-mft-') && !starts_with(name, '$Environment-mft-db-') && !starts_with(name, '$Environment-mft-cert-')].{Name:name, Enabled:attributes.enabled, Expires:attributes.expires}" -o json 2>$null | ConvertFrom-Json
    if ($appSecrets) {
        $appSecrets | Format-Table -AutoSize
    } else {
        Write-Warning "No application secrets found"
    }
} catch {
    Write-Warning "No application secrets found"
}

# Certificate secrets
Write-Host ""
Write-Info "Certificate Secrets (mft-cert-*):"
try {
    $certSecrets = az keyvault secret list --vault-name $KvName --query "[?starts_with(name, '$Environment-mft-cert-')].{Name:name, Enabled:attributes.enabled, Expires:attributes.expires}" -o json 2>$null | ConvertFrom-Json
    if ($certSecrets) {
        $certSecrets | Format-Table -AutoSize
    } else {
        Write-Warning "No certificate secrets found"
    }
} catch {
    Write-Warning "No certificate secrets found"
}

# Certificate objects
Write-Host ""
Write-Info "Certificate Objects:"
try {
    $certObjects = az keyvault certificate list --vault-name $KvName --query "[?starts_with(name, '$Environment-mft-')].{Name:name, Enabled:attributes.enabled, Expires:attributes.expires}" -o json 2>$null | ConvertFrom-Json
    if ($certObjects) {
        $certObjects | Format-Table -AutoSize
    } else {
        Write-Warning "No certificate objects found"
    }
} catch {
    Write-Warning "No certificate objects found"
}

Write-Host ""
Write-Success "Secret listing complete"

# Made with Bob
