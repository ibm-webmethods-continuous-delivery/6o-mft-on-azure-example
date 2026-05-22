#!/usr/bin/env bash
set -euo pipefail

# Diagnostics script:
# - Resolves SFTP/DMZ NSG name from Terraform state
# - Resolves AKS subnet CIDR from Terraform state
# - Resolves DMZ VM names and private IPs from Terraform state / Azure CLI
# - Checks NSG security rules for inbound allow on TCP ports 8500 and 8501 from AKS subnet
# - Reports whether the rule is broad enough to cover the two DMZ machines
#
# Reference:
# - 03-TechnologyServices/03-ATGateway/README.md, section:
#   "Add NSG Rules for Gateway Ports"
#
# Usage examples:
#   ./diagnostics/check-gateway-ports-from-aks.sh
#   ./diagnostics/check-gateway-ports-from-aks.sh --nsg my-nsg --aks-cidr 10.1.10.0/24
#   ./diagnostics/check-gateway-ports-from-aks.sh --rg my-rg --vm1 vm-one --vm2 vm-two
#
# Requirements:
# - bash
# - terraform
# - az CLI
# - jq

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

RG_NAME=""
NSG_NAME=""
AKS_SUBNET_CIDR=""
VM1_NAME=""
VM2_NAME=""
VM1_PRIVATE_IP=""
VM2_PRIVATE_IP=""

usage() {
  cat <<'EOF'
Usage:
  check-gateway-ports-from-aks.sh [options]

Options:
  --rg <name>           Resource group name
  --nsg <name>          NSG name for the DMZ/SFTP VMs
  --aks-cidr <cidr>     AKS subnet CIDR expected as source, e.g. 10.1.10.0/24
  --vm1 <name>          Explicit VM 1 name
  --vm2 <name>          Explicit VM 2 name
  --vm1-ip <ip>         Explicit VM 1 private IP
  --vm2-ip <ip>         Explicit VM 2 private IP
  -h, --help            Show this help

Behavior:
  - If values are not provided explicitly, the script tries to infer them from:
    1) terraform output -json
    2) terraform show -json
    3) Azure CLI lookups for current NIC private IPs
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

infer_from_terraform() {
  if [[ -z "$RG_NAME" ]]; then
    RG_NAME="$(get_tf_output_value '.resource_group_name.value')"
  fi

  if [[ -z "$VM1_NAME" ]]; then
    VM1_NAME="$(get_tf_state_value '
      .values.root_module.resources[]
      | select(.address=="azurerm_linux_virtual_machine.sftp_vm_1")
      | .values.name
    ' | head -n 1)"
  fi

  if [[ -z "$VM2_NAME" ]]; then
    VM2_NAME="$(get_tf_state_value '
      .values.root_module.resources[]
      | select(.address=="azurerm_linux_virtual_machine.sftp_vm_2")
      | .values.name
    ' | head -n 1)"
  fi

  if [[ -z "$RG_NAME" ]]; then
    RG_NAME="$(get_tf_state_value '
      .values.root_module.resources[]
      | select(.address=="azurerm_linux_virtual_machine.sftp_vm_1")
      | .values.resource_group_name
    ' | head -n 1)"
  fi

  if [[ -z "$NSG_NAME" ]]; then
    NSG_NAME="$(get_tf_state_value '
      .values.root_module.resources[]
      | select(.address=="azurerm_network_security_group.sftp")
      | .values.name
    ' | head -n 1)"
  fi

  if [[ -z "$AKS_SUBNET_CIDR" ]]; then
    AKS_SUBNET_CIDR="$(get_tf_state_value '
      .values.root_module.resources[]
      | select(.address=="azurerm_subnet.private_1")
      | .values.address_prefixes[0]
    ' | head -n 1)"
  fi

  if [[ -z "$VM1_PRIVATE_IP" ]]; then
    VM1_PRIVATE_IP="$(get_tf_state_value '
      .values.root_module.resources[]
      | select(.address=="azurerm_network_interface.sftp_vm_1")
      | .values.ip_configuration[0].private_ip_address
    ' | head -n 1)"
  fi

  if [[ -z "$VM2_PRIVATE_IP" ]]; then
    VM2_PRIVATE_IP="$(get_tf_state_value '
      .values.root_module.resources[]
      | select(.address=="azurerm_network_interface.sftp_vm_2")
      | .values.ip_configuration[0].private_ip_address
    ' | head -n 1)"
  fi
}

