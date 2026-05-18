# Platform Architecture Overview

Complete architecture documentation for the AI-Driven Secure GitOps Kubernetes Platform.

---

## Table of Contents

- [High-Level Architecture](#high-level-architecture)
- [Technology Stack](#technology-stack)
- [Key Design Decisions](#key-design-decisions)
- [Component Architecture](#component-architecture)
- [Data Flow](#data-flow)
- [Deployment Architecture](#deployment-architecture)
- [Network Architecture](#network-architecture)
- [Security Architecture](#security-architecture)
- [Observability Architecture](#observability-architecture)
- [AIOps Architecture](#aiops-architecture)
- [GitOps Architecture](#gitops-architecture)

---

## High-Level Architecture

### System Context Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                             External Actors                                 │
│                                                                             │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────────────────────┐    │
│  │ Developer │  │ Operator │  │ End User │  │ External Services       │    │
│  │ (GitHub)  │  │ (CLI)    │  │ (HTTPS)  │  │ (OIDC, LLM, Observ.)   │    │
│  └─────┬────┘  └────┬─────┘  └────┬─────┘  └────────────┬────────────┘    │
│        │            │             │                      │                 │
└────────┼────────────┼─────────────┼──────────────────────┼─────────────────┘
         │            │             │                      │
         ▼            ▼             ▼                      ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                           Platform Boundary                                │
│                                                                             │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │                         AWS Cloud                                     │  │
│  │                                                                       │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────────────────┐    │  │
│  │  │ EKS      │  │ RDS      │  │ Elasti-  │  │ S3 / ECR / Route53  │    │  │
│  │  │ Cluster  │  │ PostgreSQL│  │ Cache    │  │ CloudWatch / IAM    │    │  │
│  │  └──────────┘  └──────────┘  └──────────┘  └────────────────────┘    │  │
│  │                                                                       │  │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │  │
│  │  │                    GitOps Control Plane                          │  │  │
│  │  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────────────┐  │  │  │
│  │  │  │ GitHub   │  │ ArgoCD   │  │ External │  │ cert-manager   │  │  │  │
│  │  │  │ Actions  │  │ App-of-  │  │ Secrets  │  │ ClusterIssuer  │  │  │  │
│  │  │  │          │  │ Apps     │  │ Operator │  │                │  │  │  │
│  │  │  └──────────┘  └──────────┘  └──────────┘  └────────────────┘  │  │  │
│  │  └─────────────────────────────────────────────────────────────────┘  │  │
│  │                                                                       │  │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │  │
│  │  │                    Platform Services                             │  │  │
│  │  │                                                                  │  │  │
│  │  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────────────┐  │  │  │
│  │  │  │ Kyverno  │  │ Falco    │  │ Prometheus│  │ Grafana        │  │  │  │
│  │  │  │ Policies │  │ Runtime  │  │ + Alert- │  │ Datasources    │  │  │  │
│  │  │  │          │  │ Security │  │ manager  │  │ Dashboards     │  │  │  │
│  │  │  └──────────┘  └──────────┘  └──────────┘  └────────────────┘  │  │  │
│  │  │                                                                  │  │  │
│  │  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────────────┐  │  │  │
│  │  │  │ Loki     │  │ Tempo    │  │ Karpenter│  │ Chaos Mesh     │  │  │  │
│  │  │  │ Logs     │  │ Traces   │  │ Autoscal │  │ Experiments    │  │  │  │
│  │  │  └──────────┘  └──────────┘  └──────────┘  └────────────────┘  │  │  │
│  │  └─────────────────────────────────────────────────────────────────┘  │  │
│  │                                                                       │  │
│  │  ┌─────────────────────────────────────────────────────────────────┐  │  │
│  │  │                    Application Layer                             │  │  │
│  │  │                                                                  │  │  │
│  │  │  ┌──────────────────────┐    ┌──────────────────────────────┐   │  │  │
│  │  │  │    AIOps Engine      │    │      Microservices           │   │  │  │
│  │  │  │  ┌────────────────┐  │    │  ┌────────┐ ┌────────────┐   │   │  │  │
│  │  │  │  │ FastAPI        │  │    │  │ Auth   │ │ Orders     │   │   │  │  │
│  │  │  │  │ LangChain      │  │    │  │ Service│ │ Service    │   │   │  │  │
│  │  │  │  │ ChromaDB       │  │    │  └────────┘ └────────────┘   │   │  │  │
│  │  │  │  └────────────────┘  │    │  ┌────────┐ ┌────────────┐   │   │  │  │
│  │  │  │  ┌────────────────┐  │    │  │ Payment│ │ Notification│   │   │  │  │
│  │  │  │  │ Analyzer       │  │    │  │ Service│ │ Service     │   │   │  │  │
│  │  │  │  │ Remediation    │  │    │  └────────┘ └────────────┘   │   │  │  │
│  │  │  │  └────────────────┘  │    └──────────────────────────────┘   │  │  │
│  │  │  └──────────────────────┘                                       │  │  │
│  │  └─────────────────────────────────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────────┘
```

---

## Technology Stack

| Layer | Technology | Version | Purpose |
|-------|-----------|---------|---------|
| **Infrastructure** | AWS, Terraform | >= 1.7 | Infrastructure as Code |
| **Compute** | EKS, Karpenter | 1.29, >= 0.37 | Kubernetes orchestration, intelligent autoscaling |
| **Networking** | VPC, ALB/NLB, Route53, CloudFront | - | Connectivity, DNS, CDN |
| **Container Runtime** | Docker, containerd | >= 24.0 | Image execution, CRI |
| **Scheduling** | Kubernetes | 1.29 | Container orchestration |
| **Packaging** | Helm, Kustomize | >= 3.14 | K8s manifest packaging |
| **GitOps** | ArgoCD, Argo Rollouts | >= 2.10, >= 1.6 | Continuous delivery, progressive delivery |
| **CI/CD** | GitHub Actions | - | Build, test, security scan, deploy |
| **Security - Admission** | Kyverno | >= 1.12 | Policy as code, admission control |
| **Security - Runtime** | Falco, Falcosidekick | >= 0.37 | Behavioral monitoring, automated response |
| **Security - Supply Chain** | Cosign, Trivy, Syft | >= 2.0, >= 0.50 | Image signing, vulnerability scanning, SBOM |
| **Security - Secrets** | External Secrets, Sealed Secrets, SOPS | - | Multi-layered secrets management |
| **Security - Network** | Calico, Cilium | - | Network policies, eBPF |
| **Observability - Metrics** | Prometheus, kube-state-metrics, node-exporter | - | Metrics collection, alerting |
| **Observability - Logs** | Loki, Promtail | - | Log aggregation, query |
| **Observability - Traces** | Tempo, OpenTelemetry | - | Distributed tracing |
| **Observability - Visualization** | Grafana | >= 10 | Dashboards, alerting |
| **AIOps** | FastAPI, LangChain, ChromaDB | - | Incident analysis, RCA automation |
| **Chaos Engineering** | Chaos Mesh | >= 2.6 | Resilience testing |
| **Certificate Management** | cert-manager | >= 1.14 | TLS automation |
| **Backup & DR** | Velero | >= 1.13 | Cluster backup and restore |
| **DNS Automation** | ExternalDNS | - | Kubernetes-aware DNS |
| **Service Mesh** | Istio (optional) | >= 1.21 | Traffic management, mTLS |

---

## Key Design Decisions

### Why Amazon EKS?

| Factor | Decision | Rationale |
|--------|----------|-----------|
| **Managed Control Plane** | EKS vs self-managed | AWS manages etcd, API server; no operational burden |
| **IRSA Integration** | EKS-native | Native IAM integration for service accounts |
| **K8s Conformance** | Certified Kubernetes | Full compatibility with K8s ecosystem |
| **VPC Integration** | EKS + VPC CNI | Native VPC networking for pods |
| **Ecosystem** | Large community | Extensive documentation, tooling, support |

### Why ArgoCD?

| Factor | ArgoCD | Alternative |
|--------|--------|-------------|
| **App-of-Apps** | Native support | Flux requires Kustomize |
| **Progressive Delivery** | Argo Rollouts (sister project) | Flagger (add-on) |
| **Multi-Cluster** | Built-in | Flux requires additional config |
| **UI/CLI** | Rich UI + full-featured CLI | Flux UI is less mature |
| **Community** | CNCF graduated | Larger community than Flux |

### Why Prometheus + Loki + Tempo?

| Signal | Tool | Rationale |
|--------|------|-----------|
| **Metrics** | Prometheus | CNCF graduated, K8s-native, 1000+ integrations |
| **Logs** | Loki | Cost-effective, K8s-native, no log shipping |
| **Traces** | Tempo | Cost-effective, works with existing storage |
| **Visualization** | Grafana | Single pane for all signals, extensive plugin ecosystem |

### Why LangChain + ChromaDB for AIOps?

| Component | Choice | Rationale |
|-----------|--------|-----------|
| **LLM Framework** | LangChain | Standardized LLM workflow, multi-provider, RAG support |
| **Vector Store** | ChromaDB | Lightweight, in-process, no separate infrastructure |
| **API Framework** | FastAPI | Async, auto-docs, high performance |
| **LLM Providers** | OpenAI, Anthropic, Azure | Multi-provider for redundancy |

### Why Kyverno over OPA/Gatekeeper?

| Factor | Kyverno | OPA/Gatekeeper |
|--------|---------|----------------|
| **Policy Language** | YAML-native | Rego (learning curve) |
| **K8s-native** | Deep K8s integration | Generic policy engine |
| **Policy Library** | 100+ built-in | Smaller built-in library |
| **Reporting** | Built-in policy reports | Requires additional tooling |
| **Mutation** | Native support | More complex |

---

## Component Architecture

### EKS Cluster Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                       EKS Control Plane                          │
│  ┌─────────────┐  ┌─────────────┐  ┌───────────────────────┐   │
│  │ API Server  │  │ etcd        │  │ Controller Manager    │   │
│  │ (AWS managed)│  │ (AWS managed)│  │ Scheduler             │   │
│  └─────────────┘  └─────────────┘  └───────────────────────┘   │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Data Plane (EC2 / Karpenter)                  │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ System Nodes │  │ App Nodes    │  │ Spot Nodes   │          │
│  │ t3.medium    │  │ m5.xlarge    │  │ m5.xlarge    │          │
│  │ Networking   │  │ Workloads    │  │ Non-critical │          │
│  │ Ingress      │  │ AIOps        │  │ Batch        │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
└─────────────────────────────────────────────────────────────────┘
```

---

## Data Flow

### CI/CD Pipeline Flow

```
Developer Push → GitHub
    │
    ▼
GitHub Actions
    │
    ├── Lint & Test
    ├── SAST Scan (Semgrep)
    ├── Dependency Scan (Trivy)
    ├── Build Image
    ├── Push to ECR
    ├── Sign Image (Cosign)
    ├── Generate SBOM (Syft)
    └── Deploy to ArgoCD
            │
            ▼
        ArgoCD
            │
            ├── Sync Git → Cluster
            ├── Kyverno Admission (validate)
            ├── Deploy Pod
            ├── Readiness Probe (verify)
            └── Rollout (canary if configured)
```

### Observability Data Flow

```
Application Metrics ──► Prometheus ──► Grafana Dashboards
    │                                        │
    │                                        ├── Alertmanager
    │                                        │       │
    │                                        │       └── PagerDuty
    │                                        │
    │                                        └── AIOps Engine
    │                                                │
Application Logs ──► Promtail ──► Loki ───────────────┤
    │                                                   │
    │                                                    └── Incident Analysis
Application Traces ──► OpenTelemetry ──► Tempo ──────► Trace Discovery
```

### GitOps Control Flow

```
Developer (Git Push)
    │
    ▼
┌──────────────────────┐
│   GitHub Repository  │
│  ┌────────────────┐  │
│  │ app-of-apps/   │  │  Source of Truth
│  │ 00-infra.yaml  │  │
│  │ 01-security.yaml│  │
│  │ 02-observ.yaml │  │
│  │ 03-aiops.yaml  │  │
│  │ 04-apps.yaml   │  │
│  └────────────────┘  │
└──────────┬───────────┘
           │ (3 min sync)
           ▼
┌──────────────────────┐
│  ArgoCD App-of-Apps  │
│  (root-app)           │
│                      │
│  ├── 00-infra ───────┤──► cert-manager, ingress-nginx
│  ├── 01-security ────┤──► Kyverno, Falco, Network Pol.
│  ├── 02-observ ──────┤──► Prometheus, Grafana, Loki
│  ├── 03-aiops ───────┤──► AIOps Engine, ChromaDB
│  └── 04-apps ────────┤──► Microservices
└──────────────────────┘
           │
           ▼
    Kubernetes Cluster
    (Desired State)
```

---

## Deployment Architecture

### Multi-Environment Layout

```
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│   Development   │  │    Staging      │  │   Production    │
│                 │  │                 │  │                 │
│ AWS Account:    │  │ AWS Account:    │  │ AWS Account:    │
│ 123456789012    │  │ 234567890123    │  │ 345678901234    │
│                 │  │                 │  │                 │
│ Region: us-west2│  │ Region: us-west2│  │ Region: us-west2│
│                 │  │                 │  │                 │
│ VPC: 10.0.0.0/16│  │ VPC: 10.1.0.0/16│  │ VPC: 10.2.0.0/16│
│                 │  │                 │  │                 │
│ Nodes: 2-5      │  │ Nodes: 3-10     │  │ Nodes: 5-30     │
│ t3.medium       │  │ m5.xlarge      │  │ m5.2xlarge     │
│                 │  │                 │  │                 │
│ RDS: db.t4g.small│  │ RDS: db.r6g.large│  │ RDS: db.r6g.xlarge│
│ Single-AZ       │  │ Multi-AZ        │  │ Multi-AZ        │
│                 │  │                 │  │                 │
│ - Cost: ~$275/mo│  │ - Cost: ~$1.2k/m│  │ - Cost: ~$2.2k/m│
└─────────────────┘  └─────────────────┘  └─────────────────┘
                          │                       │
                          └───────────────────────┘
                                      │
                    ┌─────────────────┴────────────────┐
                    │           DR Region               │
                    │         us-east-1                 │
                    │     (Passive / Read Replicas)     │
                    └──────────────────────────────────┘
```

---

## Network Architecture

### Network Segmentation

```
Internet
    │
    ▼
┌──────────────────────────────────────────────────────┐
│                  VPC (10.x.0.0/16)                   │
│                                                       │
│  ┌────────────────────────────────────────────────┐  │
│  │              Public Subnets                     │  │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐       │  │
│  │  │ AZ-a     │ │ AZ-b     │ │ AZ-c     │       │  │
│  │  │ 10.x.0   │ │ 10.x.16  │ │ 10.x.32  │       │  │
│  │  │ NAT GW   │ │ NAT GW   │ │ NAT GW   │       │  │
│  │  │ ALB      │ │ ALB      │ │ ALB      │       │  │
│  │  └──────────┘ └──────────┘ └──────────┘       │  │
│  └────────────────────────────────────────────────┘  │
│                                                       │
│  ┌────────────────────────────────────────────────┐  │
│  │              Private Subnets                    │  │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐       │  │
│  │  │ AZ-a     │ │ AZ-b     │ │ AZ-c     │       │  │
│  │  │ 10.x.64  │ │ 10.x.80  │ │ 10.x.96  │       │  │
│  │  │ EKS      │ │ EKS      │ │ EKS      │       │  │
│  │  │ RDS      │ │ RDS      │ │ RDS      │       │  │
│  │  │ Redis    │ │ Redis    │ │ Redis    │       │  │
│  │  └──────────┘ └──────────┘ └──────────┘       │  │
│  └────────────────────────────────────────────────┘  │
│                                                       │
│  ┌────────────────────────────────────────────────┐  │
│  │           VPC Endpoints                         │  │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐       │  │
│  │  │ S3       │ │ ECR      │ │ EKS API  │       │  │
│  │  │ CloudW.  │ │ SM       │ │ STS      │       │  │
│  │  └──────────┘ └──────────┘ └──────────┘       │  │
│  └────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────┘
```

---

## Security Architecture

### Defense in Depth Layers

```
Layer 0: Source Code
├── SAST (Semgrep, CodeQL)
├── Dependency Scanning (Dependabot, Trivy)
└── Secret Scanning (GitGuardian)

Layer 1: Supply Chain
├── Image Signing (Cosign)
├── SBOM Generation (Syft)
├── Image Vulnerability Scanning (Trivy)
└── SLSA Level 3 Provenance

Layer 2: Kubernetes Admission
├── Kyverno Policies (50+)
├── Pod Security Standards (Restricted)
├── Image Signature Verification
└── Resource Quota Enforcement

Layer 3: Network Security
├── Default-Deny Network Policies
├── Calico Network Policies
├── AWS Security Groups
├── WAF with OWASP Rules
└── TLS Everywhere (cert-manager)

Layer 4: Identity & Access
├── OIDC (GitHub Actions, CLI)
├── RBAC (Least Privilege)
├── IRSA (Pod Identities)
└── Service Account Token Projection

Layer 5: Runtime Security
├── Falco (1000+ Rules)
├── Kubernetes Audit Logging
├── AWS CloudTrail
└── Container Runtime Security

Layer 6: Secrets Management
├── AWS Secrets Manager (Source of Truth)
├── External Secrets Operator (Sync)
├── SOPS + KMS (Client Encryption)
└── Sealed Secrets (GitOps Safe)

Layer 7: Data Protection
├── Encryption at Rest (KMS)
├── Encryption in Transit (TLS 1.3)
├── RDS Encryption (TDE)
└── Application-Level Encryption

Layer 8: Monitoring & Response
├── Security Monitoring (Falco, CloudWatch)
├── Alerting (Alertmanager → PagerDuty)
├── AIOps Automated Analysis
└── Incident Response Automation
```

---

## Observability Architecture

### Signals Collection

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Single Pane (Grafana)                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐             │
│  │ Metrics      │  │ Logs         │  │ Traces       │             │
│  │ Dashboards   │  │ Explore      │  │ Service Graph│             │
│  │ Alerting     │  │ Alerting     │  │ Search       │             │
│  └──────────────┘  └──────────────┘  └──────────────┘             │
└─────────────────────────────────────────────────────────────────────┘
           │                    │                    │
           ▼                    ▼                    ▼
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│   Prometheus     │  │      Loki        │  │     Tempo        │
│   Metrics Store  │  │    Log Store     │  │   Trace Store    │
│                  │  │                  │  │                  │
│  Retention: 15d  │  │ Retention: 30d   │  │ Retention: 7d    │
│  Storage: PV     │  │ Storage: S3      │  │ Storage: S3      │
└────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘
         │                     │                      │
         ▼                     ▼                      ▼
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│  Exporters       │  │   Promtail       │  │ OpenTelemetry    │
│  - kube-state    │  │   - Pod logs     │  │ Collector        │
│  - node-exporter │  │   - System logs  │  │ - Auto-instr.    │
│  - cAdvisor      │  │   - K8s events   │  │ - Custom spans   │
│  - Blackbox      │  └──────────────────┘  └──────────────────┘
│  - Custom apps   │
└──────────────────┘
```

---

## AIOps Architecture

### Incident Analysis Pipeline

```
┌─────────────────────────────────────────────────────────────────────┐
│                        AIOps Engine (FastAPI)                        │
│                                                                     │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────────┐   │
│  │ Incident Router  │  │ Analyzer Service │  │ Remediation Svc  │   │
│  │ POST /analyze   │  │ RAG Pipeline     │  │ Runbook Lookup   │   │
│  │ POST /remediate │  │ Context Builder  │  │ Action Generator │   │
│  └────────┬────────┘  └────────┬────────┘  └────────┬─────────┘   │
│           │                    │                     │              │
└───────────┼────────────────────┼─────────────────────┼──────────────┘
            │                    │                     │
            ▼                    ▼                     ▼
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│   ChromaDB       │  │   LangChain      │  │   External       │
│   Vector Store   │  │   Orchestration  │  │   Tools          │
│                  │  │                  │  │                  │
│  - Past incidents│  │  - LLM Provider  │  │  - Prometheus    │
│  - Runbooks      │  │  - Prompt Tmpl   │  │  - Loki          │
│  - Known fixes   │  │  - Memory        │  │  - PagerDuty     │
│  - Documentation │  │  - Chains        │  │  - Kubernetes    │
└──────────────────┘  └──────────────────┘  └──────────────────┘
```

### AIOps Data Flow

```
1. Alert Fires (Prometheus → Alertmanager → PagerDuty)
2. Incident Created (PagerDuty webhook → AIOps)
3. Context Collection (AIOps queries Prometheus, Loki, Tempo)
4. Vector Search (ChromaDB: similar past incidents)
5. RAG Pipeline (LangChain: context + similar incidents → LLM)
6. Analysis Generated (Root cause, impact, recommended actions)
7. Remediation Suggested (Runbook steps, or auto-remediate)
8. Feedback Loop (Resolution stored → ChromaDB for future)
```

---

## GitOps Architecture

### App-of-Apps Pattern

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Git Repository (Source of Truth)                  │
│                                                                     │
│  argocd/app-of-apps/templates/                                      │
│  ├── 00-namespaces.yaml     (Create all platform namespaces)        │
│  ├── 01-infra.yaml          (cert-manager, ingress-nginx)           │
│  ├── 02-security.yaml       (Kyverno, Falco, Network Policies)      │
│  ├── 03-observability.yaml  (Prometheus, Grafana, Loki, Tempo)     │
│  ├── 04-secrets.yaml        (External Secrets, Sealed Secrets)      │
│  ├── 05-aiops.yaml          (AIOps Engine, Analyzer, ChromaDB)      │
│  ├── 06-chaos.yaml          (Chaos Mesh, Experiments)               │
│  └── 07-applications.yaml   (Microservices, Sample Apps)            │
│                                                                     │
│  Each template creates an ArgoCD Application that points to:        │
│  - A Helm chart in the repo or external Helm repository             │
│  - Values files per environment (argocd/values/{env}/)              │
└─────────────────────────────────────────────────────────────────────┘
```

### Sync Wave Ordering

```
Wave 0:  Namespaces
Wave 1:  CRDs (Custom Resource Definitions)
Wave 2:  Security Controllers (Kyverno, network policies)
Wave 3:  Infrastructure (cert-manager, ingress-nginx)
Wave 4:  Secrets Infrastructure (External Secrets)
Wave 5:  Observability (Prometheus, Grafana, Loki, Tempo)
Wave 6:  Security Agents (Falco)
Wave 7:  AIOps Engine
Wave 8:  Chaos Mesh
Wave 9:  Applications (Microservices)
```

---

## Related Documentation

### Detailed Architecture Documents

| Document | Description |
|----------|-------------|
| [Deployment Prerequisites](../deployment/01-prerequisites.md) | AWS setup, tools, limits |
| [Bootstrap Sequence](../deployment/02-bootstrap-sequence.md) | Step-by-step deployment |
| [AWS Deployment Guide](../deployment/04-aws-deployment.md) | Production deployment |
| [Security Overview](../security/01-security-overview.md) | Security architecture |
| [Threat Model](../security/02-threat-model.md) | STRIDE per component |
| [SRE Runbook](../operations/01-sre-runbook.md) | Operational procedures |
| [Incident Response](../operations/02-incident-response.md) | Incident handling |
| [Disaster Recovery](../operations/03-disaster-recovery.md) | DR procedures |

### ADR Index

| ADR | Title | Status |
|-----|-------|--------|
| ADR-001 | Use EKS as Kubernetes provider | Accepted |
| ADR-002 | Use ArgoCD for GitOps | Accepted |
| ADR-003 | Use Prometheus + Loki + Tempo for observability | Accepted |
| ADR-004 | Use Kyverno for policy engine | Accepted |
| ADR-005 | Use Falco for runtime security | Accepted |
| ADR-006 | Use Karpenter for node autoscaling | Accepted |
| ADR-007 | Use External Secrets + SOPS + Sealed Secrets | Accepted |
| ADR-008 | Use LangChain + ChromaDB for AIOps | Accepted |
| ADR-009 | Use Chaos Mesh for chaos engineering | Accepted |
| ADR-010 | Use cert-manager for certificate management | Accepted |
| ADR-011 | Multi-account strategy for environments | Accepted |
| ADR-012 | VPC design with public/private subnets | Accepted |
