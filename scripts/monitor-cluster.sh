#!/bin/bash
# Comprehensive AKS Cluster Monitoring Script
# Usage: ./monitor-cluster.sh [refresh_interval_seconds]

REFRESH_INTERVAL=${1:-10}
NAMESPACE=${2:-default}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

while true; do
  clear
  echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║                    AKS Cluster Monitoring Dashboard                        ║${NC}"
  echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "${YELLOW}⏰ TIMESTAMP: $(date)${NC}"
  echo ""

  # ============================================================================
  # NODES SECTION
  # ============================================================================
  echo -e "${GREEN}═══ NODES (Availability Zones) ═══${NC}"
  kubectl get nodes -o custom-columns=\
NAME:.metadata.name,\
STATUS:.status.conditions[-1].type,\
ZONE:.metadata.labels.'topology\.kubernetes\.io/zone',\
CPU:.status.capacity.cpu,\
MEMORY:.status.capacity.memory,\
AGE:.metadata.creationTimestamp 2>/dev/null || echo "Error fetching nodes"

  echo ""
  TOTAL_NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
  READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready")
  echo -e "Total Nodes: ${GREEN}${TOTAL_NODES}${NC} | Ready: ${GREEN}${READY_NODES}${NC}"

  # ============================================================================
  # ACTIVE TRANSFER PODS SECTION
  # ============================================================================
  echo ""
  echo -e "${GREEN}═══ ACTIVE TRANSFER PODS ═══${NC}"
  AT_PODS=$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=active-transfer --no-headers 2>/dev/null | wc -l)

  if [ "$AT_PODS" -gt 0 ]; then
    kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=active-transfer -o wide 2>/dev/null

    echo ""
    RUNNING=$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=active-transfer --no-headers 2>/dev/null | grep -c "Running")
    READY=$(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=active-transfer -o json 2>/dev/null | jq -r '.items[] | select(.status.conditions[] | select(.type=="Ready" and .status=="True")) | .metadata.name' | wc -l)
    echo -e "Total: ${BLUE}${AT_PODS}${NC} | Running: ${GREEN}${RUNNING}${NC} | Ready: ${GREEN}${READY}${NC}"
  else
    echo -e "${YELLOW}No Active Transfer pods found in namespace '${NAMESPACE}'${NC}"
  fi

  # ============================================================================
  # POD DISTRIBUTION BY NODE
  # ============================================================================
  echo ""
  echo -e "${GREEN}═══ POD DISTRIBUTION BY NODE ═══${NC}"
  for node in $(kubectl get nodes -o name 2>/dev/null); do
    NODE_NAME=${node#node/}
    POD_COUNT=$(kubectl get pods --all-namespaces -o wide --field-selector spec.nodeName=${NODE_NAME} --no-headers 2>/dev/null | wc -l)
    ZONE=$(kubectl get node ${NODE_NAME} -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}' 2>/dev/null)
    echo -e "${NODE_NAME} (${ZONE}): ${BLUE}${POD_COUNT}${NC} pods"
  done

  # ============================================================================
  # SYSTEM PODS HEALTH
  # ============================================================================
  echo ""
  echo -e "${GREEN}═══ CRITICAL SYSTEM PODS ═══${NC}"
  COREDNS=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | grep -c "Running")
  METRICS=$(kubectl get pods -n kube-system -l k8s-app=metrics-server --no-headers 2>/dev/null | grep -c "Running")
  INGRESS=$(kubectl get pods -n agic -l app=ingress-azure --no-headers 2>/dev/null | grep -c "Running")

  echo -e "CoreDNS: ${GREEN}${COREDNS}${NC} | Metrics Server: ${GREEN}${METRICS}${NC} | Ingress (AGIC): ${GREEN}${INGRESS}${NC}"

  # ============================================================================
  # PROBLEMATIC PODS
  # ============================================================================
  echo ""
  echo -e "${GREEN}═══ PROBLEMATIC PODS ═══${NC}"
  PROBLEM_PODS=$(kubectl get pods --all-namespaces --no-headers 2>/dev/null | grep -v "Running\|Completed" | wc -l)

  if [ "$PROBLEM_PODS" -gt 0 ]; then
    echo -e "${RED}Found ${PROBLEM_PODS} pods not in Running/Completed state:${NC}"
    kubectl get pods --all-namespaces --no-headers 2>/dev/null | grep -v "Running\|Completed" | head -10
  else
    echo -e "${GREEN}✓ All pods are Running or Completed${NC}"
  fi

  # ============================================================================
  # RECENT EVENTS
  # ============================================================================
  echo ""
  echo -e "${GREEN}═══ RECENT CLUSTER EVENTS (Last 8) ═══${NC}"
  kubectl get events --all-namespaces --sort-by='.lastTimestamp' 2>/dev/null | tail -8

  # ============================================================================
  # RESOURCE USAGE (if metrics-server is available)
  # ============================================================================
  echo ""
  echo -e "${GREEN}═══ NODE RESOURCE USAGE ═══${NC}"
  kubectl top nodes 2>/dev/null || echo -e "${YELLOW}Metrics not available (metrics-server may not be ready)${NC}"

  # ============================================================================
  # ACTIVE TRANSFER SPECIFIC CHECKS
  # ============================================================================
  if [ "$AT_PODS" -gt 0 ]; then
    echo ""
    echo -e "${GREEN}═══ ACTIVE TRANSFER HEALTH CHECKS ═══${NC}"

    # Check readiness probe failures
    READINESS_FAILURES=$(kubectl get events -n ${NAMESPACE} --field-selector involvedObject.kind=Pod 2>/dev/null | grep -c "Readiness probe failed")
    if [ "$READINESS_FAILURES" -gt 0 ]; then
      echo -e "${RED}⚠ Readiness probe failures detected: ${READINESS_FAILURES}${NC}"
    else
      echo -e "${GREEN}✓ No recent readiness probe failures${NC}"
    fi

    # Check for database connection errors in logs
    echo -e "\nChecking for database connection errors..."
    for pod in $(kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=active-transfer -o name 2>/dev/null); do
      POD_NAME=${pod#pod/}
      DB_ERRORS=$(kubectl logs ${pod} -n ${NAMESPACE} --tail=50 2>/dev/null | grep -c "remaining connection slots are reserved")
      if [ "$DB_ERRORS" -gt 0 ]; then
        echo -e "${RED}⚠ ${POD_NAME}: ${DB_ERRORS} database connection errors${NC}"
      else
        echo -e "${GREEN}✓ ${POD_NAME}: No database connection errors${NC}"
      fi
    done
  fi

  # ============================================================================
  # FOOTER
  # ============================================================================
  echo ""
  echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════${NC}"
  echo -e "${YELLOW}Refreshing in ${REFRESH_INTERVAL} seconds... (Ctrl+C to stop)${NC}"
  echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════${NC}"

  sleep ${REFRESH_INTERVAL}
done

# Made with Bob
