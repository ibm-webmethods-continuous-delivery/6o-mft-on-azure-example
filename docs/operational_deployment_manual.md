# Operational Deployment Manual
## IBM webMethods Active Transfer on Azure AKS

**Version:** 0.1 DRAFT
**Date:** 2026-05-26
**Repository:** `iwcd/6o-mft-on-azure-example/`

---

## Executive Summary

This manual provides comprehensive operational procedures for deploying IBM webMethods Active Transfer (MFT) on Azure Kubernetes Service (AKS), including gateway services for external SFTP access.

### Deployment Architecture Overview

```
┌───────────────────────────────────────────────────────────────────────────┐
│                         DEPLOYMENT FLOW DIAGRAM                           │
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │ PHASE 0: INFRASTRUCTURE (Terraform - Pre-requisite)                 │  │
│  │ ✓ Azure AKS Cluster                                                 │  │
│  │ ✓ Azure PostgreSQL Flexible Server (Online + Archive DBs)           │  │
│  │ ✓ Azure Container Registry (ACR)                                    │  │
│  │ ✓ Gateway VMs (2x in public subnets)                                │  │
│  │ ✓ Virtual Network with subnets                                      │  │
│  │ ✓ Application Gateway for ingress                                   │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                    │                                      │
│                                    ▼                                      │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │ PHASE 1: CERTIFICATES (00-Certificates)                             │  │
│  │ Duration: ~5 minutes                                                │  │
│  │ • Generate Admin UI certificates (JKS, PKCS12)                      │  │
│  │ • Generate Web Client certificates (JKS, PKCS12)                    │  │
│  │ • Generate SFTP SSH keys (RSA)                                      │  │
│  │ • Generate CA root certificate                                      │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                    │                                      │
│                                    ▼                                      │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │ PHASE 2: DATABASE PREPARATION                                       │  │
│  │                                                                     │  │
│  │  Step 2.1: Database User Init (00-DatabaseUserInit)                 │  │
│  │  Duration: ~2 minutes                                               │  │
│  │  • Create application database users                                │  │
│  │  • Grant necessary privileges                                       │  │
│  │                                                                     │  │
│  │                         ▼                                           │  │
│  │                                                                     │  │
│  │  Step 2.2: Database Configurator (01-DatabaseConfigurator)          │  │
│  │  Duration: ~10-15 minutes                                           │  │
│  │  • Initialize webMethods schemas in Online DB                       │  │
│  │  • Initialize webMethods schemas in Archive DB                      │  │
│  │  • Create ISInternal, ISCoreAudit, ActiveTransfer, CentralUsers     │  │
│  │  • Create ActiveTransferArchive, ComponentTracker, TaskArchive      │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                    │                                      │
│                                    ▼                                      │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │ PHASE 3: ACTIVE TRANSFER DEPLOYMENT (02-AT)                         │  │
│  │ Duration: ~5-10 minutes                                             │  │
│  │ • Generate Kubernetes secrets (DB creds, certificates, MFT config)  │  │
│  │ • Deploy Helm chart (2 replicas across AZs)                         │  │
│  │ • Create Azure Files PVC for VFS storage                            │  │
│  │ • Configure ingress for Admin UI                                    │  │
│  │ • Verify pod startup and database connectivity                      │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                    │                                      │
│                                    ▼                                      │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │ PHASE 4: GATEWAY DEPLOYMENT (03-ATGateway)                          │  │
│  │ Duration: ~5 minutes per gateway                                    │  │
│  │ • Deploy Gateway 1 (VM in AZ1, IP: 10.1.0.4)                        │  │
│  │ • Deploy Gateway 2 (VM in AZ2, IP: 10.1.1.4)                        │  │
│  │ • Configure Docker Compose with ACR image                           │  │
│  │ • Enable systemd service for auto-start                             │  │
│  │ • Verify gateway registration with AT server                        │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                                                           │
└───────────────────────────────────────────────────────────────────────────┘

                                    ▼

┌─────────────────────────────────────────────────────────────────────────────┐
│                         RUNTIME ARCHITECTURE                                │
│                                                                             │
│  External Clients (SFTP)                                                    │
│         │                                                                   │
│         ▼                                                                   │
│  ┌─────────────────┐                                                        │
│  │ Load Balancer   │ (Public IP)                                            │
│  └────────┬────────┘                                                        │
│           │                                                                 │
│     ┌─────┴─────┐                                                           │
│     │           │                                                           │
│     ▼           ▼                                                           │
│  ┌──────┐   ┌──────┐                                                        │
│  │ GW1  │   │ GW2  │  (Public Subnet VMs)                                   │
│  │10.1. │   │10.1. │  Port 8500 (Gateway)                                   │
│  │0.4   │   │1.4   │  Port 55022 (SFTP)                                     │
│  └───┬──┘   └───┬──┘                                                        │
│      │          │                                                           │
│      └────┬─────┘                                                           │
│           │                                                                 │
│           ▼                                                                 │
│  ┌─────────────────────────────────────┐                                    │
│  │   AKS Cluster (Private Subnet)      │                                    │
│  │   ┌──────────┐     ┌──────────┐     │                                    │
│  │   │ AT Pod 1 │     │ AT Pod 2 │     │                                    │
│  │   │  (AZ1)   │     │  (AZ2)   │     │                                    │
│  │   └────┬─────┘     └────┬─────┘     │                                    │
│  │        │                │           │                                    │
│  │        └────────┬───────┘           │                                    │
│  └─────────────────┼───────────────────┘                                    │
│                    │                                                        │
│          ┌─────────┴─────────┐                                              │
│          │                   │                                              │
│          ▼                   ▼                                              │
│  ┌──────────────┐   ┌──────────────┐                                        │
│  │ Azure Files  │   │ PostgreSQL   │                                        │
│  │ (VFS)        │   │ Flex Server  │                                        │
│  │ ReadWriteMany│   │ • Online DB  │                                        │
│  └──────────────┘   │ • Archive DB │                                        │
│                     └──────────────┘                                        │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Key Deployment Characteristics

- **Total Deployment Time:** ~30-40 minutes (excluding infrastructure provisioning)
- **High Availability:** 2 replicas across Azure Availability Zones
- **Storage:** Azure Files (ReadWriteMany) for shared VFS
- **Database:** PostgreSQL Flexible Server with separate online and archive databases
- **External Access:** Gateway VMs in public subnets for SFTP traffic
- **Security:** Certificate-based HTTPS, SSH keys for SFTP, managed identities for ACR

### Critical Dependencies

1. **Infrastructure First:** All Azure resources must be provisioned via Terraform
2. **Sequential Execution:** Database preparation must complete before AT deployment
3. **Gateway Configuration:** Gateway IPs are configured in AT secret template, not values.yaml
4. **Certificates:** Must be generated before AT deployment
5. **Network Connectivity:** AKS must have network access to PostgreSQL and Gateway VMs

---

## Table of Contents

1. [Prerequisites Verification](#prerequisites-verification)
2. [Phase 0: Infrastructure Validation](#phase-0-infrastructure-validation)
3. [Phase 1: Certificate Generation](#phase-1-certificate-generation)
4. [Phase 2: Database Preparation](#phase-2-database-preparation)
5. [Phase 3: Active Transfer Deployment](#phase-3-active-transfer-deployment)
6. [Phase 4: Gateway Deployment](#phase-4-gateway-deployment)
7. [Post-Deployment Verification](#post-deployment-verification)
8. [Troubleshooting Guide](#troubleshooting-guide)
9. [Rollback Procedures](#rollback-procedures)

---

## Prerequisites Verification

### Required Tools

Verify all required tools are installed and accessible:

```bash
# Check kubectl
kubectl version --client
# Expected: Client Version: v1.28.x or higher

