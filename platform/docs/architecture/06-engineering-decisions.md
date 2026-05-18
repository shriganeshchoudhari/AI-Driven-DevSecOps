# Engineering Decision Log: AI-Driven Secure GitOps Kubernetes Platform

## Document Control

| Attribute | Value |
|---|---|
| **Document ID** | ARC-DEC-006 |
| **Version** | 1.0 |
| **Classification** | Internal — Engineering |
| **Author** | Platform Architecture Team |
| **Last Updated** | 2026-05-17 |

---

## 1. ADR-001: Kubernetes Distribution — Amazon EKS

| Field | Value |
|---|---|
| **Status** | **Accepted** |
| **Decision Date** | 2026-02-15 |
| **Deciders** | Platform Architecture, CloudOps, Security |
| **Last Reviewed** | 2026-05-17 |

### Context

We needed a Kubernetes distribution that supports multi-AZ HA, IAM integration, FIPS compliance, and managed control plane operations. The platform targets regulated enterprises with SOC 2/PCI-DSS requirements.

### Options Considered

| Option | Pros | Cons |
|---|---|---|
| **Amazon EKS** | Managed control plane (99.95% SLA); native IAM (IRSA); KMS integration for etcd encryption; EBS/EFS CSI drivers; Graviton support; Kubernetes原生 upgradd; AWS PrivateLink for API isolation | $0.10/hr per cluster control plane; version upgrade requires some manual steps |
| **Self-Managed (kubeadm)** | No control plane cost; full control over etcd/API server versions | Operational burden (etcd backup, control plane HA, cert rotation, patching); no IAM integration; SOC 2 audit scope larger |
| **AKS (Azure)** | If in Azure, superior integration | Not in Azure; no cross-cloud strategy for this platform |
| **GKE (Google Cloud)** | Auto-pilot mode; advanced networking | Not in GCP; different IAM model (Workload Identity) |
| **OpenShift** | Built-in security features (SCC); operator hub | Higher cost ($3K+/cluster/year); proprietary APIs; vendor lock-in |
| **Rancher/RKE2** | Multi-cluster management UI | Adds operational complexity; not as mature for managed control planes |

### Decision

**Amazon EKS** — with the following specific configuration:
- Kubernetes 1.30+
- EKS-managed node groups for system components; Karpenter for tenant workloads
- IRSA for all pod-to-AWS IAM
- KMS-backed etcd encryption
- Private API server endpoint (no public access)
- Cluster endpoint accessible only via AWS PrivateLink from hub VPC

### Consequences

- **Positive**: Reduced operational burden; strong audit trail via CloudTrail for control plane operations; native IAM integration simplifies secrets management; FIPS-validated crypto modules available.
- **Negative**: $0.10/hr per cluster (~$876/yr for prod, plus per-cluster costs for staging/dev); EKS version upgrades require some planning (we use a blue/green cluster migration strategy for major versions).

---

## 2. ADR-002: GitOps Operator — ArgoCD

| Field | Value |
|---|---|
| **Status** | **Accepted** |
| **Decision Date** | 2026-02-20 |
| **Deciders** | Platform Architecture, DevOps |

### Context

The GitOps operator is the core of the delivery pipeline. It must support multi-cluster, multi-tenant, App-of-Apps patterns, and deep integration with Helm/Kustomize. It must also provide a robust audit trail and support for progressive delivery.

### Options Considered

| Option | Pros | Cons |
|---|---|---|
| **ArgoCD 2.12+** | Multi-cluster (cluster registration secrets); App-of-Apps; native Helm/Kustomize/Jsonnet support; RBAC with OIDC; SSO (Dex, Okta, Google); sync waves; hooks; automated drift detection; 450+ contributors; CNCF graduated | Complex upgrade path for major versions; Redis HA required for production |
| **Flux v2** | Simpler CRD model (Kustomization, GitRepository); no separate DB (uses K8s secrets); built-in OCI support; Source Controller; CNCF graduated | Less mature SSO/RBAC; fewer progressive delivery features; smaller community |
| **Jenkins X** | Pipeline-centric (Lighthouse/Tekton); preview environments | Heavier weight; couples CI to CD; declining community velocity; over-engineered for our needs |
| **Helm Operator (Flux v1)** | Deprecated | Deprecated |
| **Manual kubectl apply** | Simple | No drift detection; no audit trail; no rollback automation; error-prone |

