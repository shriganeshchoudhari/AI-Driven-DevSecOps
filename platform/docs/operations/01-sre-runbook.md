# SRE Operational Handbook

Complete operations guide for Site Reliability Engineers managing the AI-Driven Secure GitOps Platform.

---

## Table of Contents

- [On-Call Responsibilities](#on-call-responsibilities)
- [Alert Triage Process](#alert-triage-process)
- [Key Metrics & SLOs](#key-metrics--slos)
- [Daily Operations](#daily-operations)
- [Weekly Operations](#weekly-operations)
- [Monthly Operations](#monthly-operations)
- [Maintenance Windows](#maintenance-windows)
- [Runbook Index](#runbook-index)
- [SLA Definitions](#sla-definitions)
- [Escalation Matrix](#escalation-matrix)

---

## On-Call Responsibilities

### Rotation Schedule

| Role | Hours | Responsibilities |
|------|-------|-----------------|
| **Primary SRE** | 8am - 8pm (12h) | First responder, alert triage, incident management |
| **Secondary SRE** | 8pm - 8am (12h) | Night coverage, backup for primary |
| **Shadow SRE** | Business hours | Training, runbook maintenance, non-critical tasks |
| **Escalation Lead** | 24/7 on-call | SEV1 escalation, cross-team coordination |

### On-Call Handover Process

```bash
# 1. Review open incidents
# 2. Check PagerDuty for acknowledged alerts
# 3. Review overnight changes
# 4. Verify cluster health
# 5. Document in Slack #sre-handover
```

Handover template:
```
## SRE Handover - {Date}

**Outgoing**: @engineer1
**Incoming**: @engineer2

### Active Incidents
- INC-001: {summary} - {status}
- INC-002: {summary} - {status}

### Pending Changes
- PR #123: {description} - scheduled for {time}
- PR #124: {description} - requires approval

### Cluster Status
- Nodes: {healthy}/{total}
- Pods: {running}/{total}
- Alerts: {critical}/{warning}

### Notes
- {anything noteworthy}

### Next Actions
- [ ] {action}
- [ ] {action}
```

### Escalation Paths

| If | Then |
|----|------|
| Alert not acknowledged in 5 min | Secondary SRE is paged |
| SEV1 declared | Engineering Director notified |
| Issue spans > 30 min without progress | Incident Commander activated |
| Security incident suspected | Security team paged immediately |
| AWS infrastructure issue | AWS Support case opened (SEV1) |

---

## Alert Triage Process

### Alert Flow

```
Alert Fires
    │
    ▼
Acknowledge (≤5 min)
    │
    ▼
Assess Severity
    │
    ├── SEV1 ──► Declare Incident ──► Incident Commander ──► Mitigation
    │
    ├── SEV2 ──► Investigate ──► Fix or Escalate
    │
    ├── SEV3 ──► Create Ticket ──► Fix during business hours
    │
    └── SEV4 ──► Log for later review
```

### Triage Checklist

```bash
# 1. Check the alert details
# 2. Open Grafana dashboard for context
# 3. Check related logs in Loki
# 4. Check recent deployments/changes
# 5. Determine if this is a known issue
# 6. Decide on immediate action
```

### Investigation Commands

```bash
# Quick cluster health
kubectl get nodes -o wide
kubectl get pods -A | grep -v Running | grep -v Completed
kubectl top nodes
kubectl top pods -A

# Check recent events
kubectl get events -A --sort-by='.lastTimestamp' | tail -30

# Check ArgoCD status
argocd app list -o json | jq '.[] | select(.status.health.status != "Healthy") | .metadata.name'

# Check recent changes
git log --oneline -10 --decorate

# Check recent deployments
kubectl rollout history deployment -A

# AIOps analysis
curl -s http://aiops-engine.aiops:8000/api/v1/analyze \
  -H "Content-Type: application/json" \
  -d '{"query": "What is the current state of the cluster?"}' | jq .
```

### Alert Acknowledgement

```bash
# PagerDuty
pagerduty acknowledge --incident-id INC-001

# Via Slack
/inc acknowledge INC-001

# Via CLI
curl -X POST https://api.pagerduty.com/incidents/INC-001/acknowledge \
  -H "Authorization: Token token=PD_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"requester_id": "USER_ID"}'
```

---

## Key Metrics & SLOs

### Service Level Objectives

| Metric | SLO Target | Measurement | Window | Severity if Breached |
|--------|-----------|-------------|--------|----------------------|
| **Availability** | ≥ 99.95% | Uptime of critical services | Monthly | SEV1 |
| **Latency P99** | ≤ 500ms | API response times | Rolling 5m | SEV2 |
| **Error Rate** | ≤ 0.1% | HTTP 5xx / total requests | Rolling 5m | SEV1 |
| **Deployment Frequency** | ≥ 5/week | Successful deployments | Weekly | Process |
| **MTTR** | ≤ 60 min | Time to resolve incidents | Rolling 30d | SEV1 |
| **Change Failure Rate** | ≤ 5% | Failed / total deployments | Monthly | Process |
| **Pod Startup Time** | ≤ 30s | Pod ready / pod created | Rolling 1h | SEV3 |
| **Cluster Node Ready** | 100% | Nodes in Ready state | Real-time | SEV2 |
| **Certificate Expiry** | ≥ 30d | Days until cert expiration | Daily | SEV3 |
| **Backup Success** | 100% | Backup completion | Daily | SEV2 |

### Error Budget Calculation

```bash
# Monthly error budget at 99.95% availability
TOTAL_MINUTES=43200  # 30 days
ALLOWED_DOWNTIME=21.6 minutes  # 43200 * 0.0005

# Current consumption
CURRENT_DOWNTIME=$(prometheus query 'sum(increase(probe_success{job="platform"}[30d]))')
REMAINING_BUDGET=$((ALLOWED_DOWNTIME - CURRENT_DOWNTIME))
```

### SLI Collection

| SLI | Source | PromQL Query |
|-----|--------|-------------|
| Request Rate | Istio metrics | `sum(rate(istio_requests_total{destination_service=~"platform.*"}[5m]))` |
| Error Rate | Istio metrics | `sum(rate(istio_requests_total{destination_service=~"platform.*", response_code=~"5.*"}[5m])) / sum(rate(istio_requests_total{destination_service=~"platform.*"}[5m]))` |
| Latency P50 | Istio metrics | `histogram_quantile(0.50, sum(rate(istio_request_duration_milliseconds_bucket{destination_service=~"platform.*"}[5m])) by (le, destination_service))` |
| Latency P99 | Istio metrics | `histogram_quantile(0.99, sum(rate(istio_request_duration_milliseconds_bucket{destination_service=~"platform.*"}[5m])) by (le, destination_service))` |
| Availability | Blackbox exporter | `probe_success{job="platform-endpoints"}` |
| Pod Restarts | kube-state-metrics | `sum(kube_pod_container_status_restarts_total) by (namespace, pod)` |

---

## Daily Operations

### Morning Checklist

```bash
#!/bin/bash
# morning-check.sh - Run at start of shift

echo "=== Morning Platform Check ==="
echo "Date: $(date)"
echo ""

# 1. Review overnight alerts
echo "1. Overnight Alerts:"
curl -s "http://alertmanager:9093/api/v2/alerts" | jq '. | length'
echo ""

# 2. Check cluster capacity
echo "2. Cluster Capacity:"
kubectl top nodes --no-headers | awk '{print $1, $2, $3}'
echo ""

# 3. Check pending pods
echo "3. Pending Pods:"
kubectl get pods -A --field-selector=status.phase=Pending -o wide
echo ""

# 4. Check node conditions
echo "4. Node Conditions:"
kubectl get nodes -o json | jq -r '
  .items[] | select(.spec.unschedulable == true or (.status.conditions[] | select(.type == "Ready" and .status != "True"))) |
  .metadata.name
'
echo ""

# 5. Check recent deployments
echo "5. Recent Deployments (last 24h):"
kubectl rollout history deployment -A --revision=1 2>/dev/null | tail -20
echo ""

# 6. Check certificate expiry
echo "6. Certificate Expiry:"
kubectl get certificate -A -o json | jq -r '
  .items[] | "\(.metadata.namespace)/\(.metadata.name): expires \(.status.notAfter)"
' | sort -k3
echo ""

# 7. Verify backup status
echo "7. Last Backup:"
velero get backup --output json | jq -r '
  .items | sort_by(.metadata.creationTimestamp) | last |
  "Last backup: \(.metadata.creationTimestamp) - Status: \(.status.phase)"
'
echo ""

# 8. Check cost anomalies (if available)
echo "8. Daily Cost:"
aws ce get-cost-and-usage \
  --time-period Start=$(date -d "-1 day" +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity DAILY \
  --metrics "UnblendedCost" \
  --query "ResultsByTime[0].Total.UnblendedCost.Amount" \
  --output text

echo ""
echo "=== Morning Check Complete ==="
```

### Daily Operations Checklist

```
□ Review and acknowledge all alerts from the past 12 hours
□ Check cluster utilization (CPU, Memory, Storage)
□ Review pending pods and PVCs
□ Verify all ArgoCD apps are Synced and Healthy
□ Review recent deployments for failures
□ Check certificate expiry dates
□ Verify backup completion
□ Review cost anomalies
□ Check open incident tickets
□ Update Slack #platform-status
□ Review and approve pending change requests
□ Check security scan reports (Trivy)
□ Verify AIOps engine health
```

### Shift Handover Checklist

```
□ Document open incidents and their status
□ Note any ongoing mitigation efforts
□ List pending changes scheduled for next shift
□ Summarize cluster health
□ Flag any concerning trends
□ Transfer PagerDuty notifications
□ Update on-call documentation
```

---

## Weekly Operations

### Weekly Review

```bash
# 1. Capacity planning review
echo "=== Weekly Capacity Review ==="
echo "CPU Utilization (7d avg):"
# Query Prometheus for weekly averages

echo "Memory Utilization (7d avg):"
# Query Prometheus

echo "Node count changes:"
kubectl get nodes -o wide

# 2. Security review
echo "=== Security Review ==="
echo "Recent policy violations:"
kubectl get policyreport -A | grep -v "pass"

echo "Vulnerability scan summary:"
trivy image --severity CRITICAL,HIGH \
  --exit-code 0 \
  --ignore-unfixed \
  123456789012.dkr.ecr.us-west-2.amazonaws.com/platform/aiops-engine:latest \
  2>/dev/null | tail -20

# 3. Cost review
echo "=== Cost Review ==="
aws ce get-cost-and-usage \
  --time-period Start=$(date -d "-7 days" +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity DAILY \
  --metrics "UnblendedCost" \
  --group-by Type=DIMENSION,Key=SERVICE
```

### Weekly Checklist

```
□ Review and update runbooks
□ Perform capacity planning review
□ Review security vulnerabilities and patch status
□ Review cost report and budget alerts
□ Test backup restoration in dev environment
□ Review and update on-call schedule
□ Review incident trends
□ Update knowledge base
□ Perform chaos experiment in dev environment
□ Update AIOps model with recent incident data
```

---

## Monthly Operations

### Monthly Review

```bash
# 1. SLO compliance
echo "=== Monthly SLO Review ==="
echo "Availability:"
# Prometheus query for monthly uptime

echo "Error budget consumed:"
# Prometheus query

# 2. Incident analysis
echo "=== Incident Analysis ==="
# Count incidents by severity
echo "Incidents this month: SEV1: X, SEV2: X, SEV3: X, SEV4: X"
echo "Average MTTR: X minutes"
echo "Top incident types: [list]"

# 3. Performance review
echo "=== Performance Review ==="
echo "P99 Latency trend: [improving/stable/degrading]"
echo "P50 Latency trend: [improving/stable/degrading]"

# 4. Postmortem status
echo "=== Postmortem Status ==="
echo "Open action items: X"
echo "Overdue action items: X"
```

### Monthly Checklist

```
□ Review and report SLO compliance to stakeholders
□ Complete incident postmortems for all SEV1/SEV2
□ Perform disaster recovery drill
□ Update disaster recovery plan
□ Review and rotate credentials
□ Complete SOX/compliance controls testing
□ Review and update all documentation
□ Conduct platform team training session
□ Perform chaos engineering experiment
□ Review and tune alerting thresholds
□ Review and update cost budget forecasts
□ Update on-call rotation schedule
```

---

## Maintenance Windows

### Standard Maintenance Windows

| Environment | Schedule | Scope |
|-------------|----------|-------|
| Development | Mon-Fri, 8am-6pm | Any changes, no approval needed |
| Staging | Tues/Thurs, 10am-2pm | Platform upgrades, breaking changes |
| Production | Tues/Thurs, 10am-2pm | Non-breaking changes only |
| Emergency | As needed | Requires VP Engineering approval |

### Maintenance Window Procedure

```bash
# 1. Announce maintenance window
echo "Starting maintenance window for ${ENVIRONMENT} at $(date)"

# 2. Update status page
# POST to status page API

# 3. Disable auto-remediation if needed
kubectl annotate application -n argocd --all \
  argocd.argoproj.io/sync-wave=1000 --overwrite

# 4. Perform maintenance
# ...

# 5. Verify system health
./scripts/validation.sh

# 6. Re-enable auto-remediation
kubectl annotate application -n argocd --all \
  argocd.argoproj.io/sync-wave- --overwrite

# 7. End maintenance window
echo "Completed maintenance window at $(date)"
```

### Maintenance Blackout Periods

| Period | Dates | Reason |
|--------|-------|--------|
| End of Quarter | Last week of quarter | Financial reporting |
| Major Holidays | Dec 20 - Jan 5 | Reduced staffing |
| Product Launch | 24 hours pre/post | Stability priority |
| Audit Period | During external audits | Change freeze |

### Change Freeze Procedure

```bash
# During change freeze:
# 1. All changes require Change Advisory Board (CAB) approval
# 2. Emergency changes require VP Engineering sign-off
# 3. Only critical security patches or outage fixes permitted
# 4. All changes must have rollback plan documented
```

---

## Runbook Index

### Infrastructure Runbooks

| Runbook | Description | Severity | Response Time |
|---------|-------------|----------|---------------|
| [Node Not Ready](../troubleshooting/01-common-issues.md#node-not-ready) | Kubernetes node goes NotReady | SEV2 | 15 min |
| [EKS API Unreachable](../troubleshooting/01-common-issues.md#eks-api) | EKS control plane unavailable | SEV1 | 5 min |
| [Karpenter Provisioning Failure](../troubleshooting/01-common-issues.md#karpenter-failure) | Nodes not provisioning | SEV2 | 15 min |
| [PVC Stuck Pending](../troubleshooting/01-common-issues.md#pvc-pending) | Storage volume not provisioning | SEV3 | 60 min |
| [RDS Connection Failure](../troubleshooting/01-common-issues.md#rds-failure) | Database unreachable | SEV1 | 5 min |

### Security Runbooks

| Runbook | Description | Severity | Response Time |
|---------|-------------|----------|---------------|
| [Falco Critical Alert] | Malicious process detected | SEV1 | Immediate |
| [Kyverno Policy Violation] | Policy enforcement failure | SEV2 | 15 min |
| [Secret Rotation Failed] | Secrets not rotating | SEV2 | 30 min |
| [Image Vulnerability Critical] | Critical CVE in running image | SEV1 | Immediate |
| [Unauthorized Access Detected] | RBAC violation | SEV1 | Immediate |

### Application Runbooks

| Runbook | Description | Severity | Response Time |
|---------|-------------|----------|---------------|
| [AIOps Down](../troubleshooting/01-common-issues.md#aiops-down) | AIOps Engine unavailable | SEV2 | 15 min |
| [High Error Rate](../troubleshooting/01-common-issues.md#high-error-rate) | >0.1% 5xx errors | SEV1 | 5 min |
| [High Latency](../troubleshooting/01-common-issues.md#high-latency) | P99 > 500ms | SEV2 | 15 min |
| [ArgoCD Sync Failure](../troubleshooting/01-common-issues.md#argocd-sync-failure) | Application sync stuck | SEV3 | 60 min |
| [Deployment Rollback] | Automated rollback triggered | SEV2 | 15 min |

### Monitoring Runbooks

| Runbook | Description | Severity | Response Time |
|---------|-------------|----------|---------------|
| [Prometheus Down] | Metrics collection stopped | SEV2 | 15 min |
| [Grafana Unavailable] | Dashboard access lost | SEV3 | 60 min |
| [Loki Ingestion Lag] | Logs not being indexed | SEV2 | 30 min |
| [Alertmanager Not Sending] | Notifications failing | SEV2 | 15 min |

### Chaos Runbooks

| Runbook | Description | Severity |
|---------|-------------|----------|
| [Pod Failure Unexpected] | Pods failing outside chaos experiment | SEV1 |
| [Network Partition] | Unexpected network issues | SEV1 |
| [DNS Resolution Failure] | Service discovery failing | SEV1 |
| [Self-Healing Not Working] | Auto-remediation not triggering | SEV2 |

---

## SLA Definitions

### Response Times by Severity

| Severity | Initial Response | Status Updates | Resolution Target | Escalation |
|----------|-----------------|----------------|-------------------|------------|
| **SEV1** | ≤ 5 minutes | Every 30 minutes | ≤ 4 hours | SRE → Director |
| **SEV2** | ≤ 15 minutes | Every 60 minutes | ≤ 8 hours | SRE → Team Lead |
| **SEV3** | ≤ 60 minutes | Every 24 hours | ≤ 5 business days | Engineering Team |
| **SEV4** | ≤ 24 hours | Per request | Next release | Regular channels |

### SLA Exclusions

The following are excluded from SLA calculations:
- Scheduled maintenance windows
- Third-party service dependencies
- Force majeure events
- Customer-initiated changes
- Previously disclosed limitations

### Service Credits

| Availability | Credit |
|-------------|--------|
| < 99.95% but ≥ 99.0% | 10% monthly credit |
| < 99.0% | 25% monthly credit |
| < 95.0% | 50% monthly credit |

---

## Escalation Matrix

### Level 1: On-Call SRE

| Role | Contact | Response Time |
|------|---------|---------------|
| Primary SRE | PagerDuty: `platform-primary` | ≤ 5 min |
| Secondary SRE | PagerDuty: `platform-secondary` | ≤ 10 min |
| Shadow SRE | Slack: @sre-shadow | Business hours |

### Level 2: Platform Engineering Team

| Role | Contact | Response Time |
|------|---------|---------------|
| Team Lead | Email: lead@example.com, Phone: +1-555-0100 | ≤ 30 min |
| Senior Engineer | Email: senior@example.com, Phone: +1-555-0101 | ≤ 1 hour |
| Infrastructure Lead | Email: infra-lead@example.com | ≤ 1 hour |

### Level 3: Security Team

| Role | Contact | Response Time |
|------|---------|---------------|
| Security Lead | Email: security@example.com, PagerDuty: `security` | ≤ 15 min |
| Compliance Officer | Email: compliance@example.com | ≤ 1 hour |
| AppSec Engineer | Email: appsec@example.com | Business hours |

### Level 4: External Support

| Vendor | Contact | SLA | Account |
|--------|---------|-----|---------|
| AWS Support (Enterprise) | AWS Console → Support → Create Case | 15 min (SEV1) | Account: 123456789012 |
| Grafana Labs | support@grafana.com | 4 hours | Contract: PLATFORM-2026 |
| Datadog | support@datadog.com | 4 hours | Contract: DD-2026 |
| PagerDuty | support@pagerduty.com | 4 hours | Contract: PD-2026 |
| HashiCorp | portal.hashicorp.com | 4 hours | TFE - Enterprise |

### Communication Channels

| Channel | Purpose | Escalation Path |
|---------|---------|----------------|
| Slack: #platform-alerts | Automated alerts | Auto-posted |
| Slack: #platform-incidents | Incident coordination | All levels |
| Slack: #platform-ops | Operational discussion | L1-L2 |
| Email: platform-ops@example.com | Non-urgent issues | L2-L3 |
| PagerDuty | Urgent notifications | L1 immediate |
| Phone Bridge | Crisis coordination | SEV1 only |

### Escalation Script

```bash
# escalation.sh - Automated escalation notification
#!/bin/bash

SEVERITY=$1
INCIDENT_ID=$2
MESSAGE=$3

notify_slack() {
  curl -X POST -H "Content-Type: application/json" \
    -d "{\"channel\":\"#platform-incidents\",\"text\":\"*[${SEVERITY}]* ${INCIDENT_ID}: ${MESSAGE}\"}" \
    "$SLACK_WEBHOOK_URL"
}

create_pagerduty_incident() {
  curl -X POST -H "Authorization: Token token=$PD_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"incident\":{\"type\":\"incident\",\"title\":\"${INCIDENT_ID}: ${MESSAGE}\",\"service\":{\"id\":\"$PD_SERVICE_ID\",\"type\":\"service_reference\"},\"urgency\":\"high\"}}" \
    "https://api.pagerduty.com/incidents"
}

trigger_bridge() {
  # Start Twilio/Zoom bridge
  echo "Starting conference bridge..."
}

case $SEVERITY in
  SEV1)
    notify_slack
    create_pagerduty_incident
    trigger_bridge
    ;;
  SEV2)
    notify_slack
    create_pagerduty_incident
    ;;
  SEV3)
    notify_slack
    ;;
  *)
    echo "Unknown severity: $SEVERITY"
    ;;
esac
```

---

## Change Management

### Change Types

| Type | Approval | Risk | Window |
|------|----------|------|--------|
| Standard | Pre-approved | Low | Any time |
| Normal | Team Lead | Medium | Maintenance window |
| Emergency | VP Engineering | High | Any time (post-review) |
| Major | CAB | High | Planned release |

### Change Request Template

```markdown
## Change Request

**Request ID**: CHG-XXXXX
**Requester**: @engineer
**Date**: 2026-05-17

### Change Description
Brief description of what is changing and why.

### Risk Assessment
- **Risk Level**: Low / Medium / High
- **Impact**: Brief description of potential impact
- **Rollback Plan**: Steps to roll back if needed

### Implementation Plan
1. Pre-change validation
2. Change steps
3. Post-change validation

### Verification
- [ ] Unit tests pass
- [ ] Integration tests pass
- [ ] Smoke tests pass
- [ ] Monitoring confirms health

### Approval
- [ ] Team Lead: {name} {date}
- [ ] (if major) CAB: {name} {date}
```

---

## Next Steps

1. [Review incident response procedures](02-incident-response.md)
2. [Review disaster recovery plan](03-disaster-recovery.md)
3. [Review cost optimization strategies](04-cost-optimization.md)