get_vm_private_ip_from_azure() {
  local rg="$1"
  local vm="$2"
  az vm show -d \
    --resource-group "$rg" \
    --name "$vm" \
    --query 'privateIps' \
    -o tsv 2>/dev/null || true
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rg)
      RG_NAME="${2:-}"
      shift 2
      ;;
    --nsg)
      NSG_NAME="${2:-}"
      shift 2
      ;;
    --aks-cidr)
      AKS_SUBNET_CIDR="${2:-}"
      shift 2
      ;;
    --vm1)
      VM1_NAME="${2:-}"
      shift 2
      ;;
    --vm2)
      VM2_NAME="${2:-}"
      shift 2
      ;;
    --vm1-ip)
      VM1_PRIVATE_IP="${2:-}"
      shift 2
      ;;
    --vm2-ip)
      VM2_PRIVATE_IP="${2:-}"
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

log "Module directory: ${MODULE_DIR}"

infer_from_terraform

if [[ -n "$RG_NAME" && -n "$VM1_NAME" && -z "$VM1_PRIVATE_IP" ]]; then
  VM1_PRIVATE_IP="$(get_vm_private_ip_from_azure "$RG_NAME" "$VM1_NAME")"
fi

if [[ -n "$RG_NAME" && -n "$VM2_NAME" && -z "$VM2_PRIVATE_IP" ]]; then
  VM2_PRIVATE_IP="$(get_vm_private_ip_from_azure "$RG_NAME" "$VM2_NAME")"
fi

if [[ -z "$RG_NAME" || -z "$NSG_NAME" || -z "$AKS_SUBNET_CIDR" || -z "$VM1_NAME" || -z "$VM2_NAME" ]]; then
  err "Could not resolve all required values from Terraform state/outputs."
  printf 'Resolved so far:\n'
  printf '  resource_group_name: %s\n' "${RG_NAME:-<empty>}"
  printf '  nsg_name: %s\n' "${NSG_NAME:-<empty>}"
  printf '  aks_subnet_cidr: %s\n' "${AKS_SUBNET_CIDR:-<empty>}"
  printf '  vm1_name: %s\n' "${VM1_NAME:-<empty>}"
  printf '  vm2_name: %s\n' "${VM2_NAME:-<empty>}"
  printf '  vm1_private_ip: %s\n' "${VM1_PRIVATE_IP:-<empty>}"
  printf '  vm2_private_ip: %s\n' "${VM2_PRIVATE_IP:-<empty>}"
  printf '\n'
  err "Provide missing values with --rg, --nsg, --aks-cidr, --vm1, --vm2, --vm1-ip, --vm2-ip."
  exit 1
fi

log "Resolved inputs:"
printf '  Resource Group : %s\n' "$RG_NAME"
printf '  NSG Name       : %s\n' "$NSG_NAME"
printf '  AKS CIDR       : %s\n' "$AKS_SUBNET_CIDR"
printf '  VM 1 Name      : %s\n' "$VM1_NAME"
printf '  VM 2 Name      : %s\n' "$VM2_NAME"
printf '  VM 1 IP        : %s\n' "${VM1_PRIVATE_IP:-<unknown>}"
printf '  VM 2 IP        : %s\n' "${VM2_PRIVATE_IP:-<unknown>}"

NSG_RULES_JSON="$(az network nsg rule list \
  --resource-group "$RG_NAME" \
  --nsg-name "$NSG_NAME" \
  -o json 2>/dev/null || echo '[]')"

