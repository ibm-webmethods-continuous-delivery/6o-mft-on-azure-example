#!/usr/bin/env bash
KEYVAULT_NAME="${1:-$KEYVAULT_NAME}"

echo "Secrets in Key Vault: ${KEYVAULT_NAME}"
echo "================================================"

az keyvault certificate list --vault-name "${KEYVAULT_NAME}" --query "[].name" -o tsv | while read -r secret; do
  details=$(az keyvault certificate show --vault-name "${KEYVAULT_NAME}" --name "$secret" \
    --query "{contentType:contentType, description:tags.Description}" -o json)

  content_type=$(echo "$details" | jq -r '.contentType // "N/A"')
  description=$(echo "$details" | jq -r '.description // "N/A"')

  printf "%-50s | %-25s | %s\n" "$secret" "$content_type" "$description"
done