### Decision

**ArgoCD** — with the following architecture:
- **Management cluster**: Single ArgoCD instance managing 10+ workload clusters via cluster registration secrets stored in AWS Secrets Manager (synced via ESO)
- **App-of-Apps**: A root Application (`bootstrap`) that syncs `applicationset.yaml` which generates Applications per repository path
- **Drift detection**: 3-minute polling + webhook events
- **Auto-heal**: Enabled (but gated: only for production namespaces; staging/dev auto-heal disabled for learning)
- **Sync waves**: Platform CRDs (Phase 0) → Security policies (Phase 1) → Platform services (Phase 2) → Tenant apps (Phase 3)
- **Prune**: Enabled (but requires admin annotation for production namespaces)

### Consequences

- **Positive**: Battle-tested at massive scale (Adobe, Ticketmaster, Intuit use ArgoCD with 1000+ apps); rich RBAC model maps naturally to our multi-team structure; sync waves ensure dependency ordering.
- **Negative**: Must maintain Redis HA for ArgoCD cache; ArgoCD versions > 2.10 require careful migration of project roles; Redis Sentinel vs. Redis Cluster decision adds operational complexity.

---

## 3. ADR-003: Observability Stack — Prometheus + Grafana + OpenTelemetry

| Field | Value |
|---|---|
| **Status** | **Accepted** |
| **Decision Date** | 2026-02-25 |
| **Deciders** | Platform Architecture, SRE |

### Context

We needed a unified observability strategy spanning metrics, logs, and traces with the ability to feed the AIOps subsystem. Requirements: 30-day retention, multi-cluster aggregation, integration with AI pipeline, and cost predictability.

### Options Considered

| Option | Pros | Cons |
|---|---|---|
| **Prometheus + Grafana + OTel** | CNCF graduated; self-managed (cost-predictable); no per-series cost; PromQL is industry standard; OTel is vendor-neutral; Thanos for long-term storage; massive community | Operational overhead (Thanos compactor, store gateways); no built-in log management (needs Loki); requires significant tuning for scale |
| **Datadog** | Best-in-class UX; out-of-the-box dashboards; APM + logs + metrics in one UI; ML-based anomaly detection built-in | $15-23/host/month for Pro (10 hosts = $2,300+/month); vendor lock-in; data egress costs; per-index log pricing unpredictable |
| **Grafana Cloud** | Managed Grafana + Mimir (metrics) + Loki (logs) + Tempo (traces); no operational burden; 14-day free tier | $50/series/month for pro; vendor lock-in; data residency concerns; cost grows linearly with ingestion volume |
| **New Relic** | Good APM; AI-powered alerting | Expensive at scale ($0.55/GB ingested for logs); fewer K8s-native integrations |
| **Dynatrace** | Davis AI automates root cause analysis; excellent K8s support | High cost ($69/host/month); proprietary query language; heavy agent overhead |

### Decision

**Prometheus + Grafana + OpenTelemetry** — with Thanos for long-term retention:
- **Metrics**: Prometheus Operator (kube-prometheus-stack) with Thanos sidecar → S3 (30-day retention in Prometheus TSDB, 180-day in S3)
- **Logs**: Grafana Loki (distributed, S3-backed) — 30-day hot retention, 365-day cold
- **Traces**: OpenTelemetry Collector (tail-based sampling, 10% of low-error traces, 100% of error traces) → Tempo backend (S3-backed, 30-day retention)
- **AI integration**: OTel Collector forwards all error spans and high-cardinality metrics to AIOps API via gRPC

### Consequences

- **Positive**: Full control over data retention and costs; no per-series pricing; OTel standard enables future provider swaps; AI pipeline gets all three signals (metrics, logs, traces) for correlation.
- **Negative**: Team must learn to operate Thanos + Loki + Tempo (significant learning curve); initial tuning required for cardinality explosion prevention; no single-pane-of-glass out of the box (Grafana UI ties it together but experience varies).

---

## 4. ADR-004: AIOps Framework — FastAPI + LangChain

| Field | Value |
|---|---|
| **Status** | **Accepted** |
| **Decision Date** | 2026-03-01 |
| **Deciders** | Platform Architecture, ML/AI Team |

### Context

The AIOps intelligence layer requires a lightweight, Python-native API framework for event ingestion, combined with a flexible LLM orchestration engine for chain-of-thought reasoning. The solution must support local (on-premise) and cloud LLM routing based on data sensitivity, and must fit within Kubernetes resource constraints.

