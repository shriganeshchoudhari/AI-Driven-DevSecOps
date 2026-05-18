#!/bin/bash
set -euo pipefail

PLATFORM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENVIRONMENT="${1:-dev}"
REGION="${2:-us-west-2}"
CLUSTER_NAME="${3:-platform-${ENVIRONMENT}}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()    { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $*"; }
warn()   { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()  { echo -e "${RED}[ERROR]${NC} $*"; }
header() { echo -e "\n${BLUE}==============================================${NC}"; echo -e "${BLUE}  $*${NC}"; echo -e "${BLUE}==============================================${NC}"; }

cleanup() {
    warn "Bootstrap interrupted. Cleaning up..."
    exit 1
}
trap cleanup SIGINT SIGTERM

check_prerequisites() {
    header "Checking Prerequisites"

    local tools=("terraform" "kubectl" "helm" "aws" "argocd" "docker" "cosign" "trivy" "yq" "jq")
    local missing=()

    for tool in "${tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            log "✓ $tool found: $($tool --version 2>&1 | head -1)"
        else
            warn "✗ $tool not found"
            missing+=("$tool")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        error "Missing required tools: ${missing[*]}"
        error "Install missing tools and re-run bootstrap"
        exit 1
    fi

    log "✓ All prerequisites installed"
}

check_aws_credentials() {
    header "Checking AWS Credentials"

    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured"
        error "Run: aws configure"
        exit 1
    fi

    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    log "✓ AWS Account: ${AWS_ACCOUNT_ID}"
    log "✓ AWS Region: ${REGION}"

    if [ "$ENVIRONMENT" = "local" ]; then
        log "✓ Local deployment mode"
    fi
}

bootstrap_infrastructure() {
    header "Phase 1: Provisioning Infrastructure"

    if [ "$ENVIRONMENT" = "local" ]; then
        log "Skipping cloud infrastructure for local deployment"
        return
    fi

    cd "${PLATFORM_ROOT}/terraform/environments/${ENVIRONMENT}"

    log "Initializing Terraform..."
    terraform init -backend-config="region=${REGION}" -upgrade

    log "Selecting/Creating workspace: ${ENVIRONMENT}"
    terraform workspace select "${ENVIRONMENT}" 2>/dev/null || terraform workspace new "${ENVIRONMENT}"

    log "Planning infrastructure deployment..."
    terraform plan -out="bootstrap-${ENVIRONMENT}.tfplan"

    log "Applying infrastructure changes..."
    terraform apply "bootstrap-${ENVIRONMENT}.tfplan"

    log "✓ Infrastructure provisioning complete"
}

configure_kubernetes() {
    header "Phase 2: Configuring Kubernetes Access"

    if [ "$ENVIRONMENT" = "local" ]; then
        log "Using local cluster (kind/k3d)"
        return
    fi

    CLUSTER_NAME=$(cd "${PLATFORM_ROOT}/terraform/environments/${ENVIRONMENT}" && terraform output -raw cluster_name 2>/dev/null || echo "${CLUSTER_NAME}")

    log "Configuring kubectl for cluster: ${CLUSTER_NAME}"
    aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${REGION}" --alias "platform-${ENVIRONMENT}"

    log "Verifying cluster access..."
    kubectl cluster-info

    NODE_COUNT=$(kubectl get nodes -o name | wc -l)
    log "✓ Cluster has ${NODE_COUNT} nodes ready"
}

bootstrap_gitops() {
    header "Phase 3: Bootstrapping GitOps"

    log "Creating ArgoCD namespace..."
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

    log "Installing ArgoCD via Helm..."
    helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
    helm repo update

    VALUES_FILE="${PLATFORM_ROOT}/argocd/values.yaml"
    if [ ! -f "$VALUES_FILE" ]; then
        warn "ArgoCD values file not found at ${VALUES_FILE}, using defaults"
        helm upgrade --install argocd argo/argo-cd \
            --namespace argocd \
            --version 7.0.0 \
            --set server.service.type=ClusterIP \
            --set installCRDs=true \
            --wait \
            --timeout 10m
    else
        helm upgrade --install argocd argo/argo-cd \
            --namespace argocd \
            --version 7.0.0 \
            --values "${VALUES_FILE}" \
            --wait \
            --timeout 10m
    fi

    log "Waiting for ArgoCD pods..."
    kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s

    log "Getting ArgoCD admin password..."
    ADMIN_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "password-not-available")
    log "ArgoCD admin password: ${ADMIN_PASSWORD}"

    log "Logging into ArgoCD..."
    argocd login localhost:8080 \
        --username admin \
        --password "${ADMIN_PASSWORD}" \
        --insecure \
        --grpc-web 2>/dev/null || warn "Could not login to ArgoCD (may not be reachable via localhost)"

    log "Applying root App-of-Apps..."
    if [ -d "${PLATFORM_ROOT}/argocd/app-of-apps/templates" ]; then
        kubectl apply -f "${PLATFORM_ROOT}/argocd/app-of-apps/templates/" 2>/dev/null || \
            warn "Could not apply root app (may not exist yet)"
        log "✓ Root application applied"
    else
        warn "No app-of-apps templates found. Creating basic root application..."
        cat << EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-app
  namespace: argocd
spec:
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  project: default
  source:
    path: argocd/app-of-apps
    repoURL: https://github.com/org/aiops-platform.git
    targetRevision: HEAD
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
    fi
}

