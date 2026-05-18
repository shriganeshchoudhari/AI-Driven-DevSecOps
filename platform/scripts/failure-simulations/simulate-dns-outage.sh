#!/bin/bash
# simulate-dns-outage.sh - Simulate a DNS outage by scaling down CoreDNS
set -euo pipefail

DURATION_SECONDS="${1:-30}"

echo "=== Kubernetes CoreDNS DNS Outage Simulation ==="
echo "WARNING: This will disrupt DNS resolution across the entire cluster!"
echo "Do NOT run this in a production cluster."
echo ""

# Store current replica count
CURRENT_REPLICAS=$(kubectl get deployment coredns -n kube-system -o jsonpath='{.spec.replicas}')
echo "Current CoreDNS replicas: $CURRENT_REPLICAS"

echo "Scaling down CoreDNS deployment to 0 replicas to induce DNS failure..."
kubectl scale deployment/coredns -n kube-system --replicas=0

echo ""
echo "DNS resolution is now disrupted. Testing resolution from default pod (expected to fail):"
kubectl run dns-test-temp --image=busybox:latest --restart=Never --rm -i --timeout=5s -- nslookup google.com || true

echo ""
echo "Outage induced. Waiting for $DURATION_SECONDS seconds..."
sleep "$DURATION_SECONDS"

echo ""
echo "Restoring CoreDNS to original state ($CURRENT_REPLICAS replicas)..."
kubectl scale deployment/coredns -n kube-system --replicas="$CURRENT_REPLICAS"

echo "Waiting for CoreDNS pods to recover..."
kubectl rollout status deployment/coredns -n kube-system

echo ""
echo "Verification - Testing DNS resolution again (expected to succeed):"
kubectl run dns-test-temp --image=busybox:latest --restart=Never --rm -i --timeout=15s -- nslookup google.com || echo "DNS recovery pending."

echo ""
echo "=== CoreDNS DNS Outage Simulation Complete ==="