# Check helm
helm version
# Expected: version.BuildInfo{Version:"v3.x.x"}

# Check Azure CLI (for gateway deployment)
az --version
# Expected: azure-cli 2.x.x

# Check openssl (for certificate generation)
openssl version
# Expected: OpenSSL 1.1.1 or higher

# Check envsubst (for template processing)
envsubst --version
# Expected: envsubst (GNU gettext-runtime) 0.x
```

### Kubernetes Access

```bash
# Verify cluster access
kubectl cluster-info

# Verify namespace exists or create it
kubectl get namespace mft || kubectl create namespace mft

# Verify RBAC permissions
kubectl auth can-i create deployments --namespace mft
kubectl auth can-i create secrets --namespace mft
kubectl auth can-i create configmaps --namespace mft
```

### Azure Access (for Gateway Deployment)

```bash
# Verify Azure CLI authentication
az account show

# Set correct subscription
az account set --subscription "<subscription-id-or-name>"

# Verify permissions on resource group
az role assignment list --assignee $(az account show --query user.name -o tsv) \
  --scope "/subscriptions/<subscription-id>/resourceGroups/<resource-group>"
```

---

## Phase 0: Infrastructure Validation

**Duration:** 5 minutes
**Location:** `6o-mft-on-azure-example/01-AzurePrerequisites/02-ServiceFulfillment`

### Objective

Verify that all Azure infrastructure components are provisioned and accessible.

### Steps

**Step 0.1: Navigate to Terraform Directory**

```bash
cd 6o-mft-on-azure-example/01-AzurePrerequisites/02-ServiceFulfillment
```

**Step 0.2: Retrieve Terraform Outputs**

```bash
# Display all outputs
terraform output

# Save outputs to file for reference
terraform output -json > /tmp/terraform-outputs.json
```

**Step 0.3: Verify Critical Resources**

```bash
# AKS Cluster
terraform output aks_cluster_name
terraform output aks_cluster_id

# PostgreSQL Server
terraform output postgres_server_fqdn
terraform output postgres_online_db_name
terraform output postgres_archive_db_name

# ACR
terraform output acr_login_server
terraform output acr_name

# Gateway VMs
terraform output gateway1_vm_name
terraform output gateway1_private_ip  # Should be 10.1.0.4
terraform output gateway2_vm_name
terraform output gateway2_private_ip  # Should be 10.1.1.4

# Network
terraform output vnet_name
terraform output aks_subnet_id
terraform output gateway_subnet_ids
```

**Step 0.4: Verify AKS Connectivity**

```bash
# Get AKS credentials
az aks get-credentials \
  --resource-group $(terraform output -raw resource_group_name) \
  --name $(terraform output -raw aks_cluster_name) \
  --overwrite-existing

# Test connectivity
kubectl get nodes
kubectl get namespaces
```

**Step 0.5: Verify PostgreSQL Connectivity**

```bash
# Test from local machine (if allowed by firewall)
PGPASSWORD='<admin-password>' psql \
  -h $(terraform output -raw postgres_server_fqdn) \
  -U $(terraform output -raw postgres_admin_username) \
  -d postgres \
  -c "SELECT version();"

# Or test from AKS pod
kubectl run psql-test --image=postgres:15 --rm -it --restart=Never -- \
  psql -h $(terraform output -raw postgres_server_fqdn) \
  -U $(terraform output -raw postgres_admin_username) \
  -d postgres \
  -c "SELECT version();"
```

**Step 0.6: Verify ACR Access**

```bash
# Login to ACR
az acr login --name $(terraform output -raw acr_name)

# List images
az acr repository list --name $(terraform output -raw acr_name)

# Verify required images exist
az acr repository show-tags \
  --name $(terraform output -raw acr_name) \
  --repository active-transfer-enhance

az acr repository show-tags \
  --name $(terraform output -raw acr_name) \
  --repository active-transfer-dcc
```

### Success Criteria

- ✅ All Terraform outputs are available
- ✅ AKS cluster is accessible via kubectl
- ✅ PostgreSQL server is reachable from AKS
- ✅ ACR contains required container images
- ✅ Gateway VMs are running and accessible

### Troubleshooting

**Issue:** Terraform outputs are missing or incomplete

**Solution:**
```bash
# Re-run terraform apply
terraform plan
terraform apply
```

**Issue:** Cannot connect to AKS

**Solution:**
```bash
# Verify AKS is running
az aks show --resource-group <rg-name> --name <aks-name> --query provisioningState

# Re-fetch credentials
az aks get-credentials --resource-group <rg-name> --name <aks-name> --overwrite-existing
```

---

## Phase 1: Certificate Generation

**Duration:** 5 minutes
**Location:** `6o-mft-on-azure-example/03-TechnologyServices/00-Certificates`

### Objective

Generate all required certificates and SSH keys for Active Transfer deployment.

### Steps

**Step 1.1: Navigate to Certificates Directory**

```bash
cd 6o-mft-on-azure-example/03-TechnologyServices/00-Certificates
```

**Step 1.2: Review Certificate Configuration**

```bash
# Check docker-compose.yml for certificate generation settings
cat docker-compose.yml

# Verify scripts directory
ls -la scripts/
```

**Step 1.3: Generate Certificates**

```bash
# On Windows (from repository root)
generate.bat

# On Linux/macOS (if docker-compose is available)
docker-compose up
```

**Step 1.4: Verify Generated Certificates**

```bash
# Check data directory for generated files
ls -la data/

