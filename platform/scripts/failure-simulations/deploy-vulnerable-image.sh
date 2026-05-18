#!/bin/bash
# deploy-vulnerable-image.sh - Deploy a container with known vulnerabilities
# Used to test image scanning, Kyverno admission control, and Falco runtime detection
set -euo pipefail

NAMESPACE="${1:-default}"
echo "=== Deploying vulnerable container to namespace: $NAMESPACE ==="

kubectl create deployment vulnerable-app \
  --image=vulnerables/web-dvwa:latest \
  --namespace="$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl expose deployment vulnerable-app \
  --port=80 \
  --target-port=80 \
  --namespace="$NAMESPACE" \
  --name=vulnerable-app \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "✓ Vulnerable deployment created"
echo ""
echo "Expected security responses:"
echo "  1. TRIVY - Image scan will find CRITICAL vulnerabilities"
echo "  2. KYVERNO - Policy 'block-registry-external' will flag external registry"
echo "  3. FALCO - Runtime suspicious behavior detection may trigger"
echo ""
echo "Check results:"
echo "  kubectl get pods -n $NAMESPACE -l app=vulnerable-app"
echo "  kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=50"
echo ""
echo "To clean up:"
echo "  kubectl delete deployment vulnerable-app -n $NAMESPACE"
echo "  kubectl delete service vulnerable-app -n $NAMESPACE"
