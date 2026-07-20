#Requires -Version 5.1
<#
.SYNOPSIS
    Set or update an MFT secret in Azure Key Vault

.DESCRIPTION
    Sets or updates individual secrets in Azure Key Vault with proper content-type detection and validation

.PARAMETER SecretSuffix
    Secret name suffix (without environment prefix)
    Examples: admin-password, db-postgres-online-password

.PARAMETER SecretValue
    Secret value to set

.PARAMETER Environment
    Environment name (optional, defaults from Terraform)

.EXAMPLE
    .\set-at-helm-secret.ps1 mft-admin-password "MySecurePassword123!"
    .\set-at-helm-secret.ps1 mft-db-postgres-online-password "DbPassword456" dev
    .\set-at-helm-secret.ps1 mft-sftp-ssh-private-key (Get-Content ~/.ssh/id_rsa -Raw)
#>

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$SecretSuffix,

    [Parameter(Mandatory=$true, Position=1)]
    [string]$SecretValue,

    [Parameter(Position=2)]
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

function Write-Header {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Cyan
}

function Show-Usage {
    Write-Header "Usage:"
    Write-Host "  .\set-at-helm-secret.ps1 <secret-suffix> <value> [environment]"
    Write-Host ""
    Write-Header "Arguments:"
    Write-Host "  secret-suffix    Secret name suffix (without environment prefix)"
    Write-Host "                   Examples: admin-password, db-postgres-online-password"
    Write-Host "  value           Secret value to set"
    Write-Host "  environment     Environment name (optional, defaults from Terraform)"
    Write-Host ""
    Write-Header "Common Secret Suffixes:"
    Write-Host "  Application Secrets:" -ForegroundColor Green
    Write-Host "    mft-admin-password"
    Write-Host "    mft-metering-config-xml-file"
    Write-Host "    mft-sftp-ssh-private-key"
    Write-Host "    mft-sftp-ssh-private-key-loaded"
    Write-Host ""
    Write-Host "  Database Secrets:" -ForegroundColor Green
    Write-Host "    mft-db-postgres-server-fqdn"
    Write-Host "    mft-db-postgres-online-db"
    Write-Host "    mft-db-postgres-archive-db"
    Write-Host "    mft-db-postgres-admin-user"
    Write-Host "    mft-db-postgres-admin-password"
    Write-Host "    mft-db-postgres-online-user"
    Write-Host "    mft-db-postgres-online-password"
    Write-Host "    mft-db-postgres-archive-user"
    Write-Host "    mft-db-postgres-archive-password"
    Write-Host ""
    Write-Host "  Certificate Passwords:" -ForegroundColor Green
    Write-Host "    mft-admin-ui-jks-keystore-password"
    Write-Host "    mft-admin-ui-jks-truststore-password"
    Write-Host "    mft-admin-ui-pkcs12-keystore-password"
    Write-Host "    mft-admin-ui-pkcs12-truststore-password"
    Write-Host "    mft-web-client-jks-keystore-password"
    Write-Host "    mft-web-client-jks-truststore-password"
    Write-Host "    mft-web-client-pkcs12-keystore-password"
    Write-Host "    mft-web-client-pkcs12-truststore-password"
    Write-Host "    mft-cert-jks-truststore-password"
    Write-Host "    mft-cert-pkcs12-truststore-password"
    Write-Host ""
    Write-Header "Examples:"
    Write-Host "  # Set admin password"
    Write-Host "  .\set-at-helm-secret.ps1 mft-admin-password `"MySecurePassword123!`""
    Write-Host ""
    Write-Host "  # Set database password for specific environment"
    Write-Host "  .\set-at-helm-secret.ps1 mft-db-postgres-online-password `"DbPassword456`" dev"
    Write-Host ""
    Write-Host "  # Set SSH private key from file"
    Write-Host "  .\set-at-helm-secret.ps1 mft-sftp-ssh-private-key (Get-Content ~/.ssh/id_rsa -Raw)"
    Write-Host ""
    Write-Host "  # Set metering config XML from file"
    Write-Host "  .\set-at-helm-secret.ps1 mft-metering-config-xml-file (Get-Content metering.xml -Raw)"
    Write-Host ""
    Write-Header "Notes:"
    Write-Host "  - Secret names are automatically prefixed with environment name"
    Write-Host "  - Existing secrets will be updated (previous versions are retained)"
    Write-Host "  - Use quotes around values containing special characters"
    Write-Host "  - For binary files (certificates), use base64 encoding first"
    Write-Host ""
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

# Construct full secret name
# Remove any leading "mft-" or environment prefix if user provided it
$SecretSuffix = $SecretSuffix -replace "^$Environment-", "" -replace "^mft-", ""

# Ensure it starts with "mft-" for consistency
if ($SecretSuffix -notmatch "^mft-") {
    $SecretSuffix = "mft-$SecretSuffix"
}

$FullSecretName = "$Environment-$SecretSuffix"

Write-Info "Environment: $Environment"
Write-Info "Key Vault: $KvName"
Write-Info "Secret Name: $FullSecretName"
Write-Host ""

# Check if secret already exists
try {
    az keyvault secret show --vault-name $KvName --name $FullSecretName --output none 2>$null
    Write-Warning "Secret already exists and will be updated"
    Write-Info "Previous versions will be retained in Key Vault history"
    Write-Host ""
} catch {
    # Secret doesn't exist, which is fine
}

# Validate secret value is not empty
if ([string]::IsNullOrWhiteSpace($SecretValue)) {
    Write-Error "Secret value cannot be empty"
    exit 1
}

# Determine content type based on secret suffix
$ContentType = "text/plain"
switch -Regex ($SecretSuffix) {
    '.*-config-json$' {
        $ContentType = "application/json"
        # Validate JSON if it looks like JSON
        if ($SecretValue -match '^\s*\{') {
            try {
                $SecretValue | ConvertFrom-Json | Out-Null
            } catch {
                Write-Warning "Value does not appear to be valid JSON"
                $response = Read-Host "Continue anyway? (y/N)"
                if ($response -ne 'y' -and $response -ne 'Y') {
                    Write-Info "Operation cancelled"
                    exit 0
                }
            }
        }
    }
    '.*-xml-file$' {
        $ContentType = "application/xml"
    }
    '.*-cert-.*|.*-keystore-.*|.*-truststore-.*' {
        $ContentType = "application/octet-stream"
    }
}

# Set the secret
Write-Info "Setting secret in Key Vault..."

try {
    az keyvault secret set `
        --vault-name $KvName `
        --name $FullSecretName `
        --value $SecretValue `
        --content-type $ContentType `
        --output none 2>$null

    Write-Success "Secret set successfully: $FullSecretName"
    Write-Host ""

    # Display secret info (without value)
    Write-Info "Secret Details:"
    $secretInfo = az keyvault secret show `
        --vault-name $KvName `
        --name $FullSecretName `
        --query "{Name:name, ContentType:contentType, Enabled:attributes.enabled, Updated:attributes.updated}" `
        -o json 2>$null | ConvertFrom-Json

    $secretInfo | Format-List

    Write-Host ""
    Write-Info "Next Steps:"
    Write-Host "  1. Verify the secret was set correctly:"
    Write-Host "     .\view-at-vault-secrets.ps1 $Environment -ShowValues | Select-String -Pattern '$FullSecretName' -Context 0,10"
    Write-Host ""
    Write-Host "  2. If this secret is used by the Helm chart, restart pods to pick up changes:"
    Write-Host "     kubectl rollout restart deployment/active-transfer -n <namespace>"
    Write-Host ""
    Write-Host "  3. Monitor secret rotation (if enabled):"
    Write-Host "     kubectl logs -f deployment/active-transfer -n <namespace> | Select-String -Pattern 'secret'"

} catch {
    Write-Error "Failed to set secret: $FullSecretName"
    Write-Info "Check Azure CLI permissions and Key Vault access policies"
    Write-Error $_.Exception.Message
    exit 1
}

# Made with Bob
