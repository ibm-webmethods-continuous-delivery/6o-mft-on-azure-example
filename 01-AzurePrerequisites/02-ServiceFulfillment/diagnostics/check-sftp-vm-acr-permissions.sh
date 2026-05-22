#!/usr/bin/env bash
set -euo pipefail

# Diagnostics script:
# - Resolves SFTP VM names primarily from Terraform state/outputs
# - Resolves ACR name from Terraform state, then tfvars/CLI arguments
# - Finds VM managed identity principal IDs
# - Finds ACR resource ID
# - Checks whether AcrPull role assignments exist on the ACR scope
# - Checks whether Terraform state already tracks the related role assignments
#
# Usage examples:
#   ./diagnostics/check-sftp-vm-acr-permissions.sh
#   ./diagnostics/check-sftp-vm-acr-permissions.sh --tfvars common.tfvars
#   ./diagnostics/check-sftp-vm-acr-permissions.sh --tfvars full.tfvars --acr-rg my-acr-rg
#   ./diagnostics/check-sftp-vm-acr-permissions.sh --rg my-rg --prefix myprefix --acr-name myacr --acr-rg my-acr-rg
#
# Requirements:
# - bash
# - terraform
# - az CLI
# - jq
#
# Notes:
# - This script does not modify resources.
# - It prefers Terraform-derived values over tfvars parsing.
# - It does not depend on awk/sed/grep parsing for core resolution logic.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

TFVARS_FILE=""
RG_NAME=""
PREFIX=""
ACR_NAME=""
ACR_RG=""
SFTP_VM_1_NAME=""
SFTP_VM_2_NAME=""

usage() {
  cat <<'EOF'
Usage:
  check-sftp-vm-acr-permissions.sh [options]

Options:
  --tfvars <file>         Optional tfvars file path, relative to module dir or absolute
  --rg <name>             Resource group name for the SFTP VMs
  --prefix <value>        Prefix used to derive default VM names
  --acr-name <name>       Azure Container Registry name
  --acr-rg <name>         Resource group containing the ACR
  --vm1 <name>            Explicit SFTP VM 1 name
  --vm2 <name>            Explicit SFTP VM 2 name
  -h, --help              Show this help

Behavior:
  - If values are not provided explicitly, the script tries to infer them from:
    1) terraform output -json
    2) terraform state show
    3) selected tfvars file (JSON parser only)
    4) naming defaults from prefix
EOF
}

log()  { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
err()  { printf '[ERROR] %s\n' "$*" >&2; }

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    err "Required command not found: $cmd"
    exit 1
  fi
}

resolve_path() {
  local p="$1"
  if [[ -z "$p" ]]; then
    return 1
  fi
  if [[ -f "$p" ]]; then
    printf '%s\n' "$p"
  elif [[ -f "${MODULE_DIR}/${p}" ]]; then
    printf '%s\n' "${MODULE_DIR}/${p}"
  else
    return 1
  fi
}

get_tf_output_json() {
  terraform -chdir="${MODULE_DIR}" output -json 2>/dev/null || echo '{}'
}

get_tf_output_value() {
  local query="$1"
  local out_json
  out_json="$(get_tf_output_json)"
  jq -r "$query // empty" <<<"$out_json" 2>/dev/null || true
}

get_tf_state_json() {
  terraform -chdir="${MODULE_DIR}" show -json 2>/dev/null || echo '{}'
}

get_tf_state_value() {
  local query="$1"
  local state_json
  state_json="$(get_tf_state_json)"
  jq -r "$query // empty" <<<"$state_json" 2>/dev/null || true
}

parse_tfvars_json_string() {
  local file="$1"
  local key="$2"
  jq -r --arg key "$key" '.[$key] // empty' "$file" 2>/dev/null || true
}