### Options Considered

| Option | Pros | Cons |
|---|---|---|
| **FastAPI + LangChain** | Async-native (high throughput for event ingestion); LangChain provides chain-of-thought, RAG, tool-use out of the box; routes to 40+ LLM providers; lightweight (no JVM overhead); great Pydantic integration for event schema validation | LangChain upgrades sometimes break APIs (mitigated by pinning versions); Python GIL limits CPU-bound embedding computation (offloaded to separate service); relatively new ecosystem (v0.3+ stable) |
| **Node.js/Express + LangChain.js** | JavaScript ecosystem; async-native | LangChain.js is behind Python version; weaker typing for data processing; less mature agent/tool support |
| **Go + custom LLM client** | High performance; single binary deployment | No mature LLM orchestration framework (must build chain-of-thought from scratch); significantly more development effort for equivalent functionality |
| **Golang + Haystack (canopy)** | Haystack has RAG pipelines; typed | Haystack Python-centric; Golang support experimental; smaller community |
| **Python + Semantic Kernel (Microsoft)** | Good Azure integration; enterprise support | Tight coupling to Azure OpenAI; Python SDK less mature than .NET; fewer community integrations |

### Decision

**FastAPI + LangChain** — with the following architecture:
- **FastAPI**: Serves as event ingestion gateway (5K events/sec target); 3 replicas; async worker model with Uvicorn
- **LangChain**: Runs reasoning chains (chain-of-thought, context retrieval, RCA hypothesis generation)
- **Embedding Service**: Separate microservice (sentence-transformers/all-MiniLM-L6-v2) to avoid GIL contention
- **LLM Routing**: Sensitive data → local Llama 3 (70B via vLLM on GPU node); non-sensitive → GPT-4o via Azure OpenAI
- **Vector Store**: pgvector (PostgreSQL extension) — co-located with operational DB to reduce operational complexity
- **Anomaly Clustering**: Separate Python service using scikit-learn DBSCAN; triggered every 30s on sliding window

### Consequences

- **Positive**: FastAPI provides excellent throughput (benchmarked at 8K req/s on 2 vCPUs); LangChain abstraction allows swapping LLM providers without code changes; Pydantic models ensure event schema validation at ingress.
- **Negative**: Must manage Python dependency drift (pinned with `poetry.lock`); embedding service requires separate scaling from API; LangChain tool-calling API changes require active monitoring of changelog.

---

## 5. ADR-005: Supply Chain Security — Cosign + Kyverno

| Field | Value |
|---|---|
| **Status** | **Accepted** |
| **Decision Date** | 2026-03-05 |
| **Deciders** | Platform Architecture, Security Engineering |

### Context

The platform must enforce image provenance, signature verification, and vulnerability scanning at multiple points in the pipeline. Key requirements: keyless signing (no long-lived signing keys), OCI artifact attachment (SBOM as attestation), and admission-time enforcement.

### Options Considered

| Option | Pros | Cons |
|---|---|---|
| **Cosign (Sigstore) + Kyverno** | Keyless signing via OIDC (no key management); transparency log (Rekor) creates immutable record; Sigstore is CNCF sandbox; Kyverno native Cosign integration (`verifyImage` rule); attaches SBOM as in-toto attestation; free public instance | Public Rekor log may expose metadata (private Sigstore instance for regulated workloads); keyless signing requires network access to Fulcio/OIDC provider |
| **Notation + Notary** | OCI 1.1 spec; used by Microsoft; Docker Desktop built-in support | No keyless signing (requires x509 key management); no built-in transparency log; smaller ecosystem |
| **Docker Content Trust** | Simple (Docker Engine built-in) | Server-side only; no admission enforcement; no SBOM support; effectively deprecated |
| **TUF + in-toto** | Comprehensive framework; used by The Update Framework | Overkill for our use case; significant implementation effort; Python-heavy tooling |

### Decision

