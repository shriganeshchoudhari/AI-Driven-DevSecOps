#!/bin/bash
# create-memory-leak.sh - Simulate memory leak in a pod
# Triggers: OOMKilled, CrashLoopBackOff, HighMemoryUsage alert, HPA events
set -euo pipefail

NAMESPACE="${1:-default}"
POD_NAME="${2:-memory-leak-simulator}"

echo "=== Creating memory leak simulator in namespace: $NAMESPACE ==="
echo "Pod name: $POD_NAME"
echo ""

kubectl run "$POD_NAME" \
    --image=python:3.11-slim \
    --namespace="$NAMESPACE" \
    --limits="memory=256Mi" \
    --requests="memory=128Mi" \
    -- /bin/sh -c '
python3 -c "
import time
import sys

leak = []
iteration = 0
try:
    while True:
        iteration += 1
        # Allocate 10MB per iteration
        leak.append(\" \" * 1024 * 1024 * 10)
        print(f\"[{iteration}] Allocated {iteration * 10}MB (PID: {__import__(\"os\").getpid()})\")
        sys.stdout.flush()
        time.sleep(1)
except MemoryError:
    print(f\"OOM after {iteration * 10}MB allocation\")
    sys.stdout.flush()
    time.sleep(5)
"
'

echo ""
echo "✓ Memory leak simulator started"
echo ""
echo "Expected alerts and behaviors:"
echo "  1. Pod will be OOMKilled (exit code 137)"
echo "  2. Pod will enter CrashLoopBackOff"
echo "  3. Prometheus alert 'KubernetesPodCrashLooping' will fire"
echo "  4. AIOps will detect memory anomaly pattern"
echo "  5. HPA may scale if configured on memory"
echo ""
echo "Monitoring commands:"
echo "  kubectl get pods -n $NAMESPACE -w | grep $POD_NAME"
echo "  kubectl describe pod $POD_NAME -n $NAMESPACE"
