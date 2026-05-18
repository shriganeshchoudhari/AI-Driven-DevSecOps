#!/bin/bash
set -euo pipefail

ENVIRONMENT="${1:-dev}"
OUTPUT_FORMAT="${2:-text}"
OUTPUT_FILE="${3:-}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0
SKIP=0
TESTS=()
START_TIME=$(date +%s)

init_report() {
    if [ "$OUTPUT_FORMAT" = "html" ] && [ -n "$OUTPUT_FILE" ]; then
        cat > "$OUTPUT_FILE" << 'EOF'
<!DOCTYPE html>
<html><head><title>Platform Validation Report</title>
<style>
body { font-family: monospace; margin: 20px; background: #1a1a2e; color: #eee; }
h1 { color: #e94560; }
.pass { color: #4ecca3; }
.fail { color: #e94560; }
.skip { color: #f0a500; }
.summary { border-top: 2px solid #444; padding-top: 10px; }
</style></head><body>
<h1>Platform Validation Report</h1>
<p>Environment: '"${ENVIRONMENT}"' | Date: '"$(date -u)"'</p>
<table border="1" style="border-collapse:collapse;width:100%">
<tr><th>#</th><th>Test</th><th>Status</th><th>Details</th></tr>
EOF
    fi
}

append_result() {
    local test_name="$1" status="$2" detail="$3"
    if [ "$OUTPUT_FORMAT" = "html" ] && [ -n "$OUTPUT_FILE" ]; then
        local css_class="${status}"
        echo "<tr class=\"${css_class}\"><td>${#TESTS[@]}</td><td>${test_name}</td><td>${status}</td><td>${detail}</td></tr>" >> "$OUTPUT_FILE"
    fi
}

close_report() {
    local duration=$(( $(date +%s) - START_TIME ))
    if [ "$OUTPUT_FORMAT" = "html" ] && [ -n "$OUTPUT_FILE" ]; then
        cat >> "$OUTPUT_FILE" << EOF
</table>
<div class="summary">
<p>Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped</p>
<p>Duration: ${duration}s</p>
</div></body></html>
EOF
        echo "HTML report written to: ${OUTPUT_FILE}"
    fi
}

assert() {
    local test_name="$1"
    local expected="$2"
    shift 2
    local actual
    actual=$("$@" 2>&1) || true

    TESTS+=("$test_name")

    if echo "$actual" | grep -q "$expected"; then
        echo -e "${GREEN}✓${NC} ${test_name}"
        ((PASS++))
        append_result "$test_name" "PASS" ""
    else
        echo -e "${RED}✗${NC} ${test_name}"
        echo "  Expected: $expected"
        echo "  Got:      $actual"
        ((FAIL++))
        append_result "$test_name" "FAIL" "${actual}"
    fi
}

assert_not() {
    local test_name="$1"
    local unexpected="$2"
    shift 2
    local actual
    actual=$("$@" 2>&1) || true

    TESTS+=("$test_name")

    if echo "$actual" | grep -q "$unexpected"; then
        echo -e "${RED}✗${NC} ${test_name}"
        echo "  Unexpected: $unexpected"
        ((FAIL++))
        append_result "$test_name" "FAIL" "Found: ${unexpected}"
    else
        echo -e "${GREEN}✓${NC} ${test_name}"
        ((PASS++))
        append_result "$test_name" "PASS" ""
    fi
}

check_condition() {
    local test_name="$1"
    shift
    TESTS+=("$test_name")

    if "$@" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} ${test_name}"
        ((PASS++))
        append_result "$test_name" "PASS" ""
    else
        echo -e "${RED}✗${NC} ${test_name}"
        ((FAIL++))
        append_result "$test_name" "FAIL" "Condition not met"
    fi
}

echo "╔══════════════════════════════════════════════════════════╗"
echo "║            Platform Validation Suite                      ║"
echo "║  Environment: ${ENVIRONMENT}   $(date -u)  ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

init_report

echo "--- Kubernetes Validation ---"
assert_not "No Unready nodes" "False" kubectl get nodes -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}'
assert "CoreDNS running" "Running" kubectl get pods -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[*].status.phase}'
assert_not "No failing system pods" "" kubectl get pods -n kube-system --field-selector=status.phase!=Running,status.phase!=Succeeded -o name 2>/dev/null

echo ""
echo "--- Security Validation ---"
assert "Kyverno pods running" "Running" kubectl get pods -n kyverno -o jsonpath='{.items[*].status.phase}'
assert "Falco pods running" "Running" kubectl get pods -n falco -o jsonpath='{.items[*].status.phase}'
assert "Network policies deployed" "default-deny" kubectl get networkpolicies --all-namespaces -o jsonpath='{range .items[*]}{.metadata.name}{" "}{end}'
assert "Pod Security enforced" "restricted" kubectl get ns default -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}'
check_condition "Kyverno policies ready" bash -c '[[ $(kubectl get clusterpolicy -o json | jq ".items | length") -gt 10 ]]'
assert "cert-manager ClusterIssuer ready" "True" kubectl get clusterissuer -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}'

echo ""
echo "--- Monitoring Validation ---"
assert "Prometheus running" "Running" kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[*].status.phase}'
assert "Grafana running" "Running" kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[*].status.phase}'
assert "Loki running" "Running" kubectl get pods -n monitoring -l app.kubernetes.io/name=loki -o jsonpath='{.items[*].status.phase}'
assert "Tempo running" "Running" kubectl get pods -n monitoring -l app.kubernetes.io/name=tempo -o jsonpath='{.items[*].status.phase}'
assert "Alertmanager running" "Running" kubectl get pods -n monitoring -l app.kubernetes.io/name=alertmanager -o jsonpath='{.items[*].status.phase}'

