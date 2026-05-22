# Active Transfer (MFT) Deployment for Azure AKS

This directory contains the Helm chart and deployment scripts for IBM webMethods Active Transfer (MFT) on Azure Kubernetes Service (AKS).

## Overview

Active Transfer is deployed as a highly available service with:
- **2 replicas** distributed across Azure Availability Zones
- **Shared VFS** using Azure Files (ReadWriteMany)
- **PostgreSQL database** for transaction and archive data
- **Certificate-based security** for HTTPS and SFTP
- **Gateway integration** for external SFTP access

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Internet / External Users                    │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │  Application Gateway │
              │  (Ingress)           │
              │  - mft-admin.local   │
              └──────────┬───────────┘
                         │
         ┌───────────────┴───────────────┐
         │                               │
         ▼                               ▼
┌─────────────────┐            ┌─────────────────┐
│  AT Pod 1       │            │  AT Pod 2       │
│  (AZ 1)         │            │  (AZ 2)         │
│                 │            │                 │
│  - Admin UI     │            │  - Admin UI     │
│  - Web Client   │            │  - Web Client   │
│  - SFTP (test)  │            │  - SFTP (test)  │
└────────┬────────┘            └────────┬────────┘
         │                              │
         └───────────────┬──────────────┘
                         │
         ┌───────────────┴───────────────┐
         │                               │
         ▼                               ▼
┌─────────────────┐            ┌─────────────────┐
│  Azure Files    │            │  PostgreSQL     │
│  (VFS Storage)  │            │  Flexible Server│
│  ReadWriteMany  │            │                 │
└─────────────────┘            │  - Online DB    │
                               │  - Archive DB   │
                               └─────────────────┘
```

## Prerequisites

### 1. Infrastructure (Provisioned)

Ensure the following Azure resources are provisioned via Terraform in `01-AzurePrerequisites`:

- ✅ Azure Kubernetes Service (AKS) cluster
- ✅ Azure Container Registry (ACR)
- ✅ Azure PostgreSQL Flexible Server
- ✅ Online and Archive databases created
- ✅ Virtual Network with private subnets
- ✅ Application Gateway for ingress

### 2. Database Preparation (Completed)

Run these components in order before deploying Active Transfer:

1. **00-DatabaseUserInit** - Create application database users
2. **01-DatabaseConfigurator** - Initialize webMethods database schemas

### 3. Certificates (Generated)

Certificates must be generated in `00-Certificates`:

- ✅ Admin UI certificates (JKS, PKCS12)
- ✅ Web Client certificates (JKS, PKCS12)
- ✅ SFTP SSH keys (RSA)
- ✅ CA root certificate

### 4. Container Image (Built)

The Active Transfer container image must be available in ACR:

```bash
# Image location: <ACR_LOGIN_SERVER>/active-transfer-enhance:latest
# Built in: 02-ContainerImages/03-active-transfer-enhance/
```

### 5. Tools Required

- `kubectl` - Kubernetes CLI (configured with AKS access)
- `helm` - Helm v3+ package manager
- `bash` - For running deployment scripts

## Quick Start

### Step 1: Update Configuration

Edit `helm/values.yaml` and update the following placeholders:

```yaml
# Container image
image:
  repository: "<ACR_LOGIN_SERVER>/active-transfer-enhance"

# Database configuration
database:
  serverFqdn: "<POSTGRES_SERVER_FQDN>"
  onlineDbName: "<ONLINE_DB_NAME>"
  archiveDbName: "<ARCHIVE_DB_NAME>"
  onlineDbUser: "<ONLINE_DB_USER>"
  archiveDbUser: "<ARCHIVE_DB_USER>"

# Gateway configuration
mftConfig:
  gateways:
    - instanceName: "Gateway1"
      host: "<GATEWAY1_PRIVATE_IP>"
      port: 8500
    - instanceName: "Gateway2"
      host: "<GATEWAY2_PRIVATE_IP>"
      port: 8500
```

**Tip**: Use Terraform outputs to get these values:

```bash
cd ../../01-AzurePrerequisites/02-ServiceFulfillment
terraform output
```

### Step 2: Generate Secrets

Run the secret generation script to create Kubernetes secrets from certificates and credentials:

```bash
cd scripts

# Set passwords as environment variables (recommended)
export ADMIN_UI_KEYSTORE_PASSWORD="your-admin-ui-keystore-password"
export ADMIN_UI_TRUSTSTORE_PASSWORD="your-admin-ui-truststore-password"
export WEB_CLIENT_KEYSTORE_PASSWORD="your-web-client-keystore-password"
export WEB_CLIENT_TRUSTSTORE_PASSWORD="your-web-client-truststore-password"
export ADMIN_PASSWORD="your-admin-password"
export POSTGRES_PASSWORD="your-online-db-password"
export POSTGRES_ARCHIVE_PASSWORD="your-archive-db-password"

