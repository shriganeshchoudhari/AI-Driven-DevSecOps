# Request Flows: AI-Driven Secure GitOps Kubernetes Platform

## Document Control

| Attribute | Value |
|---|---|
| **Document ID** | ARC-FLOW-003 |
| **Version** | 1.0 |
| **Classification** | Internal — Engineering |
| **Author** | Platform Architecture Team |
| **Last Updated** | 2026-05-17 |

---

## 1. User Request Flow

A developer accesses a platform-deployed application through their browser. This flow traces the request from DNS resolution through the service mesh to the backend application pod.

```mermaid
sequenceDiagram
    participant User as Browser/User
    participant DNS as Route53 DNS
    participant CF as CloudFront/WAF
    participant GW as Istio Gateway
    participant AUTH as OAuth2 Proxy (Dex)
    participant ENVOY as Envoy Sidecar
    participant APP as Application Pod
    participant SVC as Backend Service
    participant DB as PostgreSQL/RDS

    User->>DNS: 1. Resolve app.platform.internal
    DNS-->>User: 2. A-Record → CloudFront IP
    User->>CF: 3. HTTPS Request (SNI: app.platform.internal)
    CF->>CF: 4. WAF Rule Evaluation (OWASP, rate-limit, IP blocklist)
    CF-->>User: 401/403 if blocked
    CF->>GW: 5. Forward to Istio Gateway (origin)
    GW->>GW: 6. TLS termination, sni-match to Gateway resource
    GW->>AUTH: 7. Redirect to OAuth2 Proxy for auth
    AUTH->>AUTH: 8. OIDC flow with Dex (Google/GitHub/Okta)
    AUTH-->>GW: 9. Set session cookie, redirect back
    GW->>GW: 10. Extract JWT claims, set Envoy headers (x-auth-*, x-email)
    GW->>ENVOY: 11. Route to correct VirtualService
    ENVOY->>ENVOY: 12. mTLS handshake with destination workload
    ENVOY->>APP: 13. Forward HTTP to localhost:8080
    APP->>APP: 14. Validate session, enforce RBAC (K8s ServiceAccount)
    APP->>SVC: 15. Internal gRPC call via mesh DNS
    SVC->>DB: 16. Query database (IAM-authenticated via RDS Proxy)
    DB-->>SVC: 17. Result set
    SVC-->>ENVOY: 18. gRPC response (with telemetry attributes)
    ENVOY->>ENVOY: 19. Emit Envoy gRPC metrics + access log to OTel
    ENVOY-->>GW: 20. Response via mesh
    GW-->>CF: 21. HTTP response
    CF-->>User: 22. Rendered page

    Note over ENVOY,APP: Total mesh latency target: < 5ms P99
```

### Flow Characteristics

| Step | Component | Latency Budget | Security Control |
|---|---|---|---|
| TLS Termination | Gateway | < 2ms | TLS 1.3, HSTS, mTLS between services |
| AuthN/AuthZ | OAuth2 Proxy | < 100ms | OIDC + Dex + RBAC mapping |
| WAF Inspection | CloudFront | < 50ms | OWASP CRS 3.3, rate limiting |
| Mesh Routing | Envoy | < 2ms | mTLS, AuthorizationPolicy, PeerAuthentication |
| App Processing | Application | < 500ms | Pod Security Policy, seccomp, readOnlyRootFilesystem |

---

## 2. GitOps Delivery Lifecycle

The complete path from a developer's commit to a running application pod in production, driven entirely through Git.

