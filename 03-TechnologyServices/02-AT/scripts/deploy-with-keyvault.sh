#!/usr/bin/env bash
# Deploy Active Transfer with Azure Key Vault integration and Terraform-derived values.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
HELM_DIR="${AT_DIR}/helm"
TF_DIR="${AT_DIR}/../../01-AzurePrerequisites/02-ServiceFulfillment"
GENERATED_VALUES_FILE="${HELM_DIR}/generated-values.keyvault.yaml"

NAMESPACE="default"
RELEASE_NAME="active-transfer"
TF_VARS_FILE=""
TF_OUTPUTS_FILE=""
DRY_RUN=false
SKIP_VERIFY=false

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_error() { echo -e "${RED}❌ Error: $1${NC}" >&2; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  Warning: $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Deploy Active Transfer with Azure Key Vault integration.

Options:
  -n, --namespace NAME       Kubernetes namespace (default: default)
  -r, --release NAME         Helm release name (default: active-transfer)
      --tfvars FILE          Terraform tfvars file to use with terraform output
      --tf-outputs FILE      Existing terraform output JSON file to use
      --dry-run              Generate values and run helm in dry-run mode
      --skip-verify          Skip post-deployment verification
  -h, --help                 Show this help

Examples:
  $0 --tfvars /path/to/ibm-test.tfvars
  $0 --namespace mft --release active-transfer --dry-run
  $0 --tf-outputs /path/to/terraform-outputs.json
EOF
}

check_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        print_error "Missing required tool: $1"
        exit 1
    fi
}

check_prerequisites() {
    check_command helm
    check_command kubectl
    check_command jq

    if [[ -n "${TF_OUTPUTS_FILE}" ]]; then
        if [[ ! -f "${TF_OUTPUTS_FILE}" ]]; then
            print_error "Terraform outputs file not found: ${TF_OUTPUTS_FILE}"
            exit 1
        fi
        return
    fi

    check_command terraform

    if [[ ! -d "${TF_DIR}" ]]; then
        print_error "Terraform directory not found: ${TF_DIR}"
        exit 1
    fi

    if [[ -n "${TF_VARS_FILE}" && ! -f "${TF_VARS_FILE}" ]]; then
        print_error "Terraform tfvars file not found: ${TF_VARS_FILE}"
        exit 1
    fi
}

capture_terraform_outputs() {
    if [[ -n "${TF_OUTPUTS_FILE}" ]]; then
        print_info "Using existing Terraform outputs file: ${TF_OUTPUTS_FILE}"
        return
    fi

    TF_OUTPUTS_FILE="$(mktemp)"
    print_info "Capturing Terraform outputs from ${TF_DIR}"

    if [[ -n "${TF_VARS_FILE}" ]]; then
        TF_CLI_ARGS_output="--var-file=${TF_VARS_FILE}" terraform -chdir="${TF_DIR}" output -json > "${TF_OUTPUTS_FILE}"
    else
        terraform -chdir="${TF_DIR}" output -json > "${TF_OUTPUTS_FILE}"
    fi
}

extract_output() {
    local key="$1"
    local value
    value="$(jq -r --arg key "${key}" '.[$key].value // empty' "${TF_OUTPUTS_FILE}")"
    if [[ -z "${value}" || "${value}" == "null" ]]; then
        print_error "Missing Terraform output: ${key}"
        exit 1
    fi
    printf '%s' "${value}"
}

generate_values_file() {
    local key_vault_name tenant_id client_id environment acr_login_server
    local postgres_server_fqdn postgres_online_db_name postgres_archive_db_name
    local postgres_dbc_user postgres_dbc_archive_user app_gateway_public_ip
    local sftp_vm_1_private_ip sftp_vm_2_private_ip

    key_vault_name="$(extract_output key_vault_name)"
    tenant_id="$(extract_output tenant_id)"
    client_id="$(extract_output mft_managed_identity_client_id)"
    environment="$(extract_output environment_name)"
    acr_login_server="$(extract_output acr_login_server)"
    postgres_server_fqdn="$(extract_output postgres_server_fqdn)"
    postgres_online_db_name="$(extract_output postgres_online_db_name)"
    postgres_archive_db_name="$(extract_output postgres_archive_db_name)"
    postgres_dbc_user="$(extract_output postgres_dbc_user)"
    postgres_dbc_archive_user="$(extract_output postgres_dbc_archive_user)"
    app_gateway_public_ip="$(extract_output app_gateway_public_ip)"
    sftp_vm_1_private_ip="$(extract_output sftp_vm_1_private_ip)"
    sftp_vm_2_private_ip="$(extract_output sftp_vm_2_private_ip)"

    cat > "${GENERATED_VALUES_FILE}" <<EOF
secretProvider:
  type: "azureKeyVault"

azureKeyVault:
  name: "${key_vault_name}"
  tenantId: "${tenant_id}"
  clientId: "${client_id}"
  environment: "${environment}"

image:
  repository: "${acr_login_server}/active-transfer-enhance"

database:
  serverFqdn: "${postgres_server_fqdn}"
  onlineDbName: "${postgres_online_db_name}"
  archiveDbName: "${postgres_archive_db_name}"
  onlineDbUser: "${postgres_dbc_user}"
  archiveDbUser: "${postgres_dbc_archive_user}"

ingress:
  hosts:
    - host: "${app_gateway_public_ip}.nip.io"
      paths:
        - path: /
          pathType: Prefix
          port: 5555
  tls:
    - secretName: mft-admin-tls
      hosts:
        - "${app_gateway_public_ip}.nip.io"

mftConfig:
  gateways:
    - instanceName: "Gateway1"
      host: "${sftp_vm_1_private_ip}"
      port: 8500
      active: true
      autoConnect: true
    - instanceName: "Gateway2"
      host: "${sftp_vm_2_private_ip}"
      port: 8500
      active: true
      autoConnect: true
EOF

    print_success "Generated values file: ${GENERATED_VALUES_FILE}"
}

run_helm() {
    local helm_cmd=(
        helm upgrade --install "${RELEASE_NAME}" "${HELM_DIR}"
        --namespace "${NAMESPACE}"
        --create-namespace
        --values "${HELM_DIR}/values.yaml"
        --values "${GENERATED_VALUES_FILE}"
    )

    if [[ "${DRY_RUN}" == "true" ]]; then
        helm_cmd+=(--dry-run=client --debug)
    else
        helm_cmd+=(--wait --timeout 10m)
    fi

    print_info "Running Helm deployment"
    "${helm_cmd[@]}"
}

verify_deployment() {
    if [[ "${SKIP_VERIFY}" == "true" || "${DRY_RUN}" == "true" ]]; then
        return
    fi

    print_info "Verifying deployment resources"
    kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/name=active-transfer
    kubectl get secretproviderclass -n "${NAMESPACE}"
    kubectl describe serviceaccount -n "${NAMESPACE}" mft-service-account | grep -A 3 "Annotations:" || true
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            -r|--release)
                RELEASE_NAME="$2"
                shift 2
                ;;
            --tfvars)
                TF_VARS_FILE="$2"
                shift 2
                ;;
            --tf-outputs)
                TF_OUTPUTS_FILE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-verify)
                SKIP_VERIFY=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    check_prerequisites
    capture_terraform_outputs
    generate_values_file
    run_helm
    verify_deployment

    print_success "Active Transfer Key Vault deployment flow completed"
    print_info "Generated values file retained at ${GENERATED_VALUES_FILE}"
}

main "$@"