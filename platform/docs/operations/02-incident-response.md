# Incident Response Procedure

Standardized incident response process for all severities, from alert to postmortem.

---

## Table of Contents

- [Severity Definitions](#severity-definitions)
- [Incident Lifecycle](#incident-lifecycle)
- [Incident Command Structure](#incident-command-structure)
- [Communication Templates](#communication-templates)
- [Postmortem Template](#postmortem-template)
- [Training & Drills](#training--drills)

---

## Severity Definitions

| Severity | Definition | Response Time | Escalation | Examples |
|----------|-----------|---------------|------------|----------|
| **SEV1** | Complete service outage, data loss, or security breach impacting all users | ≤ 5 min | SRE + Engineering Director | Cluster down, database inaccessible, active security incident |
| **SEV2** | Partial outage, significant degradation, or feature unavailability | ≤ 15 min | SRE + Team Lead | High error rate (>1%), high latency, some users affected |
| **SEV3** | Minor issue, cosmetic defect, or non-critical degradation | ≤ 60 min | Engineering team | Single pod crashlooping, minor performance issue |
| **SEV4** | General question, feature request, or informational alert | ≤ 24 h | Regular channels | Documentation update, monitoring tuning |

### Severity Decision Matrix

```
                    User Impact?
                    │
        ┌───────────┼───────────┐
        ▼           ▼           ▼
    All Users    Some Users   No Users
        │           │           │
        ▼           ▼           ▼
    SEV1 ───► Is data at risk? ───► SEV3/SEV4
                    │
            ┌───────┴───────┐
            ▼               ▼
          Yes              No
           │               │
           ▼               ▼
         SEV1             SEV2
```

---

## Incident Lifecycle

```
Detection ──► Triage ──► Mitigation ──► Resolution ──► Monitoring ──► Postmortem
    │            │            │              │              │              │
    ▼            ▼            ▼              ▼              ▼              ▼
  Alert       Assess      Immediate       Permanent      Verify        Document
  fires       severity    fix             fix            48h           within 48h
```

### Phase 1: Detection

Incidents are detected through:
1. **Automated alerts** from Prometheus/Alertmanager → PagerDuty
2. **User reports** via #platform-support Slack channel
3. **Monitoring dashboards** reviewed during shifts
4. **Automated health checks** (synthetic monitoring)
5. **Falco security alerts** for runtime anomalies
6. **AIOps predictive alerts** for early warning

### Phase 2: Triage (≤ 5 min)

```bash
# 1. Acknowledge the alert
# PagerDuty
pagerduty acknowledge --incident-id INC-XXXXX

# Slack
/inc acknowledge INC-XXXXX

# 2. Assess severity using decision matrix
# 3. Declare incident if SEV1 or SEV2
/inc declare SEV1 "Production API is down"
```

**Triage Questions:**
- Is this impacting users?
- Is this a security issue?
- Is there data loss or risk of data loss?
- Can this wait until business hours?
- Do we need to escalate?

### Phase 3: Mitigation

**Primary goal**: Restore service or contain damage. Not to fix the root cause.

```bash
# Common mitigation actions:

# 1. Rollback recent deployment
argocd app rollback <app-name> 1

# 2. Scale up to handle load
kubectl scale deployment <name> -n <ns> --replicas=10

# 3. Restart failing service
kubectl rollout restart deployment <name> -n <ns>

# 4. Failover to DR (if needed)
./scripts/dr-failover.sh

# 5. Block malicious traffic (if security incident)
aws wafv2 update-web-acl --name platform-prod --scope REGIONAL \
  --rules '[{"name":"emergency-block","priority":0,"action":{"block":{}},"statement":{"ip-set":{"arn":"arn:aws:wafv2:...:ipset/blocked"}},"visibilityConfig":{...}}]'

# 6. Enable maintenance mode (if applicable)
kubectl annotate ingress platform-ingress \
  nginx.ingress.kubernetes.io/server-snippet="if ($http_user_agent !~ MaintenanceBot) { return 503; }"
```

### Phase 4: Resolution

**Primary goal**: Apply permanent fix to prevent recurrence.

```bash
# 1. Identify root cause
# 2. Develop fix
# 3. Test fix in dev/staging
# 4. Submit PR for review
# 5. Deploy to production via ArgoCD
git commit -m "fix: resolve database connection pool exhaustion"
git push origin main

# Verify ArgoCD sync
argocd app sync <app-name>
argocd app wait <app-name> --health
```

### Phase 5: Monitoring

**Duration**: Continue monitoring for at least 30 minutes (SEV1) or 15 minutes (SEV2).

```bash
# Monitor for stability:
kubectl get pods -A -w &
POD_WATCH_PID=$!

# Watch error rates
watch -n 10 'curl -s http://alertmanager:9093/api/v2/alerts | jq ". | length"'

# Monitor AIOps for anomaly detection
curl -s http://aiops-engine.aiops:8000/api/v1/health | jq .

# After monitoring period
kill $POD_WATCH_PID
```

### Phase 6: Postmortem

**Primary goal**: Learn and improve. Complete within 48 hours for SEV1/SEV2.

---

## Incident Command Structure

### Role Definitions

| Role | Responsibility | Assigned To |
|------|---------------|-------------|
| **Incident Commander (IC)** | Overall coordination, decision making, stakeholder communication | Senior SRE |
| **Deputy IC** | Supports IC, manages timeline and documentation | SRE |
| **Operations Lead** | Technical mitigation, executing runbooks | Operations Engineer |
| **Communications Lead** | Status updates, stakeholder communication | PM/EM |
| **Scribe** | Real-time documentation of timeline and actions | Designated engineer |
| **SME (as needed)** | Subject matter expertise for specific components | Various |

### Command Structure

```
                    Incident Commander
                    │
        ┌───────────┼───────────┐
        ▼           ▼           ▼
    Operations   Communic-    Scribe
    Lead         ations
                    Lead
        │
    ┌───┼───┐
    ▼   ▼   ▼
   SME  SME  SME
```

### Role Handoff

```bash
# Handoff incident command
/inc command @engineer2

# Or via API
curl -X POST https://api.pagerduty.com/incidents/INC-XXXXX/handoff \
  -H "Authorization: Token token=$PD_TOKEN" \
  -d '{"from": "user_id_1", "to": "user_id_2"}'
```

### Incident Commander Duties

```
□ Acknowledge within 5 minutes
□ Assess severity and declare incident
□ Assign roles (Ops Lead, Comms Lead, Scribe)
□ Set up incident channel #inc-YYYY-MM-DD-XX
□ Establish communication cadence (every 30 min)
□ Make go/no-go decisions
□ Coordinate mitigation efforts
□ Call for escalation when needed
□ Declare incident resolved
□ Approve postmortem schedule
□ Ensure postmortem completed within 48h
```

---

## Communication Templates

### Incident Declaration

```markdown
:rotating_light: *INCIDENT DECLARED* :rotating_light:

**Incident ID**: INC-{date}-{seq}
**Severity**: SEV1 / SEV2
**Status**: Investigating / Mitigating / Resolved / Monitoring
**Detected**: {time} UTC
**Services Affected**: {service names}
**Impact**: {description of user impact}
**Lead**: @engineer

**Summary**:
Brief description of what's happening.

**Current Actions**:
- Investigating root cause
- Applying mitigation: {action}

**Next Update**: {time} UTC

:rotating_light:
```

### Status Update (Every 30 min)

```markdown
*STATUS UPDATE #{n}*

**Incident**: INC-{date}-{seq}
**Status**: Investigating / Mitigating / Monitoring
**Time**: {time} UTC

**What we know**:
- {bullet point findings}

**What we're doing**:
- {bullet point actions}

**What we need**:
- {escalation needs}

**Next Update**: {time} UTC
```

### Incident Resolved

```markdown
:white_check_mark: *INCIDENT RESOLVED* :white_check_mark:

**Incident**: INC-{date}-{seq}
**Duration**: {duration}
**Root Cause**: {brief description}
**Resolution**: {what was done to fix}

**Metrics**:
- Time to acknowledge: {X} min
- Time to mitigate: {X} min
- Time to resolve: {X} min
- User impact: {description}

**Postmortem**: Scheduled for {date} at {time} UTC
**Action Items**: Will be tracked in postmortem

Thank you to all responders: @engineer1 @engineer2 @engineer3
```

### Customer-Facing Status Update

```
Service Status Update - {date}

We are currently experiencing {issue description}. Our engineering team has 
identified the root cause as {cause} and is actively working on {mitigation}.

Expected impact: {description}
Estimated resolution: {time}

We apologize for the inconvenience and will provide another update within 
30 minutes.
```

---

## Postmortem Template

```markdown
# Incident Postmortem

## Metadata
- **Incident ID**: INC-{date}-{seq}
- **Date**: {date}
- **Duration**: {start} → {end} ({duration})
- **Severity**: SEV1 / SEV2
- **Incident Commander**: @engineer
- **Responders**: @engineer1, @engineer2, @engineer3
- **Postmortem Facilitator**: @manager

## Executive Summary
One-paragraph summary of the incident, impact, and outcome.

## Timeline

| Time (UTC) | Event |
|------------|-------|
| 10:00 | Deploy of v1.2.3 to production |
| 10:05 | Alert: error rate spike > 5% |
| 10:06 | Alert acknowledged by @primary |
| 10:08 | SEV1 declared by @primary |
| 10:10 | Incident Commander assigned: @ic |
| 10:12 | Rollback started to v1.2.2 |
| 10:15 | Rollback completed |
| 10:16 | Error rate returning to normal |
| 10:20 | Monitoring phase started |
| 10:45 | Incident declared resolved |
| 11:00 | Customer-facing status updated |

## Impact
- **Users Affected**: ~500 concurrent users
- **Services Degraded**: API gateway, user authentication
- **Data Loss**: None
- **Duration of Impact**: 15 minutes (10:05 - 10:20)
- **Error Count**: ~2,500 failed requests (0.5% of total)

## Detection
- **How detected**: Prometheus alert `HighErrorRate` fired
- **Time to detect**: 5 minutes (automated)
- **Time to acknowledge**: 1 minute
- **Mean Time to Detect (MTTD)**: 5 minutes

## Response
- **Mean Time to Acknowledge (MTTA)**: 1 minute
- **Mean Time to Mitigate (MTTM)**: 12 minutes
- **Mean Time to Resolve (MTTR)**: 35 minutes
- **What went well**: Rapid rollback, clear communication
- **What went wrong**: Missing canary deployment for this service

## Root Cause Analysis

### 5 Whys
1. Why did error rate spike? → New deployment introduced breaking API change
2. Why was breaking change deployed? → Not caught in code review
3. Why wasn't it caught? → Missing integration test for this endpoint
4. Why was there no canary? → Service not yet migrated to Argo Rollouts
5. Why wasn't migration prioritized? → Backlog item not prioritized

### Root Cause
The deployment of v1.2.3 changed the authentication endpoint response format 
from JSON to XML without updating downstream consumers. This was not caught 
because the service has not yet been migrated to Argo Rollouts for canary 
deployments, and integration tests did not cover this specific endpoint.

## Action Items

| # | Action Item | Owner | Due Date | Status |
|---|-------------|-------|----------|--------|
| 1 | Migrate auth service to Argo Rollouts | @platform-team | 2026-06-01 | Open |
| 2 | Add integration test for auth endpoint | @qa-team | 2026-05-25 | Open |
| 3 | Add API contract testing to CI/CD | @platform-team | 2026-05-30 | Open |
| 4 | Run postmortem review with all stakeholders | @manager | 2026-05-20 | Open |
| 5 | Update deployment checklist for API changes | @platform-team | 2026-05-22 | Open |
| 6 | Write runbook for auth service rollback | @sre-team | 2026-05-25 | Open |

## Lessons Learned

### What Went Well
- Alert fired within 5 minutes of deployment
- SRE team acknowledged and responded within 1 minute
- Rollback was executed quickly
- Clear communication throughout incident

### What Went Wrong
- Missing integration test coverage for this endpoint
- Service not using progressive delivery (canary)
- No API contract validation in CI pipeline

### What Can Be Improved
- Implement canary deployments for all services
- Add contract testing to CI/CD pipeline
- Increase integration test coverage
- Create service maturity model for progressive delivery adoption

## Appendix
- Related chat logs (Slack #inc-YYYY-MM-DD-XX)
- Related dashboards (Grafana link)
- Related commits (PR #1234)
- Monitoring data (Prometheus query results)

---

## Postmortem Approval

- **Incident Commander**: {name} {date}
- **Engineering Director**: {name} {date}
- **VP Engineering**: {name} {date}
```

---

## Training & Drills

### Game Day Schedule

| Drill Type | Frequency | Description |
|------------|-----------|-------------|
| Tabletop | Monthly | Walk through incident scenario |
| Chaos Experiment | Weekly | Automated chaos in dev environment |
| Full DR Drill | Quarterly | Complete disaster recovery exercise |
| Security Drill | Monthly | Simulated security incident |
| On-Call Training | Per rotation | SRE onboarding drill |

### Tabletop Exercise Template

```markdown
# Tabletop Exercise: {Scenario Name}

## Scenario
Brief description of the incident scenario.

## Participants
- Facilitator:
- IC:
- Operations Lead:
- Comms Lead:
- Scribe:

## Timeline

### T-0: Alert Fires
- Alert: {alert description}
- Action: Acknowledge, assess severity
- Question: What severity does this warrant?

### T+5: Initial Response
- Finding: {finding}
- Action: {action}
- Question: Do we need to escalate?

### T+15: Investigation
- Finding: {finding}
- Action: {action}

### T+30: Mitigation
- Action: {mitigation}
- Question: Is the rollback working?

### T+45: Resolution
- Action: {resolution}
- Question: When do we declare resolved?

### T+60: Hot Wash
- What went well?
- What could be improved?
- What was missing?

## Follow-up Actions
- [ ] Update runbook for {scenario}
- [ ] Add monitoring for {signal}
- [ ] Schedule full-scale drill
```

### Drill Evaluation

```markdown
# Drill Evaluation

## Metrics
- Time to acknowledge: {X} min (target: 5 min)
- Time to mitigate: {X} min (target: varies)
- Communication score: {1-5}
- Coordination score: {1-5}
- Runbook adherence: {1-5}

## Feedback
- Strengths:
- Areas for improvement:
- Runbook gaps found:
- Training needs identified:

## Action Items
- [ ] Update runbook
- [ ] Schedule training session
- [ ] Add monitoring/alerts
```

---

## Next Steps

1. [Review disaster recovery plan](03-disaster-recovery.md)
2. [Review common troubleshooting guides](../troubleshooting/01-common-issues.md)
3. [Review escalation matrix](../troubleshooting/02-escalation-matrix.md)
