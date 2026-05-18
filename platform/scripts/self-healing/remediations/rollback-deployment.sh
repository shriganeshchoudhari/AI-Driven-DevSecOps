#!/bin/bash
# rollback-deployment.sh - Rollback a Kubernetes deployment to previous revision
set -euo pipefail

NAMESPACE="${1:-}"
DEPLOYMENT="${2:-}"
REVISION="${3:-}"

if [[ -z "$NAMESPACE" || -z "$DEPLOYMENT" ]]; then
    echo "Usage: $0 <namespace> <deployment> [revision]"
    echo "If revision is omitted, rolls back to previous revision"
    exit 1
fi

echo "=== Rolling back deployment $DEPLOYMENT in namespace $NAMESPACE ==="

if [[ -n "$REVISION" ]]; then
    echo "Target revision: $REVISION"
    kubectl rollout undo deployment/"$DEPLOYMENT" \
        --namespace="$NAMESPACE" \
        --to-revision="$REVISION"
else
    kubectl rollout undo deployment/"$DEPLOYMENT" \
        --namespace="$NAMESPACE"
fi

echo "Waiting for rollout to complete..."
if kubectl rollout status deployment/"$DEPLOYMENT" \
    --namespace="$NAMESPACE" \
    --timeout=300s; then
    echo "✓ Rollback successful"
else
    echo "✗ Rollback timed out or failed"
    exit 1
fi
