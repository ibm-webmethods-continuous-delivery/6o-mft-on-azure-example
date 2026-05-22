# ActiveTransfer Gateway Troubleshooting Guide

## Common Issues and Solutions

### 1. ACR Authentication Failures

#### Symptom
```
Error response from daemon: pull access denied for <acr>.azurecr.io/active-transfer-enhance
```

#### Causes and Solutions

**A. Managed Identity Not Configured**
```bash
# Check if VM has managed identity
az vm identity show --resource-group <rg-name> --name <vm-name>

# If not configured, enable in Terraform:
# Set enable_sftp_vm_acr_role = true in terraform.tfvars
# Run: terraform apply
```

**B. ACR Role Assignment Missing**
```bash
# Check role assignments
az role assignment list --assignee <vm-principal-id> --scope <acr-resource-id>

# Manually assign if needed:
az role assignment create \
  --assignee <vm-principal-id> \
  --role AcrPull \
  --scope <acr-resource-id>
```

**C. ACR Login Service Not Running**
```bash
# Check service status
sudo systemctl status acr-login.service

# Restart service
sudo systemctl restart acr-login.service

# Check logs
sudo journalctl -u acr-login.service -n 50
```

**D. Docker Not Logged In**
```bash
# Manually login using managed identity
sudo az acr login --name <acr-name> --identity

# Or restart acr-login service
sudo systemctl restart acr-login.service
```

---

### 2. Container Won't Start

#### Symptom
```
Container at-gateway1 exits immediately after starting
```

#### Diagnosis Steps

**A. Check Container Logs**
```bash
# View container logs
sudo docker logs at-gateway1

# View last 100 lines
sudo docker logs at-gateway1 --tail 100

# Follow logs in real-time
sudo docker logs at-gateway1 -f
```

**B. Check Configuration File**
```bash
# Verify properties.cnf exists and is readable
ls -la /opt/at-gateway/config/properties.cnf

# Check file content
cat /opt/at-gateway/config/properties.cnf

# Verify it's mounted in container
sudo docker inspect at-gateway1 | grep -A 10 Mounts
```

**C. Check Environment Variables**
```bash
# Verify .env file exists
cat /opt/at-gateway/.env

# Should contain:
# ACR_LOGIN_SERVER=<your-acr>.azurecr.io
```

**D. Check Resource Constraints**
```bash
# Check available memory
free -h

# Check disk space
df -h /opt/at-gateway

# Check if container is OOM killed
sudo dmesg | grep -i "out of memory"
```

#### Common Configuration Errors

**Missing Runtime Mode**
```properties
# properties.cnf MUST contain:
mft.server.runtime.mode=Gateway
```

**Invalid Port Configuration**
```properties
# Port must be numeric
mft.gatewayServer.port=8500  # Correct
mft.gatewayServer.port=abc   # Wrong - will cause startup failure
```

---

### 3. Network Connectivity Issues

#### Symptom
```
Cannot connect to gateway from AKS pods
Connection timeout on port 8500
```

#### Diagnosis Steps

**A. Verify Gateway is Listening**
```bash
# On gateway VM, check if port is open
sudo netstat -tlnp | grep 8500

# Or use ss
sudo ss -tlnp | grep 8500

# Test local connectivity
nc -zv localhost 8500
```

**B. Check NSG Rules**
```bash
# Run the extraction script
cd /aio/work/c/iwcd/6o-mft-on-azure-example/01-AzurePrerequisites/02-ServiceFulfillment
bash /path/to/extract-nsg-rules.sh

# Look for rules allowing ports 8500-8501 from AKS subnet (10.1.10.0/24)
```

**C. Test from AKS**
```bash
# Create test pod
kubectl run test-gateway --image=busybox --rm -it --restart=Never -n mft -- sh

# Inside pod, test connectivity
nc -zv 10.1.0.4 8500
nc -zv 10.1.1.4 8500

# If timeout, NSG rules are likely missing
```

**D. Check VM Firewall**
```bash
# Check if firewall is running
sudo ufw status

# If active, allow gateway ports
sudo ufw allow 8500/tcp
sudo ufw allow 8501/tcp
```

#### Solution: Add NSG Rules