infer_from_terraform() {
  # resource group from outputs if present
  if [[ -z "$RG_NAME" ]]; then
    RG_NAME="$(get_tf_output_value '.resource_group_name.value')"
  fi

  # vm names from state
  if [[ -z "$SFTP_VM_1_NAME" ]]; then
    SFTP_VM_1_NAME="$(get_tf_state_value '
      .values.root_module.resources[]
      | select(.address=="azurerm_linux_virtual_machine.sftp_vm_1")
      | .values.name
    ' | head -n 1)"
  fi

  if [[ -z "$SFTP_VM_2_NAME" ]]; then
    SFTP_VM_2_NAME="$(get_tf_state_value '
      .values.root_module.resources[]
      | select(.address=="azurerm_linux_virtual_machine.sftp_vm_2")
      | .values.name
    ' | head -n 1)"
  fi

  # resource group from VM resources if output missing
  if [[ -z "$RG_NAME" ]]; then
    RG_NAME="$(get_tf_state_value '
      .values.root_module.resources[]
      | select(.address=="azurerm_linux_virtual_machine.sftp_vm_1")
      | .values.resource_group_name
    ' | head -n 1)"
  fi

  # prefix infer from VM name if possible
  if [[ -z "$PREFIX" && -n "$SFTP_VM_1_NAME" ]]; then
    PREFIX="${SFTP_VM_1_NAME%-sftp-vm-1}"
  fi

  # ACR name from data source state
  if [[ -z "$ACR_NAME" ]]; then
    ACR_NAME="$(get_tf_state_value '
      .values.root_module.resources[]
      | select(.address=="data.azurerm_container_registry.main")
      | .values.name
    ' | head -n 1)"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tfvars)
      TFVARS_FILE="${2:-}"
      shift 2
      ;;
    --rg)
      RG_NAME="${2:-}"
      shift 2
      ;;
    --prefix)
      PREFIX="${2:-}"
      shift 2
      ;;
    --acr-name)
      ACR_NAME="${2:-}"
      shift 2
      ;;
    --acr-rg)
      ACR_RG="${2:-}"
      shift 2
      ;;
    --vm1)
      SFTP_VM_1_NAME="${2:-}"
      shift 2
      ;;
    --vm2)
      SFTP_VM_2_NAME="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      err "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

require_cmd terraform
require_cmd az
require_cmd jq

if ! az account show >/dev/null 2>&1; then
  err "Azure CLI is not logged in. Run: az login"
  exit 1
fi

TFVARS_RESOLVED=""
if [[ -n "$TFVARS_FILE" ]]; then
  TFVARS_RESOLVED="$(resolve_path "$TFVARS_FILE" || true)"
  if [[ -z "$TFVARS_RESOLVED" ]]; then
    err "Could not find tfvars file: $TFVARS_FILE"
    exit 1
  fi
elif [[ -f "${MODULE_DIR}/common.tfvars.json" ]]; then
  TFVARS_RESOLVED="${MODULE_DIR}/common.tfvars.json"
fi

log "Module directory: ${MODULE_DIR}"
if [[ -n "$TFVARS_RESOLVED" ]]; then
  log "Using tfvars file for secondary inference: ${TFVARS_RESOLVED}"
else
  warn "No JSON tfvars file provided/found for secondary inference; relying on Terraform state/outputs and CLI args"
fi

infer_from_terraform

# Optional JSON tfvars fallback only
if [[ -n "$TFVARS_RESOLVED" ]]; then
  if [[ -z "$RG_NAME" ]]; then
    RG_NAME="$(parse_tfvars_json_string "$TFVARS_RESOLVED" "resource_group_name")"
  fi
  if [[ -z "$PREFIX" ]]; then
    PREFIX="$(parse_tfvars_json_string "$TFVARS_RESOLVED" "prefix")"
  fi
  if [[ -z "$ACR_NAME" ]]; then
    ACR_NAME="$(parse_tfvars_json_string "$TFVARS_RESOLVED" "acr_name")"
  fi
  if [[ -z "$SFTP_VM_1_NAME" ]]; then
    SFTP_VM_1_NAME="$(parse_tfvars_json_string "$TFVARS_RESOLVED" "sftp_vm_1_name")"
  fi
  if [[ -z "$SFTP_VM_2_NAME" ]]; then
    SFTP_VM_2_NAME="$(parse_tfvars_json_string "$TFVARS_RESOLVED" "sftp_vm_2_name")"
  fi
fi

if [[ -z "$SFTP_VM_1_NAME" && -n "$PREFIX" ]]; then
  SFTP_VM_1_NAME="${PREFIX}-sftp-vm-1"
fi

if [[ -z "$SFTP_VM_2_NAME" && -n "$PREFIX" ]]; then
  SFTP_VM_2_NAME="${PREFIX}-sftp-vm-2"
fi

if [[ -z "$RG_NAME" || -z "$ACR_NAME" || -z "$SFTP_VM_1_NAME" || -z "$SFTP_VM_2_NAME" ]]; then
  err "Could not resolve all required values from Terraform state/outputs."
  printf 'Resolved so far:\n'
  printf '  resource_group_name: %s\n' "${RG_NAME:-<empty>}"
  printf '  prefix: %s\n' "${PREFIX:-<empty>}"
  printf '  acr_name: %s\n' "${ACR_NAME:-<empty>}"
  printf '  sftp_vm_1_name: %s\n' "${SFTP_VM_1_NAME:-<empty>}"
  printf '  sftp_vm_2_name: %s\n' "${SFTP_VM_2_NAME:-<empty>}"
  printf '\n'
  err "If needed, provide missing values with --rg, --prefix, --acr-name, --vm1, --vm2."
  exit 1
fi

log "Resolved inputs:"
printf '  Resource Group : %s\n' "$RG_NAME"
printf '  ACR Name       : %s\n' "$ACR_NAME"
printf '  VM 1 Name      : %s\n' "$SFTP_VM_1_NAME"
printf '  VM 2 Name      : %s\n' "$SFTP_VM_2_NAME"
if [[ -n "$ACR_RG" ]]; then
  printf '  ACR RG         : %s\n' "$ACR_RG"
