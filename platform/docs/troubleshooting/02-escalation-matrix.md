# Escalation Matrix

Complete escalation paths and contact information for all incidents.

---

| Level | Role | Team | Response Time | Contact Method |
|-------|------|------|---------------|----------------|
| **L1** | On-Call SRE | Platform Engineering | ≤ 5 min | PagerDuty, Slack |
| **L2** | Platform Engineering Lead | Platform Engineering | ≤ 30 min | Phone, Slack |
| **L3** | Security Team | Security | ≤ 15 min (SEV1) | PagerDuty, Phone |
| **L3** | Database Administrator | Platform Engineering | ≤ 30 min | Phone, Slack |
| **L4** | AWS Support | External | ≤ 15 min (SEV1) | AWS Support Console |
| **L4** | Grafana Support | External | ≤ 4 hours | Support Portal |
| **L4** | PagerDuty Support | External | ≤ 4 hours | Support Portal |

### L1: On-Call SRE

| Role | Contact | Hours | Responsibility |
|------|---------|-------|---------------|
| Primary SRE | PagerDuty: `platform-primary` | 8am-8pm PT | First responder |
| Secondary SRE | PagerDuty: `platform-secondary` | 8pm-8am PT | Night coverage |
| Shadow SRE | Slack: @sre-shadow | Business hours | Training |

### L2: Platform Engineering Team

| Role | Name | Contact | Responsibility |
|------|------|---------|---------------|
| Team Lead | [Name] | lead@example.com, +1-555-0100 | Technical decisions |
| Senior Engineer | [Name] | senior@example.com, +1-555-0101 | Complex issues |
| Infrastructure Lead | [Name] | infra@example.com | AWS infrastructure |

### L3: Specialized Teams

| Team | Contact | When to Escalate |
|------|---------|------------------|
| Security | PagerDuty: `security`, security@example.com | Security incidents, policy bypass |
| Database Admin | Slack: @dba-team | RDS issues, replication, performance |
| Network | Slack: @networking-team | DNS, load balancer, VPN issues |
| Application | Slack: @app-team | Application-specific issues |

### L4: External Vendor Support

| Vendor | SLA | Contact | Account ID |
|--------|-----|---------|------------|
| AWS Support (Enterprise) | 15 min (SEV1) | AWS Console → Create Case | 123456789012 |
| Grafana Labs | 4 hours | support@grafana.com | PLATFORM-2026 |
| PagerDuty | 4 hours | support@pagerduty.com | PD-2026 |

### Escalation SLAs

| Level | SEV1 | SEV2 | SEV3 | SEV4 |
|-------|------|------|------|------|
| L1 Response | 5 min | 15 min | 60 min | 24h |
| L1 → L2 Escalation | 15 min | 30 min | 2h | N/A |
| L2 → L3 Escalation | 30 min | 60 min | N/A | N/A |
| L3 → L4 Escalation | 60 min | 4h | N/A | N/A |