# Generate and apply secrets
./generate-secrets.sh --apply
```

**Alternative**: Interactive mode (prompts for passwords):

```bash
./generate-secrets.sh --apply
```

### Step 3: Deploy Active Transfer

Deploy using the deployment script:

```bash
# Deploy to default namespace (mft)
./deploy.sh

# Deploy to custom namespace
./deploy.sh --namespace production

# Dry run (test without deploying)
./deploy.sh --dry-run

# Upgrade existing deployment
./deploy.sh --upgrade
```

### Step 4: Verify Deployment

Check deployment status:

```bash
# Get pod status
kubectl get pods -n mft -l app.kubernetes.io/name=active-transfer

# View logs
kubectl logs -n mft -l app.kubernetes.io/name=active-transfer -f

# Check services
kubectl get svc -n mft -l app.kubernetes.io/name=active-transfer

# Check ingress
kubectl get ingress -n mft -l app.kubernetes.io/name=active-transfer
```

### Step 5: Access Admin UI

**Option 1: Port Forward (Development)**

```bash
kubectl port-forward -n mft svc/active-transfer 5555:5555
```

Then access: http://localhost:5555

**Option 2: Ingress (Production)**

Access via configured hostname: https://mft-admin.local

**Default Credentials**:
- Username: `Administrator`
- Password: (set via `ADMIN_PASSWORD` in secrets)

## Configuration

### Database Connection

Database connections are configured in `helm/templates/configmap-application-properties.yaml`:

- **Online Database**: Transaction data (ISInternal, ISCoreAudit, ActiveTransfer, CentralUsers)
- **Archive Database**: Historical data (ActiveTransferArchive, ComponentTracker, TaskArchive)

Connection pools are configured with:
- Min connections: 2
- Max connections: 20
- SSL mode: require

### MFT Configuration

MFT-specific configuration is in `helm/templates/secret-mft-config.yaml` (generated from template during secret generation):

#### Certificates

- **Admin UI**: JKS keystore for HTTPS admin interface
- **Web Client**: JKS keystore for HTTPS web client
- **SFTP**: RSA SSH keys for SFTP server

#### Ports (Internal Testing)

- **55022**: SFTP with password authentication
- **55122**: SFTP with public key authentication
- **55043**: HTTPS for web client

**Note**: External SFTP traffic should go through gateways in public subnet VMs.

#### Virtual File System (VFS)

- **Type**: Local (Azure Files mount)
- **Path**: `/mnt/default-vfs`
- **Storage**: 100Gi Azure Files (ReadWriteMany)
- **Encryption**: Disabled (can be enabled in production)

#### Gateway Integration

Active Transfer connects to gateways for external SFTP access:

- **Gateway 1**: VM in Availability Zone 1
- **Gateway 2**: VM in Availability Zone 2
- **Port**: 8500 (gateway registration port)
- **Auto-connect**: Enabled

### High Availability

#### Pod Distribution

Pods are distributed across availability zones using pod anti-affinity:

```yaml
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
            - key: app.kubernetes.io/name
              operator: In
              values:
                - active-transfer
        topologyKey: topology.kubernetes.io/zone
```

#### Pod Disruption Budget

Ensures at least 1 pod is always available during maintenance:

```yaml
podDisruptionBudget:
  enabled: true
  minAvailable: 1
```

#### Session Management

**Important**: Active Transfer does **not** support session replication. Sessions are lost when a pod restarts. This is a known limitation of the product.

### Resource Limits

Default resource allocation per pod:

```yaml
resources:
  requests:
    cpu: 1000m
    memory: 2Gi
  limits:
    cpu: 2000m
    memory: 4Gi
```

Adjust based on your workload requirements.

### Health Probes

- **Startup Probe**: 60 attempts × 10s = 10 minutes max startup time
- **Liveness Probe**: Checks `/health/liveness` every 30s
- **Readiness Probe**: Checks `/health/readiness` every 15s

## Secrets Management

### ⚠️ IMPORTANT: Production Security

This vanilla example uses **basic Kubernetes Secrets** for simplicity. This approach is **NOT recommended for production environments**.

### Production Recommendations

Organizations deploying this solution in production should implement enterprise-grade secrets management:

#### 1. Azure Key Vault with Secrets Store CSI Driver

**Benefits**:
- Native Azure integration
- Automatic secret rotation
- Centralized secrets management
- Audit logging via Azure Monitor

**Implementation**:

```bash
# Install CSI driver
helm repo add csi-secrets-store-provider-azure https://azure.github.io/secrets-store-csi-driver-provider-azure/charts
helm install csi csi-secrets-store-provider-azure/csi-secrets-store-provider-azure

