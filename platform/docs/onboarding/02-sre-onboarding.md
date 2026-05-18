# SRE Onboarding Guide

Onboarding guide for new Site Reliability Engineers joining the platform team.

---

## Table of Contents

- [Platform Architecture Overview](#platform-architecture-overview)
- [Monitoring Stack Walkthrough](#monitoring-stack-walkthrough)
- [Alert Response Training](#alert-response-training)
- [Incident Response Drill](#incident-response-drill)
- [On-Call Rotation Setup](#on-call-rotation-setup)
- [PagerDuty Configuration](#pagerduty-configuration)
- [Runbook Familiarization](#runbook-familiarization)

---

## Platform Architecture Overview

### Week 1: Foundation

```markdown
## SRE Training Schedule

### Day 1-2: Platform Architecture
- [ ] Review high-level architecture diagram
- [ ] Read ARCHITECTURE.md
- [ ] Understand component interactions
- [ ] Tour all environments (dev, staging, prod)
- [ ] Review Terraform structure

### Day 3-4: Operational Tools
- [ ] Grafana dashboards tour
- [ ] Prometheus query language (PromQL)
- [ ] Loki log queries (LogQL)
- [ ] Tempo trace investigation
- [ ] kubectl power user skills

### Day 5: First On-Call Shadow
- [ ] Shadow primary SRE
- [ ] Review morning checklist
- [ ] Practice alert triage
- [ ] Review open incidents
- [ ] Perform handover
```

### Architecture Deep Dive

```bash
# Explore the platform
echo "=== Cluster Overview ==="
kubectl cluster-info
kubectl get nodes -o wide
kubectl get pods -A | wc -l

echo "=== Core Components ==="
kubectl get pods -n argocd
kubectl get pods -n monitoring
kubectl get pods -n kyverno
kubectl get pods -n falco
kubectl get pods -n ingress-nginx
kubectl get pods -n external-secrets
kubectl get pods -n cert-manager

echo "=== AIOps ==="
kubectl get pods -n aiops
curl -s http://aiops-engine.aiops:8000/health | jq .

echo "=== GitOps Status ==="
argocd app list
```

---

## Monitoring Stack Walkthrough

### Grafana Dashboards

| Dashboard | Location | Purpose |
|-----------|----------|---------|
| Platform Overview | Grafana → Dashboards → Platform | High-level platform health |
| Kubernetes Cluster | Grafana → Dashboards → K8s | Cluster-wide metrics |
| Node Exporter | Grafana → Dashboards → Nodes | Per-node metrics |
| Application Errors | Grafana → Dashboards → Apps | Application error rates |
| Security Overview | Grafana → Dashboards → Security | Security events dashboard |
| AIOps Engine | Grafana → Dashboards → AIOps | AIOps internal metrics |

### PromQL Practice

```promql
# Essential PromQL queries for SRE

# Node CPU utilization
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Pod CPU usage by namespace
sum(rate(container_cpu_usage_seconds_total{container!=""}[5m])) by (namespace)

# Memory usage by node
node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes

# Request error rate
sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))

# P99 latency
histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le, service))

# Pod restarts
sum(kube_pod_container_status_restarts_total) by (pod, namespace)

# Top CPU consumers
topk(10, sum(rate(container_cpu_usage_seconds_total{container!=""}[5m])) by (pod, namespace))
```

### LogQL Practice

```logql
# Essential LogQL queries for SRE

# Errors in namespace in last hour
{namespace="aiops"} |= "error" | logfmt

# Rate of errors by service
rate({namespace="aiops"} |= "error"[5m])

# Filter specific pod logs
{pod="aiops-engine-xxxxx"} |= "ERROR"

# JSON log parsing
{namespace="aiops"} | json | line_format "{{.message}}"

# Error count over time
count_over_time({namespace="aiops"} |= "error"[1h])
```

---

## Alert Response Training

### Alert Types and Initial Response

```bash
# Practice alert response scenarios

## Scenario 1: Pod CrashLoopBackOff
echo "Alert: Pod crashlooping in production"
kubectl describe pod <name> -n <namespace>
kubectl logs <name> -n <namespace> --previous
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

## Scenario 2: High Latency
echo "Alert: P99 latency > 500ms"
# Check Grafana dashboard
# Check recent deployments
# Check database query performance

## Scenario 3: Node Not Ready
echo "Alert: Node is NotReady"
kubectl describe node <node-name>
kubectl get pods -n kube-system -o wide | grep <node-name>
kubectl get events --field-selector involvedObject.kind=Node

## Scenario 4: Certificate Expiring
echo "Alert: TLS certificate expiring in 7 days"
kubectl get certificate -A -o json | jq -r '
  .items[] | select(.status.notAfter < now + 7*24*3600) |
  "\(.metadata.namespace)/\(.metadata.name): expires \(.status.notAfter)"
'
```

### Hands-On Alert Exercises

```bash
# Exercise 1: Trace an alert from PagerDuty to resolution
# 1. Acknowledge in PagerDuty
# 2. Find Grafana dashboard
# 3. Query Loki for related logs
# 4. Apply mitigation
# 5. Document in runbook

# Exercise 2: On-call handover
# 1. Review current incidents
# 2. Check cluster health
# 3. Document pending items
# 4. Transfer to next SRE

# Exercise 3: Incident commander role
# 1. Declare incident
# 2. Set up Slack channel
# 3. Assign roles
# 4. Communicate status
# 5. Coordinate response
# 6. Complete postmortem
```

---

## Incident Response Drill

### Drill Setup

```bash
#!/bin/bash
# drill-setup.sh - Prepare drill scenario

SCENARIO=$1

case $SCENARIO in
  pod-failure)
    kubectl run -n default drill-stress --image=nginx:alpine
    sleep 5
    kubectl delete pod drill-stress -n default --force --grace-period=0
    ;;
  high-cpu)
    kubectl run -n default drill-cpu --image=containerstack/alpine-stress \
      --resources='requests=cpu=500m,limits=cpu=1000m' \
      -- --cpu 4
    ;;
  network-delay)
    # Requires Chaos Mesh installed
    kubectl apply -f chaos/experiments/network-delay.yaml
    ;;
  *)
    echo "Unknown scenario: $SCENARIO"
    echo "Usage: $0 {pod-failure|high-cpu|network-delay}"
    exit 1
    ;;
esac
```

### Drill Evaluation

```markdown
## Drill Evaluation Criteria

### Timing
- Alert acknowledged within: 5 minutes (target)
- Severity assessed within: 2 minutes
- Mitigation started within: 10 minutes
- Incident resolved within: 30 minutes

### Communication
- Incident declared in #incidents channel
- Status updates every 30 minutes
- Stakeholders notified appropriately
- Postmortem completed within 48 hours

### Response Quality
- Correct runbook followed
- Appropriate escalation triggered
- Mitigation effective
- Root cause identified
- Action items documented
```

---

## On-Call Rotation Setup

### Configure Local Tools

```bash
# Install PagerDuty CLI
brew install pagerduty/tap/pd

# Configure API token
pd auth login

# Verify access
pd incident list --status=triggered,acknowledged --limit=5

# Test notification
pd incident create \
  --title "Test incident - SRE onboarding" \
  --urgency high \
  --service-id $SERVICE_ID
```

### Test On-Call Setup

```bash
# Verify PagerDuty escalation
pd on-call show --schedule-id $SCHEDULE_ID

# Check notification preferences
pd user show --me

# Test alert delivery
# Trigger a test alert in PagerDuty
pd incident create \
  --title "TEST: Do not respond - SRE onboarding verification" \
  --urgency low \
  --service-id $SERVICE_ID

# Verify you receive notification (email/SMS/push)
```

### Local Alert Simulation

```bash
#!/bin/bash
# simulate-alert.sh - Alert simulation tool

ALERT_TYPE=$1
SEVERITY=$2

echo "Simulating $SEVERITY alert: $ALERT_TYPE"

case $ALERT_TYPE in
  "high-cpu")
    kubectl run -n default cpu-stress --image=containerstack/alpine-stress \
      -- --cpu 4 &
    echo "CPU stress started. Alert should fire when CPU > 80%"
    sleep 30
    kubectl delete pod cpu-stress -n default --now
    ;;
  "high-error-rate")
    echo "Simulating 500 errors..."
    for i in {1..100}; do
      curl -s -o /dev/null http://aiops-engine.aiops:8000/nonexistent
    done
    ;;
  "pod-crash")
    kubectl run -n default crash-test --image=nginx:alpine \
      --command -- sh -c "exit 1"
    sleep 10
    kubectl delete pod crash-test -n default --now
    ;;
  *)
    echo "Usage: $0 {high-cpu|high-error-rate|pod-crash} {critical|warning|info}"
    ;;
esac
```

---

## PagerDuty Configuration

### Notification Rules

```yaml
# Recommended PagerDuty notification rules
notification_rules:
  high_urgency:
  - Push notification: Immediately
  - Phone call: After 1 minute
  - SMS: After 2 minutes
  - Email: After 5 minutes
  
  low_urgency:
  - Push notification: Immediately
  - Email: After 5 minutes
  - No phone or SMS
```

### Schedule Preferences

```yaml
schedule:
  primary:
    days: Monday-Friday
    hours: 8:00-20:00 (local time)
    type: fixed
    
  secondary:
    days: Monday-Sunday
    hours: 20:00-8:00
    type: fixed
    
  weekend:
    days: Saturday-Sunday
    hours: 8:00-20:00
    type: fixed
```

### Escalation Policies

```yaml
escalation_policies:
  sev1_escalation:
  - target: Primary SRE
    delay: 0 minutes
  - target: Secondary SRE
    delay: 5 minutes
  - target: Platform Team Lead
    delay: 10 minutes
  - target: Engineering Director
    delay: 15 minutes
    
  sev2_escalation:
  - target: Primary SRE
    delay: 0 minutes
  - target: Secondary SRE
    delay: 10 minutes
  - target: Platform Team Lead
    delay: 20 minutes
```

---

## Runbook Familiarization

### Required Reading

| Document | Priority | Estimated Time |
|----------|----------|---------------|
| [SRE Runbook](../operations/01-sre-runbook.md) | High | 2 hours |
| [Incident Response](../operations/02-incident-response.md) | High | 1 hour |
| [Disaster Recovery](../operations/03-disaster-recovery.md) | High | 1 hour |
| [Common Issues](../troubleshooting/01-common-issues.md) | Medium | 2 hours |
| [Escalation Matrix](../troubleshooting/02-escalation-matrix.md) | High | 30 min |
| [Security Overview](../security/01-security-overview.md) | Medium | 1 hour |
| [Cost Optimization](../operations/04-cost-optimization.md) | Low | 30 min |

### Runbook Walkthrough Exercise

```bash
# Exercise: Follow a runbook end-to-end

# 1. Pick a common issue from troubleshooting guide
# 2. Simulate the issue
# 3. Follow the diagnostic steps
# 4. Apply the resolution
# 5. Document the experience
# 6. Suggest improvements to the runbook

echo "Runbook walkthrough complete for: $RUNBOOK_PATH"
```

### Runbook Improvement Process

```markdown
## Runbook Improvement

When you find a gap in a runbook:
1. Document the gap in GitHub Issues
2. Create a PR with the fix
3. Have another SRE review
4. Merge and notify the team

Runbook Quality Checklist:
- [ ] Accurate and up-to-date
- [ ] Commands work as documented
- [ ] Expected outputs match
- [ } Covers edge cases
- [ ] Clear and actionable steps
- [ ] Includes links to relevant resources
```

---

## Next Steps

1. [Review developer onboarding guide](01-developer-onboarding.md)
2. [Review architecture overview](../architecture/ARCHITECTURE.md)
3. [Begin shadowing on-call SRE rotation]
