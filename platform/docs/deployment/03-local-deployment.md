# Local Deployment Guide

Deploy the full platform stack locally for development, testing, and offline work using kind or k3d for Kubernetes and Docker Compose for supporting services.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Prerequisites](#prerequisites)
- [Option 1: kind (Kubernetes in Docker)](#option-1-kind-kubernetes-in-docker)
- [Option 2: k3d (K3s in Docker)](#option-2-k3d-k3s-in-docker)
- [Option 3: Docker Compose (Minimal)](#option-3-docker-compose-minimal)
- [Installing Platform Components](#installing-platform-components)
- [Ingress Configuration](#ingress-configuration)
- [Storage Configuration](#storage-configuration)
- [Resource Requirements](#resource-requirements)
- [Verification Steps](#verification-steps)
- [Troubleshooting Local Deployments](#troubleshooting-local-deployments)

---

## Architecture Overview

```
┌───────────────────────────────────────────────────────────────┐
│                       Local Machine                           │
│                                                               │
│  ┌────────────────────────────────┐                           │
│  │   kind / k3d Cluster           │                           │
│  │  ┌──────────────────────────┐  │                           │
│  │  │ ArgoCD  │ Prometheus     │  │                           │
│  │  │ Kyverno │ Grafana        │  │                           │
│  │  │ Falco   │ Loki           │  │    ┌──────────────────┐  │
│  │  │ AIOps   │ Tempo          │  │    │  Docker Compose  │  │
│  │  │ Nginx   │ cert-manager   │  │    │  MinIO (S3)     │  │
│  │  └──────────────────────────┘  │    │  MailHog (SMTP)  │  │
│  │                                │    │  Keycloak (IAM)  │  │
│  │  Host: 127.0.0.1              │    └──────────────────┘  │
│  │  Ingress: nip.io              │                           │
│  └────────────────────────────────┘                           │
└───────────────────────────────────────────────────────────────┘
```

## Prerequisites

```bash
# Verify all required tools
docker --version                    # >= 24.0
kubectl version --client            # >= 1.29
helm version                        # >= 3.14
kind version || k3d --version       # kind >= 0.20 or k3d >= 5.6
argocd version --client             # >= 2.10
yq --version                        # >= 4.40
jq --version                        # >= 1.7
```

Additional local tools:
```bash
# Optional but recommended
brew install kind k3d helmfile tilt   # macOS
# OR
choco install kind k3d                # Windows
```

## Option 1: kind (Kubernetes in Docker)

### Create kind Cluster

```bash
cat > kind-config.yaml << 'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: aiops-platform
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
  - containerPort: 30080
    hostPort: 8080
  - containerPort: 30081
    hostPort: 8443
- role: worker
  extraMounts:
  - hostPath: /var/lib/local-path-provisioner
    containerPath: /var/lib/local-path-provisioner
- role: worker
- role: worker
EOF

kind create cluster --config kind-config.yaml
```

Expected output:
```
Creating cluster "aiops-platform" ...
 ✓ Ensuring node image (kindest/node:v1.29.0) 🖼
 ✓ Preparing nodes 📦 📦 📦 📦
 ✓ Writing configuration 📜
 ✓ Starting control-plane 🕹️
 ✓ Installing StorageClass 💾
 ✓ Joining worker nodes 🚜
Set kubectl context to "kind-aiops-platform"
```

### Configure StorageClass

```bash
# Install local path provisioner for persistent volumes
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.24/deploy/local-path-storage.yaml

# Set as default
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Verify
kubectl get storageclass
```

Expected output:
```
NAME                   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
local-path (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  10s
standard               kubernetes.io/host-path Delete          Immediate              false                  2m
```

### Verify Cluster

```bash
kubectl get nodes -o wide
kubectl get pods -A
```

## Option 2: k3d (K3s in Docker)

### Create k3d Cluster

```bash
cat > k3d-config.yaml << 'EOF'
apiVersion: k3d.io/v1alpha5
kind: Simple
metadata:
  name: aiops-platform
servers: 1
agents: 3
ports:
- port: 80:80
  nodeFilters:
  - loadbalancer
- port: 443:443
  nodeFilters:
  - loadbalancer
- port: 8080:30080
  nodeFilters:
  - loadbalancer
- port: 8443:30081
  nodeFilters:
  - loadbalancer
options:
  k3s:
    extraServerArgs:
    - --disable=traefik
    - --disable=servicelb
    - --disable=metrics-server
    - --kube-apiserver-arg=service-node-port-range=30000-32767
EOF

k3d cluster create --config k3d-config.yaml
```

Expected output:
```
INFO[0000] Prep: Network
INFO[0000] Re-using existing network 'k3d-aiops-platform' (xxx)
INFO[0000] Created volume 'k3d-aiops-platform-images'
INFO[0010] Creating node 'k3d-aiops-platform-server-0'
INFO[0020] Creating node 'k3d-aiops-platform-agent-0'
INFO[0025] Creating node 'k3d-aiops-platform-agent-1'
INFO[0030] Creating node 'k3d-aiops-platform-agent-2'
INFO[0035] Successfully created 4 node(s)
```

### Configure kubeconfig

```bash
k3d kubeconfig merge aiops-platform -d ~/.kube/config
kubectl config use-context k3d-aiops-platform

# Verify
kubectl cluster-info
```

## Option 3: Docker Compose (Minimal)

For lightweight testing without Kubernetes, use Docker Compose for individual components:

```yaml
# docker-compose.yaml
version: '3.8'

services:
  minio:
    image: minio/minio:latest
    ports:
      - "9000:9000"
      - "9001:9001"
    environment:
      MINIO_ROOT_USER: minioadmin
      MINIO_ROOT_PASSWORD: minioadmin
    volumes:
      - ./data/minio:/data
    command: server /data --console-address ":9001"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
      interval: 30s
      timeout: 10s
      retries: 3

  postgres:
    image: postgres:16-alpine
    ports:
      - "5432:5432"
    environment:
      POSTGRES_USER: platform
      POSTGRES_PASSWORD: platform
      POSTGRES_DB: platform
    volumes:
      - ./data/postgres:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U platform"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - ./data/redis:/data
    command: redis-server --appendonly yes
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  keycloak:
    image: quay.io/keycloak/keycloak:24.0
    ports:
      - "8080:8080"
    environment:
      KC_DB: postgres
      KC_DB_URL: jdbc:postgresql://postgres:5432/keycloak
      KC_DB_USERNAME: platform
      KC_DB_PASSWORD: platform
      KEYCLOAK_ADMIN: admin
      KEYCLOAK_ADMIN_PASSWORD: admin
    command: start-dev
    depends_on:
      postgres:
        condition: service_healthy

  mailhog:
    image: mailhog/mailhog:latest
    ports:
      - "1025:1025"
      - "8025:8025"

  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./config/prometheus.yml:/etc/prometheus/prometheus.yml
      - ./data/prometheus:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    environment:
      GF_SECURITY_ADMIN_PASSWORD: admin
    volumes:
      - ./data/grafana:/var/lib/grafana
    depends_on:
      - prometheus
```

## Installing Platform Components

### Automated Bootstrap

```bash
# Run the local deployment bootstrap
./scripts/bootstrap.sh local
```

This script will:
1. Create the Kubernetes cluster (kind or k3d)
2. Install ArgoCD
3. Deploy NGINX Ingress Controller
4. Install cert-manager with self-signed certificates
5. Deploy Prometheus + Grafana + Loki + Tempo
6. Install Kyverno with policies
7. Install Falco
8. Deploy MinIO for S3-compatible storage
9. Deploy the AIOps engine
10. Configure local DNS via nip.io

### Manual Component Installation

```bash
# 1. Create namespaces
for ns in argocd cert-manager ingress-nginx monitoring kyverno falco aiops minio; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

# 2. Install ArgoCD
helm repo add argo https://argoproj.github.io/argo-helm
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --version 7.0.0 \
  --values ../argocd/values-local.yaml \
  --wait

# 3. Install NGINX Ingress
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --set controller.service.type=NodePort \
  --set controller.service.nodePorts.http=30080 \
  --set controller.service.nodePorts.https=30443 \
  --set controller.hostPort.enabled=true \
  --wait

# 4. Install cert-manager
helm repo add jetstack https://charts.jetstack.io
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --set installCRDs=true \
  --wait

# 5. Create self-signed ClusterIssuer
cat << EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: platform-ca
  namespace: cert-manager
spec:
  isCA: true
  commonName: platform.local
  secretName: platform-ca
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: platform-ca-issuer
spec:
  ca:
    secretName: platform-ca
EOF

# 6. Install monitoring stack (lighter weight for local)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set grafana.enabled=true \
  --set grafana.service.type=NodePort \
  --set grafana.service.nodePort=30300 \
  --set prometheus.service.type=NodePort \
  --set prometheus.service.nodePort=30900 \
  --wait
```

## Ingress Configuration

### Using nip.io

```bash
# Get the cluster IP (kind)
CLUSTER_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
# OR for k3d
CLUSTER_IP="127.0.0.1"

# Create wildcard ingress
cat << EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: platform-ingress
  namespace: argocd
  annotations:
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  rules:
  - host: "argocd.${CLUSTER_IP}.nip.io"
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 80
EOF

# Access ArgoCD at http://argocd.127.0.0.1.nip.io:80
```

### Using Localhost

```bash
cat << EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: platform-ingress
  namespace: argocd
spec:
  ingressClassName: nginx
  rules:
  - host: "argocd.localhost"
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 80
EOF

# Edit /etc/hosts (add: 127.0.0.1 argocd.localhost)
# Or use port forwarding:
kubectl port-forward -n argocd svc/argocd-server 8080:443
# Access at https://localhost:8080
```

### Complete Ingress Configuration

```bash
# Create a single ingress for all services
cat > ../argocd/local-ingress.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: platform-ingress
  namespace: ingress-nginx
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/proxy-body-size: "100m"
spec:
  ingressClassName: nginx
  rules:
  - host: argocd.127.0.0.1.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            namespace: argocd
            port:
              number: 80
  - host: grafana.127.0.0.1.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kube-prometheus-stack-grafana
            namespace: monitoring
            port:
              number: 80
  - host: prometheus.127.0.0.1.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kube-prometheus-stack-prometheus
            namespace: monitoring
            port:
              number: 9090
  - host: alertmanager.127.0.0.1.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kube-prometheus-stack-alertmanager
            namespace: monitoring
            port:
              number: 9093
  - host: minio.127.0.0.1.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: minio-console
            namespace: minio
            port:
              number: 9001
EOF

kubectl apply -f ../argocd/local-ingress.yaml
```

## Storage Configuration

### MinIO for S3-Compatible Object Storage

```bash
# Deploy MinIO
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: minio-data
  namespace: minio
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minio
  namespace: minio
spec:
  replicas: 1
  selector:
    matchLabels:
      app: minio
  template:
    metadata:
      labels:
        app: minio
    spec:
      containers:
      - name: minio
        image: quay.io/minio/minio:latest
        args:
        - server
        - /data
        - --console-address
        - ":9001"
        env:
        - name: MINIO_ROOT_USER
          value: "minioadmin"
        - name: MINIO_ROOT_PASSWORD
          value: "minioadmin"
        ports:
        - containerPort: 9000
        - containerPort: 9001
        volumeMounts:
        - name: data
          mountPath: /data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: minio-data
---
apiVersion: v1
kind: Service
metadata:
  name: minio-api
  namespace: minio
spec:
  ports:
  - port: 9000
    targetPort: 9000
  selector:
    app: minio
---
apiVersion: v1
kind: Service
metadata:
  name: minio-console
  namespace: minio
spec:
  ports:
  - port: 9001
    targetPort: 9001
  selector:
    app: minio
EOF

# Create bucket
kubectl run -n minio mc --image=minio/mc --rm -it --restart=Never -- \
  /bin/sh -c "mc alias set local http://minio-api:9000 minioadmin minioadmin \
  && mc mb local/velero-backups \
  && mc mb local/loki-data \
  && mc mb local/tempo-data \
  && mc policy set public local/velero-backups"
```

### Local Path Storage Classes

```bash
# Verify storage classes
kubectl get storageclass
# Should show local-path as default (for kind) or rancher (for k3d)

# Test PVC
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF

kubectl get pvc
# Should be Bound
kubectl delete pvc test-pvc
```

## Resource Requirements

### Minimum Requirements

| Resource | kind | k3d | Docker Compose |
|----------|------|-----|----------------|
| CPU | 4 cores | 4 cores | 2 cores |
| RAM | 8 GB | 8 GB | 4 GB |
| Disk | 30 GB | 30 GB | 10 GB |
| Docker Disk | 20 GB | 20 GB | 5 GB |

### Recommended Requirements

| Resource | kind | k3d | Docker Compose |
|----------|------|-----|----------------|
| CPU | 6 cores | 6 cores | 4 cores |
| RAM | 16 GB | 16 GB | 8 GB |
| Disk | 50 GB | 50 GB | 20 GB |
| Docker Disk | 40 GB | 40 GB | 10 GB |

### Checking Resource Usage

```bash
# Docker resource usage
docker stats --no-stream

# Kind node resources
docker exec kind-aiops-platform-control-plane free -h
docker exec kind-aiops-platform-control-plane df -h

# Kubernetes resource usage
kubectl top nodes
kubectl top pods -A
```

## Verification Steps

### 1. Cluster Health

```bash
echo "=== Cluster Health ==="
kubectl cluster-info
kubectl get nodes -o wide
kubectl get pods -A | grep -v Running | grep -v Completed
```

### 2. ArgoCD Health

```bash
echo "=== ArgoCD Health ==="
kubectl get pods -n argocd
argocd login localhost:8080 --insecure --username admin \
  --password $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
argocd app list
```

### 3. Ingress Health

```bash
echo "=== Ingress Health ==="
curl -s -o /dev/null -w "%{http_code}" http://argocd.127.0.0.1.nip.io
# Expected: 200 or 302
```

### 4. Monitoring Health

```bash
echo "=== Monitoring Health ==="
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets | length'
kill %1
```

### 5. AIOps Engine

```bash
echo "=== AIOps Engine ==="
kubectl port-forward -n aiops svc/aiops-engine 8000:8000 &
curl -s http://localhost:8000/health | jq
kill %1
```

### 6. Storage

```bash
echo "=== Storage Health ==="
kubectl get pvc -A
kubectl get pv
```

### Quick Validation Script

```bash
cat > check-local.sh << 'EOF'
#!/bin/bash
set -euo pipefail

echo "=========================================="
echo "  Local Platform Validation"
echo "=========================================="

PASS=0
FAIL=0

check() {
  local desc="$1"
  shift
  if "$@" > /dev/null 2>&1; then
    echo "  [PASS] $desc"
    ((PASS++))
  else
    echo "  [FAIL] $desc"
    ((FAIL++))
  fi
}

check "Cluster nodes ready" kubectl get nodes -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' | grep -v False
check "CoreDNS running" kubectl get pods -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[*].status.phase}' | grep -v Pending
check "ArgoCD running" kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o jsonpath='{.items[*].status.phase}' | grep -v Pending
check "NGINX Ingress running" kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller -o jsonpath='{.items[*].status.phase}' | grep -v Pending
check "cert-manager running" kubectl get pods -n cert-manager -l app=cert-manager -o jsonpath='{.items[*].status.phase}' | grep -v Pending
check "Prometheus running" kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[*].status.phase}' | grep -v Pending
check "Grafana running" kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[*].status.phase}' | grep -v Pending
check "Loki running" kubectl get pods -n monitoring -l app.kubernetes.io/name=loki -o jsonpath='{.items[*].status.phase}' | grep -v Pending
check "Kyverno running" kubectl get pods -n kyverno -l app.kubernetes.io/instance=kyverno -o jsonpath='{.items[*].status.phase}' | grep -v Pending
check "Falco running" kubectl get pods -n falco -l app.kubernetes.io/name=falco -o jsonpath='{.items[*].status.phase}' | grep -v Pending
check "AIOps running" kubectl get pods -n aiops -l app.kubernetes.io/name=aiops -o jsonpath='{.items[*].status.phase}' | grep -v Pending
check "MinIO running" kubectl get pods -n minio -l app=minio -o jsonpath='{.items[*].status.phase}' | grep -v Pending

echo "------------------------------------------"
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "=========================================="
exit $FAIL
EOF

chmod +x check-local.sh
./check-local.sh
```

## Troubleshooting Local Deployments

| Issue | Cause | Solution |
|-------|-------|----------|
| Cluster won't start | Docker not running | `docker info` to verify |
| Pods stuck in Pending | Insufficient resources | `docker system prune -a` |
| DNS not resolving | CoreDNS configuration | `kubectl rollout restart -n kube-system deployment/coredns` |
| Image pull errors | Rate limiting | `docker login` or use `--set global.imagePullSecrets` |
| LoadBalancer pending | No cloud provider | Use NodePort or port-forward |
| StorageClass not found | Missing provisioner | Install local-path-provisioner |
| cert-manager failing | DNS validation | Use self-signed issuer for local |
| ArgoCD sync timeout | Network issues | `argocd app sync --prune --timeout 300` |

### Resetting Local Environment

```bash
# Delete kind cluster
kind delete cluster --name aiops-platform

# Delete k3d cluster
k3d cluster delete aiops-platform

# Clean up Docker
docker system prune -a --volumes

# Reset kubectl context
kubectl config delete-context kind-aiops-platform
kubectl config delete-context k3d-aiops-platform

# Remove data directories
rm -rf ./data
```

---

## Next Steps

After validating the local deployment:

1. [Deploy to AWS](04-aws-deployment.md) for production
2. [Configure secrets management](05-secrets-bootstrap.md)
3. [Run validation smoke tests](06-validation-smoke-tests.md)
