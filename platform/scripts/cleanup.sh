#!/bin/bash
set -euo pipefail

ENVIRONMENT="${1:-}"
CONFIRMED="${2:-}"
REASON="${3:-Platform teardown}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()    { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $*"; }
warn()   { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()  { echo -e "${RED}[ERROR]${NC} $*"; }
header() { echo -e "\n${BLUE}==============================================${NC}"; echo -e "${BLUE}  $*${NC}"; echo -e "${BLUE}==============================================${NC}"; }

usage() {
    echo "Usage: $0 <environment> [--confirm] [--reason <text>]"
    echo ""
    echo "Environments: dev, staging, prod, local"
    echo ""
    echo "Options:"
    echo "  --confirm       Confirm teardown (required for prod)"
    echo "  --reason <text> Reason for teardown (for audit log)"
    echo "  --dry-run       Show what would be deleted without deleting"
    echo ""
    echo "Examples:"
    echo "  $0 dev                     # Tear down dev"
    echo "  $0 prod --confirm --reason 'Decommissioning platform'"
    echo "  $0 dev --dry-run           # Dry run"
    exit 1
}

DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --confirm) CONFIRMED=true; shift ;;
        --reason) REASON="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        -h|--help) usage ;;
        *) break ;;
    esac
done

if [ -z "$ENVIRONMENT" ]; then
    usage
fi

if [ "$ENVIRONMENT" = "prod" ] && [ "$CONFIRMED" != "true" ]; then
    error "Production teardown requires --confirm flag"
    error "This will delete all production resources irreversibly."
    exit 1
fi

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")
AWS_REGION="us-west-2"

echo "╔══════════════════════════════════════════════════════════╗"
echo "║           Platform Cleanup - ${ENVIRONMENT}              ║"
echo "║  $(date -u)                     ║"
echo "║  Reason: ${REASON}                                       ║"
echo "╚══════════════════════════════════════════════════════════╝"

if [ "$DRY_RUN" = "true" ]; then
    echo ""
    warn "DRY RUN MODE - No resources will be deleted"
    echo ""
fi

echo ""
if [ "$DRY_RUN" = "false" ] && [ "$ENVIRONMENT" != "local" ]; then
    echo "WARNING: You are about to delete the ${ENVIRONMENT} environment."
    echo "This action is IRREVERSIBLE."
    echo ""
    if [ "$CONFIRMED" != "true" ]; then
        read -p "Type 'yes' to continue: " confirmation
        if [ "$confirmation" != "yes" ]; then
            echo "Cleanup cancelled."
            exit 0
        fi
    fi
fi

delete_argocd_apps() {
    header "Phase 1: Deleting ArgoCD Applications"

    if command -v argocd &>/dev/null; then
        log "Listing ArgoCD applications..."
        local apps
        apps=$(argocd app list -o name 2>/dev/null || true)
        
        if [ -n "$apps" ]; then
            for app in $apps; do
                if [ "$DRY_RUN" = "true" ]; then
                    log "[DRY RUN] Would delete ArgoCD application: ${app}"
                else
                    log "Deleting ArgoCD application: ${app}"
                    argocd app delete "$app" --yes 2>/dev/null || true
                fi
            done
        else
            log "No ArgoCD applications found"
        fi
    else
        warn "argocd CLI not found, deleting via kubectl"
        if [ "$DRY_RUN" = "false" ]; then
            kubectl delete applications.argoproj.io --all -n argocd 2>/dev/null || true
        fi
    fi

    if [ "$DRY_RUN" = "false" ]; then
        kubectl delete namespace argocd --wait=false 2>/dev/null || true
        kubectl delete crd applications.argoproj.io 2>/dev/null || true
        kubectl delete crd appprojects.argoproj.io 2>/dev/null || true
        kubectl delete crd applicationsets.argoproj.io 2>/dev/null || true
    fi

    log "✓ Phase 1 complete"
}

delete_kubernetes_resources() {
    header "Phase 2: Deleting Kubernetes Resources"

    local namespaces=(
        aiops chaos-mesh monitoring kyverno falco ingress-nginx
        cert-manager external-secrets sealed-secrets minio karpenter velero
    )

    for ns in "${namespaces[@]}"; do
        if kubectl get namespace "$ns" &>/dev/null 2>&1; then
            if [ "$DRY_RUN" = "true" ]; then
                log "[DRY RUN] Would delete namespace: ${ns}"
            else
                log "Deleting all resources in namespace: ${ns}"
                kubectl delete all --all -n "$ns" --wait=false 2>/dev/null || true
                kubectl delete pvc --all -n "$ns" --wait=false 2>/dev/null || true
                kubectl delete configmap --all -n "$ns" --wait=false 2>/dev/null || true
                kubectl delete secret --all -n "$ns" --wait=false 2>/dev/null || true
                kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
            fi
        fi
    done

    if [ "$DRY_RUN" = "false" ]; then
        log "Deleting cluster-scoped resources..."
        kubectl get clusterrole -o name 2>/dev/null | grep -E "platform|argocd|kyverno|falco|karpenter|external-secrets|velero" | while read cr; do
            kubectl delete "$cr" 2>/dev/null || true
        done

        kubectl get clusterrolebinding -o name 2>/dev/null | grep -E "platform|argocd|kyverno|falco|karpenter|external-secrets|velero" | while read crb; do
            kubectl delete "$crb" 2>/dev/null || true
        done

        kubectl delete clustersecretstore --all 2>/dev/null || true
        kubectl delete clusterissuer --all 2>/dev/null || true
        kubectl delete mutatingwebhookconfiguration -l app.kubernetes.io/instance=kyverno 2>/dev/null || true
        kubectl delete validatingwebhookconfiguration -l app.kubernetes.io/instance=kyverno 2>/dev/null || true
    fi

    log "✓ Phase 2 complete"
}