# Create SecretProviderClass
kubectl apply -f - <<EOF
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: azure-mft-secrets
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "true"
    userAssignedIdentityID: "<IDENTITY_CLIENT_ID>"
    keyvaultName: "<KEY_VAULT_NAME>"
    objects: |
      array:
        - |
          objectName: postgres-password
          objectType: secret
        - |
          objectName: keystore-password
          objectType: secret
    tenantId: "<TENANT_ID>"
EOF
```

**Reference**: https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-driver

#### 2. External Secrets Operator (ESO)

Multi-cloud support with automatic synchronization.

**Reference**: https://external-secrets.io/

#### 3. HashiCorp Vault

Enterprise-grade secrets management with dynamic secrets.

**Reference**: https://www.vaultproject.io/

### Security Best Practices

1. **Never commit secrets to version control**
   - Use `.gitignore` to exclude generated secret files
   - Only commit `.template` files

2. **Use separate credentials per environment**
   - Development, staging, and production should have different credentials

3. **Implement credential rotation policies**
   - Rotate database passwords every 90 days
   - Rotate certificates before expiration

4. **Enable audit logging**
   - Track who accesses secrets and when
   - Monitor for unauthorized access attempts

5. **Use managed identities**
   - Prefer Azure Managed Identity over service principals
   - Eliminate the need to manage credentials for Azure resources

## Monitoring

### Prometheus Integration

The chart includes Prometheus annotations for metrics scraping:

```yaml
prometheus:
  path: "/metrics"
  port: "5555"
  scheme: "http"
  scrape: "true"
```

### ServiceMonitor (Optional)

Enable ServiceMonitor for Prometheus Operator:

```yaml
serviceMonitor:
  enabled: true
```

### Logs

View logs from all pods:

```bash
kubectl logs -n mft -l app.kubernetes.io/name=active-transfer -f
```

View logs from specific pod:

```bash
kubectl logs -n mft <pod-name> -f
```

## Troubleshooting

### Pods Not Starting

**Symptoms**: Pods remain in `Pending` or `CrashLoopBackOff` state

**Possible Causes**:
- Missing secrets
- Image pull errors
- Insufficient resources
- Database connectivity issues

**Solutions**:

```bash
# Check pod events
kubectl describe pod -n mft -l app.kubernetes.io/name=active-transfer

# Check pod logs
kubectl logs -n mft -l app.kubernetes.io/name=active-transfer

# Check secrets
kubectl get secrets -n mft

# Check image pull
kubectl get events -n mft --sort-by='.lastTimestamp'
```

### Database Connection Errors

**Symptoms**: "Cannot connect to database" errors in logs

**Possible Causes**:
- Incorrect database credentials
- Network connectivity issues
- Firewall rules blocking AKS
- SSL/TLS configuration issues

**Solutions**:

```bash
# Test database connectivity from pod
kubectl run -it --rm debug -n mft --image=postgres:15 --restart=Never -- \
  psql -h <POSTGRES_FQDN> -U <USER> -d <DATABASE>

# Check database credentials secret
kubectl get secret mft-db-credentials -n mft -o yaml

# Verify PostgreSQL firewall rules in Azure Portal
# Ensure AKS subnet is allowed
```

### Certificate Errors

**Symptoms**: SSL/TLS handshake failures, certificate validation errors

**Possible Causes**:
- Incorrect certificate format
- Wrong keystore password
- Certificate expired
- Missing CA certificate

**Solutions**:

```bash
# Check certificate secrets
kubectl get secret mft-admin-ui-certs -n mft -o yaml
kubectl get secret mft-web-client-certs -n mft -o yaml

# Verify certificate expiration
# Extract certificate from secret and check with openssl

# Regenerate certificates if needed
cd ../00-Certificates
# Follow certificate generation process
```

### Gateway Connection Issues

**Symptoms**: Active Transfer cannot connect to gateways

**Possible Causes**:
- Incorrect gateway IP addresses
- Gateway not running
- Port 8500 blocked by firewall
- Network connectivity issues

**Solutions**:

```bash
# Check gateway configuration in values.yaml
cat helm/values.yaml | grep -A 10 "gateways:"

# Test connectivity to gateway from pod
kubectl exec -it -n mft <pod-name> -- nc -zv <GATEWAY_IP> 8500

# Check gateway logs (on gateway VMs)
# See 03-ATGateway documentation
```

### VFS Storage Issues

**Symptoms**: File transfer failures, "Cannot write to VFS" errors

**Possible Causes**:
- PVC not bound
- Azure Files mount failures
- Insufficient storage space
- Permission issues

**Solutions**:

```bash
# Check PVC status
kubectl get pvc -n mft

# Check PV status
kubectl get pv

# Describe PVC for events
kubectl describe pvc -n mft active-transfer-vfs

# Check storage class
kubectl get storageclass azurefile-csi