# Expected files:
# - admin-ui-keystore.jks
# - admin-ui-keystore.p12
# - admin-ui-truststore.jks
# - web-client-keystore.jks
# - web-client-keystore.p12
# - web-client-truststore.jks
# - sftp-ssh-key (RSA private key)
# - sftp-ssh-key.pub (RSA public key)
# - ca-cert.pem (CA root certificate)
```

**Step 1.5: Secure Certificate Files**

```bash
# Set appropriate permissions (Linux/macOS)
chmod 600 data/*.jks data/*.p12 data/sftp-ssh-key
chmod 644 data/*.pub data/*.pem

# Backup certificates to secure location
mkdir -p ~/mft-certificates-backup
cp -r data/* ~/mft-certificates-backup/
```

### Success Criteria

- ✅ All certificate files are generated in `data/` directory
- ✅ JKS keystores and truststores are present
- ✅ PKCS12 keystores are present
- ✅ SSH key pair is generated
- ✅ CA certificate is available
- ✅ Certificates are backed up securely

### Troubleshooting

**Issue:** Docker container fails to start

**Solution:**
```bash
# Check Docker is running
docker ps

# Check logs
docker-compose logs

# Rebuild container
docker-compose build --no-cache
docker-compose up
```

**Issue:** Permission denied errors

**Solution:**
```bash
# Ensure data directory is writable
chmod 755 data/

# Run with appropriate user permissions
docker-compose up
```

---

## Phase 2: Database Preparation

### Phase 2.1: Database User Initialization

**Duration:** 2 minutes
**Location:** `6o-mft-on-azure-example/03-TechnologyServices/00-DatabaseUserInit`

#### Objective

Create application database users with appropriate privileges for Active Transfer.

#### Steps

**Step 2.1.1: Navigate to Database User Init Directory**

```bash
cd 6o-mft-on-azure-example/03-TechnologyServices/00-DatabaseUserInit
```

**Step 2.1.2: Define Application Credentials**

```bash
# Set usernames (customize if needed)
export POSTGRES_USER="mft_app_user"
export POSTGRES_ARCHIVE_USER="mft_archive_user"

# Generate strong passwords
export POSTGRES_PASSWORD=$(openssl rand -base64 24)
export POSTGRES_ARCHIVE_PASSWORD=$(openssl rand -base64 24)

# Display credentials (SAVE THESE SECURELY!)
echo "=== APPLICATION DATABASE CREDENTIALS ==="
echo "Online DB User: ${POSTGRES_USER}"
echo "Online DB Password: ${POSTGRES_PASSWORD}"
echo "Archive DB User: ${POSTGRES_ARCHIVE_USER}"
echo "Archive DB Password: ${POSTGRES_ARCHIVE_PASSWORD}"
echo "========================================"

# Save to secure file
cat > ~/mft-db-credentials.txt <<EOF
Online DB User: ${POSTGRES_USER}
Online DB Password: ${POSTGRES_PASSWORD}
Archive DB User: ${POSTGRES_ARCHIVE_USER}
Archive DB Password: ${POSTGRES_ARCHIVE_PASSWORD}
EOF
chmod 600 ~/mft-db-credentials.txt
```

**Step 2.1.3: Generate Kubernetes Secret**

```bash
# Generate secret using script
./scripts/generate-secret.sh

# Verify secret file was created
ls -la kubernetes/secret-db-user-init-admin-creds.yaml
```

**Step 2.1.4: Apply Secret to Kubernetes**

```bash
# Apply the secret
kubectl apply -f kubernetes/secret-db-user-init-admin-creds.yaml

# Verify secret was created
kubectl get secret db-user-init-admin-creds -n mft
```

**Step 2.1.5: Deploy Database User Init Job**

```bash
# Deploy using script
./deploy.sh

# Or deploy manually
kubectl apply -f kubernetes/configmap-db-user-init-script.yaml
kubectl apply -f kubernetes/job-db-user-init.yaml
```

**Step 2.1.6: Monitor Job Execution**

```bash
# Watch job status
kubectl get jobs -n mft -l app=database-user-init -w

# View logs
kubectl logs -n mft -l app=database-user-init -f

# Expected output:
# Creating application users...
# User mft_app_user created successfully
# User mft_archive_user created successfully
# Granting privileges...
# Privileges granted successfully
```

**Step 2.1.7: Verify User Creation**

```bash
# Connect to PostgreSQL and verify users
kubectl run psql-verify --image=postgres:15 --rm -it --restart=Never -n mft -- \
  psql -h <POSTGRES_FQDN> -U <ADMIN_USER> -d postgres -c "\du"

# Should show mft_app_user and mft_archive_user
```

#### Success Criteria

- ✅ Application credentials are generated and saved securely
- ✅ Kubernetes secret is created
- ✅ Job completes successfully
- ✅ Database users are created with correct privileges

---

### Phase 2.2: Database Schema Initialization

**Duration:** 10-15 minutes
**Location:** `6o-mft-on-azure-example/03-TechnologyServices/01-DatabaseConfigurator`

#### Objective

Initialize webMethods database schemas in both online and archive databases.

#### Steps

**Step 2.2.1: Navigate to Database Configurator Directory**

```bash
cd 6o-mft-on-azure-example/03-TechnologyServices/01-DatabaseConfigurator
```

**Step 2.2.2: Display Terraform Outputs**

```bash
# Use helper script to display database connection info
./show_db_tf_outputs.sh

# Output will show:
# - POSTGRES_SERVER_FQDN
# - POSTGRES_ONLINE_DB
# - POSTGRES_ARCHIVE_DB
```

**Step 2.2.3: Create Database Credentials Secret**

```bash
# Copy template
cp kubernetes/secret-dbc-creds.yaml.template kubernetes/secret-dbc-creds.yaml

# Edit the file and fill in values from Terraform outputs and Phase 2.1
vi kubernetes/secret-dbc-creds.yaml

# Required values:
# - POSTGRES_SERVER_FQDN: from Terraform
# - POSTGRES_ONLINE_DB: from Terraform
# - POSTGRES_ARCHIVE_DB: from Terraform
# - POSTGRES_USER: from Phase 2.1 (mft_app_user)
# - POSTGRES_PASSWORD: from Phase 2.1
# - POSTGRES_ARCHIVE_USER: from Phase 2.1 (mft_archive_user)
# - POSTGRES_ARCHIVE_PASSWORD: from Phase 2.1
```

**Step 2.2.4: Apply Database Credentials Secret**

```bash
# Apply the secret
kubectl apply -f kubernetes/secret-dbc-creds.yaml

# Verify secret
kubectl get secret dbc-postgres-credentials -n mft
kubectl describe secret dbc-postgres-credentials -n mft
```

**Step 2.2.5: Deploy Database Configurator**

```bash
# Deploy using automated script (recommended)
./deploy.sh

# The script will:
# 1. Retrieve ACR login server from Terraform
# 2. Generate job manifest from template
# 3. Validate prerequisites
# 4. Deploy ConfigMap and Job
# 5. Show status and helpful commands
```

**Step 2.2.6: Monitor Database Initialization**

```bash
# Watch job status
kubectl get jobs -n mft -l app=database-configurator -w

# View logs in real-time
kubectl logs -n mft -l app=database-configurator -f

# Expected output:
# ==========================================
# Database Configurator - Starting
# ==========================================
# PostgreSQL Server: <server>.postgres.database.azure.com
# Online Database: mft_online
# Archive Database: mft_archive
# ==========================================
#
# Initializing online database: mft_online
# ------------------------------------------
# [DBC output showing schema creation...]
# ✓ Online database initialized successfully
#
# Initializing archive database: mft_archive
# ------------------------------------------
# [DBC output showing schema creation...]
# ✓ Archive database initialized successfully
#
# ==========================================
# Database Configurator - Completed
# ==========================================
```

**Step 2.2.7: Verify Schema Creation**

```bash
# Connect to online database and verify tables
kubectl run psql-verify --image=postgres:15 --rm -it --restart=Never -n mft -- \
  psql -h <POSTGRES_FQDN> -U mft_app_user -d mft_online -c "\dt"

# Should show tables like:
# - ISInternal tables
# - ISCoreAudit tables
# - ActiveTransfer tables
# - CentralUsers tables

# Connect to archive database and verify tables
kubectl run psql-verify --image=postgres:15 --rm -it --restart=Never -n mft -- \
  psql -h <POSTGRES_FQDN> -U mft_archive_user -d mft_archive -c "\dt"

# Should show tables like:
# - ActiveTransferArchive tables
# - ComponentTracker tables
# - TaskArchive tables
```

#### Success Criteria

- ✅ Database credentials secret is created
- ✅ Database Configurator job completes successfully
- ✅ Online database contains all required schemas
- ✅ Archive database contains all required schemas
- ✅ No errors in job logs

#### Troubleshooting

**Issue:** Job fails with connection errors

**Solution:**
```bash
# Verify database connectivity from AKS
kubectl run psql-test --image=postgres:15 --rm -it --restart=Never -n mft -- \
  psql -h <POSTGRES_FQDN> -U mft_app_user -d mft_online -c "SELECT 1;"

# Check PostgreSQL firewall rules in Azure Portal
# Ensure AKS subnet (10.1.10.0/24) is allowed

# Verify credentials in secret
kubectl get secret dbc-postgres-credentials -n mft -o yaml
```

**Issue:** Schema already exists warnings

**Solution:**
```
# This is normal and expected - DBC is idempotent
# The job will complete successfully
# No action needed
```

---

## Phase 3: Active Transfer Deployment

**Duration:** 5-10 minutes
**Location:** `6o-mft-on-azure-example/03-TechnologyServices/02-AT`

### Objective

Deploy Active Transfer Helm chart with 2 replicas across Azure Availability Zones.

### Steps

**Step 3.1: Navigate to Active Transfer Directory**

```bash
cd 6o-mft-on-azure-example/03-TechnologyServices/02-AT
```

**Step 3.2: Review and Update Helm Values**

```bash
# Review current values
cat helm/values.yaml

# Update values.yaml with your environment-specific settings
vi helm/values.yaml

# Key values to update:
# - image.repository: <ACR_LOGIN_SERVER>/active-transfer-enhance
# - database.serverFqdn: from Terraform output
# - database.onlineDbName: from Terraform output
# - database.archiveDbName: from Terraform output
# - database.onlineDbUser: from Phase 2.1 (mft_app_user)
# - database.archiveDbUser: from Phase 2.1 (mft_archive_user)
```

**Step 3.3: Prepare Certificate Passwords**

```bash
# Set certificate passwords as environment variables
export ADMIN_UI_KEYSTORE_PASSWORD="<your-admin-ui-keystore-password>"
export ADMIN_UI_TRUSTSTORE_PASSWORD="<your-admin-ui-truststore-password>"
export WEB_CLIENT_KEYSTORE_PASSWORD="<your-web-client-keystore-password>"
export WEB_CLIENT_TRUSTSTORE_PASSWORD="<your-web-client-truststore-password>"

# Set admin password
export ADMIN_PASSWORD="<your-admin-password>"

# Set database passwords (from Phase 2.1)
export POSTGRES_PASSWORD="<online-db-password>"
export POSTGRES_ARCHIVE_PASSWORD="<archive-db-password>"
```

**Step 3.4: Generate Kubernetes Secrets**

```bash
cd scripts

# Generate secrets (uses environment variables)
./generate-secrets.sh --apply

# The script will:
# 1. Process secret templates
# 2. Replace placeholders with actual values
# 3. Include gateway IPs (10.1.0.4, 10.1.1.4) in MFT config
# 4. Apply secrets to Kubernetes

# Verify secrets were created
kubectl get secrets -n mft | grep -E "mft-|active-transfer"
```

**Step 3.5: Deploy Active Transfer Helm Chart**

```bash
# Return to helm directory
cd ../helm

# Deploy using deployment script
../scripts/deploy.sh

# Or deploy manually with helm
helm install active-transfer . \
  --namespace mft \
  --values values.yaml \
  --wait \
  --timeout 10m

# For upgrade (if already deployed)
../scripts/deploy.sh --upgrade
```

**Step 3.6: Monitor Deployment**

```bash
# Watch pod creation
kubectl get pods -n mft -l app.kubernetes.io/name=active-transfer -w

# View deployment status
kubectl rollout status deployment/active-transfer -n mft

# Check pod events
kubectl describe pods -n mft -l app.kubernetes.io/name=active-transfer

# View logs from all pods
kubectl logs -n mft -l app.kubernetes.io/name=active-transfer -f --all-containers
```

**Step 3.7: Verify Pod Distribution**

```bash
# Verify pods are distributed across availability zones
kubectl get pods -n mft -l app.kubernetes.io/name=active-transfer \
  -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,ZONE:.metadata.labels.topology\\.kubernetes\\.io/zone

# Expected: Pods should be on different nodes in different zones
```

**Step 3.8: Verify Services and Ingress**

```bash
# Check service
kubectl get svc -n mft -l app.kubernetes.io/name=active-transfer

# Check ingress
kubectl get ingress -n mft -l app.kubernetes.io/name=active-transfer

# Describe ingress for details
kubectl describe ingress -n mft active-transfer
```

**Step 3.9: Verify Storage**

```bash
# Check PVC status
kubectl get pvc -n mft

# Should show: active-transfer-vfs with status "Bound"

# Check PV
kubectl get pv | grep active-transfer

# Verify Azure Files storage class
kubectl get storageclass azurefile-csi
```

**Step 3.10: Test Database Connectivity**

```bash
# Check database connection from pod
kubectl exec -it -n mft deployment/active-transfer -- \
  psql -h <POSTGRES_FQDN> -U mft_app_user -d mft_online -c "SELECT 1;"

# Should return: 1
```

### Success Criteria

- ✅ Helm chart deploys successfully
- ✅ 2 pods are running and ready
- ✅ Pods are distributed across different availability zones
- ✅ PVC is bound to Azure Files
- ✅ Services and ingress are created
- ✅ Database connectivity is verified
- ✅ No errors in pod logs

### Troubleshooting

**Issue:** Pods stuck in Pending state

**Solution:**
```bash
# Check pod events
kubectl describe pod -n mft -l app.kubernetes.io/name=active-transfer

# Common causes:
# - Insufficient resources
# - PVC not binding
# - Image pull errors
```

**Issue:** Database connection errors

**Solution:**
```bash
# Verify database credentials secret
kubectl get secret mft-db-credentials -n mft -o yaml

# Test connectivity from pod
kubectl exec -it -n mft deployment/active-transfer -- \
  nc -zv <POSTGRES_FQDN> 5432
```

---

## Phase 4: Gateway Deployment

**Duration:** 10 minutes (5 minutes per gateway)
**Location:** `6o-mft-on-azure-example/03-TechnologyServices/03-ATGateway`

### Objective

Deploy gateway services on Azure VMs to provide external SFTP access.

### Important Notes

- **Gateway IPs are configured in the AT secret template**, not in values.yaml
- Location: `03-TechnologyServices/02-AT/helm/templates/secret-mft-config.yaml.template`
- Gateway 1 IP: 10.1.0.4
- Gateway 2 IP: 10.1.1.4
- These IPs are replaced during secret generation in Phase 3

### Steps

**Step 4.1: Navigate to Gateway Directory**

```bash
cd 6o-mft-on-azure-example/03-TechnologyServices/03-ATGateway
```

**Step 4.2: Set Environment Variables**

```bash
# Get values from Terraform outputs
cd ../../01-AzurePrerequisites/02-ServiceFulfillment

export RESOURCE_GROUP=$(terraform output -raw resource_group_name)
export GATEWAY1_VM_NAME=$(terraform output -raw gateway1_vm_name)
export GATEWAY2_VM_NAME=$(terraform output -raw gateway2_vm_name)
export ACR_LOGIN_SERVER=$(terraform output -raw acr_login_server)

# Return to gateway directory
cd ../../03-TechnologyServices/03-ATGateway

# Verify variables
echo "Resource Group: ${RESOURCE_GROUP}"
echo "Gateway 1 VM: ${GATEWAY1_VM_NAME}"
echo "Gateway 2 VM: ${GATEWAY2_VM_NAME}"
echo "ACR: ${ACR_LOGIN_SERVER}"
```

**Step 4.3: Deploy Gateway 1**

```bash
# Make script executable
chmod +x deploy-gateway1-vm-run-command.sh

# Deploy Gateway 1
./deploy-gateway1-vm-run-command.sh

# Expected output:
# Deploying Gateway 1 to VM: <vm-name>
# Creating deployment directory...
# Copying docker-compose.yml...
# Copying configuration files...
# Creating systemd service...
# Pulling container image...
# Starting gateway service...
# Gateway 1 deployment completed successfully
```

**Step 4.4: Verify Gateway 1**

```bash
# Check service status
az vm run-command invoke \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${GATEWAY1_VM_NAME}" \
    --command-id RunShellScript \
    --scripts "systemctl status at-gateway.service" \
    --output table

# Check container status
az vm run-command invoke \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${GATEWAY1_VM_NAME}" \
    --command-id RunShellScript \
    --scripts "docker ps | grep at-gateway" \
    --output table

# View logs
az vm run-command invoke \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${GATEWAY1_VM_NAME}" \
    --command-id RunShellScript \
    --scripts "docker logs at-gateway1 --tail 50" \
    --output table
```

**Step 4.5: Deploy Gateway 2**

```bash
# Make script executable
chmod +x deploy-gateway2-vm-run-command.sh

# Deploy Gateway 2
./deploy-gateway2-vm-run-command.sh

# Expected output similar to Gateway 1
```

**Step 4.6: Verify Gateway 2**

```bash
# Check service status
az vm run-command invoke \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${GATEWAY2_VM_NAME}" \
    --command-id RunShellScript \
    --scripts "systemctl status at-gateway.service" \
    --output table

# Check container status
az vm run-command invoke \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${GATEWAY2_VM_NAME}" \
    --command-id RunShellScript \
    --scripts "docker ps | grep at-gateway" \
    --output table
```

**Step 4.7: Test Gateway Connectivity from AKS**

```bash
# Test Gateway 1 connectivity
kubectl run test-gateway1 --image=busybox --rm -it --restart=Never -n mft -- \
    sh -c "nc -zv 10.1.0.4 8500 && echo 'Gateway 1 is reachable'"

# Expected output:
# 10.1.0.4 (10.1.0.4:8500) open
# Gateway 1 is reachable

# Test Gateway 2 connectivity
kubectl run test-gateway2 --image=busybox --rm -it --restart=Never -n mft -- \
    sh -c "nc -zv 10.1.1.4 8500 && echo 'Gateway 2 is reachable'"

# Expected output:
# 10.1.1.4 (10.1.1.4:8500) open
# Gateway 2 is reachable
```

**Step 4.8: Verify Gateway Registration in Active Transfer**

```bash
# Access Active Transfer Admin UI
# Method 1: Port forward
kubectl port-forward -n mft svc/active-transfer 5555:5555

# Then open browser: http://localhost:5555
# Login with Administrator and password from Phase 3

# Method 2: Via ingress (if configured)
# https://mft-admin.local

# Navigate to: Settings > Gateways
# Verify both gateways show:
# - Status: Connected
# - Health: Green
# - Last Heartbeat: Recent timestamp
```

### Success Criteria

- ✅ Gateway 1 service is running on VM
- ✅ Gateway 2 service is running on VM
- ✅ Both gateways are reachable from AKS on port 8500
- ✅ Both gateways show as "Connected" in Active Transfer Admin UI
- ✅ No errors in gateway container logs

### Troubleshooting

**Issue:** Gateway container fails to start

**Solution:**
```bash
# Check logs
az vm run-command invoke \
    -g "${RESOURCE_GROUP}" \
    -n "${GATEWAY1_VM_NAME}" \
    --command-id RunShellScript \
    --scripts "docker logs at-gateway1 --tail 100" \
    --output table

# Common causes:
# - ACR authentication failure
# - Missing configuration file
# - Port already in use
```

**Issue:** Gateway not reachable from AKS

**Solution:**
```bash
# Verify NSG rules allow traffic from AKS subnet (10.1.10.0/24)
# Check in Azure Portal: Network Security Groups > Inbound rules
# Required rule: Allow TCP 8500-8501 from 10.1.10.0/24

# Test from gateway VM
az vm run-command invoke \
    -g "${RESOURCE_GROUP}" \
    -n "${GATEWAY1_VM_NAME}" \
    --command-id RunShellScript \
    --scripts "netstat -tlnp | grep 8500" \
    --output table
```

**Issue:** Gateway shows as "Disconnected" in Admin UI

**Solution:**
```bash
# Verify gateway configuration in secret
kubectl get secret mft-config-json -n mft -o yaml | grep -A 10 "declareGateways"

# Should show:
# - Gateway1: 10.1.0.4:8500
# - Gateway2: 10.1.1.4:8500

# If incorrect, regenerate secrets and upgrade helm chart
cd 6o-mft-on-azure-example/03-TechnologyServices/02-AT
./scripts/generate-secrets.sh --apply
helm upgrade active-transfer ./helm --namespace mft --values ./helm/values.yaml
```

---

## Post-Deployment Verification

### Comprehensive Health Check

**Step V.1: Verify All Components**

```bash
# Check all pods
kubectl get pods -n mft

# Expected output:
# NAME                               READY   STATUS    RESTARTS   AGE
# active-transfer-xxxxxxxxxx-xxxxx   1/1     Running   0          10m
# active-transfer-xxxxxxxxxx-xxxxx   1/1     Running   0          10m

# Check all services
kubectl get svc -n mft

# Check ingress
kubectl get ingress -n mft

# Check PVC
kubectl get pvc -n mft
```

**Step V.2: Access Admin UI**

```bash
# Port forward method
kubectl port-forward -n mft svc/active-transfer 5555:5555

# Open browser: http://localhost:5555
# Login: Administrator / <password-from-phase-3>
```

**Step V.3: Verify Database Connectivity**

```bash
# From Admin UI:
# 1. Navigate to: Settings > Database
# 2. Verify connection status shows "Connected"
# 3. Check both online and archive databases

# From command line:
kubectl exec -it -n mft deployment/active-transfer -- \
  psql -h <POSTGRES_FQDN> -U mft_app_user -d mft_online -c "SELECT COUNT(*) FROM wmuser;"
```

**Step V.4: Verify Gateway Status**

```bash
# From Admin UI:
# 1. Navigate to: Settings > Gateways
# 2. Verify both gateways show:
#    - Gateway1: Connected, IP: 10.1.0.4
#    - Gateway2: Connected, IP: 10.1.1.4
#    - Health: Green
#    - Last Heartbeat: Recent
```

**Step V.5: Test File Transfer (Optional)**

```bash
# From Admin UI:
# 1. Navigate to: Transfers > New Transfer
# 2. Create a test transfer
# 3. Execute and verify completion
```

**Step V.6: Verify Monitoring**

```bash
# Check Prometheus metrics (if enabled)
kubectl port-forward -n mft svc/active-transfer 5555:5555

# Access metrics: http://localhost:5555/metrics

# Verify key metrics:
# - jvm_memory_used_bytes
# - process_cpu_usage
# - active_transfer_connections_active
```

**Step V.7: Verify Logs**

```bash
# View application logs
kubectl logs -n mft -l app.kubernetes.io/name=active-transfer --tail=100

# Check for errors
kubectl logs -n mft -l app.kubernetes.io/name=active-transfer | grep -i error

# Check for warnings
kubectl logs -n mft -l app.kubernetes.io/name=active-transfer | grep -i warn
```

### Deployment Checklist

Use this checklist to verify successful deployment:

- [ ] **Infrastructure**
  - [ ] AKS cluster is accessible
  - [ ] PostgreSQL server is reachable
  - [ ] ACR contains required images
  - [ ] Gateway VMs are running

- [ ] **Certificates**
  - [ ] All certificates generated
  - [ ] Certificates backed up securely

- [ ] **Database**
  - [ ] Application users created
  - [ ] Online database schemas initialized
  - [ ] Archive database schemas initialized

- [ ] **Active Transfer**
  - [ ] Helm chart deployed successfully
  - [ ] 2 pods running and ready
  - [ ] Pods distributed across AZs
  - [ ] PVC bound to Azure Files
  - [ ] Services created
  - [ ] Ingress configured
  - [ ] Database connectivity verified

- [ ] **Gateways**
  - [ ] Gateway 1 deployed and running
  - [ ] Gateway 2 deployed and running
  - [ ] Both gateways reachable from AKS
  - [ ] Both gateways registered in Admin UI

- [ ] **Verification**
  - [ ] Admin UI accessible
  - [ ] Database connections working
  - [ ] Gateways showing as connected
  - [ ] No errors in logs
  - [ ] Monitoring metrics available

---

## Troubleshooting Guide

### Common Issues and Solutions

#### Issue 1: Pods Not Starting

**Symptoms:**
- Pods remain in `Pending` or `CrashLoopBackOff` state
- Deployment rollout stuck

**Diagnosis:**
```bash
# Check pod status
kubectl get pods -n mft -l app.kubernetes.io/name=active-transfer

# Describe pod for events
kubectl describe pod -n mft -l app.kubernetes.io/name=active-transfer

# Check logs
kubectl logs -n mft -l app.kubernetes.io/name=active-transfer
```

**Common Causes and Solutions:**

1. **Image Pull Errors**
   ```bash
   # Verify image exists in ACR
   az acr repository show-tags --name <acr-name> --repository active-transfer-enhance

   # Verify AKS can pull from ACR
   az aks check-acr --resource-group <rg> --name <aks-name> --acr <acr-name>
   ```

2. **Missing Secrets**
   ```bash
   # Verify all secrets exist
   kubectl get secrets -n mft | grep -E "mft-|active-transfer"

   # Recreate secrets if missing
   cd 6o-mft-on-azure-example/03-TechnologyServices/02-AT/scripts
   ./generate-secrets.sh --apply
   ```

3. **Insufficient Resources**
   ```bash
   # Check node resources
   kubectl top nodes

   # Check resource requests
   kubectl describe deployment active-transfer -n mft | grep -A 5 "Requests"

   # Scale down or adjust resource limits in values.yaml
   ```

#### Issue 2: Database Connection Failures

**Symptoms:**
- "Cannot connect to database" errors in logs
- Pods crash with database errors

**Diagnosis:**
```bash
# Test connectivity from pod
kubectl exec -it -n mft deployment/active-transfer -- \
  nc -zv <POSTGRES_FQDN> 5432

# Check database credentials
kubectl get secret mft-db-credentials -n mft -o yaml
```

**Solutions:**

1. **Network Connectivity**
   ```bash
   # Verify PostgreSQL firewall rules in Azure Portal
   # Ensure AKS subnet (10.1.10.0/24) is allowed

   # Test from AKS
   kubectl run psql-test --image=postgres:15 --rm -it --restart=Never -n mft -- \
     psql -h <POSTGRES_FQDN> -U mft_app_user -d mft_online -c "SELECT 1;"
   ```

2. **Invalid Credentials**
   ```bash
   # Verify credentials match those from Phase 2.1
   # Regenerate secrets with correct credentials
   cd 6o-mft-on-azure-example/03-TechnologyServices/02-AT/scripts

   # Set correct passwords
   export POSTGRES_PASSWORD="<correct-password>"
   export POSTGRES_ARCHIVE_PASSWORD="<correct-archive-password>"

   # Regenerate and apply
   ./generate-secrets.sh --apply

   # Restart pods
   kubectl rollout restart deployment/active-transfer -n mft
   ```

#### Issue 3: Gateway Connection Problems

**Symptoms:**
- Gateways show as "Disconnected" in Admin UI
- Cannot connect to gateways from AKS

**Diagnosis:**
```bash
# Test connectivity from AKS
kubectl run test-gw --image=busybox --rm -it --restart=Never -n mft -- \
  nc -zv 10.1.0.4 8500

# Check gateway logs
az vm run-command invoke \
  -g <resource-group> \
  -n <gateway-vm-name> \
  --command-id RunShellScript \
  --scripts "docker logs at-gateway1 --tail 100"
```

**Solutions:**

1. **Network Security Rules**
   ```bash
   # Verify NSG allows traffic from AKS subnet
   # Azure Portal > Network Security Groups > Inbound rules
   # Required: Allow TCP 8500-8501 from 10.1.10.0/24
   ```

2. **Gateway Configuration**
   ```bash
   # Verify gateway IPs in secret
   kubectl get secret mft-config-json -n mft -o yaml | grep -A 10 "declareGateways"

   # Should show:
   # Gateway1: 10.1.0.4:8500
   # Gateway2: 10.1.1.4:8500

   # If incorrect, regenerate secrets
   cd 6o-mft-on-azure-example/03-TechnologyServices/02-AT/scripts
   ./generate-secrets.sh --apply
   helm upgrade active-transfer ../helm --namespace mft
   ```

3. **Gateway Service Not Running**
   ```bash
   # Restart gateway service
   az vm run-command invoke \
     -g <resource-group> \
     -n <gateway-vm-name> \
     --command-id RunShellScript \
     --scripts "systemctl restart at-gateway.service"
   ```

#### Issue 4: Storage/VFS Problems

**Symptoms:**
- File transfer failures
- "Cannot write to VFS" errors
- PVC not binding

**Diagnosis:**
```bash
# Check PVC status
kubectl get pvc -n mft

# Describe PVC for events
kubectl describe pvc active-transfer-vfs -n mft

# Check storage class
kubectl get storageclass azurefile-csi
```

**Solutions:**

1. **PVC Not Binding**
   ```bash
   # Check if storage class exists
   kubectl get storageclass

   # Verify Azure Files is available
   # Azure Portal > Storage Accounts > File Shares

   # Delete and recreate PVC if needed
   kubectl delete pvc active-transfer-vfs -n mft
   helm upgrade active-transfer ./helm --namespace mft
   ```

2. **Permission Issues**
   ```bash
   # Check pod logs for permission errors
   kubectl logs -n mft -l app.kubernetes.io/name=active-transfer | grep -i permission

   # Verify mount permissions in deployment
   kubectl describe deployment active-transfer -n mft | grep -A 10 "Mounts"
   ```

#### Issue 5: Certificate Errors

**Symptoms:**
- SSL/TLS handshake failures
- Certificate validation errors
- Admin UI not accessible via HTTPS

**Diagnosis:**
```bash
# Check certificate secrets
kubectl get secret mft-admin-ui-certs -n mft -o yaml
kubectl get secret mft-web-client-certs -n mft -o yaml

# Check pod logs for certificate errors
kubectl logs -n mft -l app.kubernetes.io/name=active-transfer | grep -i certificate
```

**Solutions:**

1. **Regenerate Certificates**
   ```bash
   cd 6o-mft-on-azure-example/03-TechnologyServices/00-Certificates

   # Regenerate certificates
   docker-compose up

   # Regenerate secrets
   cd ../02-AT/scripts
   ./generate-secrets.sh --apply

   # Restart pods
   kubectl rollout restart deployment/active-transfer -n mft
   ```

2. **Incorrect Certificate Passwords**
   ```bash
   # Set correct passwords
   export ADMIN_UI_KEYSTORE_PASSWORD="<correct-password>"
   export ADMIN_UI_TRUSTSTORE_PASSWORD="<correct-password>"

   # Regenerate secrets
   cd 6o-mft-on-azure-example/03-TechnologyServices/02-AT/scripts
   ./generate-secrets.sh --apply

   # Restart pods
   kubectl rollout restart deployment/active-transfer -n mft
   ```

### Performance Issues

**Symptoms:**
- Slow response times
- High CPU/memory usage
- Timeouts

**Diagnosis:**
```bash
# Check resource usage
kubectl top pods -n mft -l app.kubernetes.io/name=active-transfer

# Check pod metrics
kubectl describe pod -n mft -l app.kubernetes.io/name=active-transfer | grep -A 10 "Limits\|Requests"
```

**Solutions:**

1. **Increase Resources**
   ```yaml
   # Edit helm/values.yaml
   resources:
     requests:
       cpu: 2000m      # Increase from 1000m
       memory: 4Gi     # Increase from 2Gi
     limits:
       cpu: 4000m      # Increase from 2000m
       memory: 8Gi     # Increase from 4Gi
   ```

2. **Scale Horizontally**
   ```bash
   # Increase replica count
   kubectl scale deployment active-transfer -n mft --replicas=3

   # Or update values.yaml and upgrade
   ```

3. **Optimize Database Connections**
   ```yaml
   # Edit helm/templates/configmap-application-properties.yaml
   # Adjust connection pool settings
   ```

---

## Rollback Procedures

### Rollback Active Transfer Deployment

**Scenario:** Active Transfer deployment fails or causes issues

**Steps:**

```bash
# View deployment history
helm history active-transfer -n mft

# Rollback to previous version
helm rollback active-transfer <revision-number> -n mft

# Or rollback to last successful deployment
helm rollback active-transfer -n mft

# Verify rollback
kubectl get pods -n mft -l app.kubernetes.io/name=active-transfer
kubectl logs -n mft -l app.kubernetes.io/name=active-transfer
```

### Rollback Gateway Deployment

**Scenario:** Gateway deployment fails or causes connectivity issues

**Steps:**

```bash
# Stop gateway service
az vm run-command invoke \
  -g <resource-group> \
  -n <gateway-vm-name> \
  --command-id RunShellScript \
  --scripts "systemctl stop at-gateway.service"

# Remove deployment
az vm run-command invoke \
  -g <resource-group> \
  -n <gateway-vm-name> \
  --command-id RunShellScript \
  --scripts "rm -rf /opt/at-gateway"

# Redeploy with previous configuration
# (Keep backup of working configuration)
```

### Rollback Database Changes

**Scenario:** Database schema issues

**Important:** Database rollback is complex and should be avoided. Always test in non-production first.

**Steps:**

```bash
# If database configurator needs to be re-run:
# 1. Drop and recreate databases (DESTRUCTIVE!)
# 2. Re-run database configurator

# Connect to PostgreSQL
kubectl run psql-admin --image=postgres:15 --rm -it --restart=Never -n mft -- \
  psql -h <POSTGRES_FQDN> -U <ADMIN_USER> -d postgres

# Drop databases (CAUTION!)
DROP DATABASE mft_online;
DROP DATABASE mft_archive;

# Recreate databases
CREATE DATABASE mft_online;
CREATE DATABASE mft_archive;

# Re-run database configurator (Phase 2.2)
```

### Complete Uninstall

**Scenario:** Need to completely remove deployment

**Steps:**

```bash
# 1. Uninstall Helm release
helm uninstall active-transfer -n mft

# 2. Delete PVCs (optional - will delete data!)
kubectl delete pvc active-transfer-vfs -n mft

# 3. Delete secrets
kubectl delete secret -n mft -l app.kubernetes.io/name=active-transfer

# 4. Delete namespace (if no other resources)
kubectl delete namespace mft

# 5. Stop gateway services
az vm run-command invoke \
  -g <resource-group> \
  -n <gateway1-vm-name> \
  --command-id RunShellScript \
  --scripts "systemctl stop at-gateway.service && systemctl disable at-gateway.service"

az vm run-command invoke \
  -g <resource-group> \
  -n <gateway2-vm-name> \
  --command-id RunShellScript \
  --scripts "systemctl stop at-gateway.service && systemctl disable at-gateway.service"

# 6. Clean up databases (optional)
# Connect to PostgreSQL and drop databases
```

---

## Appendix

### A. Environment Variables Reference

| Variable | Description | Example | Phase |
|----------|-------------|---------|-------|
| `POSTGRES_USER` | Online DB application user | `mft_app_user` | 2.1 |
| `POSTGRES_PASSWORD` | Online DB password | `<generated>` | 2.1 |
| `POSTGRES_ARCHIVE_USER` | Archive DB application user | `mft_archive_user` | 2.1 |
| `POSTGRES_ARCHIVE_PASSWORD` | Archive DB password | `<generated>` | 2.1 |
| `ADMIN_UI_KEYSTORE_PASSWORD` | Admin UI keystore password | `<your-password>` | 3 |
| `ADMIN_UI_TRUSTSTORE_PASSWORD` | Admin UI truststore password | `<your-password>` | 3 |
| `WEB_CLIENT_KEYSTORE_PASSWORD` | Web client keystore password | `<your-password>` | 3 |
| `WEB_CLIENT_TRUSTSTORE_PASSWORD` | Web client truststore password | `<your-password>` | 3 |
| `ADMIN_PASSWORD` | Active Transfer admin password | `<your-password>` | 3 |
| `RESOURCE_GROUP` | Azure resource group | `rg-mft-prod` | 4 |
| `GATEWAY1_VM_NAME` | Gateway 1 VM name | `vm-mft-gateway1` | 4 |
| `GATEWAY2_VM_NAME` | Gateway 2 VM name | `vm-mft-gateway2` | 4 |
| `ACR_LOGIN_SERVER` | ACR login server | `acrmft.azurecr.io` | 3, 4 |

### B. Port Reference

| Port | Service | Protocol | Purpose |
|------|---------|----------|---------|
| 5555 | Active Transfer | HTTP/HTTPS | Admin UI |
| 8500 | Gateway | TCP | Gateway registration |
| 8501 | Gateway | TCP | Gateway secondary port |
| 55022 | Active Transfer | SSH | SFTP (password auth) |
| 55122 | Active Transfer | SSH | SFTP (key auth) |
| 55043 | Active Transfer | HTTPS | Web client |
| 5432 | PostgreSQL | TCP | Database connection |

### C. File Locations Reference

| Component | Location |
|-----------|----------|
| Terraform | `6o-mft-on-azure-example/01-AzurePrerequisites/02-ServiceFulfillment` |
| Certificates | `6o-mft-on-azure-example/03-TechnologyServices/00-Certificates` |
| DB User Init | `6o-mft-on-azure-example/03-TechnologyServices/00-DatabaseUserInit` |
| DB Configurator | `6o-mft-on-azure-example/03-TechnologyServices/01-DatabaseConfigurator` |
| Active Transfer | `6o-mft-on-azure-example/03-TechnologyServices/02-AT` |
| Gateways | `6o-mft-on-azure-example/03-TechnologyServices/03-ATGateway` |

### D. Useful Commands

**Quick Status Check:**
```bash
# All pods
kubectl get pods -n mft

# All services
kubectl get svc -n mft

# All ingress
kubectl get ingress -n mft

# All PVCs
kubectl get pvc -n mft

# Resource usage
kubectl top pods -n mft
```

**Log Collection:**
```bash
# Collect all logs
kubectl logs -n mft -l app.kubernetes.io/name=active-transfer --all-containers > at-logs.txt

# Collect gateway logs
az vm run-command invoke \
  -g <rg> -n <gateway-vm> \
  --command-id RunShellScript \
  --scripts "docker logs at-gateway1" > gateway1-logs.txt
```

**Health Check Script:**
```bash
#!/bin/bash
echo "=== Active Transfer Health Check ==="
echo ""
echo "Pods:"
kubectl get pods -n mft -l app.kubernetes.io/name=active-transfer
echo ""
echo "Services:"
kubectl get svc -n mft -l app.kubernetes.io/name=active-transfer
echo ""
echo "PVC:"
kubectl get pvc -n mft
echo ""
echo "Recent Events:"
kubectl get events -n mft --sort-by='.lastTimestamp' | tail -10
echo ""
echo "Gateway Connectivity:"
kubectl run test-gw1 --image=busybox --rm -it --restart=Never -n mft -- nc -zv 10.1.0.4 8500
kubectl run test-gw2 --image=busybox --rm -it --restart=Never -n mft -- nc -zv 10.1.1.4 8500
```

---

## Document Control

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 0.1 | 2026-05-26 | AI Assistant | Initial version |

---

**End of Operational Deployment Manual**