```mermaid
sequenceDiagram
    participant DEV as Developer
    participant GIT as GitHub Repository
    participant CI as GitHub Actions CI
    participant REG as Amazon ECR
    participant SBOM as SBOM Service (Syft)
    participant SIGN as Cosign Signer
    participant ARGO as ArgoCD
    participant K8S as Kubernetes Cluster
    participant KYV as Kyverno

    DEV->>GIT: 1. git push (feature branch)
    GIT->>CI: 2. Webhook trigger: push event
    CI->>CI: 3. Checkout, lint, unit tests
    CI->>CI: 4. Build container image
    CI->>CI: 5. Run Trivy vulnerability scan
    alt Scan fails (CRITICAL/HIGH)
        CI-->>DEV: 6. Fail pipeline; notify developer
    else Scan passes
        CI->>SBOM: 7. Generate SPDX-2.3 SBOM
        SBOM->>SIGN: 8. Sign image & SBOM (keyless Sigstore)
        SIGN->>REG: 9. Push signed image:tag
        SIGN->>REG: 10. Attach SBOM as OCI artifact
        CI->>GIT: 11. Update k8s manifest with new image digest
        DEV->>GIT: 12. Open PR to main branch
        GIT->>GIT: 13. PR checks: policy-bot, DCO, required reviews
        GIT->>CI: 14. Merge to main → trigger deploy pipeline
        CI->>GIT: 15. Update ArgoCD app-of-apps manifest
        GIT-->>ARGO: 16. Commit change to config repo
        ARGO->>ARGO: 17. Detect drift (desired vs. live state)
        ARGO->>KYV: 18. Submit resource for admission
        KYV->>KYV: 19. Evaluate 30+ policy rules
        KYV->>KYV: 20. Verify Cosign signature on image
        KYV->>KYV: 21. Verify SBOM attestation
        alt Policy violation
            KYV-->>ARGO: 22. Admission denied (ValidatingWebhook)
            ARGO-->>DEV: 23. Sync failure notification
        else All policies pass
            KYV-->>ARGO: 24. Admission allowed
            ARGO->>K8S: 25. Apply manifest (rolling update)
            K8S->>K8S: 26. Pod readiness probe, liveness probe
            K8S-->>ARGO: 27. Health check PASS
            ARGO-->>DEV: 28. Sync complete; application healthy
        end
    end
```

### Delivery Cadence Specifications

| Stage | Duration (Target) | Automation Level |
|---|---|---|
| Code push to CI trigger | < 5s | Fully automated |
| CI build + scan | < 3 minutes | Fully automated |
| SBOM generation + sign | < 30s | Fully automated |
| PR review cycle | < 4 hours | Human-in-loop (policy-bot auto-approve for low-risk) |
| ArgoCD sync + admission | < 60s | Fully automated |
| Pod readiness | < 30s | Health checks |
| **Total (commit to pod)** | **< 2 hours** (target: < 15 min for critical patches) | |

---

## 3. Secure SDLC Flow

Every commit passes through a gauntlet of automated security checks before reaching production.

```mermaid
sequenceDiagram
    participant DEV as Developer
    participant GIT as GitHub
    participant LINT as Linter + Secrets Scan
    participant SAST as SAST (Semgrep)
    participant SCA as SCA (Trivy)
    participant DAST as DAST (ZAP)
    participant SIGN as Cosign + SBOM
    participant DEP as Deploy (ArgoCD)

    DEV->>GIT: 1. Commit code
    GIT->>LINT: 2. Pre-commit hook: gitleaks + eslint/golangci-lint
    LINT-->>DEV: 3. Reject if secrets detected
    GIT->>SAST: 4. CI stage: Semgrep (custom & pro rules)
    SAST-->>DEV: 5. Fail on blocking rules (RCE, SQLi, path traversal)
    GIT->>SCA: 6. CI stage: Trivy filesystem scan (OS + library vulns)
    SCA-->>DEV: 7. Fail on CRITICAL + HIGH (30-day SLA for MEDIUM)
    GIT->>DAST: 8. Deploy to ephemeral env → ZAP baseline scan
    DAST-->>DEV: 9. Fail on HIGH-risk findings
    GIT->>SIGN: 10. All gates passed → build, sign, atttach SBOM
    SIGN-->>GIT: 11. Signed digest: sha256:abc...
    GIT->>DEP: 12. Deploy to staging → integration tests
    DEP->>DEP: 13. Integration tests pass → promote to production
    DEP->>GIT: 14. Tag release: v1.2.3-rc.1 → GA

    Note over LINT,SIGN: Shift-left: 95% of vulnerabilities caught before build
```

### Security Gate Configuration

