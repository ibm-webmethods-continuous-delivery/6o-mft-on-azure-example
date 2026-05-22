#!/bin/bash
# Test pod-to-pod connectivity on JGroups port 7800

NAMESPACE="${NAMESPACE:-default}"

echo "Testing Pod-to-Pod JGroups Connectivity"
echo "========================================"
echo ""

# Get all pods with their IPs
echo "Getting pod information..."
PODS_INFO=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=active-transfer" -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.podIP}{"\n"}{end}')

echo "$PODS_INFO"
echo ""

# Convert to arrays (without awk)
POD_NAMES=()
POD_IPS=()
while IFS=' ' read -r name ip; do
    if [ -n "$name" ]; then
        POD_NAMES+=("$name")
        POD_IPS+=("$ip")
    fi
done <<< "$PODS_INFO"

POD_COUNT=${#POD_NAMES[@]}

if [ "$POD_COUNT" -lt 2 ]; then
    echo "Only $POD_COUNT pod(s) found. Need at least 2 for testing."
    exit 1
fi

echo "Testing connectivity between $POD_COUNT pods..."
echo ""

# Test from each pod to every other pod
for ((i=0; i<$POD_COUNT; i++)); do
    SOURCE_POD="${POD_NAMES[$i]}"
    SOURCE_IP="${POD_IPS[$i]}"

    echo "From: $SOURCE_POD ($SOURCE_IP)"

    for ((j=0; j<$POD_COUNT; j++)); do
        if [ $i -ne $j ]; then
            TARGET_POD="${POD_NAMES[$j]}"
            TARGET_IP="${POD_IPS[$j]}"

            # Test connectivity
            if kubectl exec -n "$NAMESPACE" "$SOURCE_POD" -- bash -c "(echo > /dev/tcp/$TARGET_IP/7800) >/dev/null 2>&1" 2>/dev/null; then
                echo "  ✓ -> $TARGET_POD ($TARGET_IP:7800) - CONNECTED"
            else
                echo "  ✗ -> $TARGET_POD ($TARGET_IP:7800) - FAILED"
            fi
        fi
    done
    echo ""
done

echo "Testing if JGroups is bound to pod IP (not localhost)..."
for ((i=0; i<$POD_COUNT; i++)); do
    POD="${POD_NAMES[$i]}"
    IP="${POD_IPS[$i]}"

    echo "Pod: $POD"
    echo "  Testing localhost:7800..."
    if kubectl exec -n "$NAMESPACE" "$POD" -- bash -c "(echo > /dev/tcp/localhost/7800) >/dev/null 2>&1" 2>/dev/null; then
        echo "    ✓ localhost:7800 - CONNECTED"
    else
        echo "    ✗ localhost:7800 - FAILED (expected if JGroups binds to pod IP)"
    fi

    echo "  Testing $IP:7800..."
    if kubectl exec -n "$NAMESPACE" "$POD" -- bash -c "(echo > /dev/tcp/$IP/7800) >/dev/null 2>&1" 2>/dev/null; then
        echo "    ✓ $IP:7800 - CONNECTED"
    else
        echo "    ✗ $IP:7800 - FAILED"
    fi
    echo ""
done

# Made with Bob