delete_eks_cluster() {
    header "Phase 3: Deleting EKS Cluster"

    local cluster_name="platform-${ENVIRONMENT}"

    if aws eks describe-cluster --name "$cluster_name" --region "$AWS_REGION" &>/dev/null 2>&1; then
        if [ "$DRY_RUN" = "true" ]; then
            log "[DRY RUN] Would delete EKS cluster: ${cluster_name}"
        else
            log "Deleting EKS cluster: ${cluster_name}"

            # Delete node groups first
            local nodegroups
            nodegroups=$(aws eks list-nodegroups --cluster-name "$cluster_name" --region "$AWS_REGION" --query "nodegroups[]" --output text 2>/dev/null || true)
            for ng in $nodegroups; do
                log "  Deleting node group: ${ng}"
                aws eks delete-nodegroup --cluster-name "$cluster_name" --nodegroup-name "$ng" --region "$AWS_REGION" 2>/dev/null || true
            done

            # Wait for node groups to delete
            for ng in $nodegroups; do
                aws eks wait nodegroup-deleted --cluster-name "$cluster_name" --nodegroup-name "$ng" --region "$AWS_REGION" 2>/dev/null || true
            done

            # Delete cluster
            aws eks delete-cluster --name "$cluster_name" --region "$AWS_REGION" 2>/dev/null || true
            log "Waiting for cluster deletion..."
            aws eks wait cluster-deleted --name "$cluster_name" --region "$AWS_REGION" 2>/dev/null || true
        fi
    else
        log "EKS cluster ${cluster_name} not found"
    fi

    log "✓ Phase 3 complete"
}

delete_infrastructure() {
    header "Phase 4: Deleting Supporting Infrastructure"

    if [ "$DRY_RUN" = "true" ]; then
        log "[DRY RUN] Would delete RDS instances"
        log "[DRY RUN] Would delete ElastiCache clusters"
        log "[DRY RUN] Would delete load balancers"
        log "[DRY RUN] Would delete NAT Gateways"
        return
    fi

    # Delete RDS
    log "Checking RDS instances..."
    local rds_ids
    rds_ids=$(aws rds describe-db-instances --region "$AWS_REGION" \
        --query "DBInstances[?contains(DBInstanceIdentifier, 'platform-${ENVIRONMENT}')].DBInstanceIdentifier" \
        --output text 2>/dev/null || true)
    
    for rds_id in $rds_ids; do
        log "Deleting RDS: ${rds_id}"
        if [ "$ENVIRONMENT" = "prod" ]; then
            aws rds delete-db-instance \
                --db-instance-identifier "$rds_id" \
                --final-db-snapshot-identifier "${rds_id}-final-$(date +%Y%m%d)" \
                --region "$AWS_REGION" 2>/dev/null || true
        else
            aws rds delete-db-instance \
                --db-instance-identifier "$rds_id" \
                --skip-final-snapshot \
                --region "$AWS_REGION" 2>/dev/null || true
        fi
    done

    # Delete ElastiCache
    log "Checking ElastiCache clusters..."
    local redis_ids
    redis_ids=$(aws elasticache describe-replication-groups --region "$AWS_REGION" \
        --query "ReplicationGroups[?contains(ReplicationGroupId, 'platform-${ENVIRONMENT}')].ReplicationGroupId" \
        --output text 2>/dev/null || true)
    
    for redis_id in $redis_ids; do
        log "Deleting ElastiCache: ${redis_id}"
        aws elasticache delete-replication-group \
            --replication-group-id "$redis_id" \
            --region "$AWS_REGION" 2>/dev/null || true
    done

    # Delete load balancers
    log "Checking load balancers..."
    local lb_arns
    lb_arns=$(aws elbv2 describe-load-balancers --region "$AWS_REGION" \
        --query "LoadBalancers[?contains(LoadBalancerName, 'platform-${ENVIRONMENT}')].LoadBalancerArn" \
        --output text 2>/dev/null || true)
    
    for lb_arn in $lb_arns; do
        log "Deleting load balancer: ${lb_arn}"
        aws elbv2 delete-load-balancer --load-balancer-arn "$lb_arn" --region "$AWS_REGION" 2>/dev/null || true
    done

    # Delete NAT Gateways
    log "Checking NAT Gateways..."
    local nat_ids
    nat_ids=$(aws ec2 describe-nat-gateways --region "$AWS_REGION" \
        --filter "Name=tag:Environment,Values=${ENVIRONMENT}" \
        --query "NatGateways[*].NatGatewayId" \
        --output text 2>/dev/null || true)
    
    for nat_id in $nat_ids; do
        log "Deleting NAT Gateway: ${nat_id}"
        aws ec2 delete-nat-gateway --nat-gateway-id "$nat_id" --region "$AWS_REGION" 2>/dev/null || true
    done

    log "✓ Phase 4 complete"
}