| Gate | Tool | Blocking Threshold | Exceptions |
|---|---|---|---|
| Secret Leakage | Gitleaks | Any secret-like pattern | False-positive review within 24h |
| SAST | Semgrep | RCE, SQLi, OS Command, Path Traversal | None; must fix before merge |
| SCA | Trivy | CRITICAL or HIGH with fix available | 7-day SLA with approved exception |
| Image Signing | Cosign | Unsigned image → reject at admission | None in production namespaces |
| SBOM Attestation | Syft + Cosign | Missing or malformed SBOM | None; must regenerate |

---

## 4. Incident Response Flow

When Falco detects a runtime anomaly, the platform's AI-driven incident response pipeline activates.

```mermaid
sequenceDiagram
    participant F as Falco Agent (Node)
    participant T as Falco Talon
    participant AI as AIOps API (FastAPI)
    participant LC as LangChain Reasoner
    participant V as pgvector
    participant G as Grafana
    participant S as Slack/PagerDuty
    participant K as Kubernetes API
    participant H as Human SRE (escalation)

    F->>F: 1. Monitor syscalls (eBPF)
    F->>T: 2. Detect: "Unexpected outbound connection" (rule: 500+)
    T->>AI: 3. Emit enriched event (JSON with container_id, ns, process, fd)
    AI->>AI: 4. Normalize to unified event schema
    AI->>AI: 5. Compute embedding vector (sentence-transformers)
    AI->>V: 6. Store embedding + metadata
    AI->>V: 7. Query: cosine similarity to past incidents
    V-->>AI: 8. Top-5 similar incidents + their remediations
    AI->>LC: 9. Forward event + historical context
    LC->>LC: 10. Build chain-of-thought prompt
    LC->>LC: 11. Invoke LLM (Llama 3 local for sensitive data)
    LC-->>AI: 12. RCA hypothesis: "Container xyz:latest making connection to known C2 IP 198.51.100.10"
    AI->>AI: 13. Compute risk score (blast radius × severity × confidence)

    alt Risk Score < 0.3 (Low Risk)
        AI->>K: 14a. Automated action: Isolate pod via NetworkPolicy
        K-->>AI: 15a. NetworkPolicy applied
        AI->>G: 16a. Create annotated dashboard panel
        AI->>S: 17a. Send summary: "Pod isolated. Confidence: 92%"
    else Risk Score 0.3–0.7 (Medium Risk)
        AI->>K: 14b. Automated action: Add taint + cordon node
        AI->>S: 15b. Alert: "Node cordoned. Awaiting human confirmation for pod eviction"
    else Risk Score > 0.7 (High Risk)
        AI->>H: 14c. Escalate to on-call SRE via PagerDuty
        AI->>S: 15c. Alert: "🚨 Critical: potential C2 communication. Action required."
        H->>AI: 16c. Acknowledge → approve/reject remediation
        AI->>K: 17c. Execute approved remediation
    end

    AI->>V: 18. Store full incident record (event, RCA, action, outcome)
```

### Incident Response SLA

| Severity | Detection | AI Correlation | Automated Response | Human Escalation |
|---|---|---|---|---|
| **Critical** (C2, privilege esc) | < 5s | < 15s | < 30s | Immediate |
| **High** (crypto miner, data exfil) | < 10s | < 30s | < 60s | < 2 min |
| **Medium** (policy violation, unusual traffic) | < 30s | < 2 min | < 5 min | < 10 min |
| **Low** (info, best practice) | < 60s | N/A | Logged | Batched daily |

---

## 5. AI Correlation Workflow

The system ingests multi-modal telemetry and performs unsupervised learning to identify incident patterns.

