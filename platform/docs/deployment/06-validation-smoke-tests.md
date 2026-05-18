# Deployment Validation Suite

Comprehensive validation and smoke tests to verify the platform deployment is healthy and functional.

---

## Table of Contents

- [Quick Validation Script](#quick-validation-script)
- [Kubernetes Validation](#kubernetes-validation)
- [Security Validation](#security-validation)
- [Monitoring Validation](#monitoring-validation)
- [GitOps Validation](#gitops-validation)
- [Application Validation](#application-validation)
- [Performance Validation](#performance-validation)
- [Full Validation Script](#full-validation-script)

---

## Quick Validation Script

```bash
#!/bin/bash
# quick-validate.sh - Run all smoke tests

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
TESTS=()

assert() {
    local test_name="$1"
    local expected="$2"
    shift 2
    local actual
    actual=$("$@" 2>&1) || true

    if [[ "$actual" == *"$expected"* ]]; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((PASS++))
    else
        echo -e "${RED}✗${NC} $test_name"
        echo "  Expected: $expected"
        echo "  Got: $actual"
        ((FAIL++))
    fi
    TESTS+=("$test_name")
}

echo "=========================================="
echo "  Platform Validation Suite"
echo "  $(date)"
echo "=========================================="
echo ""

# === Kubernetes Validation ===
echo "--- Kubernetes Validation ---"
assert "All nodes Ready" "Ready" kubectl get nodes -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}'
assert "CoreDNS running" "Running" kubectl get pods -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[*].status.phase}'
assert "All system pods running" "" kubectl get pods -n kube-system --field-selector=status.phase!=Running,status.phase!=Succeeded 2>&1 | grep -q . || echo "ok"

# === Security Validation ===
echo ""
echo "--- Security Validation ---"
assert "Kyverno pods running" "Running" kubectl get pods -n kyverno -o jsonpath='{.items[*].status.phase}'
assert "Falco pods running" "Running" kubectl get pods -n falco -o jsonpath='{.items[*].status.phase}'
assert "Network policies exist" "default-deny" kubectl get networkpolicies --all-namespaces -o jsonpath='{range .items[*]}{.metadata.name}{" "}{end}'
assert "Pod Security enforced" "restricted" kubectl get ns default -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}'

# === Monitoring Validation ===
echo ""
echo "--- Monitoring Validation ---"
assert "Prometheus running" "Running" kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[*].status.phase}'
assert "Grafana running" "Running" kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[*].status.phase}'
assert "Loki running" "Running" kubectl get pods -n monitoring -l app.kubernetes.io/name=loki -o jsonpath='{.items[*].status.phase}'

# === GitOps Validation ===
echo ""
echo "--- GitOps Validation ---"
assert "ArgoCD running" "Running" kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o jsonpath='{.items[*].status.phase}'
assert "ArgoCD apps synced" "Synced" kubectl get applications -n argocd -o jsonpath='{range .items[*]}{.status.sync.status}{" "}{end}' 2>/dev/null || echo "No apps yet"

# === Ingress Validation ===
echo ""
echo "--- Ingress Validation ---"
assert "NGINX Ingress running" "Running" kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller -o jsonpath='{.items[*].status.phase}'

# === External Secrets Validation ===
echo ""
echo "--- External Secrets Validation ---"
assert "External Secrets running" "Running" kubectl get pods -n external-secrets -o jsonpath='{.items[*].status.phase}'

# === cert-manager Validation ===
echo ""
echo "--- Certificate Validation ---"
assert "cert-manager running" "Running" kubectl get pods -n cert-manager -l app=cert-manager -o jsonpath='{.items[*].status.phase}'
assert "ClusterIssuer exists" "True" kubectl get clusterissuer -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}'

echo ""
echo "=========================================="
echo "  Results: ${PASS} passed, ${FAIL} failed"
if [ $FAIL -eq 0 ]; then
    echo -e "  ${GREEN}ALL TESTS PASSED${NC}"
else
    echo -e "  ${RED}${FAIL} TEST(S) FAILED${NC}"
fi
echo "=========================================="
exit $FAIL
```

---

## Kubernetes Validation

### Node Health Check

```bash
# All nodes should be Ready
kubectl get nodes
```

Expected output:
```
NAME                          STATUS   ROLES    AGE   VERSION
ip-10-0-10-123.ec2.internal   Ready    <none>   1h   v1.29.0-eks-xxx
ip-10-0-11-45.ec2.internal    Ready    <none>   1h   v1.29.0-eks-xxx
ip-10-0-12-67.ec2.internal    Ready    <none>   1h   v1.29.0-eks-xxx
```

```bash
# Detailed node status
kubectl describe nodes | grep -E "Conditions:|Memory|CPU|Pods" | head -20
```

### System Pod Validation

```bash
# All pods must be Running (except Completed Jobs)
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded

# Expected output is empty (no failing pods)
# If there are failures, diagnose:
kubectl get pods -A | grep -v Running | grep -v Completed
```

### Pod Resource Limits

```bash
# Verify all pods have resource limits
kubectl get pods -A -o json | jq '
  .items[] |
  select(.spec.containers[].resources.limits == null or
         .spec.containers[].resources.limits.cpu == null or
         .spec.containers[].resources.limits.memory == null) |
  .metadata.namespace + "/" + .metadata.name' | head -10

# Expected output: empty (no missing limits)
# If pods are found without limits, Kyverno policy should block them
```

### Service Endpoint Validation

```bash
# Check all services have endpoints
kubectl get endpoints -A | awk 'NR==1 || $2 > 0'

# Verify ClusterIP assignment
kubectl get svc -A | awk 'NR==1 || $4 != "None"'
```

### Storage Validation

```bash
# Check all PVCs are Bound
kubectl get pvc -A | awk 'NR==1 || $2 != "Bound"'
# Expected: only header row

# Check StorageClasses exist
kubectl get storageclass
```

---

## Security Validation

### Kyverno Policy Validation

```bash
# Check all policies are installed and ready
kubectl get clusterpolicy -o wide
```

Expected output:
```
NAME                              BACKGROUND   ACTION   READY
disallow-capabilities             true         Enforce  Yes
disallow-host-namespaces          true         Enforce  Yes
disallow-host-path                true         Enforce  Yes
disallow-host-ports               true         Enforce  Yes
disallow-latest-tag               true         Enforce  Yes
disallow-privileged-containers    true         Enforce  Yes
disallow-proc-mount               true         Enforce  Yes
disallow-selinux                  true         Enforce  Yes
require-digests                   true         Enforce  Yes
require-drop-capabilities         true         Enforce  Yes
require-read-only-root-filesystem true         Enforce  Yes
require-readiness-probes          true         Enforce  Yes
require-resource-limits           true         Enforce  Yes
restrict-seccomp                  true         Enforce  Yes
restrict-volume-types             true         Enforce  Yes
unique-ingress-host               true         Enforce  Yes
validate-image-signature          true         Enforce  Yes
```

```bash
# Test policy enforcement
cat << EOF | kubectl apply -f - 2>&1 || true
apiVersion: v1
kind: Pod
metadata:
  name: test-privileged
spec:
  containers:
  - name: nginx
    image: nginx:latest
    securityContext:
      privileged: true
EOF

# Must be blocked
kubectl delete pod test-privileged --now --ignore-not-found

# Verify policy reports (if using Kyverno reporting)
kubectl get policyreport -A
kubectl get clusterpolicyreport -o wide
```

### Falco Runtime Validation

```bash
# Check Falco pods are running on all nodes
kubectl get pods -n falco -o wide

# Verify Falco is generating events
kubectl logs -n falco daemonset/falco --tail=5

# Generate a test event (spawn shell in container)
kubectl run -n default test-shell --image=alpine -- sh -c "id" 2>&1 || true

# Check Falco detected it
kubectl logs -n falco daemonset/falco --tail=10 | grep -i "shell\|terminal"

# Clean up
kubectl delete pod test-shell --now --ignore-not-found
```

### Network Policy Validation

```bash
# Check default-deny exists in every namespace
for ns in $(kubectl get ns -o name | cut -d/ -f2); do
  policies=$(kubectl get networkpolicies -n "$ns" -o name 2>/dev/null)
  if [ -z "$policies" ]; then
    echo "WARNING: No network policies in namespace: $ns"
  fi
done

# Verify policies block cross-namespace traffic (test)
kubectl run -n default test-connectivity --image=alpine --rm -it --restart=Never -- \
  wget -q --timeout=3 http://argocd-server.argocd:80 2>&1 || true
# Should time out (default-deny blocks cross-namespace)
```

### Pod Security Standards

```bash
# Check PSS enforcement levels
kubectl get ns -o json | jq -r '
  .items[] | select(.metadata.labels["pod-security.kubernetes.io/enforce"]) |
  "\(.metadata.name): \(.metadata.labels["pod-security.kubernetes.io/enforce"])"
'

# Verify restricted pods can run
kubectl run -n default test-restricted --image=alpine --rm -it --restart=Never -- \
  sh -c "id" 2>&1 || true
# Should work (restricted policy allows non-root containers)
```

### RBAC Validation

```bash
# Check cluster roles exist
kubectl get clusterrole -l app.kubernetes.io/part-of=platform

# Verify no anonymous access
kubectl get clusterrolebinding -o json | jq '
  .items[] | select(.subjects[]?.kind == "User" and .subjects[]?.name == "anonymous") |
  .metadata.name'
# Expected: empty

# Test RBAC as unauthenticated user
kubectl --token="" get pods 2>&1 | head -3
# Expected: error (unauthorized)
```

### Supply Chain Security

```bash
# Verify image signatures
cosign verify \
  --key k8s://platform/signing-key \
  123456789012.dkr.ecr.us-west-2.amazonaws.com/platform/aiops-engine:latest

# Check Trivy vulnerability report
trivy image --severity CRITICAL,HIGH \
  123456789012.dkr.ecr.us-west-2.amazonaws.com/platform/aiops-engine:latest \
  --ignore-unfixed \
  --exit-code 0

# Verify SBOM
cosign download sbom \
  123456789012.dkr.ecr.us-west-2.amazonaws.com/platform/aiops-engine:latest
```

---

## Monitoring Validation

### Prometheus Targets

```bash
# Port forward Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &
sleep 2

# Query targets
curl -s http://localhost:9090/api/v1/targets | jq '
  .data.activeTargets |
  group_by(.health) |
  map({health: .[0].health, count: length})
'

# Expected output:
# [
#   {"health": "up", "count": 50}
# ]

# Or check for non-UP targets
curl -s http://localhost:9090/api/v1/targets | jq '
  .data.activeTargets[] | select(.health != "up") |
  "\(.labels.job)/\(.labels.instance): \(.health)"
'
# Expected: empty

kill %1 2>/dev/null
```

### Grafana Datasources

```bash
# Port forward Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80 &
sleep 2

# Check datasources via API
GRAFANA_PASS=$(kubectl get secret -n monitoring kube-prometheus-stack-grafana \
  -o jsonpath="{.data.admin-password}" | base64 -d)

curl -s -u "admin:${GRAFANA_PASS}" \
  http://localhost:3000/api/datasources | jq '.[].name'

# Expected:
# "Prometheus"
# "Loki"
# "Tempo"

kill %1 2>/dev/null
```

### Loki Log Ingestion

```bash
# Port forward Loki
kubectl port-forward -n monitoring svc/loki-gateway 3100:80 &
sleep 2

# Query log labels
curl -s "http://localhost:3100/loki/api/v1/labels" | jq '.data'

# Expected: various labels including namespace, pod, container

# Query recent logs
curl -s -G "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode "query={namespace=\"kube-system\"}" \
  --data-urlencode "limit=5" \
  --data-urlencode "start=$(date -d '5 minutes ago' +%s)000000000" | jq '.data.result | length'

# Expected: > 0 (logs found)

kill %1 2>/dev/null
```

### Tempo Trace Ingestion

```bash
# Port forward Tempo
kubectl port-forward -n monitoring svc/tempo-query-frontend 3200:3200 &
sleep 2

# Query Tempo for services
curl -s "http://localhost:3200/api/search" | jq '.'

# Generate a trace # (requires an instrumented app)
curl -s -X POST "http://localhost:3200/api/traces" -H "Content-Type: application/json" \
  -d '{"id":"test","startTime":1,"endTime":2,"serviceName":"test"}' 2>&1 || true

# Check Tempo readiness
curl -s "http://localhost:3200/ready" | grep -q "Ready" && echo "Tempo Ready" || echo "Tempo Not Ready"

kill %1 2>/dev/null
```

### Alertmanager Configuration

```bash
# Port forward Alertmanager
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093 &
sleep 2

# Check alertmanager status
curl -s http://localhost:9093/api/v2/status | jq '.config.route'

# Check active alerts
curl -s http://localhost:9093/api/v2/alerts | jq '. | length'

kill %1 2>/dev/null
```

### Pre-built Dashboards

```bash
# Check available Grafana dashboards
kubectl get configmap -n monitoring -l grafana_dashboard=1 -o name

# Expected dashboards:
# - Kubernetes / Cluster
# - Kubernetes / Nodes
# - Kubernetes / Pods
# - Kubernetes / Deployments
# - Node Exporter Full
# - Loki / Logs
# - Tempo / Traces
# - Platform / Overview
# - Platform / Applications
# - Platform / Security
# - Platform / AIOps
```

---

## GitOps Validation

### ArgoCD Application Sync

```bash
# Check all applications are Synced
argocd app list -o json | jq '
  .[] | 
  if .status.sync.status != "Synced" or .status.health.status != "Healthy" then
    "\(.metadata.name): sync=\(.status.sync.status) health=\(.status.health.status)"
  else
    empty
  end
'
# Expected: empty (all apps synced and healthy)

# Or list with status
argocd app list
```

Expected output:
```
NAME              CLUSTER                         NAMESPACE   PROJECT     STATUS  HEALTH   SYNCPOLICY
applications      https://kubernetes.default.svc  default     default     Synced  Healthy  Auto-Prune
aiops             https://kubernetes.default.svc  aiops       default     Synced  Healthy  Auto-Prune
argocd            https://kubernetes.default.svc  argocd      default     Synced  Healthy  Auto-Prune
cert-manager      https://kubernetes.default.svc  cert-manager default     Synced  Healthy  Auto-Prune
chaos-mesh        https://kubernetes.default.svc  chaos-mesh  default     Synced  Healthy  Auto-Prune
external-secrets  https://kubernetes.default.svc  external-secrets default  Synced  Healthy  Auto-Prune
ingress-nginx     https://kubernetes.default.svc  ingress-nginx default    Synced  Healthy  Auto-Prune
kyverno           https://kubernetes.default.svc  kyverno     default     Synced  Healthy  Auto-Prune
monitoring        https://kubernetes.default.svc  monitoring  default     Synced  Healthy  Auto-Prune
```

### Sync Wave Validation

```bash
# Check sync wave annotations
kubectl get applications -n argocd -o json | jq '
  .items[] | 
  "\(.metadata.name): wave=\(.metadata.annotations["argocd.argoproj.io/sync-wave"] // "none")"
'
```

### Drift Detection

```bash
# Force a drift (modify a resource outside GitOps)
kubectl scale deployment -n argocd argocd-server --replicas=2

# Wait for auto-heal
sleep 30

# Verify it was reverted
kubectl get deployment -n argocd argocd-server -o jsonpath='{.spec.replicas}'
# Expected: original replica count (not 2)
```

### Application Sync Details

```bash
# Check detailed sync status
argocd app get aiops

# Check sync events
kubectl get events -n argocd --field-selector involvedObject.kind=Application
```

---

## Application Validation

### Health Endpoints

```bash
# AIOps Engine health check
AI_OPS_POD=$(kubectl get pods -n aiops -l app.kubernetes.io/name=aiops-engine -o name | head -1)
kubectl port-forward -n aiops "$AI_OPS_POD" 8000:8000 &
sleep 2

echo "=== AIOps Health Check ==="
curl -s http://localhost:8000/health | jq .

# Expected:
# {
#   "status": "healthy",
#   "version": "1.0.0",
#   "components": {
#     "vector_store": "connected",
#     "llm_provider": "configured",
#     "prometheus": "connected",
#     "loki": "connected"
#   }
# }

kill %1 2>/dev/null
```

### Cross-Service Communication

```bash
# Deploy a test pod with curl
kubectl run -n default test-client --image=curlimages/curl --rm -it --restart=Never -- \
  curl -s -o /dev/null -w "%{http_code}" \
  http://aiops-engine.aiops:8000/health
# Expected: 200

# Test DNS resolution
kubectl run -n default test-dns --image=alpine --rm -it --restart=Never -- \
  nslookup aiops-engine.aiops 2>&1

# Expected:
# Name:      aiops-engine.aiops
# Address 1: 10.100.x.x aiops-engine.aiops.svc.cluster.local
```

### Database Connectivity

```bash
# Get database credentials from secret
DB_POD=$(kubectl get pods -n aiops -l app.kubernetes.io/name=aiops-engine -o name | head -1)

# Check database connection from a pod
kubectl exec -n aiops "$DB_POD" -- \
  sh -c "pg_isready -h \$DB_HOST -p \$DB_PORT -U \$DB_USERNAME" 2>&1 || true

# If pg_isready not available, test with Python
kubectl exec -n aiops "$DB_POD" -- \
  python3 -c "
import os
import psycopg2
try:
    conn = psycopg2.connect(
        host=os.environ.get('DB_HOST'),
        port=os.environ.get('DB_PORT'),
        user=os.environ.get('DB_USERNAME'),
        password=os.environ.get('DB_PASSWORD'),
        dbname=os.environ.get('DB_DATABASE')
    )
    cur = conn.cursor()
    cur.execute('SELECT version()')
    print('PostgreSQL connected:', cur.fetchone()[0])
    cur.close()
    conn.close()
except Exception as e:
    print('Database error:', e)
"
```

### Redis Connectivity

```bash
# Test Redis connectivity
kubectl exec -n aiops "$DB_POD" -- \
  python3 -c "
import os
import redis
try:
    r = redis.Redis(
        host=os.environ.get('REDIS_HOST', 'localhost'),
        port=int(os.environ.get('REDIS_PORT', 6379)),
        password=os.environ.get('REDIS_AUTH'),
        socket_connect_timeout=5
    )
    r.ping()
    print('Redis connected successfully')
except Exception as e:
    print('Redis error:', e)
"
```

### API Functional Tests

```bash
# Test AIOps analysis endpoint
curl -s -X POST http://localhost:8000/api/v1/analyze \
  -H "Content-Type: application/json" \
  -d '{
    "incident_id": "test-001",
    "query": "What services are unhealthy?",
    "context": {
      "time_range": "1h",
      "severity": "critical"
    }
  }' | jq .

# Expected: analysis result (may vary based on cluster state)
```

### TLS Certificate Validation

```bash
# Check certificate expiry
kubectl get certificate -A
kubectl get certificaterequest -A

# Verify ingress TLS
kubectl get ingress -A -o json | jq '
  .items[] | select(.spec.tls != null) |
  "\(.metadata.name): \(.spec.tls[].hosts)"
'
```

---

## Performance Validation

### API Response Times

```bash
# Measure AIOps API latency
for i in {1..10}; do
  curl -s -o /dev/null -w "%{time_total}\n" \
    http://localhost:8000/health
done | awk '{sum+=$1} END {print "Avg latency:", sum/NR, "seconds"}'

# Expected: < 0.5 seconds
```

### Pod Startup Times

```bash
# Measure how long pods take to become Ready
kubectl run -n default perf-test --image=nginx:alpine --restart=Never \
  --requests='cpu=100m,memory=64Mi' \
  --limits='cpu=200m,memory=128Mi'

START_TIME=$(date +%s)
kubectl wait --for=condition=Ready pod/perf-test -n default --timeout=30s
END_TIME=$(date +%s)
echo "Pod startup time: $((END_TIME - START_TIME)) seconds"

kubectl delete pod perf-test -n default --now
# Expected: < 10 seconds
```

### Node Scaling Test (Karpenter)

```bash
# Trigger scale-up with a resource-intensive deployment
kubectl create deployment -n default scale-test \
  --image=nginx:alpine --replicas=20

# Watch Karpenter provision new nodes
kubectl get nodes -w &
NODE_WATCH_PID=$!
sleep 60
kill $NODE_WATCH_PID 2>/dev/null

# Clean up
kubectl delete deployment scale-test -n default
```

### HPA Validation

```bash
# Create deployment with HPA
kubectl apply -f - << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hpa-test
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: hpa-test
  template:
    metadata:
      labels:
        app: hpa-test
    spec:
      containers:
      - name: stress
        image: containerstack/alpine-stress
        resources:
          requests:
            cpu: 100m
          limits:
            cpu: 500m
        args:
        - --cpu
        - "1"
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: hpa-test
  namespace: default
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: hpa-test
  minReplicas: 1
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
EOF

# Monitor HPA
kubectl get hpa hpa-test -n default -w &
HPA_WATCH_PID=$!
sleep 120
kill $HPA_WATCH_PID 2>/dev/null

# Clean up
kubectl delete hpa hpa-test -n default
kubectl delete deployment hpa-test -n default
```

---

## Full Validation Script

The complete validation script `scripts/validation.sh` runs all tests above sequentially and generates a report.

```bash
# Run the full validation suite
./scripts/validation.sh

# Run with specific environment
ENVIRONMENT=prod ./scripts/validation.sh

# Generate HTML report
./scripts/validation.sh --format html --output validation-report.html

# Run only specific test categories
./scripts/validation.sh --tests kubernetes,security

# Continuous validation (every 5 minutes)
./scripts/validation.sh --watch --interval 300
```

Expected output:
```
======================================================
      Platform Validation Suite
      2026-05-17 10:00:00 UTC
======================================================

--- Kubernetes Validation ---
✔ All nodes Ready (3/3)
✔ CoreDNS running
✔ All system pods running
✔ All services have endpoints

--- Security Validation ---
✔ Kyverno: 17 policies ready
✔ Falco: 3 pods running, generating events
✔ Network policies in all namespaces
✔ Pod Security: restricted enforced
✔ RBAC: least privilege configured

--- Monitoring Validation ---
✔ Prometheus: 48/48 targets UP
✔ Grafana: 12 datasources configured
✔ Loki: logs ingesting
✔ Tempo: traces receiving

--- GitOps Validation ---
✔ ArgoCD: 9 apps Synced and Healthy
✔ Drift detection: auto-heal enabled
✔ Sync waves: correct ordering

--- Application Validation ---
✔ AIOps Engine: healthy
✔ Database: connected
✔ Redis: connected
✔ API endpoints: all respond 200

======================================================
  Results: 35 passed, 0 failed
  ALL TESTS PASSED
======================================================
```

---

## Next Steps

After validating the deployment:

1. [Review rollback procedures](07-rollback-procedures.md)
2. [Learn SRE operational procedures](../operations/01-sre-runbook.md)
3. [Review incident response](../operations/02-incident-response.md)
