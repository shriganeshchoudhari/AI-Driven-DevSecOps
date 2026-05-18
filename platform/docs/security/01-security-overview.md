# Security Architecture Overview

Defense-in-depth security architecture for the AI-Driven Secure GitOps Platform.

---

## Table of Contents

- [Security Principles](#security-principles)
- [Defense in Depth Layers](#defense-in-depth-layers)
- [Zero Trust Architecture](#zero-trust-architecture)
- [Supply Chain Security](#supply-chain-security)
- [Runtime Security](#runtime-security)
- [Secrets Management](#secrets-management)
- [Identity and Access Management](#identity-and-access-management)
- [Network Security](#network-security)
- [Data Protection](#data-protection)
- [Compliance Mapping](#compliance-mapping)

---

## Security Principles

### Guiding Principles

1. **Defense in Depth**: Multiple layers of security controls at every level
2. **Least Privilege**: Minimal permissions for every identity and process
3. **Zero Trust**: Never trust, always verify — no implicit trust for any actor
4. **Shift Left**: Security integrated from the earliest stages of development
5. **Immutable Infrastructure**: All changes deployed, never manually modified
6. **Secure by Default**: Security defaults that protect without configuration
7. **Continuous Verification**: Ongoing validation of security controls
8. **Audit Everything**: Complete audit trail for all operations

### Security Ownership

| Layer | Owner | Responsibility |
|-------|-------|----------------|
| Code Security | Development Team | SAST, dependency scanning, code review |
| Image Security | Platform Team | Base images, signing, vulnerability scanning |
| Cluster Security | Platform Team | RBAC, network policies, Pod Security Standards |
| Runtime Security | Security Team | Falco rules, incident response |
| Infrastructure Security | Platform Team | IAM, encryption, network ACLs |
| Compliance | Compliance Team | Audit evidence, control testing |

---

## Defense in Depth Layers

```
Layer 0: Code & Dependencies
  ├── SAST (Semgrep, CodeQL)
  ├── Dependency scanning (Trivy, Dependabot)
  ├── Secret scanning (GitGuardian)
  └── Code review (mandatory 2+ approvals)

Layer 1: Supply Chain
  ├── Image signing (Cosign)
  ├── SBOM generation (Syft)
  ├── Image vulnerability scanning (Trivy)
  └── SLSA provenance (SLSA L3)

Layer 2: Kubernetes Admission
  ├── Kyverno policies (50+ enforcements)
  ├── Pod Security Standards (restricted)
  ├── Image signature verification
  └── Resource quota enforcement

Layer 3: Network Security
  ├── Default-deny network policies
  ├── Calico (Cilium) network policies
  ├── AWS Security Groups
  ├── WAF (OWASP rules, rate limiting)
  └── TLS everywhere (cert-manager)

Layer 4: Identity & Access
  ├── OIDC (GitHub Actions, IRSA)
  ├── RBAC (least privilege)
  ├── Pod Identity (IRSA)
  └── Multi-factor authentication

Layer 5: Runtime Security
  ├── Falco (1000+ rules)
  ├── Audit logging (Kubernetes audit)
  ├── CloudTrail
  └── Container runtime security

Layer 6: Secrets Management
  ├── AWS Secrets Manager
  ├── External Secrets Operator
  ├── SOPS encryption
  └── Sealed Secrets

Layer 7: Data Protection
  ├── Encryption at rest (KMS)
  ├── Encryption in transit (TLS 1.3)
  ├── Database encryption (RDS TDE)
  └── Application-level encryption

Layer 8: Monitoring & Response
  ├── Security monitoring (Falco, CloudWatch)
  ├── Alerting (Alertmanager)
  ├── SIEM integration
  └── Incident response automation
```

---

## Zero Trust Architecture

### Key Principles Applied

| Zero Trust Principle | Implementation | Verification |
|---------------------|----------------|--------------|
| Verify explicitly | OIDC authentication for all API calls | JWT validation, IRSA |
| Use least privilege | RBAC + IAM policies | Policy as code, regular audit |
| Assume breach | Network segmentation, micro-segmentation | Falco monitoring, audit logs |
| Never trust, always verify | Mutual TLS (mTLS) | Certificate-based authentication |
| Verify end-to-end | Encryption at rest + in transit | KMS key rotation, cert rotation |

### Network Micro-Segmentation

```
┌──────────────────┐
│   DMZ (Public)   │
│   - ALB/NLB      │
│   - WAF          │
│   - CloudFront   │
└────────┬─────────┘
         │ 443 (mTLS)
┌────────▼─────────┐
│   Ingress Layer  │
│   - NGINX Ingress│
│   - cert-manager │
│   - ExternalDNS  │
└────────┬─────────┘
         │ 443 (mTLS)
┌────────▼─────────┐
│   Service Mesh   │
│   - Istio (mTLS) │
│   - Auth policy  │
│   - Rate limit   │
└────────┬─────────┘
         │ 443 (mTLS)
┌────────▼─────────┐
│   Applications   │
│   - Microservices│
│   - AIOps Engine │
│   - Data stores  │
└──────────────────┘
```

### Identity-Based Access

```yaml
# Service-to-service authentication using mTLS
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: aiops
spec:
  mtls:
    mode: STRICT
---
# Application-level authorization
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: aiops-engine
  namespace: aiops
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: aiops-engine
  rules:
  - from:
    - source:
        principals: ["cluster.local/ns/aiops/sa/aiops-analyzer"]
    to:
    - operation:
        methods: ["POST", "GET"]
        paths: ["/api/v1/*"]
```

---

## Supply Chain Security

### CI/CD Security Gates

```yaml
# .github/workflows/security-scan.yaml
name: Security Scan
on:
  push:
    branches: [main, develop]
  pull_request:

jobs:
  sast:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    - name: Run Semgrep SAST
      uses: semgrep/semgrep-action@v1
      with:
        config: p/default

  dependency-scan:
    runs-on: ubuntu-latest
    steps:
    - name: Scan dependencies
      uses: aquasecurity/trivy-action@master
      with:
        scan-type: fs
        scan-ref: .
        format: sarif
        severity: CRITICAL,HIGH

  image-sign:
    needs: [sast, dependency-scan]
    runs-on: ubuntu-latest
    steps:
    - name: Sign container image
      env:
        COSIGN_PRIVATE_KEY: ${{ secrets.COSIGN_PRIVATE_KEY }}
        COSIGN_PASSWORD: ${{ secrets.COSIGN_PASSWORD }}
      run: |
        cosign sign --key env://COSIGN_PRIVATE_KEY \
          ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}

  sbom:
    runs-on: ubuntu-latest
    steps:
    - name: Generate SBOM
      uses: anchore/sbom-action@v0
      with:
        image: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}

    - name: Attach SBOM
      run: |
        cosign attach sbom --sbom sbom.spdx.json \
          ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
```

### SLSA Level 3 Compliance

```yaml
# Build provenance attestation
apiVersion: slsa.dev/provenance/v1
kind: Build
metadata:
  name: aiops-engine
spec:
  builder:
    id: "https://github.com/org/aiops-platform/.github/workflows/ci.yaml@refs/heads/main"
  invocation:
    configSource:
      uri: "git+https://github.com/org/aiops-platform@refs/heads/main"
      entryPoint: ".github/workflows/ci.yaml"
  buildConfig:
    steps:
    - command: ["build"]
      env:
        IMAGE_NAME: aiops-engine
  materials:
  - uri: "git+https://github.com/org/aiops-platform"
    digest:
      sha1: "abcdef1234567890"
```

### Image Verification Policy (Kyverno)

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: validate-image-signature
spec:
  validationFailureAction: Enforce
  rules:
  - name: verify-signature
    match:
      any:
      - resources:
          kinds:
          - Pod
    verifyImages:
    - imageReferences:
      - "123456789012.dkr.ecr.us-west-2.amazonaws.com/platform/*"
      attestors:
      - count: 1
        entries:
        - keys:
            publicKeys: |-
              -----BEGIN PUBLIC KEY-----
              MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE...
              -----END PUBLIC KEY-----
      required: true
```

---

## Runtime Security

### Falco Rules

Falco is deployed with 1000+ default rules plus custom rules for platform-specific threats:

```yaml
# Custom Falco rules for platform
- rule: AIOps Engine Unauthorized Network Connection
  desc: Detect unauthorized outbound connections from AIOps engine
  condition: >
    container.image.repository = "123456789012.dkr.ecr.us-west-2.amazonaws.com/platform/aiops-engine"
    and evt.type = connect
    and not fd.sip in (trusted_ips)
  output: "Unauthorized network connection from AIOps engine (connection=%fd.name)"
  priority: CRITICAL
  tags: [platform, aiops, network]

- rule: Secret File Access Outside Expected
  desc: Detect access to secret files outside of expected processes
  condition: >
    open_read
    and fd.name contains "/etc/kubernetes/pki"
    and not proc.name in (expected_k8s_processes)
  output: "Unexpected process accessing secret file (user=%user.name command=%proc.cmdline file=%fd.name)"
  priority: WARNING
  tags: [platform, secrets, filesystem]

- rule: Detect Crypto Mining
  desc: Detect cryptocurrency mining activity
  condition: >
    evt.type = execve
    and proc.name in (miner_procs)
  output: "Crypto miner process detected (user=%user.name command=%proc.cmdline)"
  priority: CRITICAL
  tags: [platform, crypto, attack]
```

### Incident Response Automation

```yaml
# Falcosidekick configuration for automated response
apiVersion: v1
kind: ConfigMap
metadata:
  name: falcosidekick-config
  namespace: falco
data:
  falcosidekick.yaml: |
    listenport: 2801
    debug: false
    
    webhook:
      kubernetes:
        namespace: falco
        pod:
          patch:
            - match:
                rule: "Terminate shell in container"
              patch: |
                {
                  "metadata": {
                    "annotations": {
                      "container.apparmor.security.beta.kubernetes.io/falco-event": "localhost/restrictive"
                    }
                  },
                  "spec": {
                    "containers": [
                      {
                        "name": "*",
                        "env": [
                          {
                            "name": "FALCO_EVENT",
                            "value": "SHELL_DETECTED"
                          }
                        ]
                      }
                    ]
                  }
                }
              action: delete
    
    aws:
      lambda:
        functionname: "platform-falco-response"
      sqs:
        queueurl: "https://sqs.us-west-2.amazonaws.com/123456789012/falco-events"
    
    alertmanager:
      hostport: "http://alertmanager.monitoring:9093"
      minimumpriority: warning
    
    slack:
      webhookurl: "https://hooks.slack.com/services/T00/B00/xxxxx"
      minimumpriority: warning
```

---

## Secrets Management

### Secrets Architecture (Summary)

| Layer | Method | Use Case | GitOps Safe |
|-------|--------|----------|-------------|
| Source of Truth | AWS Secrets Manager | All secrets | No |
| Cluster Sync | External Secrets Operator | Auto-sync to K8s secrets | No |
| GitOps Storage | Sealed Secrets | ArgoCD manifests | Yes |
| Client Encryption | SOPS + KMS | Encrypted configs in Git | Yes |
| Emergency | Break-glass IAM role | Direct access | N/A |

### Secret Rotation Policy

| Secret Type | Rotation Period | Method | Automation |
|-------------|----------------|--------|------------|
| Database passwords | 90 days | Lambda + RDS | Automated |
| Redis auth tokens | 90 days | Lambda | Automated |
| OIDC client secrets | 180 days | Manual | Manual |
| LLM API keys | 30 days | Manual | Manual |
| TLS certificates | 60 days | cert-manager | Automated |
| SSH keys | 180 days | Manual | Manual |

---

## Identity and Access Management

### RBAC Model

```
┌─────────────────────────────────────────────────┐
│                    Cluster                       │
│  ┌──────────┐  ┌──────────┐  ┌──────────────┐  │
│  │ Admin    │  │ Engineer │  │ Viewer       │  │
│  │ Full     │  │ Namespace│  │ Read-only    │  │
│  │ Access   │  │ Level    │  │ Cluster      │  │
│  └──────────┘  └──────────┘  └──────────────┘  │
│        │             │              │            │
│  ┌─────┴─────┐ ┌────┴────┐  ┌──────┴──────┐    │
│  │ Platform  │ │ App     │  │ Auditors    │    │
│  │ SRE       │ │ Teams   │  │             │    │
│  └───────────┘ └─────────┘  └─────────────┘    │
└─────────────────────────────────────────────────┘
```

### Role Definitions

| Role | Permissions | Assigned To |
|------|-------------|-------------|
| **cluster-admin** | Full cluster access | Platform SRE (5 members) |
| **platform-admin** | Namespace admin (platform/*) | Platform Engineering |
| **namespace-admin** | Full access to specific namespace | App Team Lead |
| **namespace-edit** | Deploy, update resources in namespace | App Developer |
| **namespace-view** | Read-only access to namespace | App Developer (read-only) |
| **cluster-viewer** | Read-only cluster access | Auditors, Compliance |
| **security-viewer** | Read security policies, audit logs | Security Team |

### IRSA (IAM Roles for Service Accounts)

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aiops-engine
  namespace: aiops
  annotations:
    eks.amazonaws.com/role-arn: "arn:aws:iam::123456789012:role/aiops-engine"
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: aiops-engine
  namespace: aiops
rules:
- apiGroups: [""]
  resources: ["pods", "services", "endpoints"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["autoscaling"]
  resources: ["horizontalpodautoscalers"]
  verbs: ["get", "list", "watch"]
```

---

## Network Security

### Default Deny Network Policies

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

### Per-Namespace Policies

```yaml
# Allow monitoring namespace to scrape metrics
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-prometheus-scrape
  namespace: aiops
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: aiops-engine
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: monitoring
      podSelector:
        matchLabels:
          app.kubernetes.io/name: prometheus
    ports:
    - port: 8000
    - port: 9090
```

### Security Group Rules

| Purpose | Source | Destination | Port | Protocol |
|---------|--------|-------------|------|----------|
| EKS API access | EKS control plane | Nodes | 443 | TCP |
| Node communication | Nodes (self) | Nodes (self) | 10250 | TCP |
| CoreDNS | All pods | CoreDNS pods | 53 | UDP/TCP |
| Prometheus scraping | Prometheus pods | All pods | 9090 | TCP |
| Falco events | Falco pods | Alertmanager | 9093 | TCP |

---

## Data Protection

### Encryption at Rest

| Service | Encryption Method | Key Management |
|---------|------------------|----------------|
| EBS (Kubernetes nodes) | AWS EBS Encryption | AWS managed key |
| RDS (PostgreSQL) | AWS RDS Encryption | KMS key (platform-rds) |
| ElastiCache (Redis) | AWS Redis Encryption | KMS key (platform-redis) |
| S3 (Objects) | S3 SSE-S3 | AWS managed key |
| S3 (Logs, sensitive) | S3 SSE-KMS | KMS key (platform-s3) |
| ECR (Images) | AWS ECR Encryption | AWS managed key |
| Secrets Manager | AWS Secrets Manager encryption | KMS key (platform-secrets) |
| K8s Secrets | KMS envelope encryption | KMS key (platform-eks) |

### Encryption in Transit

| Traffic Type | Protocol | Cipher | Minimum TLS |
|-------------|----------|--------|-------------|
| External HTTPS | TLS 1.3 | TLS_AES_128_GCM_SHA256 | TLS 1.2 |
| Internal mTLS | TLS 1.3 | TLS_AES_256_GCM_SHA384 | TLS 1.2 |
| Database connection | PostgreSQL SSL | - | TLS 1.2 |
| Redis connection | Redis AUTH + TLS | - | TLS 1.2 |
| EKS API | Kubernetes TLS | - | TLS 1.2 |
| AWS API | HTTPS | - | TLS 1.2 |

---

## Compliance Mapping

### SOC 2 Controls

| Control Area | Platform Implementation | Evidence |
|-------------|------------------------|----------|
| **CC6.1** - Logical Access | OIDC, IRSA, RBAC | CloudTrail logs, Kubernetes audit |
| **CC6.6** - Data Encryption | KMS encryption at rest + TLS in transit | Certificate inventory, KMS key list |
| **CC7.1** - Monitoring | Prometheus, Falco, CloudWatch | Monitoring dashboards, alert history |
| **CC7.2** - Incident Response | PagerDuty, automated response | Incident records, postmortems |
| **CC7.3** - Change Management | GitOps, PR reviews, CodeOwner | Git history, ArgoCD sync records |
| **CC8.1** - Availability | Multi-AZ, HA, backup strategy | DR drill reports, backup logs |

### PCI-DSS Requirements

| Requirement | Platform Implementation |
|-------------|------------------------|
| **3.4** - Encrypt cardholder data | KMS encryption for all data stores |
| **3.5** - Key management | KMS automatic key rotation |
| **4.1** - Encrypt transmission | TLS 1.2+ for all traffic |
| **7.1** - Restrict access | RBAC + IRSA least privilege |
| **7.2** - Need-to-know access | Namespace isolation, network policies |
| **8.1** - Authentication | OIDC + MFA for all users |
| **8.3** - Secure authentication | Certificate-based (mTLS) |
| **10.1** - Audit trails | CloudTrail, Kubernetes audit, Falco |
| **10.3** - Audit logging | Centralized logging in Loki |
| **10.5** - Protect audit trails | Immutable log storage (S3 + WORM) |

### NIST 800-53 Controls

| Control | Platform Implementation |
|---------|------------------------|
| **AC-2** - Account Management | OIDC, SCIM provisioning |
| **AC-3** - Access Enforcement | RBAC, Kyverno policies |
| **AC-4** - Information Flow | Network policies, Istio |
| **AC-6** - Least Privilege | IRSA, namespaced RBAC |
| **AU-2** - Audit Events | Kubernetes audit, Falco |
| **AU-3** - Content of Audit Records | Structured JSON logging |
| **CM-2** - Baseline Configuration | GitOps, Terraform |
| **CM-3** - Configuration Change | ArgoCD sync, PR review |
| **CP-9** - Backup | Velero, RDS snapshots |
| **IA-2** - Identification & Auth | OIDC, mTLS |
| **SC-8** - Transmission | TLS 1.2+, mTLS |
| **SC-12** - Key Management | KMS, cert-manager |
| **SC-28** - Protection at Rest | KMS encryption |

### CIS Benchmarks

| Benchmark | Status | Tools |
|-----------|--------|-------|
| CIS Kubernetes v1.29 | Automated | kube-bench, Kyverno |
| CIS Amazon EKS | Automated | kube-bench-eks |
| CIS Docker | Automated | docker-bench |
| CIS Linux (Nodes) | Manual | - |

### Compliance Automation

```yaml
# Automated compliance validation in CI/CD
name: Compliance Scan
on:
  schedule:
  - cron: "0 6 * * *"  # Daily at 6 AM

jobs:
  kube-bench:
    runs-on: ubuntu-latest
    steps:
    - name: Run kube-bench
      uses: aquasecurity/kube-bench-action@v0.9
      with:
        version: latest
        target: eks

    - name: Upload results
      uses: actions/upload-artifact@v4
      with:
        name: kube-bench-report
        path: kube-bench-results/

  compliance-check:
    runs-on: ubuntu-latest
    steps:
    - name: Check Kyverno policies
      run: |
        kubectl get clusterpolicy -o json | jq '.items | length'
        kubectl get policyreport -o json | jq '.items[] | select(.summary.fail > 0) | .metadata.name'

    - name: Verify encryption
      run: |
        # Check KMS keys are enabled
        # Check TLS certificates
        # Check secret store configuration

    - name: Generate compliance report
      run: |
        # Generate SOC2/PCI-DSS/NIST compliance report
```

---

## Next Steps

1. [Review the STRIDE threat model](02-threat-model.md)
2. [Review compliance documentation](03-compliance.md)
3. [Review common troubleshooting guides](../troubleshooting/01-common-issues.md)