echo ""
echo "--- GitOps Validation ---"
if kubectl get namespace argocd &>/dev/null; then
    assert "ArgoCD server running" "Running" kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o jsonpath='{.items[*].status.phase}'
    assert "ArgoCD application controller running" "Running" kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-application-controller -o jsonpath='{.items[*].status.phase}'
    assert "ArgoCD repo server running" "Running" kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-repo-server -o jsonpath='{.items[*].status.phase}'
    check_condition "ArgoCD applications synced" bash -c '[[ $(kubectl get applications -n argocd -o json | jq "[.items[] | select(.status.sync.status != \"Synced\")] | length") -eq 0 ]]' 2>/dev/null || echo "  - No applications or can't check"
else
    echo "  - ArgoCD not installed (skipping GitOps tests)"
    ((SKIP++))
fi

echo ""
echo "--- Infrastructure Validation ---"
assert "NGINX Ingress running" "Running" kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller -o jsonpath='{.items[*].status.phase}'
assert "cert-manager running" "Running" kubectl get pods -n cert-manager -l app=cert-manager -o jsonpath='{.items[*].status.phase}'
assert "External Secrets running" "Running" kubectl get pods -n external-secrets -o jsonpath='{.items[*].status.phase}'
assert "Karpenter running" "Running" kubectl get pods -n karpenter -o jsonpath='{.items[*].status.phase}' 2>/dev/null || echo "  - Karpenter not installed"

echo ""
echo "--- AIOps Validation ---"
if kubectl get namespace aiops &>/dev/null; then
    assert "AIOps Engine running" "Running" kubectl get pods -n aiops -l app.kubernetes.io/name=aiops-engine -o jsonpath='{.items[*].status.phase}' 2>/dev/null || echo "  - AIOps engine labels may differ"
    assert "ChromaDB running" "Running" kubectl get pods -n aiops -l app.kubernetes.io/name=chromadb -o jsonpath='{.items[*].status.phase}' 2>/dev/null || echo "  - ChromaDB labels may differ"
else
    echo "  - AIOps not installed"
    ((SKIP++))
fi

echo ""
echo "--- Storage Validation ---"
assert_not "No pending PVCs" "Pending" kubectl get pvc -A --field-selector=status.phase!=Bound -o name 2>/dev/null || echo "  - No PVCs found"

echo ""
echo "------------------------------------------"
DURATION=$(( $(date +%s) - START_TIME ))

if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}  ALL ${PASS} TESTS PASSED${NC} (${DURATION}s)"
    echo "------------------------------------------"
    close_report
    exit 0
else
    echo -e "${RED}  ${PASS} passed, ${FAIL} failed, ${SKIP} skipped${NC} (${DURATION}s)"
    echo "------------------------------------------"
    close_report
    exit 1
fi