**Cosign (Sigstore) + Kyverno** — with the following specifics:
- **Keyless signing**: Each CI job signs images using the OIDC token from GitHub Actions (no stored keys)
- **Private Sigstore**: Deployed private Fulcio + Rekor within the VPC for regulated workloads; public Sigstore for non-sensitive
- **SBOM attestation**: Cosign attaches SPDX-2.3 SBOM as in-toto predicate (`cosign attach attestation --type spdx`)
- **Admission**: Kyverno `ClusterPolicy` enforces `verifyImage` with `attestations` check:

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-image-signature
spec:
  validationFailureAction: Enforce
  rules:
  - name: verify-image
    match:
      any:
      - resources:
          kinds: ["Pod"]
    verifyImages:
    - imageReferences: ["*"]
      attestors:
      - count: 1
        entries:
        - keyless:
            subject: "https://github.com/org/repo/.github/workflows/ci.yml@refs/heads/main"
            issuer: "https://token.actions.githubusercontent.com"
            rekor:
              url: https://rekor.internal.platform
      attestations:
      - type: https://spdx.dev/Document
        predicate:
          fields:
          - key: packages
            operator: NotEquals
            value: []
```

### Consequences

- **Positive**: No long-lived signing keys to rotate or compromise; private Sigstore ensures metadata stays internal; Kyverno `verifyImage` is a one-line policy for signature enforcement; SBOM attestation provides full supply-chain transparency.
- **Negative**: Must operate private Fulcio + Rekor (additional infrastructure); keyless signing fails gracefully (CI job fails if OIDC token cannot be resolved — mitigated with retry logic); SBOM attestation increases image push time by ~10s.

---

## 6. ADR-006: Configuration Packaging — Helm + Kustomize

| Field | Value |
|---|---|
| **Status** | **Accepted** |
| **Decision Date** | 2026-03-02 |
| **Deciders** | Platform Architecture, DevOps |

### Context

The platform needs a layered configuration strategy that separates base charts (upstream) from environment-specific overlays. Must support multi-tenant, multi-environment, and multi-cluster configurations without duplication.

### Options Considered

| Option | Pros | Cons |
|---|---|---|
| **Helm + Kustomize** | Helm provides sophisticated templating + dependency management + rollback; Kustomize provides pure-YAML overlays (no templating required) for environment deltas; ArgoCD supports both natively; Kustomize supports `helmChartInflationGenerator` | Two tools to learn; occasional confusion about which concern belongs to which tool; Helm charts from third parties may not follow best practices |
| **Helm-only** | Single tool; post-renderer for custom logic | Environment overlays require complex `values.yaml` inheritance; no easy patching of third-party chart values mid-object |
| **Kustomize-only** | Pure YAML (easy for platform engineers); no templating complexity | Limited conditional logic; no package management; no dependency resolution; no versioned chart distribution from upstream |
| **Jsonnet** | Powerful functional language; Tanka for K8s deployment | Steep learning curve; smaller community; not natively supported by ArgoCD |
| **CDK8s** | TypeScript/Python for K8s manifests | Brings entire Node.js or Python runtime into config generation; overkill for YAML-native teams |

### Decision

**Helm + Kustomize** — with the following convention:

```
charts/
  base/                          # Upstream Helm chart (pinned version)
    Chart.yaml
    values.yaml
  overlays/
    production/
      kustomization.yaml         # patches, namePrefix, namespace, images
      values-production.yaml     # environment-specific values
    staging/
      kustomization.yaml
      values-staging.yaml
    dev/
      kustomization.yaml
      values-dev.yaml
  platforms/                     # Platform components use the same pattern
    argocd/
      base/
      overlays/
    kyverno/
      base/
      overlays/
    aio-api/
      base/
      overlays/
