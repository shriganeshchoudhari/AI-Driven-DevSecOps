#!/bin/bash
# restart-daemonset.sh - Rolling restart all pods in a DaemonSet
set -euo pipefail

NAMESPACE="${1:-}"
DAEMONSET="${2:-}"

if [[ -z "$NAMESPACE" || -z "$DAEMONSET" ]]; then
    echo "Usage: $0 <namespace> <daemonset>"
    exit 1
fi

kubectl rollout restart daemonset/"$DAEMONSET" \
    --namespace="$NAMESPACE"

kubectl rollout status daemonset/"$DAEMONSET" \
    --namespace="$NAMESPACE" \
    --timeout=300s

echo "DaemonSet $DAEMONSET in $NAMESPACE successfully restarted"