```mermaid
sequenceDiagram
    participant P as Prometheus (Metrics)
    participant O as OTel Collector (Traces)
    participant F as Falco (Events)
    participant I as AIOps Ingestion API
    participant E as Embedding Service
    participant V as pgvector
    participant C as Clustering Engine (DBSCAN)
    participant L as LangChain Reasoner

    loop Every 30s (batch window)
        P->>I: 1a. Push alert events (webhook)
        O->>I: 1b. Push trace samples (tail-based)
        F->>I: 1c. Push anomaly events (talon webhook)
        I->>I: 2. Normalize into unified Event schema
        I->>E: 3. Batch of 10–100 events → request embeddings
        E->>E: 3a. Model: sentence-transformers/all-MiniLM-L6-v2
        E->>V: 4. Store [event_id, embedding(1536d), metadata, timestamp]
        I->>C: 5. Request clustering on recent window (last 15 min)
        C->>V: 6. Query recent embeddings (< 15 min)
        V-->>C: 7. 100–500 vectors
        C->>C: 8. DBSCAN (eps=0.5, min_samples=3)
        C-->>I: 9. Cluster assignments: cluster_id per event_id
        I->>I: 10. Identify unresolved clusters (no prior root cause)
        I->>L: 11. For each novel cluster → request RCA
        L->>L: 12. Build aggregated context from cluster members
        L->>V: 13. Query historical incidents for similarity
        L->>L: 14. Chain-of-thought reasoning
        L-->>I: 15. RCA hypothesis + confidence score
        I->>V: 16. Store RCA as incident record
        I->>I: 17. Optionally trigger remediation (see flow 4)
    end
```

### Embedding Strategy

| Telemetry Type | Input Features | Embedding Model | Dimensionality |
|---|---|---|---|
| Prometheus Alert | rule_name, labels, annotations, severity, timestamp | MiniLM-L6-v2 | 1536 |
| Falco Event | rule, priority, container_id, process, fd, syscall | MiniLM-L6-v2 | 1536 |
| OTel Trace | service_name, operation, error_type, duration_ms, status_code | MiniLM-L6-v2 | 1536 |
| Incident Record | RCA summary, remediation, affected_services, resolved_by | BAAI/bge-small-en-v1.5 | 384 |

---

## 6. Self-Healing Workflow

Automated remediation workflow triggered when an anomaly is detected and the risk score is below the automated-action threshold.

```mermaid
sequenceDiagram
    participant M as Monitoring (Prom/Grafana)
    participant AI as AIOps API
    participant LC as LangChain Reasoner
    participant K as Kubernetes API
    participant A as ArgoCD
    participant L as Logging Stack

    M-->>AI: 1. Alert: "High error rate (5.5% > SLO 1%) on svc:checkout"
    AI->>LC: 2. Enriched alert → request RCA + remediation plan
    LC->>LC: 3. Analyze: error_rate > threshold, p95_latency > 2000ms, pod OOMKill events
    LC-->>AI: 4. Hypothesis: "Pod memory leak in checkout:v2.1.0"
    LC-->>AI: 5. Recommendation: "Increase memory limit from 256Mi to 512Mi and rollout restart"
    AI->>AI: 6. Validate: risk score < 0.3 (config change, reversible)
    AI->>K: 7. Execute: Patch Deployment checkout memory limit
    K-->>AI: 8. Deployment patched
    AI->>A: 9. Trigger: Force ArgoCD sync (bypass reconciliation delay)
    A->>A: 10. Rolling restart of checkout pods
    A-->>AI: 11. Sync complete; 3/3 pods healthy
    AI->>M: 12. Monitoring: error rate trending down (3.2% → 1.8% → 0.9%)
    M-->>AI: 13. Confirm: error rate within SLO after 5 min
    AI->>L: 14. Log: Full incident report, action taken, outcome, duration
    AI->>AI: 15. Update risk model: similar patterns → lower threshold for auto-remediation

    Note over AI,LC: Healing cycle target: < 5 minutes from alert to resolution
```

### Self-Healing Action Catalog

| Action | Risk Score Threshold | Reversible | Approval Required |
|---|---|---|---|
| Increase resource limits | < 0.3 | Yes | No (auto) |
| Restart Deployment (rollout) | < 0.5 | Yes | No (auto) |
| Scale replicas (HPA override) | < 0.4 | Yes | No (auto) |
| NetworkPolicy isolation | < 0.3 | Yes | No (auto) |
| Rollback to previous revision | < 0.4 | Yes | No (auto) |
| Cordon/Drain node | < 0.6 | Yes | Human approval |
| Patch Ingress/WAF rule | < 0.5 | Yes | Human approval |
| Delete malicious pod | < 0.2 | No | Human approval |
| Scale down entire service | < 0.2 | Yes | Human approval |
| Modify RBAC/ClusterRole | N/A | Yes | Mandatory human approval |