# Verify Azure Files share in Azure Portal
```

### Performance Issues

**Symptoms**: Slow response times, high CPU/memory usage

**Solutions**:

```bash
# Check resource usage
kubectl top pods -n mft -l app.kubernetes.io/name=active-transfer

# Increase resource limits in values.yaml
# Adjust connection pool settings in application.properties
# Enable horizontal pod autoscaling if needed
```

## Maintenance

### Upgrading

```bash
# Update values.yaml or container image tag
# Then upgrade the release
cd scripts
./deploy.sh --upgrade
```

### Scaling

```bash
# Manual scaling
kubectl scale deployment active-transfer -n mft --replicas=3

# Or update values.yaml and upgrade
```

### Backup

**Database**: Use Azure PostgreSQL automated backups

**VFS**: Use Azure Files snapshots or backup solution

**Configuration**: Store Helm values and secrets in secure location

### Uninstalling

```bash
cd scripts
./deploy.sh --uninstall
```

**Note**: This does not delete PVCs. Delete manually if needed:

```bash
kubectl delete pvc -n mft active-transfer-vfs
```

## Files Structure

```
02-AT/
├── helm/
│   ├── Chart.yaml                                    # Helm chart metadata
│   ├── values.yaml                                   # Default configuration values
│   └── templates/
│       ├── _helpers.tpl                              # Template helpers
│       ├── configmap-application-properties.yaml     # Database & IS config
│       ├── secret-mft-config.yaml.template           # MFT config template (processed by generate-secrets.sh)
│       ├── deployment.yaml                           # Kubernetes Deployment
│       ├── service.yaml                              # Kubernetes Service
│       ├── ingress.yaml                              # Kubernetes Ingress
│       ├── pvc.yaml                                  # PersistentVolumeClaim for VFS
│       ├── serviceaccount.yaml                       # ServiceAccount
│       ├── poddisruptionbudget.yaml                  # PodDisruptionBudget
│       ├── secret-db-credentials.yaml.template       # Database credentials template
│       └── secret-certificates.yaml.template         # Certificates template
├── scripts/
│   ├── generate-secrets.sh                           # Generate Kubernetes secrets
│   └── deploy.sh                                     # Deploy Helm chart
└── README.md                                         # This file
```

## Environment-Specific Values

Create environment-specific values files:

```bash
# Development
helm/values-dev.yaml

# Staging
helm/values-staging.yaml

# Production
helm/values-prod.yaml
```

Deploy with specific values:

```bash
./deploy.sh --values helm/values-prod.yaml
```

## DNS Configuration

Configure DNS entries for the following FQDNs:

```
# Admin UI - Load Balanced (via Application Gateway)
mft-admin.local          A    <APP_GATEWAY_PUBLIC_IP>

# Admin UI - Individual Nodes (for troubleshooting)
mft-admin-node1.local    A    <POD_1_IP or Service_IP>
mft-admin-node2.local    A    <POD_2_IP or Service_IP>

# Web Client - Load Balanced (via Application Gateway)
web-client.local         A    <APP_GATEWAY_PUBLIC_IP>
```

**Recommendation**: Use Azure Private DNS Zone for internal services.

## Next Steps

After successful deployment:

1. **Verify Connectivity**
   - Access Admin UI via ingress or port-forward
   - Test database connectivity
   - Verify gateway connections

2. **Configure Users and Permissions**
   - Create MFT users
   - Set up file transfer rules
   - Configure partner profiles

3. **Deploy Gateways**
   - Proceed to `03-ATGateway/`
   - Deploy gateway services to public subnet VMs

4. **Set Up Monitoring**
   - Configure Prometheus scraping
   - Set up alerts for critical metrics
   - Enable Azure Monitor integration

5. **Production Hardening**
   - Implement enterprise secrets management
   - Enable network policies
   - Configure backup and disaster recovery
   - Perform security audit

## Support and References

### Documentation

- [IBM webMethods Active Transfer Documentation](https://www.ibm.com/docs/en/webmethods-activetransfer/11.1.0)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Helm Documentation](https://helm.sh/docs/)
- [Azure AKS Documentation](https://learn.microsoft.com/en-us/azure/aks/)

### Related Components

- `00-DatabaseUserInit` - Database user creation
- `01-DatabaseConfigurator` - Database schema initialization
- `03-ATGateway` - Gateway services for external SFTP access
- `00-Certificates` - Certificate generation

### Issues and Questions

For issues or questions related to this deployment:

1. Check the troubleshooting section above
2. Review logs: `kubectl logs -n mft -l app.kubernetes.io/name=active-transfer`
3. Consult IBM webMethods documentation
4. Review Azure AKS and PostgreSQL metrics in Azure Portal

## License

This example is provided as-is for demonstration purposes. Refer to IBM webMethods licensing for production use.