```

- **Helm** handles: chart packaging, dependency resolution, `values.yaml` schema validation, `--dry-run`, rollback history
- **Kustomize** handles: environment overlays, name prefixing/suffix, common labels, image tag mutations, namespace assignment, configMapGenerator/secretGenerator

### Consequences

- **Positive**: Clear separation of concerns (Helm for chart logic, Kustomize for environment plumbing); ArgoCD syncs Kustomize output directly; `helmChartInflationGenerator` allows using Helm charts as Kustomize inputs.
- **Negative**: Requires both tools in CI/CD pipelines; team must learn both syntaxes; Kustomize `patches` JSON patch syntax has a learning curve for new team members.

---

## 7. ADR-007: Multi-Tenancy and Namespace Isolation

| Field | Value |
|---|---|
| **Status** | **Accepted** |
| **Decision Date** | 2026-03-10 |
| **Deciders** | Platform Architecture, Security Engineering |

### Context

Multiple development teams share the same EKS cluster. We need strong isolation between tenants with clear resource quotas, RBAC boundaries, and network policies. The isolation model must be expressed as code and enforced by the admission controller.

### Options Considered

| Option | Pros | Cons |
|---|---|---|
| **Namespaces + Kyverno generate rules** | No additional CRDs or controllers; namespaces are native K8s primitives; Kyverno auto-generates RoleBindings, NetworkPolicies, ResourceQuotas per namespace | Teams share the same cluster control plane; noisy neighbor risk from a single PodSecurityPolicy mutation (though Kyverno enforces PSS on all namespaces); `kubectl get nodes` leak |
| **vCluster (virtual clusters)** | Each team gets a virtual control plane; full API isolation; independent CRDs and controllers | Resource overhead (each vCluster runs apiserver + controller manager); no support for NodePort or LoadBalancer services in all modes; harder to debug cross-cutting issues |
| **Capsule (project CRD)** | Multi-tenant operator; creates namespaces as "tenants" with RBAC scoping; resource quota aggregation across namespaces | Adds another CRD operator; less adoption than native K8s patterns; overlaps with Kyverno generate rules |
| **Kiosk (Loft)** | Rich multi-tenant dashboard; namespace-as-a-service | License cost for advanced features; adds third-party control plane; vendor lock-in |

### Decision

**Namespaces + Kyverno policy generation** — with the following approach:

- **Tenant onboarding**: Team submits a `Tenant` CR (custom resource) with spec containing: `name`, `environment`, `teamMembers`, `resourceLimits`, `networkPolicies`
- **Kyverno generate rules**: Automatically create from the `Tenant` CR:
  - 3 namespaces: `team-{name}-dev`, `team-{name}-staging`, `team-{name}-prod`
  - RoleBindings for each team member (scoped to their namespaces)
  - ResourceQuota per namespace
  - LimitRange per namespace
  - NetworkPolicy (default-deny ingress + allowed ingress from istio-system)
  - PodSecurityStandard (enforced: restricted)
- **Cluster-level isolation**:
  - `kubectl get nodes` blocked for all tenant roles (ClusterRole: `system:aggregated-to-view` stripped of node access)
  - `kubectl get clusterroles/clusterrolebindings` blocked for non-platform team members
  - PriorityClasses prevent tenant pods from preempting system pods

### Consequences

- **Positive**: Native K8s primitives (no additional controller dependencies); Kyverno's `generate` rules enforce consistency; onboarding is a single `Tenant` CR submission; isolation is auditable via standard K8s RBAC review tools.
- **Negative**: All tenants share the cluster control plane (API server, etcd) — mitigated by API server rate limiting and PriorityClasses; resource quota conflicts require manual resolution by platform team; `Tenant` CR must be created by platform admin only (RBAC prevents tenant self-service of the CR).

---

## 8. ADR-008: Secret Management — External Secrets Operator

| Field | Value |
|---|---|
| **Status** | **Accepted** |
| **Decision Date** | 2026-03-08 |
| **Deciders** | Platform Architecture, Security Engineering |

### Context

The platform must manage secrets across GitOps, AIOps, observability, and tenant workloads without embedding secrets in Git. Requirements include automatic rotation, IAM-backed access, and audit logging.

### Options Considered

| Option | Pros | Cons |
|---|---|---|
| **External Secrets Operator (ESO) + AWS Secrets Manager** | Native K8s CRDs (`ExternalSecret`, `ClusterSecretStore`); IRSA integration; automatic refresh of K8s Secret when source changes; supports PushSecret for workloads that generate secrets; large community (CNCF incubating) | Secrets Manager costs $0.40/secret/month + $0.05/10K API calls; rotation requires Lambda functions for auto-rotation |
| **Sealed Secrets (Bitnami)** | Encrypt secrets in Git; no external dependency; simple to deploy | Encryption key management; no automatic rotation; sealed secret cannot be inspected before deploy; not suitable for high-rotation secrets |
| **SOPS + Mozilla sops** | Encrypt individual values in YAML; Git-native; ArgoCD has sops plugin | No secret rotation; decryption key must be available at deploy time; no audit trail for secret access |
| **Hashicorp Vault** | Full secret management platform; dynamic secrets; leasing; rotation | Heavy operational burden (Vault cluster, storage backend, unsealing); overkill for our use case |

### Decision

**External Secrets Operator (ESO) + AWS Secrets Manager** — configured as:

- **ClusterSecretStore**: Points to AWS Secrets Manager with IRSA authentication (`external-secrets-sa` ServiceAccount)
- **ExternalSecret CRD**: Each team creates `ExternalSecret` in their namespace referencing the Secrets Manager ARN:
- **Refresh interval**: 1 hour (can be polled more frequently for high-rotation secrets)
- **PushSecret**: For AIOps API that generates API keys for tenant ingestion endpoints

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-credentials
  namespace: tenant-checkout-prod
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secretsmanager
    kind: ClusterSecretStore
  target:
    name: db-credentials  # K8s Secret name
    creationPolicy: Owner
  data:
  - secretKey: username
    remoteRef:
      key: /platform/tenant/checkout/prod/db
      property: username
  - secretKey: password
    remoteRef:
      key: /platform/tenant/checkout/prod/db
      property: password
```

