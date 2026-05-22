# JGroups Clustering Diagnostic Scripts

Troubleshooting tools for Active Transfer JGroups clustering on Kubernetes.

## Quick Start

```bash
# Make scripts executable
chmod +x *.sh

# Run comprehensive health check
./test-deployment-health.sh

# If issues found, run detailed diagnostics
./diagnose-jgroups.sh
```

## Scripts

| Script | Purpose | When to Use |
|--------|---------|-------------|
| `test-deployment-health.sh` | Overall health check | First step - checks pods, connectivity, services |
| `diagnose-jgroups.sh` | Deep JGroups diagnostics | When clustering isn't working |
| `check-rbac.sh` | Verify RBAC permissions | When KUBE_PING can't discover pods |
| `test-pod-to-pod.sh` | Test port 7800 connectivity | When pods can't communicate |
| `verify-jgroups-config.sh` | Check deployed configuration | Verify config files are correct |
| `check-cluster-members.sh` | View cluster membership | Check if pods joined the cluster |
| `check-jgroups-logs.sh` | Analyze JGroups logs | Search for specific log messages |
| `final-cluster-check.sh` | Comprehensive verification | Final check after fixes |

## Configuration

Set environment variables to customize:
```bash
export NAMESPACE=mft-namespace
export RELEASE_NAME=active-transfer
./test-deployment-health.sh
```

## Common Issues

- **Port 7800 closed**: Check network policies and pod connectivity
- **No KUBE_PING messages**: Verify RBAC permissions and labels
- **Config not loading**: Check file paths and ConfigMap mounts
- **EOFException warnings**: Normal during reconnection, ignore if cluster forms

## Expected Results

✅ Cluster view shows all pods: `VIEW:Cloud Sync:[pod1, pod2]`
✅ Port 7800 connectivity between all pods
✅ No RBAC permission errors
✅ Config files loaded successfully

## Related Tools

For cluster-wide monitoring and real-time dashboard, see:
- **`../../../../scripts/monitor-cluster.sh`** - Comprehensive AKS cluster monitoring with auto-refresh