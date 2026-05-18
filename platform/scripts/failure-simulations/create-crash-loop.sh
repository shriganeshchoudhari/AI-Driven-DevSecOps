#!/bin/bash
# create-crash-loop.sh - Create a deployment that crashes on startup
set -euo pipefail

NAMESPACE="${1:-default}"
DEPLOYMENT_NAME="${2:-crash-loop-simulator}"

echo "Creating crash-loop deployment '$DEPLOYMENT_NAME' in namespace '$NAMESPACE'"

kubectl create deployment "$DEPLOYMENT_NAME" \
    --image=alpine:latest \
    --namespace="$NAMESPACE" \
    --replicas=3 \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl set image "deployment/$DEPLOYMENT_NAME" \
    --namespace="$NAMESPACE" \
    "alpine=alpine:latest" \
    --dry-run=client -o yaml | kubectl replace -f -

# Patch the deployment to use a crashing command
kubectl patch deployment "$DEPLOYMENT_NAME" \
    --namespace="$NAMESPACE" \
    --patch='{"spec":{"template":{"spec":{"containers":[{"name":"alpine","command":["sh","-c","echo \"Starting...\"; sleep 2; echo \"Crashing now!\"; exit 1"]}]}}}}'

kubectl rollout status "deployment/$DEPLOYMENT_NAME" \
    --namespace="$NAMESPACE" \
    --timeout=30s 2>/dev/null || true

echo ""
echo "Crash-loop deployment created. Expected behavior:"
echo " - Pods enter CrashLoopBackOff state"
echo " - Alert: KubernetesPodCrashLooping"
echo " - Remediation controller may attempt restart"
echo ""
echo "Cleanup: kubectl delete deployment $DEPLOYMENT_NAME --namespace=$NAMESPACE"
