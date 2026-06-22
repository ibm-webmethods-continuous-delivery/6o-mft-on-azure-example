#Requires -Version 5.1
<#
.SYNOPSIS
    View MFT secrets in Azure Key Vault with descriptions

.DESCRIPTION
    Displays detailed information about secrets including metadata, with optional value display

.PARAMETER Environment
    Environment name (optional, defaults from Terraform)

.PARAMETER ShowValues
    Display secret values (use with caution!)

.EXAMPLE
    .\view-at-vault-secrets.ps1
    .\view-at-vault-secrets.ps1 dev
    .\view-at-vault-secrets.ps1 dev -ShowValues
#>

param(
    [Parameter(Position=0)]
    [string]$Environment,

    [Parameter()]
    [switch]$ShowValues
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

function Write-Header {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Cyan
}

function Write-SecretName {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Magenta
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

# Get environment from Terraform if not provided
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
if ($ShowValues) {
    Write-Warning "Secret values will be displayed (use with caution!)"
}
Write-Host ""

# Function to display secret details
function Show-SecretDetails {
    param([string]$SecretName)

    try {
        $secretJson = az keyvault secret show --vault-name $KvName --name $SecretName -o json 2>$null | ConvertFrom-Json

        if (-not $secretJson) {
            Write-Error "Failed to retrieve secret: $SecretName"
            return
        }

        # Display secret name
        Write-SecretName "  $SecretName"

        # Display type
        if ($secretJson.contentType) {
            Write-Host "    Type: $($secretJson.contentType)" -ForegroundColor Cyan
        } else {
            Write-Host "    Type: text/plain" -ForegroundColor Cyan
        }

        # Display description
        if ($secretJson.tags.Description) {
            Write-Host "    Description: $($secretJson.tags.Description)" -ForegroundColor Cyan
        } else {
            Write-Host "    Description: (none)" -ForegroundColor Cyan
        }

        # Display enabled status
        Write-Host "    Enabled: $($secretJson.attributes.enabled)" -ForegroundColor Cyan

        # Display expiration
        if ($secretJson.attributes.expires) {
            Write-Host "    Expires: $($secretJson.attributes.expires)" -ForegroundColor Cyan
        }

        # Display value if requested
        if ($ShowValues -and $secretJson.value) {
            $valueLength = $secretJson.value.Length
            if ($valueLength -gt 100) {
                $truncatedValue = $secretJson.value.Substring(0, 100)
                Write-Host "    Value: $truncatedValue... (truncated, length: $valueLength)" -ForegroundColor Cyan
            } else {
                Write-Host "    Value: $($secretJson.value)" -ForegroundColor Cyan
            }
        }

        Write-Host ""
    } catch {
        Write-Error "Failed to retrieve secret: $SecretName"
        Write-Host ""
    }
}

# Get all MFT secrets for the environment
Write-Header "═══════════════════════════════════════════════════════════════"
Write-Header "MFT Secrets for Environment: $Environment"
Write-Header "═══════════════════════════════════════════════════════════════"
Write-Host ""

# Database secrets
Write-Header "Database Secrets (mft-db-*)"
Write-Header "───────────────────────────────────────────────────────────────"
try {
    $dbSecrets = az keyvault secret list --vault-name $KvName --query "[?starts_with(name, '$Environment-mft-db-')].name" -o json 2>$null | ConvertFrom-Json

    if ($dbSecrets) {
        foreach ($secret in $dbSecrets) {
            Show-SecretDetails $secret
        }
    } else {
        Write-Warning "No database secrets found"
        Write-Host ""
    }
} catch {
    Write-Warning "No database secrets found"
    Write-Host ""
}

# Application secrets (excluding db and cert)
Write-Header "Application Secrets (mft-*)"
Write-Header "───────────────────────────────────────────────────────────────"
try {
    $appSecrets = az keyvault secret list --vault-name $KvName --query "[?starts_with(name, '$Environment-mft-') && !starts_with(name, '$Environment-mft-db-') && !starts_with(name, '$Environment-mft-cert-')].name" -o json 2>$null | ConvertFrom-Json

    if ($appSecrets) {
        foreach ($secret in $appSecrets) {
            Show-SecretDetails $secret
        }
    } else {
        Write-Warning "No application secrets found"
        Write-Host ""
    }
} catch {
    Write-Warning "No application secrets found"
    Write-Host ""
}

# Certificate secrets
Write-Header "Certificate Secrets (mft-cert-*)"
Write-Header "───────────────────────────────────────────────────────────────"
try {
    $certSecrets = az keyvault secret list --vault-name $KvName --query "[?starts_with(name, '$Environment-mft-cert-')].name" -o json 2>$null | ConvertFrom-Json

    if ($certSecrets) {
        foreach ($secret in $certSecrets) {
            Show-SecretDetails $secret
        }
    } else {
        Write-Warning "No certificate secrets found"
        Write-Host ""
    }
} catch {
    Write-Warning "No certificate secrets found"
    Write-Host ""
}

# Certificate objects (Key Vault certificates, not secrets)
Write-Header "Certificate Objects"
Write-Header "───────────────────────────────────────────────────────────────"
try {
    $certObjects = az keyvault certificate list --vault-name $KvName --query "[?starts_with(name, '$Environment-mft-')].name" -o json 2>$null | ConvertFrom-Json

    if ($certObjects) {
        foreach ($cert in $certObjects) {
            try {
                $certJson = az keyvault certificate show --vault-name $KvName --name $cert -o json 2>$null | ConvertFrom-Json

                if ($certJson) {
                    Write-SecretName "  $cert"
                    Write-Host "    Type: Certificate" -ForegroundColor Cyan
                    Write-Host "    Enabled: $($certJson.attributes.enabled)" -ForegroundColor Cyan

                    if ($certJson.attributes.expires) {
                        Write-Host "    Expires: $($certJson.attributes.expires)" -ForegroundColor Cyan
                    }

                    Write-Host ""
                }
            } catch {
                # Skip if certificate can't be retrieved
            }
        }
    } else {
        Write-Warning "No certificate objects found"
        Write-Host ""
    }
} catch {
    Write-Warning "No certificate objects found"
    Write-Host ""
}

Write-Header "═══════════════════════════════════════════════════════════════"
Write-Success "Secret listing complete"

if (-not $ShowValues) {
    Write-Host ""
    Write-Info "To display secret values, run with: -ShowValues"
    Write-Warning "Warning: This will display sensitive information!"
}

# Made with Bob
