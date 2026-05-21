# Database User Initialization for Azure PostgreSQL

This component creates the application database users required by IBM webMethods Active Transfer before running the Database Configurator.

## Purpose

Terraform provisions the PostgreSQL server and databases but does **not** create application users. This component fills that gap by creating lower-privilege application users that will be used by:

1. Database Configurator (DBC) - to create webMethods schemas
2. Active Transfer pods - to connect to the databases

## Execution Order

```
00-DatabaseUserInit → 01-DatabaseConfigurator → 02-AT
```

## Quick Start

### Step 1: Decide Application Credentials

Choose usernames and generate strong passwords for the application users:

```bash
# Example usernames (you can customize these)
export POSTGRES_USER="mft_app_user"
export POSTGRES_ARCHIVE_USER="mft_archive_user"

# Generate strong passwords (Linux/macOS)
export POSTGRES_PASSWORD=$(openssl rand -base64 24)
export POSTGRES_ARCHIVE_PASSWORD=$(openssl rand -base64 24)

# Display for saving (IMPORTANT: Save these securely!)
echo "Online DB User: ${POSTGRES_USER}"
echo "Online DB Password: ${POSTGRES_PASSWORD}"
echo "Archive DB User: ${POSTGRES_ARCHIVE_USER}"
echo "Archive DB Password: ${POSTGRES_ARCHIVE_PASSWORD}"
```

**CRITICAL:** Save these credentials securely. You will need them for Database Configurator and Active Transfer deployment.

### Step 2: Generate and Apply Secret

The script automatically retrieves Terraform outputs and generates the Kubernetes secret:

```bash
cd /aio/work/c/iwcd/6o-mft-on-azure-example/03-TechnologyServices/00-DatabaseUserInit

# Generate secret (uses environment variables from Step 1)
./scripts/generate-secret.sh

# Apply the secret
kubectl apply -f kubernetes/secret-db-user-init-admin-creds.yaml
```

**Alternative:** If you prefer interactive prompts, run the script without setting environment variables:

```bash
./scripts/generate-secret.sh
# The script will prompt you for the application credentials
```

### Step 3: Deploy the Job

```bash
./deploy.sh
```

### Step 4: Verify Execution

```bash
kubectl get jobs -l app=database-user-init
kubectl logs -l app=database-user-init --tail=50
```

## What Gets Created

The initialization job:

- Connects to PostgreSQL using admin credentials (from Terraform)
- Creates two application users with strong passwords (your input)
- Grants necessary privileges on the online and archive databases
- Is idempotent and can be re-run safely

## Files

- `scripts/generate-secret.sh` - Automated secret generation from Terraform outputs
- `scripts/create-users.sh` - Idempotent PostgreSQL user/grant initialization
- `kubernetes/secret-db-user-init-admin-creds.yaml.template` - Secret template with envsubst variables
- `kubernetes/configmap-db-user-init-script.yaml` - Mounts the initialization script
- `kubernetes/job-db-user-init.yaml` - Kubernetes Job definition
- `deploy.sh` - Deployment helper script
- `show_db_tf_outputs.sh` - Display Terraform outputs (for reference)

## Notes

- The job uses PostgreSQL admin credentials only to create application users
- DBC and Active Transfer should use the application users, not admin credentials
- The generated secret file is in `.gitignore` and should never be committed
- For production, use enterprise secrets management (Azure Key Vault, HashiCorp Vault, etc.)
- Rotate credentials regularly in production environments