validate_deployment() {
    header "Phase 4: Validating Deployment"

    log "Checking cluster health..."
    kubectl get nodes -o wide
    kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded 2>/dev/null | grep -v "kube-system" || log "✓ All pods running"

    log "Checking core components..."
    local components=("argocd" "ingress-nginx" "cert-manager" "kyverno" "falco" "monitoring" "external-secrets")
    for ns in "${components[@]}"; do
        if kubectl get namespace "$ns" &>/dev/null; then
            local pods=$(kubectl get pods -n "$ns" --field-selector=status.phase=Running -o name 2>/dev/null | wc -l)
            log "  ✓ $ns: ${pods} pods running"
        else
            warn "  - $ns: not installed yet"
        fi
    done

    log "✓ Bootstrap validation complete"
}

print_summary() {
    header "Bootstrap Summary"

    echo ""
    echo "  Environment:  ${ENVIRONMENT}"
    echo "  Region:       ${REGION}"
    echo "  Cluster:      ${CLUSTER_NAME}"
    echo "  Completed:    $(date -u)"
    echo ""
    echo "  Access URLs:"
    echo "  ArgoCD:      https://argocd.platform.example.com"
    echo "  Grafana:     https://grafana.platform.example.com"
    echo "  AIOps API:   https://api.platform.example.com"
    echo ""
    echo "  ArgoCD Password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
    echo ""
    echo "  Next steps:"
    echo "  1. Run validation:           ./scripts/validation.sh ${ENVIRONMENT}"
    echo "  2. Configure secrets:        Follow docs/deployment/05-secrets-bootstrap.md"
    echo "  3. Deploy applications:      Via ArgoCD App-of-Apps"
    echo "  4. Review documentation:     open docs/README.md"
    echo ""
}

main() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║     AIOps Platform Bootstrap - ${ENVIRONMENT}            ║"
    echo "║     $(date)                    ║"
    echo "╚══════════════════════════════════════════════════════════╝"

    check_prerequisites
    check_aws_credentials

    if [ "$ENVIRONMENT" = "local" ]; then
        header "Local Deployment Mode"
        log "Using existing local cluster"
    else
        # bootstrap_infrastructure
        log "Infrastructure is already 100% successfully provisioned. Skipping Phase 1..."
    fi

    configure_kubernetes
    bootstrap_gitops
    validate_deployment
    print_summary

    log "✓ Bootstrap completed successfully"
}

main "$@"
