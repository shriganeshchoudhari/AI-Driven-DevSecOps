# Component Architecture: AI-Driven Secure GitOps Kubernetes Platform

## Document Control

| Attribute | Value |
|---|---|
| **Document ID** | ARC-COMP-002 |
| **Version** | 1.0 |
| **Classification** | Internal — Engineering |
| **Author** | Platform Architecture Team |
| **Last Updated** | 2026-05-17 |

---

## 1. System Context Diagram (C4 Level 1)

The following diagram shows the platform as a black-box system interacting with external actors.

```mermaid
C4Context
    title System Context — AI-Driven Secure GitOps Kubernetes Platform

    Person(dev, "Developer", "Commits code, views dashboards")
    Person(sre, "SRE / Platform Engineer", "Manages platform config, policies, responds to incidents")
    Person(sec, "Security Engineer", "Defines policies, reviews audit trails")
    System_Ext(github, "GitHub / GitLab", "Source control, CI pipeline trigger")
    System_Ext(container_registry, "Container Registry (ECR)", "Stores signed images & SBOMs")
    System_Ext(cloud, "AWS Cloud", "EKS, S3, RDS, Secrets Manager, KMS")
    System_Ext(slack, "Slack / PagerDuty", "Alert notifications, chatops")

    System_Boundary(platform, "AI-Driven Secure GitOps Platform") {
        Container(gitops, "GitOps Delivery Layer", "ArgoCD, Helm, Kustomize")
        Container(security, "Supply Chain Security Layer", "Kyverno, Cosign, Falco")
        Container(aio, "AIOps Intelligence Layer", "FastAPI, LangChain, pgvector")
        Container(obs, "Observability Layer", "Prometheus, Grafana, OTel")
        Container(istio, "Service Mesh Layer", "Istio, Envoy, Gateway API")
    }

    Rel(dev, github, "Pushes code, creates PRs")
    Rel(github, gitops, "Triggers pipeline via webhook")
    Rel(gitops, container_registry, "Pulls signed images")
    Rel(gitops, cloud, "Deploys to EKS, reads secrets")
    Rel(security, container_registry, "Verifies signatures, scans")
    Rel(aio, obs, "Ingests metrics/logs/traces")
    Rel(aio, cloud, "Stores embeddings in pgvector")
    Rel(istio, obs, "Emits telemetry")
    Rel(aio, slack, "Sends correlated alerts")
    Rel(sre, istio, "Configures routing rules")
    Rel(sec, security, "Defines Kyverno policies")
```

---

## 2. Container Diagram (C4 Level 2)

The container diagram decomposes the platform into its major runtime containers and their interactions.

```mermaid
C4Container
    title Container Diagram — Platform Decomposition

    Person(dev, "Developer", "Deploys applications")

    System_Boundary(platform, "AI-Driven Secure GitOps Platform") {

        System_Boundary(gitops_layer, "GitOps Delivery Layer") {
            Container(argocd, "ArgoCD", "Go/GRPC", "Git-to-cluster reconciliation, App-of-Apps sync")
            Container(helm, "Helm + Kustomize", "YAML/Go", "Chart templating, environment overlays, variable substitution")
            Container(webhook, "Git Webhook Receiver", "Go", "Validates commit signatures, triggers CI pipelines")
        }

        System_Boundary(security_layer, "Supply Chain Security Layer") {
            Container(kyverno, "Kyverno", "Go/Webhook", "Admission policies, image verification, mutation")
            Container(cosign, "Cosign Verifier", "Go", "Signature verification, attestation validation")
            Container(falco, "Falco + Talons", "C/eBPF", "Kernel-level runtime syscall monitoring, rule engine")
            Container(sbom, "SBOM Generator (Syft)", "Go", "SPDX-2.3 SBOM generation, vulnerability enrichment")
            Container(signer, "Cosign Signer", "Go", "Keyless signing via Sigstore OIDC, in-toto attestations")
        }

        System_Boundary(aio_layer, "AIOps Intelligence Layer") {
            Container(fastapi, "AIOps API (FastAPI)", "Python", "REST API for AI queries, alert ingestion, remediation triggers")
            Container(langchain, "LangChain Reasoner", "Python", "LLM orchestration, chain-of-thought RCA, context assembly")
            Container(vector, "Vector Embedding Service", "Python", "Converts telemetry to embeddings, stores in pgvector")
            Container(pgvector, "pgvector Database", "PostgreSQL", "Vector DB for similarity search, telemetry metadata store")
            Container(cluster, "Anomaly Clustering Engine", "Python/NumPy", "DBSCAN/k-means clustering of incidents by embedding distance")
        }

        System_Boundary(obs_layer, "Observability Layer") {
            Container(prom, "Prometheus", "Go/TSDB", "Time-series metrics collection, alerting rules, recording rules")
            Container(grafana, "Grafana", "Go/React", "Dashboards, alert management, AI-driven dashboard suggestions")
            Container(otel, "OpenTelemetry Collector", "Go", "Trace/metric/log collection, batching, sampling, export")
            Container(alert, "Alertmanager", "Go", "Deduplication, grouping, routing, silencing, inhibition")
        }

        System_Boundary(mesh_layer, "Service Mesh & Networking") {
            Container(istiod, "Istiod (Control Plane)", "Go", "Pilot, Citadel, Galley — service discovery, mTLS, config distribution")
            Container(envoy, "Envoy Proxy (Sidecar)", "C++", "L7 traffic management, mTLS termination, telemetry generation")
            Container(gateway, "Istio Gateway", "C++/Envoy", "Ingress traffic, TLS termination, route splitting, authz")
        }
    }

    Rel(dev, helm, "Configures Helm values & Kustomize overlays")
    Rel(helm, argocd, "Generates manifests for sync")
    Rel(argocd, kyverno, "Submits resources for admission (pre-sync)")
    Rel(kyverno, cosign, "Delegates image signature verification")
    Rel(cosign, sbom, "Retrieves and verifies SBOM attestations")

    Rel(falco, fastapi, "Streams events via Falco Talon webhook")
    Rel(fastapi, langchain, "Delegates complex reasoning chains")
    Rel(langchain, vector, "Generates embeddings for context")
    Rel(vector, pgvector, "Stores & queries vector embeddings")
    Rel(fastapi, cluster, "Runs clustering algorithms on incidents")
    Rel(cluster, pgvector, "Reads embeddings for similarity grouping")

    Rel(otel, prom, "Forwards metrics")
    Rel(prom, alert, "Sends alert events based on rules")
    Rel(alert, fastapi, "Webhooks enriched alert payloads")
    Rel(otel, fastapi, "Forwards trace data for anomaly detection")
    Rel(envoy, otel, "Emits telemetry via Envoy's OTel access log")

    Rel(fastapi, grafana, "Creates annotated dashboard panels")
    Rel(fastapi, slack, "Sends enriched, correlated incident summaries")

    Rel(gateway, envoy, "Routes traffic to mesh workloads")
    Rel(istiod, envoy, "Distributes mTLS certs & routing config")
```