Add to Terraform `main.tf` in `azurerm_network_security_group.sftp`:

```hcl
security_rule {
  name                       = "AllowGatewayFromAKS"
  priority                   = 120
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_port_range          = "*"
  destination_port_ranges    = ["8500", "8501"]
  source_address_prefix      = "10.1.10.0/24"  # AKS subnet
  destination_address_prefix = "*"
}
```

Then apply:
```bash
terraform apply
```

---

### 4. Service Won't Start

#### Symptom
```
sudo systemctl start at-gateway.service
Job for at-gateway.service failed
```

#### Diagnosis Steps

**A. Check Service Status**
```bash
# Detailed status
sudo systemctl status at-gateway.service -l

# View recent logs
sudo journalctl -u at-gateway.service -n 50

# Follow logs
sudo journalctl -u at-gateway.service -f
```

**B. Check Service File**
```bash
# Verify service file exists
ls -la /etc/systemd/system/at-gateway.service

# Check syntax
sudo systemd-analyze verify at-gateway.service

# Reload if modified
sudo systemctl daemon-reload
```

**C. Check Dependencies**
```bash
# Verify docker is running
sudo systemctl status docker

# Verify acr-login service
sudo systemctl status acr-login.service

# Start dependencies if needed
sudo systemctl start docker
sudo systemctl start acr-login.service
```

**D. Check Working Directory**
```bash
# Verify deployment directory exists
ls -la /opt/at-gateway

# Should contain:
# - docker-compose.yml
# - .env
# - config/properties.cnf
```

#### Common Issues

**Missing .env File**
```bash
# Create .env file
cat > /opt/at-gateway/.env << EOF
ACR_LOGIN_SERVER=<your-acr>.azurecr.io
EOF

chmod 600 /opt/at-gateway/.env
```

**Wrong Permissions**
```bash
# Fix permissions
sudo chown -R root:root /opt/at-gateway
sudo chmod 644 /opt/at-gateway/docker-compose.yml
sudo chmod 644 /opt/at-gateway/config/properties.cnf
sudo chmod 600 /opt/at-gateway/.env
```

---

### 5. Gateway Not Connecting to ActiveTransfer Server

#### Symptom
```
ActiveTransfer logs show: "Gateway1 connection failed"
Gateway shows as "Disconnected" in Admin UI
```

#### Diagnosis Steps

**A. Check Gateway Logs**
```bash
# On gateway VM
sudo docker logs at-gateway1 | grep -i "connection\|error"

# Look for connection attempts to AT server
```

**B. Verify Gateway Configuration**
```bash
# Check properties.cnf
cat /opt/at-gateway/config/properties.cnf | grep -i "gateway\|server"

# Verify:
# - mft.server.runtime.mode=Gateway
# - mft.gatewayServer.port=8500
```

**C. Check ActiveTransfer Configuration**
```bash
# Get AT ConfigMap
kubectl get configmap mft-config -n mft -o yaml

# Verify gateway IPs are correct:
# - Gateway1: 10.1.0.4
# - Gateway2: 10.1.1.4
```

**D. Test Bidirectional Connectivity**
```bash
# From gateway VM to AKS (if possible)
# This may not work due to network topology

# From AKS to gateway (should work)
kubectl run test --image=busybox --rm -it -n mft -- nc -zv 10.1.0.4 8500
```

#### Solutions

**Update Helm Values**
```bash
# Ensure ibm_values.yaml has correct IPs
cd /aio/work/c/iwcd/6o-mft-on-azure-example/03-TechnologyServices/02-AT/helm

# Verify gateway configuration
grep -A 10 "gateways:" ibm_values.yaml

# Upgrade helm release
helm upgrade active-transfer . --namespace mft --values ibm_values.yaml
```

**Restart Both Sides**
```bash
# Restart gateway
sudo systemctl restart at-gateway.service

# Restart AT pods
kubectl rollout restart deployment/active-transfer -n mft
```

---

### 6. High Memory Usage

#### Symptom
```
Container using more than 1GB memory
VM running out of memory
```

#### Diagnosis