printf '\n=== Matching NSG Rules for AKS -> Gateway Ports 8500/8501 ===\n'

MATCHING_RULES="$(jq --arg aks "$AKS_SUBNET_CIDR" '
  [
    .[]
    | select((.direction // "") == "Inbound")
    | select((.access // "") == "Allow")
    | select(((.protocol // "*") == "Tcp") or ((.protocol // "*") == "*"))
    | select(
        ((.sourceAddressPrefix // "") == $aks)
        or (((.sourceAddressPrefixes // []) | index($aks)) != null)
        or ((.sourceAddressPrefix // "") == "*")
      )
    | select(
        ((.destinationPortRange // "") == "8500")
        or ((.destinationPortRange // "") == "8501")
        or ((.destinationPortRange // "") == "*")
        or (((.destinationPortRanges // []) | index("8500")) != null)
        or (((.destinationPortRanges // []) | index("8501")) != null)
        or ((((.destinationPortRanges // []) | index("8500")) != null) and (((.destinationPortRanges // []) | index("8501")) != null))
      )
    | {
        name: .name,
        priority: .priority,
        sourceAddressPrefix: .sourceAddressPrefix,
        sourceAddressPrefixes: .sourceAddressPrefixes,
        destinationAddressPrefix: .destinationAddressPrefix,
        destinationAddressPrefixes: .destinationAddressPrefixes,
        destinationPortRange: .destinationPortRange,
        destinationPortRanges: .destinationPortRanges,
        protocol: .protocol,
        access: .access,
        direction: .direction
      }
  ]
' <<<"$NSG_RULES_JSON")"

echo "$MATCHING_RULES" | jq .

RULE_COUNT="$(echo "$MATCHING_RULES" | jq 'length')"

PORT_8500_OK="no"
PORT_8501_OK="no"

if echo "$MATCHING_RULES" | jq -e '
  any(.[];
    (
      (.destinationPortRange == "8500")
      or (.destinationPortRange == "*")
      or ((.destinationPortRanges // []) | index("8500") != null)
    )
  )
' >/dev/null 2>&1; then
  PORT_8500_OK="yes"
fi

if echo "$MATCHING_RULES" | jq -e '
  any(.[];
    (
      (.destinationPortRange == "8501")
      or (.destinationPortRange == "*")
      or ((.destinationPortRanges // []) | index("8501") != null)
    )
  )
' >/dev/null 2>&1; then
  PORT_8501_OK="yes"
fi

printf '\n=== Terraform State Check ===\n'
terraform -chdir="${MODULE_DIR}" state list 2>/dev/null | jq -R -s -c 'split("\n") | map(select(length > 0))' | jq .

printf '\n=== Summary ===\n'
printf 'NSG name                         : %s\n' "$NSG_NAME"
printf 'AKS subnet CIDR                  : %s\n' "$AKS_SUBNET_CIDR"
printf 'VM 1 name / private IP           : %s / %s\n' "$VM1_NAME" "${VM1_PRIVATE_IP:-<unknown>}"
printf 'VM 2 name / private IP           : %s / %s\n' "$VM2_NAME" "${VM2_PRIVATE_IP:-<unknown>}"
printf 'Matching inbound allow rules     : %s\n' "$RULE_COUNT"
printf 'Port 8500 allowed from AKS CIDR  : %s\n' "$PORT_8500_OK"
printf 'Port 8501 allowed from AKS CIDR  : %s\n' "$PORT_8501_OK"

cat <<'EOF'

Interpretation:
- This NSG is attached to the DMZ/SFTP subnet NIC path, so a matching inbound allow rule on the NSG covers the two DMZ machines behind it.
- Expected rule shape from the README reference:
  - direction: Inbound
  - access: Allow
  - protocol: Tcp
  - source: AKS subnet CIDR (for example 10.1.10.0/24)
  - destination ports: 8500 and 8501
- If port 8500 or 8501 is reported "no", AKS-to-gateway traffic is not fully allowed by the current NSG rules.
EOF

# Made with Bob