---

## 3. Component Diagram — AIOps Intelligence Layer (C4 Level 3)

This depth-level diagram shows the internal structure of the AIOps subsystem, the most architecturally novel component.

```mermaid
C4Component
    title Component Diagram — AIOps Intelligence Subsystem

    Container_Boundary(api, "AIOps API (FastAPI)") {
        Component(ingest, "Event Ingestion API", "REST/Webhook", "Accepts Prometheus alerts, Falco events, OTel traces")
        Component(rca, "Root Cause Analysis Engine", "Python", "Correlates events across timelines using embeddings")
        Component(remediate, "Remediation Orchestrator", "Python", "Executes automated actions via K8s API; gates on risk score")
        Component(query, "Natural Language Query API", "REST/SSE", "Accepts plain-English queries; returns diagnostic summaries")
        Component(risk, "Risk Scoring Service", "Python", "Assigns 0–1 risk score based on blast radius, severity, history")
    }

    Container_Boundary(reasoner, "LangChain Reasoner") {
        Component(chain, "Chain-of-Thought Builder", "LangChain", "Constructs reasoning chains from telemetry context")
        Component(llm, "LLM Router", "LangChain", "Routes to local (Llama) or cloud (GPT-4) models based on sensitivity")
        Component(context, "Context Assembler", "LangChain", "Retrieves relevant telemetry, past incidents, runbooks from vector DB")
    }

    Container_Boundary(store, "Vector & Metadata Store") {
        Component(pgv, "pgvector (Embeddings)", "PostgreSQL extension", "Stores 1536-dim embeddings of telemetry events and incident reports")
        Component(pgm, "PostgreSQL (Metadata)", "PostgreSQL", "Stores incident records, remediations, risk scores, audit log")
    }

    Rel(ingest, context, "Sends raw event for context enrichment")
    Rel(context, pgv, "Queries similar past incidents (cosine similarity)")
    Rel(context, pgm, "Queries incident metadata, runbooks")
    Rel(context, chain, "Passes enriched context for reasoning")
    Rel(chain, llm, "Delegates LLM inference")
    Rel(chain, rca, "Returns structured root-cause hypothesis")
    Rel(rca, risk, "Scores RCA confidence and blast radius")
    Rel(risk, remediate, "Triggers remediation if risk score < threshold")
    Rel(remediate, pgm, "Logs remediation outcome")

    Rel(query, chain, "Processes natural language query")
    Rel(query, pgv, "Searches vector DB for relevant context")
```

---

## 4. Platform Services and Responsibilities

### 4.1 GitOps Delivery Layer

| Service | Responsibility | Key Metrics |
|---|---|---|
| **ArgoCD Server** | Git repository reconciliation, sync operations, drift detection, webhook handling | Sync time < 30s; drift detection latency < 60s |
| **ArgoCD Application Controller** | Manages Application CR lifecycles, health assessment, pruning | Application count per cluster: 500+ |
| **Helm Controller** | Renders Helm charts, manages releases, rollback support | Chart release time < 15s |
| **Kustomize Controller** | Applies Kustomize overlays, secret generation, configMap generation | Overlay apply time < 5s |

