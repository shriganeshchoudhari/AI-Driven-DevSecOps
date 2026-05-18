# STRIDE Threat Model

Comprehensive STRIDE threat model covering every platform component.

---

## Table of Contents

- [Methodology](#methodology)
- [Component Inventory](#component-inventory)
- [STRIDE Analysis](#stride-analysis)
- [Spoofing](#spoofing)
- [Tampering](#tampering)
- [Repudiation](#repudiation)
- [Information Disclosure](#information-disclosure)
- [Denial of Service](#denial-of-service)
- [Elevation of Privilege](#elevation-of-privilege)
- [Risk Matrix](#risk-matrix)
- [Mitigation Status](#mitigation-status)

---

## Methodology

### STRIDE Categories

| Category | Definition | Example |
|----------|-----------|---------|
| **S**poofing | Impersonating a user, system, or component | Fake JWT token, identity theft |
| **T**ampering | Unauthorized modification of data or code | Modified container image, altered config |
| **R**epudiation | Denying an action without proof | No audit log for unauthorized access |
| **I**nformation Disclosure | Exposing data to unauthorized parties | Secret in logs, data leak |
| **D**enial of Service | Disrupting service availability | Resource exhaustion, DDoS |
| **E**levation of Privilege | Gaining unauthorized access | Privileged container, RBAC bypass |

### Risk Scoring

```
Likelihood: 1 (Rare) to 5 (Almost Certain)
Impact:     1 (Negligible) to 5 (Catastrophic)
Risk Score: Likelihood × Impact
Severity:   1-6 Low, 7-12 Medium, 13-19 High, 20-25 Critical
```

---

## Component Inventory

| ID | Component | Description | Data Flow |
|----|-----------|-------------|-----------|
| C1 | GitHub Actions | CI/CD pipeline | Source → Build → Registry |
| C2 | Container Registry (ECR) | Image storage | Docker push/pull |
| C3 | Terraform | Infrastructure provisioning | IaC → AWS API |
| C4 | ArgoCD | GitOps operator | Git → Kubernetes |
| C5 | EKS (Kubernetes) | Container orchestration | API → Pods |
| C6 | Istio | Service mesh | Service A → Service B |
| C7 | Kyverno | Admission controller | API request → Validation |
| C8 | Falco | Runtime security | System call → Alert |
| C9 | AIOps Engine | AI operations | Sources → Analysis |
| C10 | External Secrets | Secrets sync | AWS SM → K8s Secret |
| C11 | cert-manager | Certificate mgmt | ACME → Certificate |
| C12 | Prometheus | Metrics collection | Targets → TSDB |
| C13 | Loki | Log aggregation | Pods → Logs |
| C14 | Tempo | Distributed tracing | App spans → Traces |
| C15 | RDS | PostgreSQL database | App → SQL |
| C16 | ElastiCache | Redis cache | App → Cache |
| C17 | S3 | Object storage | App → Objects |
| C18 | Route53 | DNS management | DNS queries |
| C19 | ALB/NLB | Load balancing | Internet → Services |
| C20 | Karpenter | Node autoscaler | Scheduler → EC2 |

---

## STRIDE Analysis

### Spoofing

| ID | Threat | Component | Risk | Mitigation |
|----|--------|-----------|------|------------|
| S-01 | Fake CI/CD pipeline triggers | C1 (GitHub Actions) | Medium | OIDC token validation, branch protection |
| S-02 | Impersonated container image | C2 (ECR) | Critical | Cosign image signing, Kyverno verification |
| S-03 | Fake ArgoCD API requests | C4 (ArgoCD) | High | OIDC authentication, SSO |
| S-04 | Impersonated Kubernetes user | C5 (EKS) | Critical | OIDC + RBAC, certificate-based auth |
| S-05 | Service identity spoofing | C6 (Istio) | High | mTLS with SPIFFE identities |
| S-06 | Fake webhook calls | C7 (Kyverno) | High | TLS verification, allowed sources |
| S-07 | Counterfeit AIOps webhook events | C9 (AIOps) | Medium | Webhook secret validation |
| S-08 | DNS spoofing | C18 (Route53) | Medium | DNSSEC, ExternalDNS verification |
| S-09 | Fake load balancer targets | C19 (ALB/NLB) | High | Target group health checks |
| S-10 | Impersonated node joining cluster | C20 (Karpenter) | High | Node authentication, instance metadata |

### Tampering

| ID | Threat | Component | Risk | Mitigation |
|----|--------|-----------|------|------------|
| T-01 | Modified source code in CI | C1 (GitHub Actions) | Critical | Branch protection, signed commits, CODEOWNERS |
| T-02 | Tampered container image | C2 (ECR) | Critical | Cosign signing, image immutability |
| T-03 | Modified Terraform state | C3 (Terraform) | Critical | S3 versioning, DynamoDB locks |
| T-04 | Altered GitOps manifests | C4 (ArgoCD) | Critical | Git repository protection, signed commits |
| T-05 | Modified pod spec (in-cluster) | C5 (EKS) | High | Kyverno admission control, PSS |
| T-06 | Istio configuration tampering | C6 (Istio) | High | RBAC on configmap, admission control |
| T-07 | Kyverno policy modification | C7 (Kyverno) | Critical | RBAC, GitOps policy management |
| T-08 | Falco rule tampering | C8 (Falco) | High | Immutable Falco config via GitOps |
| T-09 | ExternalSecret modification | C10 (External Secrets) | Critical | RBAC, audit logging |
| T-10 | Certificate modification | C11 (cert-manager) | High | RBAC, approval workflow |
| T-11 | Prometheus rule tampering | C12 (Prometheus) | Medium | GitOps for alerting rules |
| T-12 | Loki log tampering | C13 (Loki) | Medium | Immutable log storage (S3 WORM) |
| T-13 | Tempo trace tampering | C14 (Tempo) | Low | - |
| T-14 | RDS data modification (unauthorized) | C15 (RDS) | Critical | Encryption, audit logging, IAM auth |
| T-15 | Redis cache poisoning | C16 (ElastiCache) | Medium | Encryption, authentication |
| T-16 | S3 object tampering | C17 (S3) | High | Versioning, object lock |
| T-17 | DNS record tampering | C18 (Route53) | High | Route53 permissions, audit |
| T-18 | Load balancer config tampering | C19 (ALB/NLB) | High | Terraform-managed, RBAC |
| T-19 | Karpenter config tampering | C20 (Karpenter) | High | GitOps-managed NodePool config |

### Repudiation

| ID | Threat | Component | Risk | Mitigation |
|----|--------|-----------|------|------------|
| R-01 | Deny CI/CD pipeline execution | C1 (GitHub Actions) | Medium | GitHub Actions audit log |
| R-02 | Deny image push | C2 (ECR) | Medium | CloudTrail, ECR API logs |
| R-03 | Deny infrastructure modifications | C3 (Terraform) | High | CloudTrail, Terraform plan logs |
| R-04 | Deny Kubernetes action | C5 (EKS) | High | Kubernetes audit logging |
| R-05 | Deny secret access | C10 (External Secrets) | High | CloudTrail, Kubernetes audit |
| R-06 | Deny data access (RDS) | C15 (RDS) | High | RDS audit logs, pgAudit |
| R-07 | Deny DNS changes | C18 (Route53) | Medium | Route53 audit logs |
| R-08 | Deny security alert handling | C8 (Falco) | Medium | Alertmanager logs, PagerDuty history |

### Information Disclosure

| ID | Threat | Component | Risk | Mitigation |
|----|--------|-----------|------|------------|
| I-01 | Secrets exposed in CI logs | C1 (GitHub Actions) | Critical | Secret masking, no-echo |
| I-02 | Container image vulnerability disclosure | C2 (ECR) | High | Private registry, Trivy scanning |
| I-03 | Terraform state contains secrets | C3 (Terraform) | Critical | KMS encryption, no secrets in state |
| I-04 | Kubernetes secret exposure | C5 (EKS) | Critical | KMS envelope encryption, RBAC |
| I-05 | Service mesh traffic sniffing | C6 (Istio) | High | mTLS encryption for all traffic |
| I-06 | Admission review contains sensitive data | C7 (Kyverno) | Medium | Minimize admission request data |
| I-07 | Runtime logs containing secrets | C8 (Falco) | High | Log scrubbing, structured logging |
| I-08 | AIOps engine data leakage | C9 (AIOps) | High | Data sanitization, RBAC on API |
| I-09 | Secret value in ExternalSecret debug | C10 (External Secrets) | High | Production logging disabled |
| I-10 | Certificate private key exposure | C11 (cert-manager) | Critical | KMS-backed private keys |
| I-11 | Prometheus metrics leaking sensitive data | C12 (Prometheus) | Medium | Metrics filtering, authentication |
| I-12 | Logs containing PII/credentials | C13 (Loki) | High | Log scrubbing, retention policy |
| I-13 | Database query logging sensitive data | C15 (RDS) | High | pgAudit filtering, data masking |
| I-14 | S3 bucket misconfiguration | C17 (S3) | High | Public access block, bucket policies |
| I-15 | DNS zone transfer (exposure) | C18 (Route53) | Low | Zone transfer disabled |

### Denial of Service

| ID | Threat | Component | Risk | Mitigation |
|----|--------|-----------|------|------------|
| D-01 | CI/CD pipeline exhaustion | C1 (GitHub Actions) | Medium | Concurrent job limits, runners |
| D-02 | Container registry pull throttling | C2 (ECR) | Medium | ECR pull-through cache, rate limits |
| D-03 | Terraform API rate limiting | C3 (Terraform) | Medium | Retry logic, backoff |
| D-04 | ArgoCD sync overload | C4 (ArgoCD) | Medium | Sync wave ordering, concurrency limits |
| D-05 | Kubernetes API overload | C5 (EKS) | Medium | API priority, fairness |
| D-06 | Service mesh sidecar overhead | C6 (Istio) | Medium | Resource limits, sidecar tuning |
| D-07 | Admission webhook latency | C7 (Kyverno) | Medium | Webhook timeout, background scanning |
| D-08 | Falco resource exhaustion | C8 (Falco) | Medium | Resource limits, rule optimization |
| D-09 | AIOps engine overload | C9 (AIOps) | High | HPA, rate limiting, async processing |
| D-10 | Prometheus target overload | C12 (Prometheus) | Medium | Target limits, recording rules |
| D-11 | Loki ingestion overload | C13 (Loki) | Medium | Rate limiting, log sampling |
| D-12 | Database connection exhaustion | C15 (RDS) | High | Connection pooling, PGBouncer |
| D-13 | Redis memory exhaustion | C16 (ElastiCache) | Medium | Eviction policy, maxmemory |
| D-14 | S3 request throttling | C17 (S3) | Medium | Request distribution, caching |
| D-15 | DNS query flood | C18 (Route53) | High | DNS rate limiting, WAF |
| D-16 | Load balancer target exhaustion | C19 (ALB/NLB) | Medium | Target group limits, autoscaling |
| D-17 | EC2 instance limit reached | C20 (Karpenter) | High | Service quota monitoring, limits |

### Elevation of Privilege

| ID | Threat | Component | Risk | Mitigation |
|----|--------|-----------|------|------------|
| E-01 | CI/CD pipeline privilege escalation | C1 (GitHub Actions) | Critical | OIDC-scoped tokens, least privilege |
| E-02 | Container breakout to host | C5 (EKS) | Critical | Seccomp, AppArmor, PSS restricted |
| E-03 | Service account token abuse | C5 (EKS) | Critical | IRSA, token volume projection |
| E-04 | Istio RBAC bypass | C6 (Istio) | High | AuthorizationPolicy enforcement |
| E-05 | Kyverno webhook bypass | C7 (Kyverno) | Critical | Webhook failure policy: fail |
| E-06 | Privileged container execution | C5 (EKS) | Critical | Kyverno disallow-privileged |
| E-07 | Host network access | C5 (EKS) | Critical | Kyverno restrict host networking |
| E-08 | HostPID/HostIPC access | C5 (EKS) | High | Kyverno restrict host namespaces |
| E-09 | RBAC privilege escalation | C5 (EKS) | Critical | RBAC review, audit alerting |
| E-10 | SecretStore cross-namespace access | C10 (External Secrets) | High | Namespaced SecretStore, RBAC |
| E-11 | Certificate issuance bypass | C11 (cert-manager) | High | Approval workflow, RBAC |
| E-12 | Database privilege escalation | C15 (RDS) | High | Database user roles, least privilege |
| E-13 | KMS key access escalation | - | Critical | KMS key policies, grants |
| E-14 | IAM role chaining | - | High | Permission boundaries, SCPs |

---

## Risk Matrix

### Top 10 Critical Risks

| ID | Risk | Component | Score | Priority |
|----|------|-----------|-------|----------|
| S-02 | Impersonated container image | ECR | 20 (5×4) | P0 |
| T-01 | Modified source code in CI | GitHub Actions | 20 (5×4) | P0 |
| T-03 | Modified Terraform state | Terraform | 20 (5×4) | P0 |
| I-01 | Secrets in CI logs | GitHub Actions | 20 (5×4) | P0 |
| I-03 | Terraform state secrets | Terraform | 20 (5×4) | P0 |
| E-01 | CI/CD privilege escalation | GitHub Actions | 20 (5×4) | P0 |
| E-02 | Container breakout | EKS | 25 (5×5) | P0 |
| E-05 | Kyverno webhook bypass | Kyverno | 20 (5×4) | P0 |
| E-06 | Privileged container | EKS | 20 (4×5) | P0 |
| E-13 | KMS key access escalation | KMS | 20 (4×5) | P0 |

### Full Risk Map

```
Critical (20-25):     ████████████████████████████████  7 risks
High (13-19):         ████████████████████████████     45 risks
Medium (7-12):        ████████████████                 30 risks
Low (1-6):            ██████                            4 risks
```

---

## Mitigation Status

### Mitigation Categories

| Category | Status | Count |
|----------|--------|-------|
| ✅ Implemented | Done | 62 |
| 🔄 In Progress | In progress | 12 |
| 📋 Planned | Not started | 8 |
| ✅ Not Applicable | N/A | 4 |

### Priority Mitigations

| Priority | Threat | Mitigation | Owner | Due |
|----------|--------|------------|-------|-----|
| P0 | S-02 | Kyverno image signature enforcement | Security Team | Done |
| P0 | T-01 | Signed commits, branch protection | Platform Team | Done |
| P0 | T-03 | S3 state locking, versioning | Platform Team | Done |
| P0 | I-01 | GitHub secret scanning, log masking | DevSecOps | Done |
| P0 | E-02 | Pod Security Standards (restricted) | Platform Team | Done |
| P0 | E-05 | Webhook failure policy: fail | Platform Team | Done |
| P0 | E-13 | KMS key permission boundary | Security Team | In Progress |
| P1 | D-12 | PGBouncer connection pooling | Platform Team | Planned |
| P1 | D-17 | Service quota automation | Platform Team | Planned |
| P1 | R-05 | Enhanced secret access audit | Security Team | In Progress |

### Threat Model Review Schedule

| Review Type | Frequency | Scope |
|-------------|-----------|-------|
| Full threat model | Quarterly | All components |
| Component review | Per major change | Specific component |
| CI/CD pipeline review | Per change | GitHub Actions workflows |
| Infrastructure change review | Per PR | Terraform changes |
| New feature review | Per feature | New component |

---

## Next Steps

1. [Review compliance documentation](03-compliance.md)
2. [Review security overview](01-security-overview.md)
3. [Review common troubleshooting guides](../troubleshooting/01-common-issues.md)
