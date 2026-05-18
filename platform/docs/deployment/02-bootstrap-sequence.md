# Bootstrap Sequence

Complete step-by-step deployment of the AI-Driven Secure GitOps Platform, organized into five phases across Day 0 through Day 4.

---

## Table of Contents

- [Phase 1: Foundation (Day 0)](#phase-1-foundation-day-0)
- [Phase 2: Platform Services (Day 1)](#phase-2-platform-services-day-1)
- [Phase 3: Security (Day 2)](#phase-3-security-day-2)
- [Phase 4: Applications (Day 3)](#phase-4-applications-day-3)
- [Phase 5: Chaos & Resilience (Day 4)](#phase-5-chaos--resilience-day-4)
- [Expected Timelines](#expected-timelines)
- [Validation Gates](#validation-gates)

---

## Phase 1: Foundation (Day 0)

Estimated time: 60-90 minutes

### Step 1: Clone Repository

```bash
git clone git@github.com:org/aiops-platform.git
cd aiops-platform
git checkout -b deploy/initial-setup
```

### Step 2: Configure AWS Credentials

```bash
# Option A: Named profile
export AWS_PROFILE=platform-admin

# Option B: Environment variables
export AWS_ACCESS_KEY_ID=AKIAXXXXXXXXXXXX
export AWS_SECRET_ACCESS_KEY=wJalrXUtxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
export AWS_REGION=us-west-2

# Verify
aws sts get-caller-identity
```

Expected output:
```json
{
    "UserId": "AIDAXXXXXXXXXXXXX",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/platform-admin"
}
```

### Step 3: Create S3 Backend Bucket and DynamoDB Lock Table

```bash
# Variables
AWS_REGION="us-west-2"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BACKEND_BUCKET="platform-terraform-state-${AWS_ACCOUNT_ID}"
LOCK_TABLE="platform-terraform-locks"

# Create S3 bucket
aws s3api create-bucket \
  --bucket "${BACKEND_BUCKET}" \
  --region "${AWS_REGION}" \
  --create-bucket-configuration LocationConstraint="${AWS_REGION}"

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket "${BACKEND_BUCKET}" \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket "${BACKEND_BUCKET}" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Block public access
aws s3api put-public-access-block \
  --bucket "${BACKEND_BUCKET}" \
  --public-access-block-configuration '{
    "BlockPublicAcls": true,
    "IgnorePublicAcls": true,
    "BlockPublicPolicy": true,
    "RestrictPublicBuckets": true
  }'

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name "${LOCK_TABLE}" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "${AWS_REGION}"

# Wait for table to be active
aws dynamodb wait table-exists --table-name "${LOCK_TABLE}"

echo "Backend bucket: s3://${BACKEND_BUCKET}"
echo "Lock table: ${LOCK_TABLE}"
```

### Step 4: Deploy Terraform — Core Infrastructure

```bash
cd terraform/environments/dev

# Initialize with backend config
cat > backend.hcl << EOF
bucket         = "platform-terraform-state-123456789012"
key            = "dev/terraform.tfstate"
region         = "us-west-2"
dynamodb_table = "platform-terraform-locks"
encrypt        = true
EOF

terraform init -backend-config=backend.hcl

# Create workspace
terraform workspace select dev || terraform workspace new dev

# Plan core infrastructure (targeted)
terraform plan -target=module.vpc \
               -target=module.kms \
               -target=module.s3 \
               -target=module.iam \
               -target=module.ecr \
               -out=phase1-core.tfplan

# Review and apply
terraform apply phase1-core.tfplan
```

Expected output:
```
Apply complete! Resources: 42 added, 0 changed, 0 destroyed.

Outputs:
vpc_id = "vpc-0a1b2c3d4e5f67890"
kms_key_id = "arn:aws:kms:us-west-2:..."
s3_log_bucket = "platform-logs-..."
ecr_repos = {
  "aiops-engine" = "123456789012.dkr.ecr.us-west-2.amazonaws.com/platform/aiops-engine"
}
```

### Step 5: Deploy Terraform — EKS Cluster

```bash
# Plan EKS cluster
terraform plan -target=module.eks \
               -target=module.karpenter \
               -out=phase2-eks.tfplan

# Apply
terraform apply phase2-eks.tfplan
```

Expected output:
```
module.eks.eks_cluster_id: Still creating... [10m0s elapsed]
module.eks.eks_cluster_id: Creation complete after 12m30s
module.eks.node_group: Still creating... [5m0s elapsed]
module.eks.node_group: Creation complete after 8m15s

Apply complete! Resources: 25 added, 0 changed, 0 destroyed.

Outputs:
cluster_name = "platform-dev"
cluster_endpoint = "https://xxxxxxxxxxxx.gr7.us-west-2.eks.amazonaws.com"
cluster_ca_certificate = "<base64-encoded-cert>"
node_role_arn = "arn:aws:iam::123456789012:role/platform-eks-node-role"
karpenter_node_role = "arn:aws:iam::123456789012:role/platform-karpenter-node-role"
```

### Step 6: Configure kubectl Context

```bash
# Get cluster name from Terraform output
CLUSTER_NAME=$(terraform output -raw cluster_name)

# Update kubeconfig
aws eks update-kubeconfig \
  --name "${CLUSTER_NAME}" \
  --region us-west-2 \
  --alias platform-dev

# Verify
kubectl cluster-info
```

Expected output:
```
Kubernetes control plane is running at https://xxxxxxxxxxxx.gr7.us-west-2.eks.amazonaws.com
CoreDNS is running at https://xxxxxxxxxxxx.gr7.us-west-2.eks.amazonaws.com/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
```

### Step 7: Validate Cluster Access

```bash
# Check nodes
kubectl get nodes -o wide
```

Expected output:
```
NAME                          STATUS   ROLES    AGE   VERSION               INTERNAL-IP    EXTERNAL-IP
ip-10-0-10-123.ec2.internal  Ready    <none>   5m    v1.29.0-eks-xxx       10.0.10.123    xx.xx.xx.xx
ip-10-0-11-45.ec2.internal   Ready    <none>   5m    v1.29.0-eks-xxx       10.0.11.45     xx.xx.xx.xx
ip-10-0-12-67.ec2.internal   Ready    <none>   4m    v1.29.0-eks-xxx       10.0.12.67     xx.xx.xx.xx
```

```bash
# Check system pods
kubectl get pods -n kube-system
```

Expected output:
```
NAME                       READY   STATUS    RESTARTS   AGE
aws-node-abc123            1/1     Running   0          5m
aws-node-def456            1/1     Running   0          5m
aws-node-ghi789            1/1     Running   0          4m
coredns-xxxxxxxxxx-yyyyy   1/1     Running   0          5m
coredns-xxxxxxxxxx-zzzzz   1/1     Running   0          5m
kube-proxy-abc123          1/1     Running   0          5m
kube-proxy-def456          1/1     Running   0          5m
kube-proxy-ghi789          1/1     Running   0          4m
```

```bash
# Check Karpenter pods
kubectl get pods -n karpenter
```

Expected output:
```
NAME                              READY   STATUS    RESTARTS   AGE
karpenter-xxxxxxxxxx-yyyyy        1/1     Running   0          3m
karpenter-xxxxxxxxxx-zzzzz        1/1     Running   0          3m
```

### Phase 1 Validation Gate

```bash
cat << 'EOF'
╔══════════════════════════════════════════════════════╗
║         PHASE 1 VALIDATION CHECKLIST                ║
╠══════════════════════════════════════════════════════╣
║ [ ] S3 backend bucket created + versioning enabled  ║
║ [ ] DynamoDB lock table active                      ║
║ [ ] VPC with public/private subnets                 ║
║ [ ] KMS key created                                  ║
║ [ ] IAM roles created (cluster, node, IRSA)         ║
║ [ ] ECR repositories created                        ║
║ [ ] EKS cluster status = ACTIVE                     ║
║ [ ] All 3 nodes Ready                               ║
║ [ ] CoreDNS and kube-proxy running                  ║
║ [ ] Karpenter pods running                          ║
╚══════════════════════════════════════════════════════╝
EOF
```

---

## Phase 2: Platform Services (Day 1)

Estimated time: 60-90 minutes

### Step 1: Install ArgoCD via Helm

```bash
# Create namespace
kubectl create namespace argocd

# Add ArgoCD Helm repository
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# Install ArgoCD
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --version 7.0.0 \
  --values ../../argocd/values.yaml \
  --wait \
  --timeout 10m
```

Expected output:
```
Release "argocd" has been upgraded. Happy Helming!
NAME: argocd
LAST DEPLOYED: ...
NAMESPACE: argocd
STATUS: deployed
REVISION: 1
TEST SUITE: None
```

```bash
# Verify ArgoCD pods
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s
kubectl get pods -n argocd
```

Expected output:
```
NAME                                                READY   STATUS    RESTARTS   AGE
argocd-application-controller-0                     1/1     Running   0          2m
argocd-applicationset-controller-xxxxxxxxxx-yyyyy   1/1     Running   0          2m
argocd-dex-server-xxxxxxxxxx-yyyyy                  1/1     Running   0          2m
argocd-notifications-controller-xxxxxxxxxx-yyyyy    1/1     Running   0          2m
argocd-redis-xxxxxxxxxx-yyyyy                       1/1     Running   0          2m
argocd-repo-server-xxxxxxxxxx-yyyyy                 1/1     Running   0          2m
argocd-server-xxxxxxxxxx-yyyyy                      1/1     Running   0          2m
```

### Step 2: Bootstrap ArgoCD Root Application

```bash
# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Login to ArgoCD
argocd login localhost:8080 \
  --username admin \
  --password $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d) \
  --insecure

# Apply root application
kubectl apply -f ../../argocd/app-of-apps/templates/
```

Expected output:
```
application.argoproj.io/root-app created
```

```bash
# Check root app status
argocd app get root-app
```

Expected output:
```
Name:               root-app
Project:            default
Server:             https://kubernetes.default.svc
Namespace:          argocd
URL:                https://localhost:8080/applications/root-app
Status:             Synced
Health:             Healthy
```

### Step 3: Install NGINX Ingress Controller

```bash
# The App-of-Apps will install this, but for manual verification:
kubectl get pods -n ingress-nginx
```

Expected output:
```
NAME                                       READY   STATUS    RESTARTS   AGE
ingress-nginx-controller-xxxxxxxxxx-yyyy   1/1     Running   0          2m
```

```bash
# Get ALB/NLB endpoint
kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

### Step 4: Install cert-manager with ClusterIssuer

```bash
# Verify cert-manager installation
kubectl get pods -n cert-manager
```

Expected output:
```
NAME                                       READY   STATUS    RESTARTS   AGE
cert-manager-xxxxxxxxxx-yyyyy              1/1     Running   0          1m
cert-manager-cainjector-xxxxxxxxxx-yyyyy   1/1     Running   0          1m
cert-manager-webhook-xxxxxxxxxx-yyyyy      1/1     Running   0          1m
```

```bash
# Create ClusterIssuer for Let's Encrypt
cat << EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: devops@platform.example.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
    - dns01:
        route53:
          region: us-west-2
          hostedZoneID: ZXXXXXXXXXXXX
EOF
```

### Step 5: Install External Secrets with AWS Integration

```bash
# Verify External Secrets installation
kubectl get pods -n external-secrets
```

Expected output:
```
NAME                                                READY   STATUS    RESTARTS   AGE
external-secrets-xxxxxxxxxx-yyyyy                   1/1     Running   0          1m
external-secrets-cert-controller-xxxxxxxxxx-yyyy    1/1     Running   0          1m
external-secrets-webhook-xxxxxxxxxx-yyyyy           1/1     Running   0          1m
```

```bash
# Create ClusterSecretStore
cat << EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-west-2
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets
EOF
```

### Step 6: Deploy Prometheus Stack

```bash
# Verify Prometheus stack
kubectl get pods -n monitoring
```

Expected output:
```
NAME                                                         READY   STATUS    RESTARTS   AGE
prometheus-kube-prometheus-stack-prometheus-0                2/2     Running   0          3m
prometheus-kube-prometheus-stack-grafana-xxxxxxxxxx-yyyy     3/3     Running   0          3m
prometheus-kube-prometheus-stack-kube-state-metrics-xxxxxxx  1/1     Running   0          3m
prometheus-kube-prometheus-stack-operator-xxxxxxxxxx-yyyy    1/1     Running   0          3m
prometheus-prometheus-node-exporter-xxxxx                    1/1     Running   0          3m
prometheus-prometheus-node-exporter-yyyyy                    1/1     Running   0          3m
prometheus-prometheus-node-exporter-zzzzz                    1/1     Running   0          3m
```

```bash
# Verify Prometheus targets
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-stack-prometheus 9090:9090
# Open http://localhost:9090/targets - all should be UP
```

### Step 7: Deploy Loki + Promtail

```bash
# Verify Loki
kubectl get pods -n monitoring -l app.kubernetes.io/name=loki
```

Expected output:
```
NAME                    READY   STATUS    RESTARTS   AGE
loki-0                  1/1     Running   0          2m
loki-1                  1/1     Running   0          2m
loki-gateway-xxxxx      1/1     Running   0          2m
promtail-xxxxx          1/1     Running   0          2m
promtail-yyyyy          1/1     Running   0          2m
promtail-zzzzz          1/1     Running   0          2m
```

```bash
# Verify log ingestion
kubectl port-forward -n monitoring svc/loki-gateway 3100:80
curl -s "http://localhost:3100/loki/api/v1/labels" | jq
```

Expected output (truncated):
```json
{
    "status": "success",
    "data": ["__name__", "container", "job", "namespace", "pod", "stream"]
}
```

### Step 8: Deploy Tempo

```bash
# Verify Tempo
kubectl get pods -n monitoring -l app.kubernetes.io/name=tempo
```

Expected output:
```
NAME                    READY   STATUS    RESTARTS   AGE
tempo-0                 1/1     Running   0          2m
tempo-1                 1/1     Running   0          2m
tempo-query-frontend-xxx 1/1   Running   0          2m
```

### Step 9: Configure Grafana Datasources

```bash
# Verify datasources are auto-configured
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-stack-grafana 3000:80

# Get Grafana admin password
kubectl get secret -n monitoring prometheus-kube-prometheus-stack-grafana \
  -o jsonpath="{.data.admin-password}" | base64 -d

# Login at http://localhost:3000 (admin / <password>)
# Verify datasources: Configuration > Data Sources
# Expected: Prometheus, Loki, Tempo
```

### Phase 2 Validation Gate

```bash
cat << 'EOF'
╔══════════════════════════════════════════════════════╗
║         PHASE 2 VALIDATION CHECKLIST                ║
╠══════════════════════════════════════════════════════╣
║ [ ] ArgoCD installed and accessible                 ║
║ [ ] Root App-of-Apps deployed and Synced            ║
║ [ ] NGINX Ingress Controller running                ║
║ [ ] cert-manager with ClusterIssuer                 ║
║ [ ] External Secrets + ClusterSecretStore           ║
║ [ ] Prometheus targets all UP                       ║
║ [ ] Grafana accessible with datasources             ║
║ [ ] Loki ingesting logs                             ║
║ [ ] Tempo receiving traces                          ║
╚══════════════════════════════════════════════════════╝
EOF
```

---

## Phase 3: Security (Day 2)

Estimated time: 45-60 minutes

### Step 1: Install Kyverno with Policies

```bash
# Verify Kyverno installation
kubectl get pods -n kyverno
```

Expected output:
```
NAME                                           READY   STATUS    RESTARTS   AGE
kyverno-admission-controller-xxxxxxxxxx-yyyy   1/1     Running   0          2m
kyverno-background-controller-xxxxxxxxxx-yyy   1/1     Running   0          2m
kyverno-cleanup-controller-xxxxxxxxxx-yyyy     1/1     Running   0          2m
kyverno-reports-controller-xxxxxxxxxx-yyyy     1/1     Running   0          2m
```

```bash
# Verify policies are installed
kubectl get clusterpolicy
```

Expected output:
```
NAME                              BACKGROUND   ACTION   READY
disallow-latest-tag               true         Enforce  Yes
disallow-privileged-containers    true         Enforce  Yes
require-readiness-probes          true         Enforce  Yes
require-resource-limits           true         Enforce  Yes
require-ro-rootfs                 true         Enforce  Yes
restrict-automount-sa-token       true         Enforce  Yes
restrict-host-namespaces          true         Enforce  Yes
restrict-host-ports               true         Enforce  Yes
restrict-seccomp                  true         Enforce  Yes
restrict-volume-types             true         Enforce  Yes
unique-ingress-host               true         Enforce  Yes
validate-image-signature          true         Enforce  Yes
```

```bash
# Test a policy violation
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: nginx-bad
spec:
  containers:
  - name: nginx
    image: nginx:latest
    securityContext:
      privileged: true
EOF
```

Expected output:
```
Error from server: admission webhook "validate.kyverno.svc-fail" denied the request:
  resource Pod/default/nginx-bad was blocked due to the following policies:
    disallow-privileged-containers:
      privilege-escalation: validate.kyverno.svc-fail: privileged container is not allowed
```

### Step 2: Install Falco with Custom Rules

```bash
# Verify Falco
kubectl get pods -n falco
```

Expected output:
```
NAME                    READY   STATUS    RESTARTS   AGE
falco-xxxxx             1/1     Running   0          2m
falco-yyyyy             1/1     Running   0          2m
falco-zzzzz             1/1     Running   0          2m
```

```bash
# Check Falco events
kubectl logs -n falco daemonset/falco --tail=10
```

Expected output:
```
Sun May 17 10:00:00 2026: Notice A shell was spawned in a container with an attached terminal (user=root ...)
Sun May 17 10:00:01 2026: Warning An executable was launched in a writeable container (user=root ...)
```

### Step 3: Configure Falcosidekick

```bash
# Verify Falcosidekick
kubectl get pods -n falco -l app.kubernetes.io/name=falcosidekick
```

Expected output:
```
NAME                          READY   STATUS    RESTARTS   AGE
falco-falcosidekick-xxxxx     1/1     Running   0          2m
```

### Step 4: Apply Network Policies

```bash
# Verify default-deny policies
kubectl get networkpolicies --all-namespaces
```

Expected output:
```
NAMESPACE     NAME          POD-SELECTOR   AGE
default       default-deny  <none>         2m
kube-system   default-deny  <none>         2m
monitoring    default-deny  <none>         2m
argocd        default-deny  <none>         2m
```

### Step 5: Configure Pod Security Standards

```bash
# Verify PSS labels on namespaces
kubectl get ns --show-labels | grep pod-security
```

Expected output:
```
default       Active    ... pod-security.kubernetes.io/enforce=restricted
monitoring    Active    ... pod-security.kubernetes.io/enforce=baseline
argocd        Active    ... pod-security.kubernetes.io/enforce=baseline
```

### Step 6: Set Up RBAC

```bash
# Verify RBAC resources
kubectl get clusterroles,clusterrolebindings -n platform
```

Expected output should show:
- `platform-admin` cluster role
- `platform-viewer` cluster role
- `platform-developer` cluster role
- Corresponding bindings for each team

### Phase 3 Validation Gate

```bash
cat << 'EOF'
╔══════════════════════════════════════════════════════╗
║         PHASE 3 VALIDATION CHECKLIST                ║
╠══════════════════════════════════════════════════════╣
║ [ ] Kyverno installed and policies enforced         ║
║ [ ] Falco running on all nodes                      ║
║ [ ] Falcosidekick configured                        ║
║ [ ] Default-deny network policies applied           ║
║ [ ] Pod Security Standards configured               ║
║ [ ] RBAC roles and bindings applied                 ║
║ [ ] Test policy violation blocked correctly         ║
╚══════════════════════════════════════════════════════╝
EOF
```

---

## Phase 4: Applications (Day 3)

Estimated time: 60-90 minutes

### Step 1: Deploy AIOps Engine

```bash
# Verify AIOps deployment
kubectl get pods -n aiops
```

Expected output:
```
NAME                                 READY   STATUS    RESTARTS   AGE
aiops-engine-xxxxxxxxxx-yyyyy        2/2     Running   0          2m
aiops-analyzer-xxxxxxxxxx-yyyyy      2/2     Running   0          2m
aiops-chromadb-0                     1/1     Running   0          2m
```

```bash
# Verify AIOps API health
kubectl port-forward -n aiops svc/aiops-engine 8000:8000
curl -s http://localhost:8000/health | jq
```

Expected output:
```json
{
    "status": "healthy",
    "version": "1.0.0",
    "components": {
        "vector_store": "connected",
        "llm_provider": "configured",
        "prometheus": "connected",
        "loki": "connected"
    }
}
```

### Step 2: Deploy Microservices via ArgoCD

```bash
# Add application to ArgoCD via App-of-Apps
# The root app should auto-sync, but verify:
argocd app sync applications -l app.kubernetes.io/part-of=platform

# Check application status
argocd app list
```

Expected output:
```
NAME                  CLUSTER                         NAMESPACE  PROJECT  STATUS   HEALTH   SYNCPOLICY
applications          https://kubernetes.default.svc  default    default  Synced   Healthy  Auto-Prune
aiops                 https://kubernetes.default.svc  aiops      default  Synced   Healthy  Auto-Prune
argocd                https://kubernetes.default.svc  argocd     default  Synced   Healthy  Auto-Prune
cert-manager          https://kubernetes.default.svc  cert-man   default  Synced   Healthy  Auto-Prune
external-secrets      https://kubernetes.default.svc  ext-sec    default  Synced   Healthy  Auto-Prune
ingress-nginx         https://kubernetes.default.svc  ingress    default  Synced   Healthy  Auto-Prune
kyverno               https://kubernetes.default.svc  kyverno    default  Synced   Healthy  Auto-Prune
monitoring            https://kubernetes.default.svc  monitor    default  Synced   Healthy  Auto-Prune
```

### Step 3: Configure Canary Deployments

```bash
# Verify Argo Rollouts
kubectl get pods -n argo-rollouts
```

Expected output:
```
NAME                                  READY   STATUS    RESTARTS   AGE
argo-rollouts-xxxxxxxxxx-yyyyy        1/1     Running   0          2m
```

```bash
# Check rollouts
kubectl get rollouts -A
```

Expected output:
```
NAMESPACE   NAME          DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   STATUS
default     my-app        5         5         5            5           Healthy
```

### Step 4: Set Up HPA/VPA

```bash
# Verify HPAs
kubectl get hpa -A
```

Expected output:
```
NAMESPACE   NAME            REFERENCE              TARGETS         MINPODS   MAXPODS   REPLICAS
default     my-app          Deployment/my-app       45%/70%        2         10        5
aiops       aiops-engine    Deployment/aiops-engine 30%/80%        2         8         3
```

```bash
# Verify VPAs
kubectl get vpa -A
```

Expected output:
```
NAMESPACE   NAME            MODE         CPU        MEM         UPDATED
default     my-app-vpa      Auto         250m       512Mi       True
aiops       aiops-vpa       Auto         500m       1Gi         True
```

### Step 5: Configure Alerting Rules

```bash
# Verify Prometheus rules
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-stack-prometheus 9090:9090
curl -s "http://localhost:9090/api/v1/rules" | jq '.data.groups[].name'
```

Expected output:
```
"kubernetes-apps"
"kubernetes-resources"
"kubernetes-storage"
"kubernetes-system"
"node-exporter"
"platform.alerts"
"aiops.alerts"
"security.alerts"
```

### Step 6: Validate End-to-End Flow

```bash
# Deploy sample application
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: demo
  labels:
    pod-security.kubernetes.io/enforce: restricted
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-app
  namespace: demo
spec:
  replicas: 3
  selector:
    matchLabels:
      app: demo-app
  template:
    metadata:
      labels:
        app: demo-app
    spec:
      containers:
      - name: app
        image: nginx:1.25
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
        readinessProbe:
          httpGet:
            path: /
            port: 80
        securityContext:
          runAsNonRoot: true
          runAsUser: 101
          capabilities:
            drop: ["ALL"]
          seccompProfile:
            type: RuntimeDefault
---
apiVersion: v1
kind: Service
metadata:
  name: demo-app
  namespace: demo
spec:
  ports:
  - port: 80
    targetPort: 80
  selector:
    app: demo-app
EOF

# Verify everything works
kubectl wait --for=condition=Ready pods -l app=demo-app -n demo --timeout=60s
kubectl port-forward -n demo svc/demo-app 8080:80
curl -s http://localhost:8080 | head -5
```

### Phase 4 Validation Gate

```bash
cat << 'EOF'
╔══════════════════════════════════════════════════════╗
║         PHASE 4 VALIDATION CHECKLIST                ║
╠══════════════════════════════════════════════════════╣
║ [ ] AIOps Engine deployed and healthy               ║
║ [ ] Microservices deployed via ArgoCD               ║
║ [ ] All ArgoCD apps Synced and Healthy              ║
║ [ ] Canary deployments configured                   ║
║ [ ] HPA/VPA operational                             ║
║ [ ] Alerting rules configured                       ║
║ [ ] Sample application deployed and accessible      ║
║ [ ] End-to-end flow validated                       ║
╚══════════════════════════════════════════════════════╝
EOF
```

---

## Phase 5: Chaos & Resilience (Day 4)

Estimated time: 45-60 minutes

### Step 1: Install Chaos Mesh

```bash
# Verify Chaos Mesh installation
kubectl get pods -n chaos-mesh
```

Expected output:
```
NAME                                        READY   STATUS    RESTARTS   AGE
chaos-dashboard-xxxxxxxxxx-yyyyy            1/1     Running   0          2m
chaos-controller-manager-xxxxxxxxxx-yyyy    1/1     Running   0          2m
chaos-daemon-xxxxx                          1/1     Running   0          2m
chaos-daemon-yyyyy                          1/1     Running   0          2m
chaos-daemon-zzzzz                          1/1     Running   0          2m
```

### Step 2: Run First Chaos Experiment

```bash
# Create pod failure experiment
cat << EOF | kubectl apply -f -
apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata:
  name: pod-failure-demo
  namespace: chaos-mesh
spec:
  action: pod-failure
  mode: one
  duration: 60s
  selector:
    namespaces: ["demo"]
    labelSelectors:
      app: demo-app
  scheduler:
    cron: "@every 5m"
EOF

# Monitor experiment
kubectl get podchaos -n chaos-mesh
kubectl describe podchaos pod-failure-demo -n chaos-mesh
```

### Step 3: Validate Self-Healing

```bash
# Watch pods being killed and recreated
kubectl get pods -n demo -l app=demo-app -w

# Verify ArgoCD auto-heals
argocd app get applications -o json | jq '.status.health.status'
# Should always return "Healthy"

# Check Karpenter provisions new nodes if needed
kubectl get nodes -w

# Run network chaos
cat << EOF | kubectl apply -f -
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: network-delay-demo
  namespace: chaos-mesh
spec:
  action: delay
  mode: all
  selector:
    namespaces: ["demo"]
    labelSelectors:
      app: demo-app
  delay:
    latency: "2000ms"
    correlation: "50"
    jitter: "100ms"
  duration: "120s"
EOF

# Verify service continues to function
while true; do
  kubectl port-forward -n demo svc/demo-app 8081:80 &
  sleep 2
  curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" http://localhost:8081 || echo "FAILED"
  kill %1 2>/dev/null
  sleep 2
done
```

### Step 4: Run Resilience Test Suite

```bash
# Execute comprehensive chaos scenario
kubectl apply -f ../../chaos/experiments/pod-failure.yaml
kubectl apply -f ../../chaos/experiments/network-delay.yaml
kubectl apply -f ../../chaos/experiments/cpu-stress.yaml
kubectl apply -f ../../chaos/experiments/dns-chaos.yaml

# Monitor all experiments
kubectl get pods -n chaos-mesh -w
kubectl get all -n demo

# Check that SLOs were maintained
# (Requires Prometheus queries)
```

### Step 5: Document Findings

```bash
# Generate resilience report
cat << 'EOF' > resilience-report.md
# Chaos Engineering Report

## Experiments Executed
1. Pod Failure - Single pod killed
2. Network Delay - 2000ms added latency
3. CPU Stress - 80% CPU utilization
4. DNS Chaos - DNS resolution failures

## Results
| Experiment | Duration | SLO Maintained | Actions Triggered |
|------------|----------|----------------|-------------------|
| Pod Failure | 60s | Yes | Pod recreated by ReplicaSet |
| Network Delay | 120s | Yes | Circuit breaker opened |
| CPU Stress | 90s | Yes | HPA scaled up replicas |
| DNS Chaos | 60s | Yes | Retry logic activated |

## Lessons Learned
- Include chaos experiments in CI/CD pipeline
- Add circuit breaker to all external calls
- Tune HPA thresholds based on results
EOF

echo "Resilience report generated."
```

### Phase 5 Validation Gate

```bash
cat << 'EOF'
╔══════════════════════════════════════════════════════╗
║         PHASE 5 VALIDATION CHECKLIST                ║
╠══════════════════════════════════════════════════════╣
║ [ ] Chaos Mesh installed                            ║
║ [ ] Pod failure experiment executed                 ║
║ [ ] Network chaos experiment executed               ║
║ [ ] Self-healing validated                          ║
║ [ ] HPA scaled correctly under load                 ║
║ [ ] Resilience report generated                     ║
╚══════════════════════════════════════════════════════╝
EOF
```

---

## Expected Timelines

| Phase | Duration | Description |
|-------|----------|-------------|
| Phase 1: Foundation | 60-90 min | VPC, EKS, IAM, Karpenter |
| Phase 2: Platform Services | 60-90 min | ArgoCD, Monitoring, GitOps |
| Phase 3: Security | 45-60 min | Kyverno, Falco, Network Policies |
| Phase 4: Applications | 60-90 min | AIOps, Microservices, HPA |
| Phase 5: Chaos & Resilience | 45-60 min | Chaos Mesh, Resilience Testing |
| **Total** | **4.5-6.5 hours** | |

### Optimization Tips

1. Run Phase 1 and 2 back-to-back while Terraform creates resources
2. Use `--parallelism=15` with Terraform for faster resource creation
3. Pre-pull container images during cluster creation
4. Use the bootstrap automation script for unattended deployment

---

## Next Steps

After completing the bootstrap sequence:

1. [Validate the deployment with smoke tests](06-validation-smoke-tests.md)
2. [Configure secrets management](05-secrets-bootstrap.md)
3. [Review SRE runbook](../operations/01-sre-runbook.md)
4. [Set up incident response procedures](../operations/02-incident-response.md)