fi

get_vm_principal_id() {
  local rg="$1"
  local vm="$2"
  az vm show \
    --resource-group "$rg" \
    --name "$vm" \
    --query 'identity.principalId' \
    -o tsv 2>/dev/null || true
}

VM1_PRINCIPAL_ID="$(get_vm_principal_id "$RG_NAME" "$SFTP_VM_1_NAME")"
VM2_PRINCIPAL_ID="$(get_vm_principal_id "$RG_NAME" "$SFTP_VM_2_NAME")"

printf '\n=== VM Managed Identities ===\n'
printf 'VM 1 principalId: %s\n' "${VM1_PRINCIPAL_ID:-<not found>}"
printf 'VM 2 principalId: %s\n' "${VM2_PRINCIPAL_ID:-<not found>}"

if [[ -z "$VM1_PRINCIPAL_ID" || -z "$VM2_PRINCIPAL_ID" ]]; then
  warn "One or both VM principal IDs could not be resolved. Check VM names/resource group."
fi

ACR_ID=""
if [[ -n "$ACR_RG" ]]; then
  ACR_ID="$(az acr show --resource-group "$ACR_RG" --name "$ACR_NAME" --query id -o tsv 2>/dev/null || true)"
else
  ACR_ID="$(az acr list --query "[?name=='${ACR_NAME}'] | [0].id" -o tsv 2>/dev/null || true)"
fi

printf '\n=== ACR Resolution ===\n'
printf 'ACR resource id: %s\n' "${ACR_ID:-<not found>}"

if [[ -z "$ACR_ID" ]]; then
  err "Could not resolve ACR resource ID. If the ACR name is not unique or inaccessible, pass --acr-rg."
  exit 1
fi

check_acr_pull() {
  local principal_id="$1"
  local label="$2"

  if [[ -z "$principal_id" ]]; then
    printf '\n%s: principal ID unavailable, skipping role assignment check.\n' "$label"
    return 0
  fi

  local result
  result="$(az role assignment list \
    --assignee "$principal_id" \
    --scope "$ACR_ID" \
    --query "[?roleDefinitionName=='AcrPull'].{role:roleDefinitionName,scope:scope,principalId:principalId}" \
    -o json 2>/dev/null || echo '[]')"

  printf '\n=== %s AcrPull Assignments on ACR Scope ===\n' "$label"
  echo "$result" | jq .

  local count
  count="$(echo "$result" | jq 'length')"
  if [[ "$count" -gt 0 ]]; then
    printf '%s: AcrPull role assignment exists.\n' "$label"
  else
    printf '%s: AcrPull role assignment NOT found.\n' "$label"
  fi
}

check_acr_pull "$VM1_PRINCIPAL_ID" "VM 1"
check_acr_pull "$VM2_PRINCIPAL_ID" "VM 2"

printf '\n=== Terraform State Check ===\n'
(
  cd "${MODULE_DIR}"
  terraform state list 2>/dev/null | grep -E 'azurerm_role_assignment\.sftp_vm_[12]_acr(\[0\])?$' || true
)

STATE_VM1="absent"
STATE_VM2="absent"
if (cd "${MODULE_DIR}" && terraform state list 2>/dev/null | grep -q 'azurerm_role_assignment\.sftp_vm_1_acr'); then
  STATE_VM1="present"
fi
if (cd "${MODULE_DIR}" && terraform state list 2>/dev/null | grep -q 'azurerm_role_assignment\.sftp_vm_2_acr'); then
  STATE_VM2="present"
fi

printf 'Terraform state contains sftp_vm_1_acr: %s\n' "$STATE_VM1"
printf 'Terraform state contains sftp_vm_2_acr: %s\n' "$STATE_VM2"

printf '\n=== Summary ===\n'
printf 'VM 1 principalId                 : %s\n' "${VM1_PRINCIPAL_ID:-<not found>}"
printf 'VM 2 principalId                 : %s\n' "${VM2_PRINCIPAL_ID:-<not found>}"
printf 'ACR id                           : %s\n' "${ACR_ID:-<not found>}"
printf 'Terraform state sftp_vm_1_acr    : %s\n' "$STATE_VM1"
printf 'Terraform state sftp_vm_2_acr    : %s\n' "$STATE_VM2"

cat <<'EOF'

Interpretation:
- If AcrPull is shown in Azure CLI output, the VM identity already has pull permission on the ACR.
- If Terraform state says "present", Terraform is already tracking the role assignment.
- If Azure has the permission but Terraform state is absent, the assignment may have been created manually/outside Terraform.
- If neither Azure nor Terraform state shows it, then the permission is missing.
EOF

# Made with Bob