### 4.2 Supply Chain Security Layer

| Service | Responsibility | Key Metrics |
|---|---|---|
| **Kyverno Admission Controller** | Validating and mutating webhooks; enforces 30+ policy rules at pod admission | Admission latency < 50ms; 100% enforcement |
| **Cosign Verifier** | Verifies container image signatures and attestations at deploy time | Verification time < 2s per image |
| **Falco** | Kernel-level syscall monitoring; 100+ default Falco rules; real-time alert stream | Event throughput 10K/sec per node |
| **SBOM Service** | Generates SPDX-2.3 SBOMs for every build; uploads to OCI registry as attestation | Generation time < 60s per image |
| **Trivy Operator** | Continuous vulnerability scanning of running pods; updates vulnerability reports | Scan cycle < 5 minutes per node |

### 4.3 AIOps Intelligence Layer

| Service | Responsibility | Key Metrics |
|---|---|---|
| **Event Ingestion API** | Receives and normalizes alerts from Prometheus, Falco, and OTel; 5 event types unified | Throughput 5K events/sec; P99 < 100ms |
| **LangChain Reasoner** | Constructs multi-step reasoning chains; routes to appropriate LLM (local or cloud) | Reasoning time < 10s per incident |
| **Embedding Service** | Converts telemetry events to 1536-dim vector embeddings via sentence-transformers | Embedding latency < 200ms per event |
| **Anomaly Clustering** | Groups related incidents by embedding cosine distance; DBSCAN clustering | Cluster formation < 30s per 1K events |
| **Remediation Orchestrator** | Executes automated K8s operations (scale, restart, network policy change); gates on risk score | Action execution < 5s; risk score computation < 500ms |

### 4.4 Observability and Mesh Layers

| Service | Responsibility | Key Metrics |
|---|---|---|
| **Prometheus** | 10M+ active time series; 30-day retention; recording rules for SLO burn rate | Query latency P99 < 1s |
| **Grafana** | 200+ dashboards; unified view of metrics, logs, traces, AI insights | Dashboard load < 3s |
| **OpenTelemetry Collector** | 50K spans/sec; tail-based sampling; metrics correlation | Export latency P99 < 500ms |
| **Istio Control Plane** | mTLS cert rotation every 24h; service discovery for 200+ services | Config propagation < 10s |
| **Envoy Sidecar** | L7 traffic management; HTTP/gRPC; telemetry generation | P99 latency overhead < 2ms |

---

## 5. Integration Patterns

### 5.1 Event-Driven Integration (AIOps)

```mermaid
graph LR
    P["Prometheus Alert"] --> AM["Alertmanager"]
    AM -->|Webhook| API["FastAPI Event Ingest"]
    F["Falco Event"] -->|Talon Webhook| API
    O["OTel Trace"] -->|gRPC Export| API
    API -->|Normalized Event| LC["LangChain Reasoner"]
    LC -->|Embedding Request| VS["Vector Service"]
    VS --> PG[("pgvector")]
    LC -->|RCA Result| API
    API -->|Remediation Action| K8S["Kubernetes API"]
    API -->|Incident Record| PG
```

### 5.2 GitOps Reconciliation Loop

```mermaid
graph TD
    DEV["Developer Push"] --> GH[("Git Repository")]
    GH -->|Webhook| ARGO["ArgoCD"]
    ARGO -->|Diff Detection| K8S["Live Cluster State"]
    K8S -->|Current State| ARGO
    ARGO -->|Apply Sync| KYW["Kyverno Admission"]
    KYW -->|Verify Policy| ARGO
    ARGO -->|Deploy| K8S
    K8S -->|Drift| ARGO
    ARGO -->|Auto-Heal| K8S
```

### 5.3 Secure Supply Chain Build

```mermaid
graph LR
    CI["CI Pipeline"] -->|Build Image| DOCKER["Docker Build"]
    DOCKER -->|Image| SCAN["Trivy Scan"]
    SCAN -->|Pass/Fail| SIGN["Cosign Sign (Keyless)"]
    SIGN -->|Attach SBOM| ATT["Cosign Attach"]
    ATT -->|Push| ECR[("Amazon ECR")]
    ECR -->|Pull + Verify| KYW["Kyverno + Cosign Verify"]
    KYW -->|Pass| DEPLOY["Admit to Cluster"]
    KYW -->|Fail| REJECT["Reject + Audit Log"]
```

### 5.4 Multi-Cluster Federation

ArgoCD operates in an App-of-Apps pattern: a single management cluster hosts ArgoCD, which reconciles Applications across 10+ workload clusters (dev, staging, prod in multiple regions). Cluster registration secrets are stored in AWS Secrets Manager and synced via External Secrets Operator.