### Consequences

- **Positive**: No secrets in Git; automatic synchronization when Secrets Manager value changes; full audit trail via CloudTrail (who accessed which secret when); integration with AWS KMS for encryption at rest.
- **Negative**: Dependency on AWS Secrets Manager (not portable to other clouds — mitigated by ClusterSecretStore abstraction); API costs at scale (mitigated by caching); secrets deleted in Secrets Manager will cause K8s Secret deletion (mitigated by `creationPolicy: Owner` and retention rules).

---

## 9. ADR-009: API Gateway / Ingress — Istio Gateway API

| Field | Value |
|---|---|
| **Status** | **Accepted** |
| **Decision Date** | 2026-03-12 |
| **Deciders** | Platform Architecture, Networking |

### Context

The platform requires advanced traffic management (canary, A/B, header-based routing), mTLS between all services, and deep telemetry integration. We evaluated the Kubernetes Gateway API standard versus the Ingress API versus service mesh ingress.

### Options Considered

| Option | Pros | Cons |
|---|---|---|
| **Istio + Gateway API** | mTLS (STRICT) for all mesh traffic; fine-grained traffic splitting (canary, mirror, header-match); rich telemetry (Envoy access logs → OTel); AuthorizationPolicy for L7 authz; Gateway API is the emerging K8s standard; Envoy is battle-tested | Adds 10-15% more resource overhead vs. nginx (istiod + Envoy sidecars); learning curve for Gateway API CRDs; turning on mTLS can break non-mesh services |
| **nginx-ingress** | Simple; widely used; low resource overhead | No mTLS between services; limited traffic splitting; no L7 authz; no deep telemetry; not suitable for zero-trust architecture |
| **AWS ALB Ingress Controller** | Native AWS integration; WAF integration at ALB; simple to set up | No mTLS; no advanced traffic management; per-ALB cost adds up; not portable off AWS |
| **Kong / Traefik** | Rich plugin ecosystem; good API gateway features | One more operator to manage; neither provides service-to-service mTLS; less K8s-native than Istio |

### Decision

**Istio + Gateway API** — with the following specifics:
- **mTLS mode**: STRICT (no PERMISSIVE fallback)
- **Ingress**: Istio Gateway (single `Gateway` CR per cluster; routing via `HTTPRoute` CRDs)
- **Authorization**: Istio `AuthorizationPolicy` at mesh level (default-deny) + per-workload allow rules
- **Telemetry**: Envoy emits structured access logs to OpenTelemetry Collector via the Envoy OTel access log sink
- **Canary deployments**: `HTTPRoute` weight-based traffic splitting (5% → 50% → 100% over 30 minutes)

### Consequences

- **Positive**: mTLS eliminates credential sniffing attack surface; fine-grained traffic management supports progressive delivery; AuthorizationPolicy enables zero-trust at L7; telemetry integration feeds directly into AIOps.
- **Negative**: Envoy sidecar adds 50-100MB per pod and 1-2ms P99 latency; team must learn Gateway API and Istio CRDs (mitigated by template library); Istio upgrades require careful planning (envoy proxy version must match istiod).

---

## 10. ADR-010: Database Strategy — PostgreSQL with pgvector

| Field | Value |
|---|---|
| **Status** | **Accepted** |
| **Decision Date** | 2026-03-15 |
| **Deciders** | Platform Architecture, Data Engineering |

### Context

The AIOps subsystem needs a vector database for embedding storage and similarity search. The platform also needs a relational database for incident metadata, audit logs, and configuration. We evaluated dedicated vector databases vs. extending PostgreSQL.

### Options Considered

