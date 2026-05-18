# Compliance Documentation

Comprehensive compliance documentation mapping platform controls to SOC 2, PCI-DSS, NIST 800-53, and CIS Benchmarks.

---

## Table of Contents

- [SOC 2 Controls Mapping](#soc-2-controls-mapping)
- [PCI-DSS Requirements](#pci-dss-requirements)
- [NIST 800-53 Framework](#nist-800-53-framework)
- [CIS Benchmarks](#cis-benchmarks)
- [Audit Evidence Collection](#audit-evidence-collection)
- [Compliance Automation](#compliance-automation)

---

## SOC 2 Controls Mapping

### Security Category (Common Criteria)

| Control ID | Control Description | Platform Implementation | Evidence Location |
|-----------|---------------------|------------------------|-------------------|
| **CC1.1** | Control Environment | GitOps-based change management, code review required | GitHub PR history |
| **CC1.2** | Communication | Slack #platform-alerts, status page, on-call rotation | Slack archives |
| **CC1.3** | Risk Assessment | Quarterly threat model, annual risk assessment | threat-model.md |
| **CC1.4** | Monitoring Activities | Prometheus, Grafana, Falco, CloudWatch | Monitoring dashboards |
| **CC1.5** | Information & Communication | Incident response documentation, runbooks | docs/operations/ |
| **CC2.1** | Entity-Level Controls | Platform engineering team, defined roles | Team charters |
| **CC2.2** | Monitoring | SRE on-call rotation, alert response metrics | PagerDuty reports |
| **CC3.1** | Risk Assessment | Threat model, vulnerability scanning | Trivy reports |
| **CC3.2** | Risk Mitigation | Security policies, Kyverno enforcement | Kyverno policies |
| **CC3.3** | Control Implementation | All security controls in this document | - |
| **CC4.1** | Information & Communication | Incident communication templates | docs/operations/02-incident-response.md |
| **CC4.2** | Monitoring | Alert response, postmortems | Incident records |

### Additional Criteria for Security

| Control ID | Control Description | Platform Implementation | Evidence |
|-----------|---------------------|------------------------|----------|
| **CC5.1** | Access Control Policy | RBAC, OIDC, IRSA defined and enforced | IAM policies, K8s RBAC |
| **CC5.2** | Access Authorization | Namespace isolation, least privilege | Network policies, roles |
| **CC5.3** | Access Removal | OIDC-based provisioning, automated offboarding | SCIM logs |
| **CC6.1** | Logical Access Security | OIDC + MFA + certificate-based auth | Auth logs |
| **CC6.2** | Identity Management | OIDC provider, IRSA for workloads | IDP configuration |
| **CC6.3** | Access Provisioning | GitOps-based, no manual access | Git history |
| **CC6.4** | Authentication | SSO, OIDC, mTLS, API tokens | AuthN configuration |
| **CC6.5** | Authorization | RBAC policies per namespace | K8s RBAC manifests |
| **CC6.6** | Data Classification | KMS encryption, secrets manager | Data classification doc |
| **CC6.7** | Encryption | At rest: KMS, In transit: TLS 1.2+ | KMS keys, certificates |
| **CC7.1** | System Monitoring | Prometheus, Grafana, Loki, Tempo | Monitoring config |
| **CC7.2** | Incident Response | PagerDuty, incident response plan | docs/operations/02-incident-response.md |
| **CC7.3** | Change Management | GitOps, PRs, ArgoCD sync | ArgoCD sync history |
| **CC7.4** | Capacity Management | Karpenter, HPA, VPA, resource quotas | Karpenter config |
| **CC8.1** | Business Continuity | Multi-AZ, DR plan, Velero backups | docs/operations/03-disaster-recovery.md |
| **CC9.1** | Risk Mitigation | Regular vulnerability scans | Trivy reports |
| **CC9.2** | Vendor Management | AWS, Grafana, PagerDuty contracts | Vendor agreements |

### SOC 2 Type II Evidence Collection

```yaml
# Evidence collection schedule
evidence_collection:
  daily:
  - CloudTrail logs (S3)
  - Kubernetes audit logs
  - Falco event logs
  - Prometheus alert history
  
  weekly:
  - Vulnerability scan reports
  - Access review logs
  - Backup verification logs
  
  monthly:
  - Incident report summary
  - Change management report
  - Capacity metrics report
  
  quarterly:
  - Access rights review
  - Threat model review
  - DR drill report
  - Vendor review
```

---

## PCI-DSS Requirements

### Applicability

The platform can be configured for PCI-DSS compliance when handling cardholder data. The following requirements must be met:

| Requirement | Description | Platform Implementation | Validation |
|-------------|-------------|------------------------|------------|
| **1.1** | Firewall Configuration | Security groups, network policies, WAF | WAF configuration |
| **1.2** | DMZ Architecture | Public/private subnet separation | VPC architecture |
| **1.3** | Inbound/Outbound Rules | Default-deny network policies | Network policy audit |
| **2.1** | System Configuration | CIS-hardened AMIs, immutable infrastructure | kube-bench results |
| **2.2** | Configuration Standards | Terraform-defined, GitOps-managed | Git history |
| **2.3** | Encryption | TLS everywhere, KMS encryption | Certificate inventory |
| **3.1** | Cardholder Data Protection | KMS encryption at rest + TLS in transit | Encryption config |
| **3.2** | Data Storage | No CHD on ephemeral storage | Storage audit |
| **3.3** | Display PAN | Masking policy | Application config |
| **3.4** | Render PAN | Tokenization service | Tokenization config |
| **3.5** | Key Management | KMS rotation, HSM-backed keys | KMS key rotation logs |
| **4.1** | Transmission Encryption | TLS 1.2+ for all external traffic | Certificate scan |
| **4.2** | Certificate Validation | cert-manager, automatic renewal | Certificate expiration |
| **6.1** | Vulnerability Management | Trivy scanning in CI/CD | Scan reports |
| **6.2** | Patch Management | Automated image rebuilds | ECR image history |
| **6.3** | Secure Development | SAST, dependency scanning, signed commits | CI pipeline logs |
| **6.4** | Change Control | GitOps, PR review, ArgoCD sync | Git history |
| **6.5** | Custom Code Review | CODEOWNERS, 2+ approvers | PR approval history |
| **6.6** | Application Security | WAF, Kyverno policies | WAF logs |
| **7.1** | Access Control | RBAC, OIDC, IRSA | IAM configuration |
| **7.2** | Need-to-Know Access | Namespace isolation, least privilege | RBAC audit |
| **7.3** | Access Reviews | Quarterly access review | Access review reports |
| **8.1** | Authentication | OIDC + MFA | IDP configuration |
| **8.2** | User ID | Unique user IDs via OIDC | User admin logs |
| **8.3** | Password Security | OIDC-managed password policy | IDP configuration |
| **8.4** | Multi-Factor Auth | MFA required for all console access | IAM policy |
| **8.5** | Service Accounts | IRSA for pod identities | Service account audit |
| **9.1** | Physical Security | AWS data centers (SOC 2 certified) | AWS SOC 2 report |
| **10.1** | Audit Trails | CloudTrail, Kubernetes audit, Falco | Log retention |
| **10.2** | Audit Log Content | Structured JSON logging | Log format config |
| **10.3** | Audit Log Security | Immutable S3 storage | S3 WORM config |
| **10.4** | Audit Log Retention | 1 year (min), 7 years (PCI) | S3 lifecycle policy |
| **10.5** | Audit Log Monitoring | Prometheus alerting on audit | Alert rules |
| **10.6** | Audit Log Review | Daily automated review | Review schedule |
| **11.1** | Network Monitoring | Falco, CloudWatch, VPC flow logs | Flow log config |
| **11.2** | Vulnerability Scanning | Trivy, weekly full scans | Scan schedule |
| **11.3** | Penetration Testing | Annual third-party pentest | Pentest reports |
| **11.4** | Intrusion Detection | Falco, GuardDuty | GuardDuty findings |
| **11.5** | File Integrity Monitoring | Falco file monitoring | Falco rules |
| **12.1** | Security Policy | Platform security documentation | docs/security/ |
| **12.2** | Risk Assessment | Quarterly threat model | Threat model report |
| **12.3** | Security Awareness | Annual training | Training records |
| **12.4** | Incident Response | Incident response plan | docs/operations/02-incident-response.md |
| **12.5** | Service Providers | AWS SOC 2 report | AWS Artifact |
| **12.6** | Security Testing | Continuous security testing | Test results |

### PCI-DSS Compliance Automation

```yaml
# .github/workflows/pci-compliance-check.yaml
name: PCI Compliance Check
on:
  schedule:
  - cron: "0 6 * * *"
  workflow_dispatch:

jobs:
  pci-check:
    runs-on: ubuntu-latest
    steps:
    - name: Check firewall rules
      run: |
        # Verify default-deny network policies
        kubectl get networkpolicies -A -o json | jq '.items | length'
        
    - name: Verify encryption
      run: |
        # Check TLS versions
        # Check KMS key rotation
        # Verify S3 bucket encryption
        
    - name: Check audit logging
      run: |
        # Verify CloudTrail is enabled
        # Verify Kubernetes audit is enabled
        # Check log retention periods
        
    - name: Generate PCI compliance report
      run: |
        # Compile report for auditor
```

---

## NIST 800-53 Framework

### Control Families

| Control Family | Platform Implementation | Coverage |
|---------------|------------------------|----------|
| **AC** - Access Control | RBAC, OIDC, IRSA, network policies | 40/40 |
| **AT** - Awareness & Training | Onboarding training, security drills | 5/5 |
| **AU** - Audit & Accountability | CloudTrail, K8s audit, Falco | 25/25 |
| **CA** - Assessment & Authorization | Continuous compliance scanning | 10/10 |
| **CM** - Configuration Management | GitOps, Terraform, IaC | 15/15 |
| **CP** - Contingency Planning | DR plan, backups, multi-AZ | 10/10 |
| **IA** - Identification & Auth | OIDC, mTLS, certificate auth | 15/15 |
| **IR** - Incident Response | PagerDuty, runbooks, postmortems | 10/10 |
| **MA** - Maintenance | Automated patching, image rebuilds | 5/5 |
| **MP** - Media Protection | KMS encryption, S3 object lock | 5/5 |
| **PE** - Physical Protection | AWS data centers | 5/5 |
| **PL** - Planning | Architecture docs, threat model | 10/10 |
| **PM** - Program Management | Security policies, reviews | 10/10 |
| **PS** - Personnel Security | OIDC-based access control | 5/5 |
| **RA** - Risk Assessment | Threat model, vulnerability scanning | 10/10 |
| **SA** - System & Services Acq | Vendor review, SBOM | 10/10 |
| **SC** - System & Communications | TLS, mTLS, KMS encryption | 30/30 |
| **SI** - System & Info Integrity | Trivy, Falco, WAF | 20/20 |

### Key NIST Controls

```yaml
# Example: AC-3 Access Enforcement
ac-3:
  description: "Enforce approved authorizations for logical access"
  implementation: |
    - RBAC roles with least privilege
    - Kyverno policies enforce pod security
    - Network policies enforce micro-segmentation
    - IRSA for AWS resource access
  evidence:
    - kubectl get clusterrolebindings -o json
    - kubectl get clusterpolicy -o json
    - kubectl get networkpolicies -A -o json

# Example: AU-3 Audit Record Content
au-3:
  description: "Ensure audit records contain sufficient information"
  implementation: |
    - Kubernetes audit: all CRUD operations on sensitive resources
    - CloudTrail: all AWS API calls
    - Falco: security events with context
    - Loki: structured JSON logging
  evidence:
    - Kubernetes audit policy config
    - CloudTrail configuration
    - Falco rules configuration

# Example: SC-8 Transmission Confidentiality
sc-8:
  description: "Protect transmitted information"
  implementation: |
    - TLS 1.2/1.3 for all external traffic
    - mTLS for service-to-service communication
    - VPC endpoints for AWS API calls
  evidence:
    - cert-manager certificate inventory
    - Istio PeerAuthentication (STRICT)
    - ALB SSL policy
```

---

## CIS Benchmarks

### CIS Kubernetes v1.29

| Section | Checks | Automated | Tool |
|---------|--------|-----------|------|
| 1 - Control Plane | 15 | Yes | kube-bench |
| 2 - etcd | 5 | Yes | kube-bench |
| 3 - Control Plane Config | 8 | Yes | kube-bench |
| 4 - Worker Nodes | 12 | Yes | kube-bench |
| 5 - Policies | 20 | Yes | Kyverno + kube-bench |

### CIS Amazon EKS

| Section | Checks | Automated | Tool |
|---------|--------|-----------|------|
| 1 - EKS Cluster | 10 | Yes | kube-bench-eks |
| 2 - Worker Nodes | 15 | Yes | kube-bench |
| 3 - Logging and Monitoring | 8 | Yes | kube-bench-eks |
| 4 - Authentication and Authorization | 12 | Yes | kube-bench-eks |
| 5 - Network Security | 10 | Yes | kube-bench-eks |

### Compliance Validation Script

```bash
#!/bin/bash
# compliance-scan.sh

echo "=== CIS Benchmark Scan ==="

# Run kube-bench
kube-bench run --targets master,node --json > kube-bench-results.json

# Parse results
FAILED_TESTS=$(jq '.Totals.total_fail' kube-bench-results.json)
WARN_TESTS=$(jq '.Totals.total_warn' kube-bench-results.json)
PASS_TESTS=$(jq '.Totals.total_pass' kube-bench-results.json)

echo "Results: ${PASS_TESTS} passed, ${WARN_TESTS} warnings, ${FAILED_TESTS} failed"

# Check Kyverno policy violations
echo "=== Kyverno Policy Report ==="
kubectl get policyreport -A -o json | jq -r '
  .items[] | select(.summary.fail > 0) |
  "\(.metadata.name): \(.summary.fail) failures"
'

# Check Falco events
echo "=== Recent Security Events ==="
kubectl logs -n falco daemonset/falco --tail=10 | grep -E "CRITICAL|WARNING"

echo "=== Compliance Scan Complete ==="
```

---

## Audit Evidence Collection

### Automated Evidence Collection

```yaml
# evidence-collector.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: evidence-collector
  namespace: compliance
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: collector
            image: platform/evidence-collector:latest
            env:
            - name: EVIDENCE_BUCKET
              value: platform-compliance-evidence
            - name: COLLECTION_PERIOD
              value: "24h"
            command:
            - /bin/sh
            - -c
            - |
              # Collect Kubernetes audit logs
              kubectl get events -A --sort-by='.lastTimestamp' > /evidence/k8s-events-$(date +%Y%m%d).log
              
              # Collect cluster state
              kubectl get nodes -o yaml > /evidence/nodes-$(date +%Y%m%d).yaml
              kubectl get pods -A -o yaml > /evidence/pods-$(date +%Y%m%d).yaml
              
              # Collect security state
              kubectl get clusterpolicy -o yaml > /evidence/kyverno-policies-$(date +%Y%m%d).yaml
              kubectl get networkpolicies -A -o yaml > /evidence/network-policies-$(date +%Y%m%d).yaml
              
              # Upload to S3
              aws s3 sync /evidence/ s3://$EVIDENCE_BUCKET/$(date +%Y/%m/%d)/
```

### Evidence Retention

| Evidence Type | Retention Period | Storage | Format |
|--------------|-----------------|---------|--------|
| CloudTrail logs | 1 year (min), 7 years (PCI) | S3 (Glacier after 90d) | JSON |
| Kubernetes audit logs | 1 year | S3 | JSON |
| Falco events | 1 year | S3 | JSON |
| Vulnerability scans | 5 years | S3 | SARIF/JSON |
| Access reviews | 5 years | S3 | PDF |
| Incident reports | 7 years | S3 | Markdown/PDF |
| Change management | 5 years | Git | Git history |
| Monitoring data | 90 days | Prometheus/Loki | TSDB/Logs |

### Audit Response Package

```markdown
# Audit Evidence Package

## Requested By: {Auditor Name}
## Date: {Request Date}
## Scope: {SOC2 / PCI-DSS / NIST}

### Evidence Provided

1. **Access Control** (CC5.x / 7.x)
   - RBAC configuration: [link to manifests]
   - IAM policies: [link to policies]
   - Access review report: [link to PDF]

2. **Change Management** (CC7.3 / 6.4)
   - Git history: [link to GitHub]
   - Deploy history: [link to ArgoCD]
   - PR review records: [link to PRs]

3. **Monitoring** (CC7.1 / 10.x)
   - Alert history: [link to PagerDuty]
   - Monitoring dashboards: [link to Grafana]
   - Uptime reports: [link to reports]

4. **Encryption** (CC6.6 / 3.x / SC-8)
   - Certificate inventory: [link to cert-manager]
   - KMS key list: [link to KMS]
   - TLS configuration: [link to config]

5. **Incident Response** (CC7.2 / 12.x)
   - Incident records: [link to PagerDuty]
   - Postmortems: [link to postmortems]
   - DR drill reports: [link to reports]

6. **Backup & Recovery** (CC8.1 / CP-9)
   - Backup schedule: [link to Velero]
   - DR plan: [link to docs]
   - Recovery test results: [link to reports]
```

---

## Compliance Automation

### CI/CD Compliance Pipeline

```yaml
# .github/workflows/compliance-pipeline.yaml
name: Compliance Pipeline
on:
  schedule:
  - cron: "0 6 * * *"
  workflow_dispatch:

jobs:
  cis-benchmark:
    runs-on: ubuntu-latest
    steps:
    - name: Run CIS Benchmark
      run: |
        kube-bench run --targets master,node --json > cis-report.json
    - name: Parse Report
      run: |
        FAILED=$(jq '.Totals.total_fail' cis-report.json)
        if [ "$FAILED" -gt 0 ]; then
          echo "CIS benchmark has $FAILED failures"
          exit 1
        fi

  kyverno-audit:
    runs-on: ubuntu-latest
    steps:
    - name: Check Policy Violations
      run: |
        FAILURES=$(kubectl get policyreport -A -o json | jq '[.items[] | .summary.fail] | add // 0')
        if [ "$FAILURES" -gt 0 ]; then
          echo "$FAILURES policy violations found"
        fi

  image-scan:
    runs-on: ubuntu-latest
    steps:
    - name: Scan All Running Images
      run: |
        kubectl get pods -A -o json | jq -r '.items[].spec.containers[].image' | sort -u | while read image; do
          trivy image --severity CRITICAL --ignore-unfixed --exit-code 0 "$image"
        done

  evidence-collection:
    runs-on: ubuntu-latest
    steps:
    - name: Collect Audit Evidence
      run: |
        ./scripts/collect-evidence.sh
    - name: Upload to S3
      run: |
        aws s3 sync evidence/ s3://platform-compliance-evidence/$(date +%Y/%m/%d)/
```

### Compliance Dashboard

```bash
# Query compliance metrics from Prometheus
echo "=== Compliance Metrics ==="
echo ""
echo "CIS Benchmark Compliance:"
curl -s 'http://prometheus:9090/api/v1/query?query=cis_benchmark_pass_rate' | jq '.data.result[] | "\(.metric.test): \(.value[1])%"'

echo ""
echo "Kyverno Policy Compliance:"
curl -s 'http://prometheus:9090/api/v1/query?query=kyverno_policy_rule_total{status="pass"}' | jq '.data.result | length'
curl -s 'http://prometheus:9090/api/v1/query?query=kyverno_policy_rule_total{status="fail"}' | jq '.data.result | length'

echo ""
echo "Vulnerability Status:"
curl -s 'http://prometheus:9090/api/v1/query?query=trivy_image_vulnerabilities{severity="CRITICAL"}' | jq '.data.result | length'
echo "CRITICAL vulnerabilities found in running images"
```

---

## Next Steps

1. [Review SRE operational handbook](../operations/01-sre-runbook.md)
2. [Review security overview](01-security-overview.md)
3. [Review threat model](02-threat-model.md)
