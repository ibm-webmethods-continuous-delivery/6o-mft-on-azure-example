#Requires -Version 5.1
<#
.SYNOPSIS
    Check completeness of MFT secrets required by Helm chart in Azure Key Vault

.DESCRIPTION
    This validates that all secrets referenced in the Helm chart are present in Key Vault

.PARAMETER Environment
    Environment name (optional, defaults from Terraform)

.EXAMPLE
    .\check-at-helm-secrets-presence.ps1
    .\check-at-helm-secrets-presence.ps1 dev
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

function Write-Header {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Cyan
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

# Define required secrets based on Helm chart SecretProviderClass
# Core application secrets
$RequiredAppSecrets = @(
    "mft-admin-password",
    "mft-sftp-ssh-private-key"
)

# Database secrets
$RequiredDbSecrets = @(
    "mft-db-postgres-server-fqdn",
    "mft-db-postgres-online-db",
    "mft-db-postgres-archive-db",
    "mft-db-postgres-admin-user",
    "mft-db-postgres-admin-password",
    "mft-db-postgres-online-user",
    "mft-db-postgres-online-password",
    "mft-db-postgres-archive-user",
    "mft-db-postgres-archive-password"
)

# Certificate password secrets - JKS format
$RequiredJksPasswordSecrets = @(
    "mft-admin-ui-jks-keystore-password",
    "mft-admin-ui-jks-truststore-password",
    "mft-web-client-jks-keystore-password",
    "mft-web-client-jks-truststore-password",
    "mft-cert-jks-truststore-password"
)

# Certificate password secrets - PKCS12 format
$RequiredPkcs12PasswordSecrets = @(
    "mft-admin-ui-pkcs12-keystore-password",
    "mft-admin-ui-pkcs12-truststore-password",
    "mft-web-client-pkcs12-keystore-password",
    "mft-web-client-pkcs12-truststore-password",
    "mft-cert-pkcs12-truststore-password"
)

# Certificate file secrets - JKS format
$RequiredJksCertSecrets = @(
    "mft-cert-admin-ui-keystore-jks",
    "mft-cert-web-client-keystore-jks",
    "mft-cert-truststore-jks"
)

# Certificate file secrets - PKCS12 format
$RequiredPkcs12CertSecrets = @(
    "mft-cert-admin-ui-keystore-pkcs12",
    "mft-cert-web-client-keystore-pkcs12",
    "mft-cert-truststore-pkcs12"
)

# Optional secrets (warn if missing but don't fail)
$OptionalSecrets = @(
    "mft-metering-config-xml-file",
    "mft-sftp-ssh-private-key-loaded",
    "mft-cert-ca-bundle-pem"
)

# Validation counters
$script:TotalRequired = 0
$script:FoundRequired = 0
$script:MissingRequired = 0
$script:TotalOptional = 0
$script:FoundOptional = 0
$script:MissingOptional = 0

# Function to check if a secret exists
function Test-Secret {
    param(
        [string]$SecretSuffix,
        [bool]$IsOptional = $false
    )

    $FullSecretName = "$Environment-$SecretSuffix"

    if (-not $IsOptional) {
        $script:TotalRequired++
    } else {
        $script:TotalOptional++
    }

    try {
        az keyvault secret show --vault-name $KvName --name $FullSecretName --output none 2>$null
        Write-Success $FullSecretName
        if (-not $IsOptional) {
            $script:FoundRequired++
        } else {
            $script:FoundOptional++
        }
        return $true
    } catch {
        if (-not $IsOptional) {
            Write-Error "$FullSecretName (MISSING - REQUIRED)"
            $script:MissingRequired++
        } else {
            Write-Warning "$FullSecretName (MISSING - OPTIONAL)"
            $script:MissingOptional++
        }
        return $false
    }
}

# Check all required secrets
Write-Header "═══════════════════════════════════════════════════════════════"
Write-Header "Checking Required Secrets for Helm Chart Deployment"
Write-Header "═══════════════════════════════════════════════════════════════"
Write-Host ""

Write-Header "Application Secrets"
Write-Header "───────────────────────────────────────────────────────────────"
foreach ($secret in $RequiredAppSecrets) {
    Test-Secret -SecretSuffix $secret -IsOptional $false
}

Write-Host ""
Write-Header "Database Secrets"
Write-Header "───────────────────────────────────────────────────────────────"
foreach ($secret in $RequiredDbSecrets) {
    Test-Secret -SecretSuffix $secret -IsOptional $false
}

Write-Host ""
Write-Header "Certificate Password Secrets - JKS Format"
Write-Header "───────────────────────────────────────────────────────────────"
foreach ($secret in $RequiredJksPasswordSecrets) {
    Test-Secret -SecretSuffix $secret -IsOptional $false
}

Write-Host ""
Write-Header "Certificate Password Secrets - PKCS12 Format"
Write-Header "───────────────────────────────────────────────────────────────"
foreach ($secret in $RequiredPkcs12PasswordSecrets) {
    Test-Secret -SecretSuffix $secret -IsOptional $false
}

Write-Host ""
Write-Header "Certificate File Secrets - JKS Format"
Write-Header "───────────────────────────────────────────────────────────────"
foreach ($secret in $RequiredJksCertSecrets) {
    Test-Secret -SecretSuffix $secret -IsOptional $false
}

Write-Host ""
Write-Header "Certificate File Secrets - PKCS12 Format"
Write-Header "───────────────────────────────────────────────────────────────"
foreach ($secret in $RequiredPkcs12CertSecrets) {
    Test-Secret -SecretSuffix $secret -IsOptional $false
}

Write-Host ""
Write-Header "Optional Secrets"
Write-Header "───────────────────────────────────────────────────────────────"
foreach ($secret in $OptionalSecrets) {
    Test-Secret -SecretSuffix $secret -IsOptional $true
}

# Summary
Write-Host ""
Write-Header "═══════════════════════════════════════════════════════════════"
Write-Header "Validation Summary"
Write-Header "═══════════════════════════════════════════════════════════════"
Write-Host ""

Write-Info "Required Secrets:"
Write-Host "  Total:   $script:TotalRequired"
Write-Host "  Found:   $script:FoundRequired" -ForegroundColor Green
if ($script:MissingRequired -gt 0) {
    Write-Host "  Missing: $script:MissingRequired" -ForegroundColor Red
} else {
    Write-Host "  Missing: $script:MissingRequired"
}

Write-Host ""
Write-Info "Optional Secrets:"
Write-Host "  Total:   $script:TotalOptional"
Write-Host "  Found:   $script:FoundOptional" -ForegroundColor Green
if ($script:MissingOptional -gt 0) {
    Write-Host "  Missing: $script:MissingOptional" -ForegroundColor Yellow
} else {
    Write-Host "  Missing: $script:MissingOptional"
}

Write-Host ""
Write-Header "═══════════════════════════════════════════════════════════════"

# Exit status and recommendations
if ($script:MissingRequired -gt 0) {
    Write-Host ""
    Write-Error "VALIDATION FAILED: $script:MissingRequired required secret(s) missing!"
    Write-Host ""
    Write-Info "Recommended Actions:"
    Write-Host ""
    Write-Host "  1. Run Terraform to create missing secrets:"
    Write-Host "     cd $TfDir"
    Write-Host "     terraform apply"
    Write-Host ""
    Write-Host "  2. For certificate secrets, ensure upload_certificates is enabled:"
    Write-Host "     Check terraform.tfvars: upload_certificates = true"
    Write-Host ""
    Write-Host "  3. Manually set secrets using:"
    Write-Host "     cd $ScriptDir"
    Write-Host "     .\set-at-helm-secret.ps1 <secret-suffix> <value>"
    Write-Host ""
    Write-Host "  4. View all secrets:"
    Write-Host "     .\view-at-vault-secrets.ps1 $Environment"
    Write-Host ""
    exit 1
} else {
    Write-Host ""
    Write-Success "VALIDATION PASSED: All required secrets are present!"

    if ($script:MissingOptional -gt 0) {
        Write-Host ""
        Write-Warning "Note: $script:MissingOptional optional secret(s) missing"
        Write-Info "These are not required for basic deployment but may be needed for:"
        Write-Host "  - IBM license metering (mft-metering-config-xml-file)"
        Write-Host "  - Alternative SSH key format (mft-sftp-ssh-private-key-loaded)"
        Write-Host "  - CA bundle in PEM format (mft-cert-ca-bundle-pem)"
    }

    Write-Host ""
    Write-Info "Next Steps:"
    Write-Host "  1. Verify secret values are correct (not default placeholders):"
    Write-Host "     .\view-at-vault-secrets.ps1 $Environment -ShowValues"
    Write-Host ""
    Write-Host "  2. Deploy Helm chart:"
    Write-Host "     cd $ScriptDir\..\02-AT\helm"
    Write-Host "     helm upgrade --install active-transfer . -f values.yaml"
    Write-Host ""
    Write-Host "  3. Monitor deployment:"
    Write-Host "     kubectl get pods -n <namespace> -w"
    Write-Host ""
    exit 0
}

# Made with Bob
