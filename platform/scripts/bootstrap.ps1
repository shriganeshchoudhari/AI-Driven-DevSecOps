# PowerShell Bootstrap Script for Windows
# Usage: .\platform\scripts\bootstrap.ps1 [prod | dev | local] [region]

param(
    [string]$Environment = 'dev',
    [string]$Region = 'us-west-2'
)

$ErrorActionPreference = 'Stop'

function Log-Info ($msg) {
    $time = (Get-Date).ToString('HH:mm:ss')
    Write-Host "[$time] [OK] $msg" -ForegroundColor Green
}

function Log-Warn ($msg) {
    Write-Host "[WARN] $msg" -ForegroundColor Yellow
}

function Log-Error ($msg) {
    Write-Host "[ERROR] $msg" -ForegroundColor Red
}

function Write-Header ($msg) {
    Write-Host "`n==============================================" -ForegroundColor Cyan
    Write-Host "  $msg" -ForegroundColor Cyan
    Write-Host "==============================================" -ForegroundColor Cyan
}

Write-Header "AIOps Platform Bootstrap - $Environment"

# Determine Cluster Name
$ClusterName = "aiops-platform-$Environment"
if ($Environment -eq 'dev') {
    $ClusterName = 'aiops-platform-dev'
}

# 1. Checking Prerequisites
Write-Header 'Checking Prerequisites'
$tools = @('kubectl', 'helm', 'aws')
$missing = @()

foreach ($tool in $tools) {
    $path = Get-Command $tool -ErrorAction SilentlyContinue
    if ($path) {
        Log-Info "$tool found"
    } else {
        Log-Warn "$tool not found in PATH"
        $missing += $tool
    }
}

if ($missing.Count -gt 0) {
    $missingList = $missing -join ', '
    Log-Error "Missing required tools: ($missingList). Please install them and try again."
    exit 1
}

# 2. Check AWS Credentials
Write-Header 'Checking AWS Credentials'
try {
    $identityJson = aws sts get-caller-identity --output json
    $identity = $identityJson | ConvertFrom-Json
    $account = $identity.Account
    Log-Info "AWS Account: $account"
    Log-Info "AWS Region: $Region"
} catch {
    Log-Error 'AWS credentials not configured or session expired. Run: aws configure'
    exit 1
}

# 3. Configure Kubernetes Access
Write-Header 'Phase 2: Configuring Kubernetes Access'
Log-Info "Updating kubeconfig for EKS cluster: $ClusterName"
try {
    aws eks update-kubeconfig --name $ClusterName --region $Region --alias "platform-$Environment"
    Log-Info 'Kubeconfig updated successfully'
} catch {
    Log-Error "Failed to update kubeconfig for cluster $ClusterName. Ensure cluster is online."
    exit 1
}

Log-Info 'Verifying cluster access...'
try {
    kubectl cluster-info
    $nodes = kubectl get nodes -o name
    $nodeCount = $nodes.Count
    Log-Info "Cluster connection validated. Found $nodeCount node(s)."
} catch {
    Log-Error 'Could not connect to the Kubernetes cluster API server.'
    exit 1
}

# 4. Bootstrapping GitOps
Write-Header 'Phase 3: Bootstrapping GitOps (ArgoCD)'
Log-Info 'Creating ArgoCD namespace...'
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

Log-Info 'Adding ArgoCD Helm repository...'
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

Log-Info 'Installing ArgoCD controller via Helm...'
try {
    helm upgrade --install argocd argo/argo-cd --namespace argocd --version 7.0.0 --set server.service.type=ClusterIP --set installCRDs=true --wait --timeout 10m
    Log-Info 'ArgoCD deployment completed successfully'
} catch {
    Log-Error 'Failed to deploy ArgoCD controller via Helm.'
    exit 1
}

Log-Info 'Waiting for all ArgoCD pods to be ready...'
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s

Log-Info 'Retrieving ArgoCD administrator password...'
$secret = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}'
if ($secret) {
    $password = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secret))
    Log-Info '=============================================='
    Log-Info "  ArgoCD UI Admin Password: $password"
    Log-Info '=============================================='
} else {
    Log-Warn 'Could not fetch initial admin secret. (It might have already been deleted/rotated).'
}

# 5. Applying Root App-of-Apps
Write-Header 'Phase 4: Applying GitOps Applications'
Log-Info 'Applying root App-of-Apps templates...'
$templatesPath = 'platform/argocd/app-of-apps/templates/'
if (Test-Path $templatesPath) {
    kubectl apply -f $templatesPath
    Log-Info 'GitOps applications successfully registered'
} else {
    Log-Warn "Templates path $templatesPath not found. Please verify folder structure."
}

Write-Header 'Bootstrap Completed Successfully!'
Log-Info 'Your AI-Driven DevSecOps platform is fully bootstrapped!'
Log-Info 'You can access ArgoCD service using: port-forward svc/argocd-server 8080'
