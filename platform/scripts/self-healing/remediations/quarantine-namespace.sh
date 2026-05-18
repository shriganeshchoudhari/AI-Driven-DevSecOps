#!/bin/bash
# quarantine-namespace.sh - Apply strict network isolation to a namespace
# Used for incident response when a compromise is detected
set -euo pipefail

NAMESPACE="${1:-}"
if [[ -z "$NAMESPACE" ]]; then
    echo "Usage: $0 <namespace>"
    echo "Applies a deny-all network policy to isolate the namespace"
    exit 1
fi

echo "=== Quarantining namespace: $NAMESPACE ==="

# Apply egress-deny policy
kubectl apply -n "$NAMESPACE" -f - <<NETPOL
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: quarantine-egress-deny
  labels:
    quarantine: "true"
    quarantined-at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
spec:
  podSelector: {}
  policyTypes:
    - Egress
NETPOL

# Apply ingress-deny policy
kubectl apply -n "$NAMESPACE" -f - <<NETPOL
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: quarantine-ingress-deny
  labels:
    quarantine: "true"
spec:
  podSelector: {}
  policyTypes:
    - Ingress
NETPOL

echo "✓ Namespace $NAMESPACE is now quarantined"
echo "  - All egress traffic blocked"
echo "  - All ingress traffic blocked"
echo ""
echo "To remove quarantine:"
echo "  kubectl delete networkpolicy quarantine-egress-deny -n $NAMESPACE"
echo "  kubectl delete networkpolicy quarantine-ingress-deny -n $NAMESPACE"
