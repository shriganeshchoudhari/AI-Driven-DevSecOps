# Developer Onboarding Guide

Complete onboarding guide for developers joining the platform.

---

## Table of Contents

- [Access Request Process](#access-request-process)
- [Tool Installation](#tool-installation)
- [Local Environment Setup](#local-environment-setup)
- [First Deployment Walkthrough](#first-deployment-walkthrough)
- [Common Workflows](#common-workflows)
- [Code Review Requirements](#code-review-requirements)
- [Testing Requirements](#testing-requirements)
- [Security Awareness](#security-awareness)

---

## Access Request Process

### Step 1: Request Access

Submit a ticket to the Platform Engineering team with:

- GitHub username
- AWS IAM username (if applicable)
- Team and role
- Required namespaces

### Step 2: Complete Onboarding Checklist

```markdown
## Developer Onboarding Checklist

### Week 1: Access & Setup
- [ ] GitHub account added to org
- [ ] AWS IAM role assigned
- [ ] OIDC provider configured for CLI access
- [ ] Tools installed (see below)
- [ ] Local environment verified
- [ ] Platform README reviewed

### Week 2: Platform Familiarization
- [ ] Architecture overview completed
- [ ] First application deployed via ArgoCD
- [ ] Grafana dashboards reviewed
- [ ] Logging (Loki) queries practiced
- [ ] Prometheus metrics explored

### Week 3: Development Workflow
- [ ] CI/CD pipeline understood
- [ ] Helm chart created for service
- [ ] Canary deployment configured
- [ ] Security scanning in CI/CD
- [ ] Code review process followed

### Week 4: Operations
- [ ] On-call shadow shift completed
- [ ] Incident response flow understood
- [ ] Troubleshooting runbooks reviewed
- [ ] Chaos engineering concepts learned
```

### Step 3: Verify Access

```bash
# Verify GitHub access
ssh -T git@github.com

# Verify AWS access
aws sts get-caller-identity

# Verify Kubernetes access
kubectl auth can-i get pods -n <your-namespace>
```

---

## Tool Installation

### Required Tools

```bash
# Install all required tools
# macOS
brew install awscli kubectl helm argocd terraform docker cosign trivy velero yq jq k9s stern

# Verify all tools
for tool in aws kubectl helm argocd terraform docker cosign trivy velero yq jq; do
  if command -v $tool &> /dev/null; then
    echo "✓ $tool: $($tool --version 2>&1 | head -1)"
  else
    echo "✗ $tool: NOT INSTALLED"
  fi
done
```

### IDE Setup (VS Code)

```bash
# Install recommended extensions
code --install-extension ms-kubernetes-tools.vscode-kubernetes-tools
code --install-extension hashicorp.terraform
code --install-extension redhat.vscode-yaml
code --install-extension golang.go
code --install-extension ms-python.python
code --install-extension redhat.vscode-docker
code --install-extension signpath.ms-vscode-helm
code --install-extension DavidAnson.vscode-markdownlint
code --install-extension eamodio.gitlens
```

### kubectl Plugins (krew)

```bash
# Install krew
brew install krew

# Install useful plugins
kubectl krew install ctx
kubectl krew install ns
kubectl krew install stern
kubectl krew install tree
kubectl krew install view-secret
kubectl krew install tail
kubectl krew install sniff
kubectl krew install who-can

# Usage
kubectl ctx          # Switch context
kubectl ns           # Switch namespace
kubectl tree pod     # View pod tree
kubectl view-secret  # Decode secrets
```

---

## Local Environment Setup

### Clone Repository

```bash
git clone git@github.com:org/aiops-platform.git
cd aiops-platform
```

### Configure AWS Profile

```bash
# Create profile for development
aws configure --profile platform-dev
# AWS Access Key ID: [your-access-key]
# AWS Secret Access Key: [your-secret-key]
# Default region: us-west-2
# Default output format: json

# Set as active profile
export AWS_PROFILE=platform-dev
```

### Deploy Local Kubernetes

```bash
# Option 1: kind (recommended)
kind create cluster --name platform-dev
kubectl config use-context kind-platform-dev

# Option 2: k3d
k3d cluster create platform-dev
kubectl config use-context k3d-platform-dev

# Verify
kubectl get nodes
```

### Deploy Platform Services

```bash
# Deploy ArgoCD locally
./scripts/deploy-argocd-local.sh

# Deploy monitoring
./scripts/deploy-monitoring-local.sh

# Access ArgoCD UI
argocd login localhost:8080 --username admin \
  --password $(kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d)
```

---

## First Deployment Walkthrough

### Step 1: Create Application Repository

```bash
# Create your application repo
gh repo create org/my-service --private --template=org/service-template

# Clone the template
git clone git@github.com:org/my-service.git
cd my-service
```

### Step 2: Define Your Service

```yaml
# deploy/values.yaml
replicaCount: 2

image:
  repository: 123456789012.dkr.ecr.us-west-2.amazonaws.com/platform/my-service
  tag: latest
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 8080

ingress:
  enabled: true
  host: my-service.platform.example.com
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod

resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 100m
    memory: 128Mi

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
```

### Step 3: Create ArgoCD Application

```yaml
# argocd/applications/my-service.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-service
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "5"
spec:
  destination:
    namespace: my-service
    server: https://kubernetes.default.svc
  project: default
  source:
    helm:
      valueFiles:
      - values.yaml
    path: deploy
    repoURL: https://github.com/org/my-service.git
    targetRevision: main
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

### Step 4: Deploy via ArgoCD

```bash
# Add application to Git
git add argocd/applications/my-service.yaml
git commit -m "feat: add my-service application"

# Push to main branch
git push origin main

# ArgoCD will auto-sync (with auto-sync enabled)
# Or trigger sync manually
argocd app sync my-service

# Check status
argocd app get my-service -o json | jq '{name: .metadata.name, sync: .status.sync.status, health: .status.health.status}'
```

### Step 5: Verify Deployment

```bash
# Check pods
kubectl get pods -n my-service -w

# Check service
kubectl get svc -n my-service

# Access the service
kubectl port-forward -n my-service svc/my-service 8080:8080

# Test health endpoint
curl -s http://localhost:8080/health | jq .
```

---

## Common Workflows

### Development Workflow

```bash
# 1. Create feature branch
git checkout -b feature/my-feature

# 2. Make changes
# ...

# 3. Run tests locally
make test
make lint

# 4. Build and push image
make docker-build
make docker-push
cosign sign <image>

# 5. Update Helm values
# deploy/values.yaml

# 6. Commit and push
git add .
git commit -m "feat: add my feature"
git push origin feature/my-feature

# 7. Create PR
gh pr create --fill

# 8. PR approved and merged
# 9. ArgoCD syncs automatically
```

### Debugging Workflow

```bash
# 1. Check pod status
kubectl get pods -n my-service

# 2. Check logs
kubectl logs -n my-service deployment/my-service --tail=100

# 3. Stream logs
stern -n my-service my-service

# 4. Exec into pod
kubectl exec -it -n my-service deployment/my-service -- /bin/sh

# 5. Check events
kubectl get events -n my-service --sort-by='.lastTimestamp'

# 6. Check Prometheus metrics
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-stack-prometheus 9090:9090
# Open http://localhost:9090, query: application_error_total

# 7. Check Grafana dashboard
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# Open http://localhost:3000
```

---

## Code Review Requirements

### Mandatory Checks

All PRs must pass:

1. **Code linting** (`make lint`)
2. **Unit tests** (`make test`)
3. **Build** (`make docker-build`)
4. **Security scan** (Trivy, Semgrep)
5. **Terraform plan** (for infra changes)
6. **At least 2 approvals** from code owners

### Review Checklist

```markdown
## Code Review Checklist

### Security
- [ ] No secrets hardcoded
- [ ] Input validation present
- [ ] Authentication required for APIs
- [ ] Least privilege for IAM/IRSA
- [ ] No privileged containers
- [ ] Resource limits specified

### Operations
- [ ] Health endpoints implemented (/health, /ready)
- [ ] Metrics exposed for Prometheus
- [ ] Structured logging
- [ ] Graceful shutdown handling
- [ ] Configuration via environment variables
- [ ] Liveness and readiness probes configured

### Reliability
- [ ] Error handling complete
- [ ] Retry logic for external calls
- [ ] Circuit breakers considered
- [ ] Rate limiting considered
- [ ] Graceful degradation

### Testing
- [ ] Unit tests pass
- [ ] Integration tests pass
- [ ] Security tests pass
- [ ] Helm chart tested locally

### Documentation
- [ ] README updated
- [ ] API documentation updated
- [ ] Deployment documentation updated
- [ ] Runbook created/updated
```

---

## Testing Requirements

### Test Categories

| Test Type | Required | Frequency | Tool |
|-----------|----------|-----------|------|
| Unit tests | ✓ | Every commit | pytest, go test |
| Integration tests | ✓ | Every PR | pytest + k8s |
| End-to-end tests | ✓ | Every deploy | Cypress, Playwright |
| Security tests | ✓ | Every PR | Trivy, Semgrep |
| Chaos tests | Monthly | Scheduled | Chaos Mesh |
| Load tests | Quarterly | Scheduled | k6, Locust |

### Local Test Commands

```bash
# Run unit tests
make test

# Run linter
make lint

# Run security scan
make security-scan

# Run integration tests
make integration-test

# Run all tests
make citest
```

---

## Security Awareness

### Mandatory Training

Complete the following before accessing production:

1. **Platform Security Overview** - Read docs/security/01-security-overview.md
2. **Phishing Awareness** - Annual training
3. **Data Classification** - Understand data handling
4. **Incident Response** - Know how to report
5. **OWASP Top 10** - Application security basics

### Security Rules

```
DO:
✓ Use OIDC for authentication
✓ Store secrets in AWS Secrets Manager
✓ Use IRSA for AWS access
✓ Follow least privilege principle
✓ Enable audit logging
✓ Run security scans before deploy
✓ Report security issues to security@example.com

DON'T:
✗ Hardcode secrets in code
✗ Use privileged containers
✗ Bypass admission controllers
✗ Share credentials
✗ Store secrets in Git
✗ Disable security controls
✗ Ignore vulnerability reports
```

### Reporting Security Issues

```yaml
# Security issue reporting
email: security@example.com
slack: #security-alerts
severity: CRITICAL / HIGH / MEDIUM / LOW
response_time:
  CRITICAL: 15 minutes
  HIGH: 1 hour
  MEDIUM: 24 hours
  LOW: 72 hours
```

---

## Next Steps

1. [Review SRE onboarding guide](02-sre-onboarding.md)
2. [Review architecture overview](../architecture/ARCHITECTURE.md)
3. [Review SRE runbook](../operations/01-sre-runbook.md)
