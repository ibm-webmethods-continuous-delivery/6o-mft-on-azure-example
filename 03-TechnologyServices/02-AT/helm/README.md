# IBM webMethods Active Transfer Helm Chart

This Helm chart deploys IBM webMethods Active Transfer (MFT) on Azure Kubernetes Service (AKS) with support for high availability and multi-node clustering.

## Features

- **High Availability**: Deploy multiple replicas across availability zones
- **JGroups Clustering**: Automatic configuration synchronization across nodes
- **Shared Storage**: Azure Files for Virtual File System (VFS)
- **Database Integration**: PostgreSQL for online and archive databases
- **Security**: TLS/SSL support, certificate management, RBAC
- **Monitoring**: Prometheus metrics and health checks
- **Ingress**: Azure Application Gateway integration

## Prerequisites

- Kubernetes 1.24+
- Helm 3.8+
- Azure AKS cluster with multiple availability zones
- Azure PostgreSQL Flexible Server
- Azure Files storage class (`azurefile-csi`)
- Container registry with Active Transfer image

## Installation

### 1. Prepare Secrets

Create the required secrets before installing the chart:

```bash
# Admin credentials
kubectl create secret generic mft-admin-credentials \
  --from-literal=admin-password='YourSecurePassword'

# Database credentials
kubectl create secret generic mft-db-credentials \
  --from-literal=online-db-password='OnlineDbPassword' \
  --from-literal=archive-db-password='ArchiveDbPassword'

# MFT configuration JSON
kubectl create secret generic mft-config-json \
  --from-file=mft-config.json=path/to/mft-config.json

# Certificates (Admin UI, Web Client, SFTP)
kubectl create secret generic mft-admin-ui-certs \
  --from-file=keystore.jks=path/to/admin-keystore.jks \
  --from-file=truststore.jks=path/to/admin-truststore.jks \
  --from-literal=keystore-password='KeystorePassword' \
  --from-literal=truststore-password='TruststorePassword'

kubectl create secret generic mft-web-client-certs \
  --from-file=keystore.jks=path/to/web-keystore.jks \
  --from-file=truststore.jks=path/to/web-truststore.jks \
  --from-literal=keystore-password='KeystorePassword' \
  --from-literal=truststore-password='TruststorePassword'

kubectl create secret generic mft-sftp-ssh-keys \
  --from-file=ssh_host_rsa_key=path/to/ssh_host_rsa_key \
  --from-file=ssh_host_rsa_key.pub=path/to/ssh_host_rsa_key.pub
```

### 2. Update Values

Edit `values.yaml` or create a custom values file:

```yaml
# Image configuration
image:
  repository: "your-acr.azurecr.io/active-transfer-enhance"
  tag: "11.1.0"

# Database configuration
database:
  serverFqdn: "your-postgres-server.postgres.database.azure.com"
  onlineDbName: "mft_online"
  archiveDbName: "mft_archive"
  onlineDbUser: "mft_online_user"
  archiveDbUser: "mft_archive_user"

# JGroups clustering (enabled by default)
jgroups:
  enabled: true
  tcpPort: 7800
  portRange: 1

# Ingress
ingress:
  enabled: true
  hosts:
    - host: "mft-admin.yourdomain.com"
      paths:
        - path: /
          pathType: Prefix
          port: 5555
```

### 3. Install the Chart

```bash
# Install with default values
helm install active-transfer . -n mft-namespace --create-namespace

# Install with custom values
helm install active-transfer . -n mft-namespace \
  --create-namespace \
  -f custom-values.yaml

# Upgrade existing installation
helm upgrade active-transfer . -n mft-namespace
```

## JGroups Clustering

### Overview

JGroups enables automatic configuration synchronization across multiple Active Transfer nodes. When you make configuration changes through the Admin UI on one node, those changes are immediately propagated to all other nodes in the cluster.

### How It Works

1. **KUBE_PING Discovery**: Uses Kubernetes API to discover other pods in the same namespace with matching labels
2. **TCP Communication**: Nodes communicate over TCP port 7800
3. **RBAC Permissions**: ServiceAccount has permissions to list/get pods for discovery
4. **Configuration Sync**: Changes made on any node are synchronized to all cluster members

### Configuration

JGroups clustering is controlled via `values.yaml`:

```yaml
jgroups:
  # Enable/disable clustering
  enabled: true

  # TCP port for inter-node communication
  tcpPort: 7800

  # Port range for discovery
  portRange: 1
```

