#!/bin/bash
# induce-latency.sh - Inject network latency using tc on a pod
set -euo pipefail

NAMESPACE="${1:-}"
POD_LABEL="${2:-}"
LATENCY_MS="${3:-200}"

if [[ -z "$NAMESPACE" || -z "$POD_LABEL" ]]; then
    echo "Usage: $0 <namespace> <pod-label-selector> [latency-ms]"
    echo "Example: $0 frontend-service 'app=frontend-service' 300"
    echo ""
    echo "Uses Istio/Envoy fault injection if available; falls back to nsenter+tc"
    exit 1
fi

echo "Inducing ${LATENCY_MS}ms latency on pods matching '$POD_LABEL' in '$NAMESPACE'"

# Check if Istio is available for cleaner fault injection
if kubectl get crd virtualservices.networking.istio.io --ignore-not-found 2>/dev/null | grep -q virtualservice; then
    echo "Using Istio VirtualService fault injection..."
    kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: latency-injection-$(echo "$POD_LABEL" | tr '=' '-')
  namespace: $NAMESPACE
spec:
  hosts:
    - "$(kubectl get svc -l "$POD_LABEL" -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo 'service')"
  http:
    - fault:
        delay:
          percentage:
            value: 100
          fixedDelay: "${LATENCY_MS}ms"
      route:
        - destination:
            host: "$(kubectl get svc -l "$POD_LABEL" -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo 'service')"
EOF
    echo "Istio fault injection applied. Expected alerts: HighLatencyP99"
    echo "Remove with: kubectl delete vs latency-injection-$(echo "$POD_LABEL" | tr '=' '-') -n $NAMESPACE"
    exit 0
fi

# Fallback: use tc directly on pods (requires NET_ADMIN or privileged container)
PODS=$(kubectl get pods -l "$POD_LABEL" -n "$NAMESPACE" -o name 2>/dev/null)

if [[ -z "$PODS" ]]; then
    echo "No pods found with label '$POD_LABEL' in namespace '$NAMESPACE'"
    exit 1
fi

echo "Using tc (traffic control) on each pod..."

for POD in $PODS; do
    POD_NAME=$(echo "$POD" | cut -d/ -f2)
    echo "Adding ${LATENCY_MS}ms latency to $POD_NAME..."

    # Check if pod has tc available
    kubectl exec -n "$NAMESPACE" "$POD_NAME" -- sh -c "tc qdisc add dev eth0 root netem delay ${LATENCY_MS}ms 2>/dev/null" || {
        # Fall back to kubectl exec nsenter approach
        NODE=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.nodeName}')
        CONTAINER_ID=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[0].containerID}' | sed 's|containerd://||' | cut -c1-12)

        echo "  Pod $POD_NAME is on node $NODE. For direct tc injection, run on node:"
        echo "  nsenter -t \$(docker inspect -f '{{.State.Pid}}' $CONTAINER_ID) -n tc qdisc add dev eth0 root netem delay ${LATENCY_MS}ms"
        echo ""
        echo "Alternatively, deploy a sidecar with NET_ADMIN or use Chaos Mesh (network-delay experiment)."
    }
done

echo ""
echo "Latency injection complete. Expected alerts:"
echo " - HighLatencyP99"
echo " - RequestDurationIncrease"
echo " - ApdexScoreBelowThreshold"
echo ""
echo "To remove latency from all matching pods:"
echo "  kubectl get pods -l \"$POD_LABEL\" -n $NAMESPACE -o name | while read p; do"
echo "    kubectl exec -n $NAMESPACE \$(echo \$p | cut -d/ -f2) -- tc qdisc del dev eth0 root netem 2>/dev/null || true"
echo "  done"