```bash
# Check container memory usage
sudo docker stats at-gateway1 --no-stream

# Check VM memory
free -h

# Check for memory leaks in logs
sudo docker logs at-gateway1 | grep -i "memory\|heap\|oom"
```

#### Solutions

**A. Adjust JVM Settings**

Edit `docker-compose.yml`:
```yaml
environment:
  - JAVA_MIN_MEM=256m   # Reduce from 512m
  - JAVA_MAX_MEM=768m   # Reduce from 1024m
```

**B. Restart Container**
```bash
sudo systemctl restart at-gateway.service
```

**C. Monitor After Changes**
```bash
# Watch memory usage
watch -n 5 'sudo docker stats at-gateway1 --no-stream'
```

---

### 7. Disk Space Issues

#### Symptom
```
No space left on device
Container logs filling disk
```

#### Diagnosis

```bash
# Check disk usage
df -h

# Check docker disk usage
sudo docker system df

# Check log sizes
sudo du -sh /var/lib/docker/containers/*
sudo du -sh /opt/at-gateway
```

#### Solutions

**A. Clean Docker Resources**
```bash
# Remove unused images
sudo docker image prune -a

# Remove unused volumes
sudo docker volume prune

# Remove unused containers
sudo docker container prune
```

**B. Configure Log Rotation**

Already configured in `docker-compose.yml`:
```yaml
logging:
  driver: "json-file"
  options:
    max-size: "10m"
    max-file: "3"
```

**C. Manual Log Cleanup**
```bash
# Truncate large log files
sudo truncate -s 0 /var/lib/docker/containers/*/\*-json.log
```

---

### 8. SSL/TLS Certificate Issues

#### Symptom
```
SSL handshake failed
Certificate validation error
```

#### Diagnosis

```bash
# Check if certificates are mounted
sudo docker exec at-gateway1 ls -la /mnt/certs/

# Check certificate validity
sudo docker exec at-gateway1 openssl x509 -in /path/to/cert -text -noout
```

#### Solutions

**A. Verify Certificate Secrets**
```bash
# Check if secrets exist in Kubernetes
kubectl get secrets -n mft | grep cert

# Verify secret content
kubectl describe secret mft-admin-ui-certs -n mft
```

**B. Update Certificates**
```bash
# If certificates expired, regenerate and update secrets
# Then restart gateway
sudo systemctl restart at-gateway.service
```

---

## Diagnostic Commands Reference

### Quick Health Check
```bash
# Run all checks at once
echo "=== Service Status ==="
sudo systemctl status at-gateway.service

echo "=== Container Status ==="
sudo docker ps | grep at-gateway

echo "=== Port Listening ==="
sudo netstat -tlnp | grep 8500

echo "=== Recent Logs ==="
sudo docker logs at-gateway1 --tail 20

echo "=== Memory Usage ==="
sudo docker stats at-gateway1 --no-stream

echo "=== Disk Usage ==="
df -h /opt/at-gateway
```

### Log Collection for Support
```bash
# Collect all relevant logs
mkdir -p /tmp/gateway-logs
sudo journalctl -u at-gateway.service > /tmp/gateway-logs/service.log
sudo docker logs at-gateway1 > /tmp/gateway-logs/container.log
sudo docker inspect at-gateway1 > /tmp/gateway-logs/inspect.json
cp /opt/at-gateway/docker-compose.yml /tmp/gateway-logs/
cp /opt/at-gateway/config/properties.cnf /tmp/gateway-logs/

# Create archive
tar -czf gateway-logs-$(date +%Y%m%d-%H%M%S).tar.gz -C /tmp gateway-logs
```

---

## Getting Help

If issues persist after trying these solutions:

1. **Collect diagnostic information** using the commands above
2. **Check Azure Portal** for VM and network resource status
3. **Review recent changes** to infrastructure or configuration
4. **Consult related documentation**:
   - [README.md](./README.md)
   - [Infrastructure Analysis](/.ai-assist/sessions/2026/05/22/03_add_gateways/agent/infrastructure_analysis.md)
   - [Helm Upgrade Guide](../02-AT/HELM-UPGRADE.md)

5. **Contact support** with:
   - Detailed symptom description
   - Diagnostic logs
   - Recent changes made
   - Steps already attempted
