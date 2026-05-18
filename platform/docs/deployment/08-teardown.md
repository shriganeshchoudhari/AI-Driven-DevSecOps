# Platform Teardown

Complete environment teardown instructions for safely removing the platform and all associated resources.

---

## Table of Contents

- [Teardown Sequence Overview](#teardown-sequence-overview)
- [Phase 1: Delete ArgoCD Applications](#phase-1-delete-argocd-applications)
- [Phase 2: Delete Kubernetes Resources](#phase-2-delete-kubernetes-resources)
- [Phase 3: Delete EKS Cluster](#phase-3-delete-eks-cluster)
- [Phase 4: Delete Supporting Infrastructure](#phase-4-delete-supporting-infrastructure)
- [Phase 5: Delete S3 Buckets and DynamoDB](#phase-5-delete-s3-buckets-and-dynamodb)
- [Phase 6: Clean Up Local Files](#phase-6-clean-up-local-files)
- [Automated Cleanup Script](#automated-cleanup-script)
- [Verification](#verification)

---

## Teardown Sequence Overview

```
Phase 1 ─► Phase 2 ─► Phase 3 ─► Phase 4 ─► Phase 5 ─► Phase 6
  │           │           │           │           │           │
  ▼           ▼           ▼           ▼           ▼           ▼
ArgoCD     K8s        EKS         Infra        Storage     Local
Apps       Resources  Cluster     (VPC,RDS,   (S3,DDB)    Files
                      (Karpenter)  ElastiCache)
```

**Important**: Follow the phases in order. Deleting infrastructure before Kubernetes resources will leave orphaned resources and may cause deletion failures.

**Recovery Point**: Before starting, ensure you have backed up any data you want to keep (database snapshots, S3 data, etc.).

---

## Phase 1: Delete ArgoCD Applications

### 1. Delete Child Applications

```bash
# List all ArgoCD applications
argocd app list

# Delete applications in reverse dependency order (children first)
argocd app delete applications --yes
argocd app delete aiops --yes
argocd app delete chaos-mesh --yes
argocd app delete kyverno --yes
argocd app delete falco --yes
argocd app delete monitoring --yes
argocd app delete cert-manager --yes
argocd app delete ingress-nginx --yes
argocd app delete external-secrets --yes
```

### 2. Delete Root Application

```bash
# Delete root app last
argocd app delete root-app --yes

# Verify all apps are deleted
argocd app list
# Expected: "No applications found"
```

### 3. Delete ArgoCD Itself

```bash
# Delete ArgoCD
helm uninstall argocd -n argocd

# Delete namespace
kubectl delete namespace argocd --wait=false

# Remove ArgoCD CRDs
kubectl delete crd applications.argoproj.io
kubectl delete crd appprojects.argoproj.io
kubectl delete crd applicationsets.argoproj.io
```

---

## Phase 2: Delete Kubernetes Resources

### 1. Delete All Application Namespaces

```bash
# List namespaces managed by the platform
NAMESPACES=(
  aiops
  chaos-mesh
  monitoring
  kyverno
  falco
  ingress-nginx
  cert-manager
  external-secrets
  sealed-secrets
  minio
  karpenter
  velero
)

# Delete all resources within namespaces first
for ns in "${NAMESPACES[@]}"; do
  if kubectl get namespace "$ns" &>/dev/null; then
    echo "Deleting all resources in namespace: $ns"
    kubectl delete all --all -n "$ns" --wait=false
    # Delete remaining resources
    kubectl delete pvc --all -n "$ns" --wait=false 2>/dev/null || true
    kubectl delete configmap --all -n "$ns" --wait=false 2>/dev/null || true
    kubectl delete secret --all -n "$ns" --wait=false 2>/dev/null || true
    kubectl delete serviceaccount --all -n "$ns" --wait=false 2>/dev/null || true
  fi
done

# Wait for resource cleanup
sleep 30

# Delete namespaces
for ns in "${NAMESPACES[@]}"; do
  kubectl delete namespace "$ns" --wait=false 2>/dev/null || true
done
```

### 2. Delete Cluster-Scoped Resources

```bash
# Delete ClusterRoles associated with the platform
kubectl get clusterrole -o name | grep -E "platform|argocd|kyverno|falco|karpenter|external-secrets|velero" | while read cr; do
  kubectl delete "$cr"
done

# Delete ClusterRoleBindings
kubectl get clusterrolebinding -o name | grep -E "platform|argocd|kyverno|falco|karpenter|external-secrets|velero" | while read crb; do
  kubectl delete "$crb"
done

# Delete ClusterIssuers
kubectl delete clusterissuer --all

# Delete ClusterSecretStores
kubectl delete clustersecretstore --all

# Delete MutatingWebhookConfigurations and ValidatingWebhookConfigurations
kubectl get mutatingwebhookconfiguration -o name | grep -E "kyverno|falco|cert-manager|karpenter" | while read mw; do
  kubectl delete "$mw"
done

kubectl get validatingwebhookconfiguration -o name | grep -E "kyverno|falco|cert-manager|karpenter" | while read vw; do
  kubectl delete "$vw"
done

# Delete StorageClasses created by the platform
kubectl get storageclass -o name | grep -v "gp2\|gp3" | while read sc; do
  kubectl delete "$sc"
done
```

### 3. Delete Persistent Volumes

```bash
# List all remaining PVs
kubectl get pv

# Delete released volumes
kubectl get pv --no-headers | awk '$5 == "Released" {print $1}' | while read pv; do
  kubectl delete pv "$pv" --wait=false
done

# Force delete stuck volumes
kubectl get pv --no-headers | awk '$5 != "Bound" {print $1}' | while read pv; do
  kubectl patch pv "$pv" -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
  kubectl delete pv "$pv" --wait=false 2>/dev/null || true
done
```

### 4. Verify Kubernetes Cleanup

```bash
# Should show minimal resources
kubectl get all -A

# Check for remaining platform resources
kubectl get crd | grep -E "argoproj|kyverno|falco|chaos-mesh"
```

---

## Phase 3: Delete EKS Cluster

### 1. Delete Karpenter Node Claims and Nodes

```bash
# Delete all NodeClaims to trigger node termination
kubectl delete nodeclaims --all --wait=false

# Verify EC2 instances are being terminated
aws ec2 describe-instances \
  --filters "Name=tag:aws:eks:cluster-name,Values=platform-${ENVIRONMENT}" \
  --query "Reservations[*].Instances[*].[InstanceId,State.Name]" \
  --output table
```

### 2. Delete Cluster with Terraform

```bash
cd terraform/environments/${ENVIRONMENT}

# Plan infrastructure destroy
terraform plan -destroy -out=destroy.tfplan

# Review the plan (should include EKS, Karpenter, node groups)
terraform show destroy.tfplan | head -100

# Execute destroy for EKS and related resources first
terraform destroy -target=module.eks -auto-approve
```

If Terraform destroy fails due to dependencies:

```bash
# Option A: Force remove Kubernetes resources from state
terraform state list | grep module.eks | xargs terraform state rm

# Option B: Clean up using AWS CLI
CLUSTER_NAME="platform-${ENVIRONMENT}"

# Delete node groups
aws eks list-nodegroups --cluster-name "$CLUSTER_NAME" \
  --query "nodegroups[]" --output text | while read ng; do
  aws eks delete-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$ng"
done

# Wait for node groups to delete
aws eks wait nodegroup-active --cluster-name "$CLUSTER_NAME" --nodegroup-name "$ng" 2>/dev/null || true
sleep 60

# Delete cluster
aws eks delete-cluster --name "$CLUSTER_NAME"

# Remove from Terraform state
terraform state rm module.eks
```

### 3. Delete Associated EC2 Resources

```bash
# Terminate any remaining instances
INSTANCE_IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:aws:eks:cluster-name,Values=platform-${ENVIRONMENT}" \
  --query "Reservations[*].Instances[*].InstanceId" \
  --output text)

if [ -n "$INSTANCE_IDS" ]; then
  aws ec2 terminate-instances --instance-ids $INSTANCE_IDS
  aws ec2 wait instance-terminated --instance-ids $INSTANCE_IDS
fi

# Delete security groups (after instances are terminated)
aws ec2 describe-security-groups \
  --filters "Name=tag:aws:eks:cluster-name,Values=platform-${ENVIRONMENT}" \
  --query "SecurityGroups[*].GroupId" \
  --output text | while read sg; do
  aws ec2 delete-security-group --group-id "$sg" 2>/dev/null || true
done
```

---

## Phase 4: Delete Supporting Infrastructure

### 1. Delete RDS

```bash
# Create final snapshot (for production)
if [ "$ENVIRONMENT" == "prod" ]; then
  aws rds delete-db-instance \
    --db-instance-identifier platform-${ENVIRONMENT} \
    --final-db-snapshot-identifier "platform-${ENVIRONMENT}-final-$(date +%Y%m%d)" \
    --skip-final-snapshot false
else
  aws rds delete-db-instance \
    --db-instance-identifier platform-${ENVIRONMENT} \
    --skip-final-snapshot
fi

# Wait for deletion
aws rds wait db-instance-deleted \
  --db-instance-identifier platform-${ENVIRONMENT}
```

### 2. Delete ElastiCache

```bash
aws elasticache delete-replication-group \
  --replication-group-id platform-${ENVIRONMENT}

aws elasticache wait replication-group-deleted \
  --replication-group-id platform-${ENVIRONMENT}

# Delete subnet group
aws elasticache delete-cache-subnet-group \
  --cache-subnet-group-name platform-${ENVIRONMENT}
```

### 3. Delete ALB/NLB

```bash
# Find and delete load balancers
aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?contains(LoadBalancerName, 'platform-${ENVIRONMENT}')].LoadBalancerArn" \
  --output text | while read lb; do
  if [ -n "$lb" ]; then
    aws elbv2 delete-load-balancer --load-balancer-arn "$lb"
  fi
done

# Delete target groups
aws elbv2 describe-target-groups \
  --query "TargetGroups[?contains(TargetGroupName, 'platform-${ENVIRONMENT}')].TargetGroupArn" \
  --output text | while read tg; do
  if [ -n "$tg" ]; then
    aws elbv2 delete-target-group --target-group-arn "$tg"
  fi
done
```

### 4. Delete NAT Gateways

```bash
# Find NAT Gateways
NAT_GW_IDS=$(aws ec2 describe-nat-gateways \
  --filter "Name=tag:Environment,Values=${ENVIRONMENT}" \
  --query "NatGateways[*].NatGatewayId" \
  --output text)

for nat in $NAT_GW_IDS; do
  aws ec2 delete-nat-gateway --nat-gateway-id "$nat"
done

# Wait and release Elastic IPs
EIP_ALLOC_IDS=$(aws ec2 describe-addresses \
  --filters "Name=tag:Environment,Values=${ENVIRONMENT}" \
  --query "Addresses[*].AllocationId" \
  --output text)

sleep 30

for eip in $EIP_ALLOC_IDS; do
  aws ec2 release-address --allocation-id "$eip" 2>/dev/null || true
done
```

### 5. Destroy Remaining Terraform Infrastructure

```bash
# Now destroy remaining infrastructure
cd terraform/environments/${ENVIRONMENT}

# Remove resources that were manually deleted from state
terraform state rm module.rds 2>/dev/null || true
terraform state rm module.elasticache 2>/dev/null || true

# Destroy remaining infrastructure
terraform destroy -auto-approve
```

If Terraform fails:

```bash
# Force remove remaining resources from state
terraform state list | while read resource; do
  echo "Removing from state: $resource"
  terraform state rm "$resource" 2>/dev/null || true
done
```

---

## Phase 5: Delete S3 Buckets and DynamoDB

### 1. Delete Application S3 Buckets

```bash
# List all S3 buckets tagged for this environment
BUCKETS=$(aws s3api list-buckets \
  --query "Buckets[?contains(Name, 'platform-${ENVIRONMENT}')].Name" \
  --output text)

for bucket in $BUCKETS; do
  # Empty the bucket first (versioned buckets need special handling)
  aws s3 rm "s3://${bucket}" --recursive

  # Delete all versions (for versioned buckets)
  aws s3api list-object-versions \
    --bucket "$bucket" \
    --query "Versions[*].[Key,VersionId]" \
    --output text | while read key version; do
    if [ -n "$key" ] && [ -n "$version" ]; then
      aws s3api delete-object \
        --bucket "$bucket" \
        --key "$key" \
        --version-id "$version"
    fi
  done

  # Delete all delete markers
  aws s3api list-object-versions \
    --bucket "$bucket" \
    --query "DeleteMarkers[*].[Key,VersionId]" \
    --output text | while read key version; do
    if [ -n "$key" ] && [ -n "$version" ]; then
      aws s3api delete-object \
        --bucket "$bucket" \
        --key "$key" \
        --version-id "$version"
    fi
  done

  # Delete bucket
  aws s3 rb "s3://${bucket}" --force
  echo "Deleted bucket: $bucket"
done
```

### 2. Delete Terraform State Bucket

```bash
# Empty Terraform state bucket (careful - this is shared across environments)
BACKEND_BUCKET="platform-terraform-state-${AWS_ACCOUNT_ID}"

# List all objects in the state bucket for this environment
aws s3api list-objects \
  --bucket "$BACKEND_BUCKET" \
  --prefix "${ENVIRONMENT}/" \
  --query "Contents[*].Key" \
  --output text | while read key; do
  if [ -n "$key" ]; then
    aws s3api delete-object --bucket "$BACKEND_BUCKET" --key "$key"
  fi
done

# Delete all versions of state files
aws s3api list-object-versions \
  --bucket "$BACKEND_BUCKET" \
  --prefix "${ENVIRONMENT}/" \
  --query "Versions[*].[Key,VersionId]" \
  --output text | while read key version; do
  if [ -n "$key" ] && [ -n "$version" ]; then
    aws s3api delete-object --bucket "$BACKEND_BUCKET" --key "$key" --version-id "$version"
  fi
done
```

### 3. Delete DynamoDB Lock Table

```bash
aws dynamodb delete-table --table-name platform-terraform-locks
aws dynamodb wait table-not-exists --table-name platform-terraform-locks
```

### 4. Delete ECR Repositories

```bash
# List ECR repositories
aws ecr describe-repositories \
  --query "repositories[?contains(repositoryName, 'platform')].repositoryName" \
  --output text | while read repo; do
  if [ -n "$repo" ]; then
    # Delete all images first
    IMAGE_IDS=$(aws ecr list-images \
      --repository-name "$repo" \
      --query "imageIds[*]" \
      --output json)

    if [ "$IMAGE_IDS" != "[]" ] && [ -n "$IMAGE_IDS" ]; then
      aws ecr batch-delete-image \
        --repository-name "$repo" \
        --image-ids "$IMAGE_IDS" 2>/dev/null || true
    fi

    # Delete repository
    aws ecr delete-repository --repository-name "$repo" --force
    echo "Deleted ECR repo: $repo"
  fi
done
```

### 5. Delete IAM Roles and Policies

```bash
# List roles associated with platform
aws iam list-roles \
  --query "Roles[?contains(RoleName, 'platform-${ENVIRONMENT}')].RoleName" \
  --output text | while read role; do
  if [ -n "$role" ]; then
    # Detach managed policies
    aws iam list-attached-role-policies --role-name "$role" \
      --query "AttachedPolicies[*].PolicyArn" \
      --output text | while read policy; do
      aws iam detach-role-policy --role-name "$role" --policy-arn "$policy"
    done

    # Delete inline policies
    aws iam list-role-policies --role-name "$role" \
      --query "PolicyNames[*]" \
      --output text | while read policy; do
      aws iam delete-role-policy --role-name "$role" --policy-name "$policy"
    done

    # Delete role
    aws iam delete-role --role-name "$role"
    echo "Deleted IAM role: $role"
  fi
done
```

### 6. Delete CloudWatch Resources

```bash
# Delete log groups
aws logs describe-log-groups \
  --log-group-name-prefix "/aws/eks/platform-${ENVIRONMENT}" \
  --query "logGroups[*].logGroupName" \
  --output text | while read group; do
  if [ -n "$group" ]; then
    aws logs delete-log-group --log-group-name "$group"
  fi
done

# Delete CloudWatch alarms
aws cloudwatch describe-alarms \
  --alarm-name-prefix "platform-${ENVIRONMENT}" \
  --query "MetricAlarms[*].AlarmName" \
  --output text | while read alarm; do
  if [ -n "$alarm" ]; then
    aws cloudwatch delete-alarms --alarm-names "$alarm"
  fi
done
```

### 7. Delete ACM Certificates

```bash
# List certificates (only non-issued or unused)
aws acm list-certificates \
  --query "CertificateSummaryList[?contains(DomainName, 'platform.example.com')].CertificateArn" \
  --output text | while read cert; do
  if [ -n "$cert" ]; then
    aws acm delete-certificate --certificate-arn "$cert" 2>/dev/null || true
  fi
done
```

### 8. Delete WAF Resources

```bash
# List and delete WAF Web ACLs
aws wafv2 list-web-acls \
  --scope REGIONAL \
  --query "WebACLs[?contains(Name, 'platform-${ENVIRONMENT}')].ARN" \
  --output text | while read acl; do
  if [ -n "$acl" ]; then
    aws wafv2 delete-web-acl --name "platform-${ENVIRONMENT}" --scope REGIONAL --id "$(echo $acl | awk -F/ '{print $NF}')" 2>/dev/null || true
  fi
done
```

---

## Phase 6: Clean Up Local Files

### 1. Delete Kubeconfig Context

```bash
# Remove EKS cluster from kubeconfig
kubectl config delete-context "platform-${ENVIRONMENT}"
kubectl config delete-cluster "platform-${ENVIRONMENT}"
kubectl config unset "users.platform-${ENVIRONMENT}"

# Verify
kubectl config get-contexts
```

### 2. Clean Up Terraform Files

```bash
# Remove Terraform state files locally
find . -name "*.tfstate*" -not -path "./.git/*" -delete
find . -name "*.tfplan" -delete
find . -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null || true
```

### 3. Clean Up Local Data

```bash
# Remove data directories
rm -rf ./data/

# Remove Docker volumes used for development
docker volume prune -f

# Remove kind/k3d clusters if they exist
kind delete cluster --name aiops-platform 2>/dev/null || true
k3d cluster delete aiops-platform 2>/dev/null || true

# Clean Docker system
docker system prune -f --volumes
```

### 4. Remove SSH Keys and Credentials

```bash
# Remove temporary SSH keys
rm -f ~/.ssh/platform-*

# Clean up any saved environment credentials
rm -f .env.prod .env.staging

# Clear AWS session
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
```

---

## Automated Cleanup Script

The complete cleanup procedure is automated in `scripts/cleanup.sh`:

```bash
# Usage
./scripts/cleanup.sh dev          # Tear down dev environment
./scripts/cleanup.sh staging      # Tear down staging environment
./scripts/cleanup.sh prod         # Tear down production (requires --confirm)
./scripts/cleanup.sh dev --force  # Force deletion without confirmation
./scripts/cleanup.sh dev --dry-run # Show what would be deleted

# Production requires explicit confirmation
./scripts/cleanup.sh prod --confirm --reason "Decommissioning platform"
```

---

## Verification

### Post-Teardown Validation

```bash
#!/bin/bash
# verify-cleanup.sh

echo "=== Post-Teardown Verification ==="
echo ""

PASS=0
FAIL=0

check() {
  if "$@" 2>/dev/null; then
    echo "[FAIL] $*"
    ((FAIL++))
  else
    echo "[PASS] $*"
    ((PASS++))
  fi
}

# Check no EKS clusters remain
check aws eks describe-cluster --name "platform-${ENVIRONMENT}" 2>&1 | grep -q "ResourceNotFoundException"

# Check no RDS instances remain
check aws rds describe-db-instances \
  --query "DBInstances[?contains(DBInstanceIdentifier, 'platform-${ENVIRONMENT}')]" \
  --output text | grep -q ""

# Check no S3 buckets remain
check aws s3api list-buckets \
  --query "Buckets[?contains(Name, 'platform-${ENVIRONMENT}')].Name" \
  --output text | grep -q ""

# Check no load balancers remain
check aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?contains(LoadBalancerName, 'platform-${ENVIRONMENT}')]" \
  --output text | grep -q ""

# Check IAM roles are cleaned up
check aws iam list-roles \
  --query "Roles[?contains(RoleName, 'platform-${ENVIRONMENT}')]" \
  --output text | grep -q ""

# Check no ECR repositories remain
check aws ecr describe-repositories \
  --query "repositories[?contains(repositoryName, 'platform')]" \
  --output text | grep -q ""

# Check DNS records are cleaned (optional)
# check aws route53 list-resource-record-sets --hosted-zone-id ZXXXXXXXX \
#   --query "ResourceRecordSets[?contains(Name, 'platform')]" \
#   --output text | grep -q ""

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
exit $FAIL
```

### Cost Confirmation

```bash
# Verify no active resources are still incurring costs
aws ce get-cost-and-usage \
  --time-period Start=$(date -d "-7 days" +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity DAILY \
  --metrics "BlendedCost" \
  --filter '{"Tags":{"Key":"Environment","Values":["'${ENVIRONMENT}'"]}}'
```

### Teardown Summary Report

```markdown
# Platform Teardown Report

## Summary
- **Environment**: dev
- **Start Time**: 2026-05-17 10:00:00 UTC
- **End Time**: 2026-05-17 11:15:00 UTC
- **Status**: Complete

## Resources Deleted
| Resource Type | Count | Status |
|--------------|-------|--------|
| ArgoCD Applications | 9 | Deleted |
| Kubernetes Namespaces | 12 | Deleted |
| EKS Cluster | 1 | Deleted |
| EC2 Instances | 5 | Terminated |
| RDS Database | 1 | Deleted with snapshot |
| ElastiCache | 1 | Deleted |
| Load Balancers | 2 | Deleted |
| NAT Gateways | 3 | Deleted |
| S3 Buckets | 4 | Deleted |
| ECR Repositories | 5 | Deleted |
| IAM Roles | 8 | Deleted |
| CloudWatch Log Groups | 3 | Deleted |

## Data Preserved
- RDS final snapshot: `platform-dev-final-20260517`
- Terraform state: Preserved in S3 (other environments)

## Notes
- Cross-account IAM roles were preserved
- Route53 hosted zone was preserved
- ACM certificates were preserved
```

---

## Next Steps

After teardown:

1. [Review the architecture document](../architecture/ARCHITECTURE.md) for redeployment planning
2. [Review security lessons learned](../security/01-security-overview.md)
3. [Plan infrastructure improvements based on postmortems](../operations/02-incident-response.md)