### RBAC Resources

The chart automatically creates:
- **Role**: Grants `get` and `list` permissions on pods
- **RoleBinding**: Binds the Role to the ServiceAccount

### Environment Variables

The deployment automatically sets:
- `KUBERNETES_NAMESPACE`: Current namespace (from pod metadata)
- `KUBERNETES_LABELS`: Label selector for pod discovery

### Label Selector

Pods are discovered using these labels:
- `app.kubernetes.io/name=active-transfer`
- `app.kubernetes.io/instance=<release-name>`

This ensures only pods from the same Helm release form a cluster.

## Testing JGroups Clustering

### Prerequisites for Testing

1. Deploy at least 2 replicas:
   ```yaml
   replicaCount: 2
   ```

2. Ensure ingress allows access to individual pods (for UI testing)

### Manual Testing Procedure

#### Step 1: Verify Cluster Formation

Check the logs to confirm nodes have discovered each other:

```bash
# Get pod names
kubectl get pods -n mft-namespace -l app.kubernetes.io/name=active-transfer

# Check logs for JGroups messages
kubectl logs -n mft-namespace <pod-name> | grep -i jgroups

# Look for messages like:
# - "Cluster view: [node1, node2]"
# - "Received new view"
# - "KUBE_PING: discovered X members"
```

#### Step 2: Access Individual Nodes

Configure ingress to route to specific pods for testing:

**Option A: Port-forward to each pod**
```bash
# Forward to pod 1
kubectl port-forward -n mft-namespace active-transfer-0 5555:5555

# In another terminal, forward to pod 2
kubectl port-forward -n mft-namespace active-transfer-1 5556:5555
```

**Option B: Create separate ingress rules per pod**
```yaml
# Add to ingress configuration
ingress:
  hosts:
    - host: "mft-node1.yourdomain.com"
      paths:
        - path: /
          pathType: Prefix
          port: 5555
      # Add pod selector annotation
    - host: "mft-node2.yourdomain.com"
      paths:
        - path: /
          pathType: Prefix
          port: 5555
```

#### Step 3: Test Configuration Synchronization

1. **Login to Node 1 UI**:
   - Access `http://localhost:5555` (or your ingress URL)
   - Login with admin credentials

2. **Make a Configuration Change**:
   - Navigate to: **Settings** → **Partners**
   - Create a new partner: `TestPartner-Sync`
   - Add details (name, email, etc.)
   - Save the configuration

3. **Verify on Node 2**:
   - Access Node 2 UI (different port-forward or ingress)
   - Login with admin credentials
   - Navigate to: **Settings** → **Partners**
   - **Expected Result**: `TestPartner-Sync` should appear immediately (within seconds)

4. **Test Reverse Synchronization**:
   - On Node 2, create another partner: `TestPartner-Reverse`
   - Check Node 1 UI - it should appear immediately

5. **Test Other Configuration Types**:
   - **VFS Configuration**: Create/modify virtual file systems
   - **Port Configuration**: Add/modify SFTP or HTTPS ports
   - **User Accounts**: Create/modify user accounts
   - **Scheduled Tasks**: Create/modify scheduled transfers

#### Step 4: Test Cluster Resilience

1. **Scale Down**:
   ```bash
   kubectl scale deployment active-transfer -n mft-namespace --replicas=1
   ```
   - Verify remaining node continues to function
   - Check logs for cluster view update

2. **Scale Up**:
   ```bash
   kubectl scale deployment active-transfer -n mft-namespace --replicas=3
   ```
   - New pods should join the cluster automatically
   - Verify they receive existing configuration

3. **Pod Restart**:
   ```bash
   kubectl delete pod active-transfer-0 -n mft-namespace
   ```
   - Pod should rejoin cluster after restart
   - Configuration should remain synchronized

### Troubleshooting

#### Pods Not Discovering Each Other

Check RBAC permissions:
```bash
# Verify Role exists
kubectl get role -n mft-namespace active-transfer-jgroups

# Verify RoleBinding exists
kubectl get rolebinding -n mft-namespace active-transfer-jgroups

# Test ServiceAccount permissions
kubectl auth can-i list pods \
  --as=system:serviceaccount:mft-namespace:mft-service-account \
  -n mft-namespace
```

#### Configuration Not Synchronizing