| Option | Pros | Cons |
|---|---|---|
| **PostgreSQL + pgvector** | Single database for relational + vector workloads; standard PostgreSQL tooling (pg_dump, WAL, replicas, patroni); no new infrastructure; pgvector supports IVFFlat and HNSW indexes; well-maintained extension | Vector search performance trails Pinecone/Weaviate at >1M vectors (mitigated by our scale: ~100K vectors/day); no built-in hybrid search without additional extensions |
| **Pinecone (managed)** | Best vector search performance; fully managed; high recall | $0.10/GB/hour for pod-based index; data residency concerns; vendor lock-in; must manage RAG pipeline integration |
| **Weaviate (self-hosted)** | Built-in vectorizer modules; hybrid search (BM25 + vector); good performance | Adds operational burden (stateful cluster); another database to back up; smaller ecosystem than PostgreSQL |
| **Redis Stack + Redisearch** | In-memory speed; vector similarity support | RAM cost at scale ($8/GB/month for RDS is cheaper than Redis memory); no persistence guarantees; not suitable as primary data store |
| **Milvus** | Purpose-built vector DB; excellent performance at 10M+ vectors | Heavy (uses etcd + minIO + pulsar); overkill for our scale; significantly more operational complexity |

### Decision

**PostgreSQL 16 + pgvector 0.7.x** — on Amazon RDS Multi-AZ with:
- **Vector schema**: `embeddings` table with columns: `event_id UUID, event_type TEXT, embedding vector(1536), metadata JSONB, created_at TIMESTAMPTZ`
- **Index**: HNSW index on embedding column (cosine distance) — 10x faster search over IVFFlat at our scale
- **Metadata schema**: `incidents, remediations, risk_scores, audit_logs` in the same PostgreSQL instance (separate schema)
- **Backup**: Continuous WAL archiving + daily pg_dump; 35-day PITR retention

### Consequences

- **Positive**: One database to manage (backup, monitor, upgrade); pgvector HNSW index provides <10ms approximate nearest-neighbor search at 500K vectors; standard PostgreSQL tooling works; RDS Multi-AZ provides 99.95% availability.
- **Negative**: Vector search at >1M vectors may need reindexing (mitigated by weekly REINDEX CONCURRENTLY); hybrid search (text + vector) requires raw SQL or additional extension (pg_bm25 or external); concurrent vector insert and search can cause checkpoint pressure.

---

## 11. Summary Tradeoff Matrix

| Decision | Chosen Option | Top Tradeoff Accepted |
|---|---|---|
| **Orchestrator** | EKS | $0.10/hr/cluster cost vs. self-managed control plane freedom |
| **GitOps** | ArgoCD | Redis HA complexity vs. unmatched multi-cluster + RBAC capabilities |
| **Observability** | Prometheus + Grafana + OTel | Operational burden of self-managed Thanos/Loki vs. predictable cost |
| **AIOps** | FastAPI + LangChain | Python ecosystem dependency vs. unmatched LLM orchestration flexibility |
| **Supply Chain** | Cosign + Kyverno | Operating private Sigstore infrastructure vs. no key management |
| **Packaging** | Helm + Kustomize | Two-tool learning curve vs. clean separation of concerns |
| **Multi-tenancy** | Namespaces + Kyverno | Shared control plane risk vs. no additional controller complexity |
| **Secrets** | ESO + AWS SM | $0.40/secret/month cost vs. no secrets in Git |
| **Ingress/Mesh** | Istio + Gateway API | 50-100MB/pod sidecar overhead vs. mTLS + zero-trust + rich routing |
| **Vector DB** | PostgreSQL + pgvector | Suboptimal >1M vector performance vs. single database simplicity |

---

## 12. Future ADRs (Forthcoming)

| ADR | Topic | Expected Timeline |
|---|---|---|
| ADR-011 | Log aggregation strategy (Loki vs. Elasticsearch vs. S3 + Athena) | Q3 2026 |
| ADR-012 | Multi-region active-active failover (stretch clusters vs. replicated clusters) | Q3 2026 |
| ADR-013 | AI model selection for RCA (fine-tuned Llama vs. GPT-4 vs. Claude) | Q4 2026 |
| ADR-014 | Platform cost showback/chargeback model (Kubecost vs. OpenCost vs. custom) | Q4 2026 |
| ADR-015 | Backstage or similar developer portal integration | Q1 2027 |
