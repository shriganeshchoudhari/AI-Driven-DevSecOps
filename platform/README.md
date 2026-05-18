# AI-Driven Secure GitOps Kubernetes Platform

**Enterprise-grade Kubernetes platform with AI-powered operations, GitOps delivery, and defense-in-depth security.**

[![Build Status](https://img.shields.io/badge/build-passing-brightgreen.svg)](https://github.com/org/platform/actions)
[![Security Scan](https://img.shields.io/badge/security-passing-brightgreen.svg)](https://github.com/org/platform/security)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Kubernetes](https://img.shields.io/badge/kubernetes-1.29-blue.svg)](https://kubernetes.io)
[![Terraform](https://img.shields.io/badge/terraform-1.7+-purple.svg)](https://terraform.io)
[![ArgoCD](https://img.shields.io/badge/ArgoCD-2.10+-orange.svg)](https://argoproj.io)
[![CIS](https://img.shields.io/badge/CIS-Benchmark%201.8-green.svg)](https://www.cisecurity.org)
[![SLSA](https://img.shields.io/badge/SLSA-3-brightgreen.svg)](https://slsa.dev)
[![SOC2](https://img.shields.io/badge/SOC%202-Compliant-success.svg)](https://www.aicpa.org/soc)

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Technology Stack](#technology-stack)
- [Quick Start](#quick-start)
- [Repository Structure](#repository-structure)
- [Prerequisites](#prerequisites)
- [Deployment Options](#deployment-options)
- [Security Features](#security-features)
- [Observability & AIOps](#observability--aiops)
- [Project Status](#project-status)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

This platform provides a complete, production-ready Kubernetes foundation that embeds security, observability, and AI-driven operations from Day 0. Built on AWS EKS and managed entirely through GitOps with ArgoCD, it enables platform engineering teams to deliver self-service infrastructure with built-in compliance and automated incident response.

### Key Capabilities

- **GitOps Everything**: Every resource is declared in Git and synced via ArgoCD — clusters, applications, policies, and configuration.
- **AI-Powered Operations**: An integrated AIOps engine analyzes observability data, accelerates root cause analysis, and automates incident response.
- **Defense in Depth**: Kyverno policies, Falco runtime security, network policies, Pod Security Standards, and supply chain verification with Cosign.
- **Chaos Engineering**: Built-in Chaos Mesh integration for resilience testing and validation of self-healing capabilities.
- **Multi-Environment**: Consistent deployment across dev, staging, and production with Terraform workspaces and environment overlays.
- **Cost Optimized**: Karpenter for intelligent node provisioning, spot instance support, and continuous right-sizing.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                             GitOps Control Plane                            │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────┐ │
│  │ GitHub   │  │ ArgoCD   │  │ ArgoCD   │  │ Argo     │  │ External     │ │
│  │ Actions  │  │ App-of-  │  │ Rollouts │  │ Image    │  │ Secrets      │ │
│  │ CI/CD    │  │ Apps     │  │ Canary   │  │ Updater  │  │ Operator     │ │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘  └──────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
                                     │
┌─────────────────────────────────────────────────────────────────────────────┐
│                           AWS EKS Cluster                                   │
│  ┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐ │
│  │   Security Layer    │  │  Observability Layer │  │    Data Layer       │ │
│  │  ┌────────────────┐ │  │  ┌────────────────┐ │  │  ┌────────────────┐ │ │
│  │  │ Kyverno        │ │  │  │ Prometheus     │ │  │  │ RDS (Postgres) │ │ │
│  │  │ Falco          │ │  │  │ Grafana        │ │  │  │ ElastiCache    │ │ │
│  │  │ OPA/Gatekeeper │ │  │  │ Loki           │ │  │  │ (Redis)        │ │ │
│  │  │ cert-manager   │ │  │  │ Tempo          │ │  │  │ S3 (Objects)   │ │ │
│  │  └────────────────┘ │  │  └────────────────┘ │  │  └────────────────┘ │ │
│  └─────────────────────┘  └─────────────────────┘  └─────────────────────┘ │
│                                                                             │
│  ┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐ │
│  │   Application Layer │  │   AIOps Layer       │  │  Chaos Layer        │ │
│  │  ┌────────────────┐ │  │  ┌────────────────┐ │  │  ┌────────────────┐ │ │
│  │  │ Microservices  │ │  │  │ AI Engine      │ │  │  │ Chaos Mesh     │ │ │
│  │  │ Service Mesh   │ │  │  │ LangChain      │ │  │  │ Experiments    │ │ │
│  │  │ (Istio)        │ │  │  │ ChromaDB       │ │  │  │ Litmus        │ │ │
│  │  └────────────────┘ │  │  └────────────────┘ │  │  └────────────────┘ │ │
│  └─────────────────────┘  └─────────────────────┘  └─────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

[Detailed Architecture Document](docs/architecture/ARCHITECTURE.md)

---

## Technology Stack

| Layer | Technology | Version | Purpose |
|-------|-----------|---------|---------|
| **Infrastructure** | AWS | - | Cloud provider, managed services |
| **IaC** | Terraform | >= 1.7 | Infrastructure provisioning |
| **Container Orchestration** | Amazon EKS | 1.29 | Managed Kubernetes |
| **Autoscaling** | Karpenter | >= 0.37 | Intelligent node provisioning |
| **GitOps** | ArgoCD | >= 2.10 | Declarative continuous delivery |
| **Progressive Delivery** | Argo Rollouts | >= 1.6 | Canary/blue-green deployments |
| **CI/CD** | GitHub Actions | - | Build, test, security scan, deploy |
| **Service Mesh** | Istio | >= 1.21 | Traffic management, mTLS |
| **Ingress** | NGINX Ingress + ALB | - | HTTP/S routing |
| **Policy Engine** | Kyverno | >= 1.12 | Admission control, policy as code |
| **Runtime Security** | Falco | >= 0.37 | Behavioral monitoring |
| **Secrets** | External Secrets + SOPS | - | Secrets management |
| **Certificate Management** | cert-manager | >= 1.14 | TLS automation |
| **Metrics** | Prometheus + kube-state-metrics | - | Metrics collection |
| **Logging** | Loki + Promtail | - | Log aggregation |
| **Tracing** | Tempo | - | Distributed tracing |
| **Visualization** | Grafana | >= 10 | Dashboards, alerting |
| **AI/ML** | FastAPI + LangChain + ChromaDB | - | Incident analysis, RCA |
| **Chaos Engineering** | Chaos Mesh | >= 2.6 | Resilience testing |
| **Supply Chain** | Cosign + Trivy | - | Image signing, vulnerability scanning |
| **Backup** | Velero | >= 1.13 | Cluster backup and restore |
| **DNS** | Route53 + ExternalDNS | - | DNS automation |

---

## Quick Start

### 1. Prerequisites Check

```bash
# Verify required tools
aws --version          # >= 2.0
kubectl version        # >= 1.29
terraform --version    # >= 1.7
helm version           # >= 3.14
argocd version         # >= 2.10
docker --version       # >= 24.0
cosign version         # >= 2.0
trivy --version        # >= 0.50
```

### 2. Clone and Configure

```bash
git clone https://github.com/org/aiops-platform.git
cd aiops-platform

# Copy environment configuration
cp config/example.env config/dev.env
# Edit config/dev.env with your AWS account details
```

### 3. Deploy Infrastructure

```bash
# Deploy complete platform to dev environment
./scripts/bootstrap.sh dev

# Or deploy locally for development
./scripts/bootstrap.sh local
```

### 4. Access the Platform

```bash
# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Port-forward ArgoCD UI
kubectl port-forward -n argocd svc/argocd-server 8080:443

# Access at https://localhost:8080 (username: admin)
```

### 5. Deploy Your First Application

```bash
# Add your app repository to ArgoCD
argocd app create my-app \
  --repo https://github.com/org/my-app.git \
  --path deploy \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace my-app \
  --sync-policy automated

# Verify sync status
argocd app get my-app
```

---

## Repository Structure

```
aiops-platform/
├── README.md
├── LICENSE
├── .gitignore
├── .github/
│   ├── workflows/
│   │   ├── ci.yaml                    # Build, test, security scan
│   │   ├── deploy.yaml                # Deploy via ArgoCD
│   │   ├── security-scan.yaml         # Trivy, Cosign, SAST
│   │   ├── renovate.yaml              # Dependency updates
│   │   └── cleanup.yaml               # Scheduled teardown (dev)
│   └── CODEOWNERS
│
├── terraform/
│   ├── modules/
│   │   ├── vpc/                       # VPC with public/private subnets
│   │   ├── eks/                       # EKS cluster + node groups
│   │   ├── karpenter/                 # Karpenter provisioner
│   │   ├── rds/                       # PostgreSQL database
│   │   ├── elasticache/               # Redis cluster
│   │   ├── s3/                        # S3 buckets
│   │   ├── ecr/                       # Container registry
│   │   ├── iam/                       # IAM roles and policies
│   │   ├── kms/                       # KMS keys
│   │   ├── waf/                       # WAF rules
│   │   └── monitoring/                # CloudWatch, alarms
│   ├── environments/
│   │   ├── dev/
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── terraform.tfvars
│   │   ├── staging/
│   │   └── prod/
│   └── backend.tf                     # S3 + DynamoDB backend
│
├── argocd/
│   ├── app-of-apps/                   # Root application definitions
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── 00-infra.yaml
│   │       ├── 01-security.yaml
│   │       ├── 02-observability.yaml
│   │       ├── 03-aiops.yaml
│   │       └── 04-applications.yaml
│   ├── projects/                      # ArgoCD projects
│   └── values/                        # Helm values per environment
│       ├── dev/
│       ├── staging/
│       └── prod/
│
├── security/
│   ├── kyverno/
│   │   ├── policies/                  # Policy definitions
│   │   │   ├── disallow-latest-tag.yaml
│   │   │   ├── require-readiness-probes.yaml
│   │   │   ├── restrict-seccomp.yaml
│   │   │   └── ...
│   │   └── exceptions/
│   ├── falco/
│   │   ├── rules/                     # Custom Falco rules
│   │   └── falco-config.yaml
│   ├── network-policies/
│   │   ├── default-deny.yaml
│   │   ├── allow-dns.yaml
│   │   └── ...
│   └── pss/                           # Pod Security Standards
│       ├── baseline.yaml
│       └── restricted.yaml
│
├── monitoring/
│   ├── prometheus/
│   │   ├── prometheus-values.yaml
│   │   └── rules/                     # Alerting rules
│   │       ├── kubernetes-alerts.yaml
│   │       ├── application-alerts.yaml
│   │       └── security-alerts.yaml
│   ├── grafana/
│   │   ├── dashboards/                # JSON dashboard definitions
│   │   ├── datasources.yaml
│   │   └── alerting/                  # Grafana alerting rules
│   ├── loki/
│   │   └── loki-values.yaml
│   └── tempo/
│       └── tempo-values.yaml
│
├── aiops/
│   ├── engine/                        # AIOps FastAPI application
│   │   ├── main.py
│   │   ├── routers/
│   │   │   ├── incidents.py
│   │   │   ├── analysis.py
│   │   │   └── remediation.py
│   │   ├── services/
│   │   │   ├── rag_service.py         # LangChain RAG pipeline
│   │   │   ├── vector_store.py        # ChromaDB client
│   │   │   └── llm_client.py          # Multi-provider LLM
│   │   └── models/
│   ├── Dockerfile
│   └── charts/                        # AIOps Helm chart
│
├── chaos/
│   ├── experiments/
│   │   ├── pod-failure.yaml
│   │   ├── network-delay.yaml
│   │   ├── cpu-stress.yaml
│   │   └── dns-chaos.yaml
│   └── schedules/
│       └── weekly-resilience.yaml
│
├── applications/                      # Sample app manifests
│   └── sock-shop/                     # Microservices demo
│
├── docs/                              # Documentation (this directory)
│   ├── deployment/
│   ├── operations/
│   ├── security/
│   ├── troubleshooting/
│   ├── onboarding/
│   └── architecture/
│
├── scripts/                           # Automation scripts
│   ├── bootstrap.sh                   # Full platform bootstrap
│   ├── validation.sh                  # Smoke test suite
│   ├── chaos-runner.sh                # Chaos experiment runner
│   └── cleanup.sh                     # Platform teardown
│
└── config/                            # Environment configurations
    ├── example.env
    ├── dev.env
    ├── staging.env
    └── prod.env
```

---

## Prerequisites

| Requirement | Version | Purpose |
|------------|---------|---------|
| AWS Account | Active | Cloud infrastructure |
| AWS CLI | >= 2.0 | AWS API operations |
| kubectl | >= 1.29 | Kubernetes management |
| Terraform | >= 1.7 | Infrastructure provisioning |
| Helm | >= 3.14 | Kubernetes package management |
| ArgoCD CLI | >= 2.10 | GitOps management |
| Docker | >= 24.0 | Container builds |
| Cosign | >= 2.0 | Container image signing |
| Trivy | >= 0.50 | Vulnerability scanning |
| yq | >= 4.40 | YAML processing |
| jq | >= 1.7 | JSON processing |
| Git | >= 2.40 | Version control |
| Python | >= 3.11 | AIOps engine |
| Node.js | >= 20 | (Optional) UI development |

Full details in [Deployment Prerequisites](docs/deployment/01-prerequisites.md).

---

## Deployment Options

### Local Development (kind/k3d)

Best for development, testing, and offline work. Runs the full stack locally.

```bash
# Deploy local cluster with all services
./scripts/bootstrap.sh local

# Access ArgoCD at https://localhost:8443
# Access Grafana at https://localhost:3000
```

**Requirements**: 16GB RAM, 4 vCPUs, 50GB disk

[Local Deployment Guide](docs/deployment/03-local-deployment.md)

### AWS Production

Full enterprise deployment with HA, DR, and production security controls.

```bash
# Deploy to dev environment
./scripts/bootstrap.sh dev

# Deploy to production
./scripts/bootstrap.sh prod
```

**Requirements**: AWS account with appropriate limits, domain name, ACM certificate.

[AWS Deployment Guide](docs/deployment/04-aws-deployment.md)

---

## Security Features

| Capability | Implementation | Description |
|------------|---------------|-------------|
| **Supply Chain Security** | Cosign + Trivy + SLSA | Image signing, SBOM generation, provenance |
| **Policy as Code** | Kyverno | 50+ admission policies, custom rules |
| **Runtime Security** | Falco | Real-time behavioral monitoring, 1000+ rules |
| **Secrets Management** | External Secrets + SOPS + Sealed Secrets | Multi-layered secrets protection |
| **Network Security** | Calico + Network Policies | Zero-trust network segmentation |
| **Pod Security** | PSS (restricted) + Pod Security Admission | Secure pod specifications |
| **Identity** | IRSA + OIDC + RBAC | AWS IAM integration, least privilege |
| **TLS Everywhere** | cert-manager + Let's Encrypt | Automated certificate lifecycle |
| **Audit Logging** | CloudTrail + Kubernetes Audit + Falco | Complete audit trail |
| **Vulnerability Management** | Trivy + Grype | Continuous scanning in CI/CD |
| **Compliance** | SOC 2, PCI-DSS, NIST 800-53, CIS | Automated compliance validation |

Detailed security documentation in [Security Overview](docs/security/01-security-overview.md) and [Threat Model](docs/security/02-threat-model.md).

---

## Observability & AIOps

### Monitoring Stack

- **Metrics**: Prometheus with 500+ metrics, custom service metrics
- **Logs**: Loki with structured logging, log-based alerting
- **Traces**: Tempo with distributed tracing, service graph
- **Dashboards**: 20+ pre-built Grafana dashboards
- **Alerting**: 100+ alerting rules with severity classification

### AIOps Capabilities

The AIOps Engine provides intelligent operations:

- **Automated RCA**: Analyzes alerts, logs, and metrics to identify root causes
- **Incident Correlation**: Groups related alerts into incidents
- **Remediation Suggestions**: Recommends proven fixes based on historical patterns
- **Natural Language Queries**: Query your infrastructure in plain English
- **Predictive Analysis**: Identifies potential issues before they become incidents
- **Runbook Automation**: Executes remediation playbooks automatically

```bash
# Query the AIOps engine
curl -X POST https://aiops.platform.internal/api/v1/analyze \
  -H "Content-Type: application/json" \
  -d '{"incident_id": "INC-12345", "query": "What caused the 5xx spike?"}'
```

### SLOs and SLIs

| Metric | Target | Measurement |
|--------|--------|-------------|
| Availability | 99.95% | Uptime of critical services |
| Latency P99 | < 500ms | API response times |
| Error Rate | < 0.1% | HTTP 5xx / total requests |
| Deployment Frequency | Multiple/day | Successful deployments |
| MTTR | < 60 minutes | Time to resolve incidents |
| Change Failure Rate | < 5% | Failed deployments / total |

---

## Project Status

**Current Version**: 1.0.0  
**Stability**: Production-ready  
**Status**: Active development  

### Roadmap

- [x] EKS cluster provisioning with Terraform
- [x] ArgoCD GitOps bootstrap with App-of-Apps
- [x] Kyverno policy engine with 50+ policies
- [x] Falco runtime security
- [x] Prometheus + Grafana monitoring
- [x] Loki log aggregation
- [x] Tempo distributed tracing
- [x] Karpenter autoscaling
- [x] Chaos Mesh integration
- [x] AIOps engine with LangChain
- [x] Supply chain security (Cosign, Trivy)
- [ ] OPA/Gatekeeper migration support
- [ ] Multi-cluster federation
- [ ] Cross-region DR automation
- [ ] FinOps dashboard
- [ ] Self-service developer portal

---

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

### Quick Guidelines

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Workflow

- All changes must go through pull requests
- Required checks: lint, test, security scan
- Code review required (minimum 2 approvals)
- Conventional commits format
- Update documentation with any changes

### Reporting Issues

- **Security issues**: Email security@platform.internal (do NOT open a public issue)
- **Bug reports**: Use the bug report template
- **Feature requests**: Use the feature request template

---

## License

Distributed under the Apache License 2.0. See [LICENSE](LICENSE) for more information.

---

**Built with** by the Platform Engineering Team.