1. **Check JGroups is enabled**:
   ```bash
   kubectl get configmap -n mft-namespace active-transfer-application-properties -o yaml | grep "mft.cluster.sync.enabled"
   ```
   Should show: `mft.cluster.sync.enabled=true`

2. **Verify JGroups config file is mounted**:
   ```bash
   kubectl exec -n mft-namespace active-transfer-0 -- \
     ls -la /opt/softwareag/IntegrationServer/instances/default/packages/WmMFT/resources/jgroups-properties.xml
   ```

3. **Check TCP port 7800 connectivity between pods**:
   ```bash
   # Get pod names and IPs
   kubectl get pods -n mft-namespace -o wide

   # Test pod-to-pod connectivity on JGroups port 7800
   # Replace <source-pod> with one pod name and <target-pod-ip> with another pod's IP
   kubectl exec -n mft-namespace <source-pod> -- \
     bash -c '(echo > /dev/tcp/<target-pod-ip>/7800) >/dev/null 2>&1 && echo "Port 7800 is open" || echo "Port 7800 is closed"'
   ```

   **Example**:
   ```bash
   # If you have pods:
   # active-transfer-97fb94659-7f9x9   10.244.1.5
   # active-transfer-97fb94659-kzdhx   10.244.2.8

   kubectl exec -n mft-namespace active-transfer-97fb94659-kzdhx -- \
     bash -c '(echo > /dev/tcp/10.244.1.5/7800) >/dev/null 2>&1 && echo "Port 7800 is open" || echo "Port 7800 is closed"'
   ```

   **Note**: JGroups requires direct pod-to-pod communication on port 7800. The test must use the target pod's IP address, not the service name, since JGroups uses KUBE_PING for discovery and TCP for direct node-to-node communication.

#### Network Policies Blocking Communication

If using network policies, ensure JGroups port is allowed:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-jgroups
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: active-transfer
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: active-transfer
      ports:
        - protocol: TCP
          port: 7800
```

## Configuration

### Key Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of replicas | `2` |
| `jgroups.enabled` | Enable JGroups clustering | `true` |
| `jgroups.tcpPort` | JGroups TCP port | `7800` |
| `database.serverFqdn` | PostgreSQL server FQDN | Required |
| `persistence.size` | VFS storage size | `100Gi` |
| `resources.msrContainer.requests.memory` | Memory request | `2Gi` |
| `resources.msrContainer.limits.memory` | Memory limit | `4Gi` |

### Full Configuration

See `values.yaml` for all available configuration options.

## Monitoring

### Health Checks

The chart includes startup, liveness, and readiness probes:

```yaml
startupProbe:
  httpGet:
    path: /health/liveness
    port: http
  failureThreshold: 60
  periodSeconds: 10

livenessProbe:
  httpGet:
    path: /health/liveness
    port: http
  periodSeconds: 30

readinessProbe:
  httpGet:
    path: /health/readiness
    port: http
  periodSeconds: 15
```

### Prometheus Metrics

Metrics are exposed on port 5555 at `/metrics`:

```yaml
prometheus:
  scrape: "true"
  port: "5555"
  path: "/metrics"
```

## Upgrading

### Upgrade Procedure

1. **Backup Configuration**:
   ```bash
   kubectl get configmap -n mft-namespace -o yaml > backup-configmaps.yaml
   kubectl get secret -n mft-namespace -o yaml > backup-secrets.yaml
   ```

2. **Update Chart**:
   ```bash
   helm upgrade active-transfer . -n mft-namespace
   ```

3. **Verify Deployment**:
   ```bash
   kubectl rollout status deployment/active-transfer -n mft-namespace
   ```

### Rolling Updates

The chart uses a rolling update strategy by default. Pods are updated one at a time to maintain availability.

## Uninstallation

```bash
# Delete Helm release
helm uninstall active-transfer -n mft-namespace

# Delete PVC (if needed)
kubectl delete pvc active-transfer-vfs -n mft-namespace

# Delete secrets (if needed)
kubectl delete secret mft-admin-credentials mft-db-credentials \
  mft-config-json mft-admin-ui-certs mft-web-client-certs \
  mft-sftp-ssh-keys -n mft-namespace
```

## Support

For issues and questions:
- Check logs: `kubectl logs -n mft-namespace <pod-name>`
- Describe pod: `kubectl describe pod -n mft-namespace <pod-name>`
- IBM Documentation: https://www.ibm.com/docs/en/webmethods-activetransfer/11.1.0

## License

See LICENSE file in the repository.