delete_storage() {
    header "Phase 5: Deleting S3 Buckets and DynamoDB"

    if [ "$DRY_RUN" = "true" ]; then
        log "[DRY RUN] Would delete S3 buckets"
        log "[DRY RUN] Would delete DynamoDB tables"
        return
    fi

    # Delete S3 buckets
    log "Checking S3 buckets..."
    local buckets
    buckets=$(aws s3api list-buckets --region "$AWS_REGION" \
        --query "Buckets[?contains(Name, 'platform-${ENVIRONMENT}')].Name" \
        --output text 2>/dev/null || true)
    
    for bucket in $buckets; do
        log "Emptying and deleting bucket: ${bucket}"
        
        # Remove all objects
        aws s3 rm "s3://${bucket}" --recursive 2>/dev/null || true
        
        # Delete all versions (for versioned buckets)
        aws s3api list-object-versions \
            --bucket "$bucket" \
            --query "Versions[*].[Key,VersionId]" \
            --output text 2>/dev/null | while read key version; do
            if [ -n "$key" ] && [ -n "$version" ]; then
                aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$version" 2>/dev/null || true
            fi
        done
        
        # Delete delete markers
        aws s3api list-object-versions \
            --bucket "$bucket" \
            --query "DeleteMarkers[*].[Key,VersionId]" \
            --output text 2>/dev/null | while read key version; do
            if [ -n "$key" ] && [ -n "$version" ]; then
                aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$version" 2>/dev/null || true
            fi
        done
        
        # Delete bucket
        aws s3 rb "s3://${bucket}" --force 2>/dev/null || true
        log "Deleted bucket: ${bucket}"
    done

    # Delete ECR repositories
    log "Checking ECR repositories..."
    local repos
    repos=$(aws ecr describe-repositories --region "$AWS_REGION" \
        --query "repositories[?contains(repositoryName, 'platform')].repositoryName" \
        --output text 2>/dev/null || true)
    
    for repo in $repos; do
        log "Deleting ECR repository: ${repo}"
        local image_ids
        image_ids=$(aws ecr list-images --repository-name "$repo" --region "$AWS_REGION" --query "imageIds[*]" --output json 2>/dev/null || echo "[]")
        if [ "$image_ids" != "[]" ]; then
            aws ecr batch-delete-image --repository-name "$repo" --image-ids "$image_ids" --region "$AWS_REGION" 2>/dev/null || true
        fi
        aws ecr delete-repository --repository-name "$repo" --force --region "$AWS_REGION" 2>/dev/null || true
    done

    log "✓ Phase 5 complete"
}

cleanup_local() {
    header "Phase 6: Local Cleanup"

    if [ "$DRY_RUN" = "true" ]; then
        log "[DRY RUN] Would clean up local files"
        return
    fi

    log "Cleaning up Terraform files..."
    find . -name "*.tfstate*" -not -path "./.git/*" -delete 2>/dev/null || true
    find . -name "*.tfplan" -delete 2>/dev/null || true
    find . -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null || true

    log "Cleaning up data directories..."
    rm -rf ./data/ 2>/dev/null || true

    log "Cleaning up Docker resources..."
    docker system prune -f --volumes 2>/dev/null || true

    log "Cleaning up kind/k3d clusters..."
    kind delete cluster --name "platform-${ENVIRONMENT}" 2>/dev/null || true
    k3d cluster delete "platform-${ENVIRONMENT}" 2>/dev/null || true

    log "Cleaning up kubeconfig..."
    kubectl config delete-context "platform-${ENVIRONMENT}" 2>/dev/null || true
    kubectl config delete-cluster "platform-${ENVIRONMENT}" 2>/dev/null || true

    log "✓ Phase 6 complete"
}

main() {
    if [ "$ENVIRONMENT" = "local" ]; then
        delete_argocd_apps
        delete_kubernetes_resources
        cleanup_local
    else
        delete_argocd_apps
        delete_kubernetes_resources
        delete_eks_cluster
        delete_infrastructure
        delete_storage
        cleanup_local
    fi

    header "Cleanup Complete"
    log "Environment ${ENVIRONMENT} has been cleaned up"
    log "Reason: ${REASON}"
    log "Completed: $(date -u)"

    if [ "$DRY_RUN" = "true" ]; then
        warn "DRY RUN - No resources were actually deleted"
    fi
}

main
