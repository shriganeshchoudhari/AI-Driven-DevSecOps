# Rollback Procedures

Comprehensive rollback procedures for every layer of the platform, from infrastructure to application code.

---

## Table of Contents

- [Rollback Decision Framework](#rollback-decision-framework)
- [Terraform State Rollback](#terraform-state-rollback)
- [Kubernetes Deployment Rollback](#kubernetes-deployment-rollback)
- [ArgoCD Application Rollback](#argocd-application-rollback)
- [Database Rollback (RDS)](#database-rollback-rds)
- [Secrets Rollback](#secrets-rollback)
- [DNS Rollback](#dns-rollback)
- [Full Environment Rollback](#full-environment-rollback)

---

## Rollback Decision Framework

```
                    ┌─────────────────────┐
                    │  Incident Detected  │
                    └──────────┬──────────┘
                               │
                    ┌──────────▼──────────┐
                    │  Assess Impact      │
                    │  - User-facing?     │
                    │  - Data loss risk?  │
                    │  - Security issue?  │
                    └──────────┬──────────┘
                               │
              ┌────────────────┼────────────────┐
              ▼                ▼                ▼
       ┌─────────────┐ ┌─────────────┐ ┌─────────────┐
       │ SEV1/SEV2   │ │   SEV3      │ │   SEV4      │
       │ Rollback    │ │ Rollback if │ │ Fix forward │
       │ Immediately │ │ risk < fix  │ │             │
       └─────────────┘ └─────────────┘ └─────────────┘
              │                │
              ▼                ▼
       ┌──────────────────────────────────┐
       │  Select Rollback Method          │
       │                                   │
       │  Layer 1: Application Rollback   │
       │  Layer 2: ArgoCD Rollback        │
       │  Layer 3: Kubernetes Rollback    │
       │  Layer 4: Database Rollback      │
       │  Layer 5: Infrastructure Rollback│
       │  Layer 6: DNS Rollback           │
       └──────────────────────────────────┘
```

---

## Terraform State Rollback

### Prerequisites

```bash
export ENVIRONMENT="dev"
export TF_DIR="terraform/environments/${ENVIRONMENT}"
export BACKEND_BUCKET="platform-terraform-state-123456789012"
export STATE_KEY="${ENVIRONMENT}/terraform.tfstate"
```

### Option 1: Revert Specific Resource Version

```bash
cd ${TF_DIR}

# List available state versions
aws s3api list-object-versions \
  --bucket "${BACKEND_BUCKET}" \
  --prefix "${STATE_KEY}" \
  --query "Versions[*].[VersionId,LastModified]" \
  --output table

# Get specific version
PREVIOUS_VERSION="xxxxxxxxxx"

# Download previous state
aws s3api get-object \
  --bucket "${BACKEND_BUCKET}" \
  --key "${STATE_KEY}" \
  --version-id "${PREVIOUS_VERSION}" \
  previous.tfstate

# Plan rollback
terraform plan -state=previous.tfstate -out=rollback.tfplan

# Apply rollback
terraform apply rollback.tfplan
```

### Option 2: Terraform State Modification

```bash
# Remove problematic resource from state
terraform state list | grep -E "module.eks|module.vpc"

# Remove specific resource
terraform state rm module.eks.aws_eks_cluster.this[0]

# Re-import the resource with correct configuration
terraform import module.eks.aws_eks_cluster.this[0] platform-dev

# Verify state
terraform state list
```

### Option 3: Full State Restoration

```bash
# Lock state file to prevent changes
aws dynamodb put-item \
  --table-name platform-terraform-locks \
  --item '{
    "LockID": {"S": "${BACKEND_BUCKET}/${STATE_KEY}-md5"},
    "Info": {"S": "Manual rollback lock - $(date -u)"}
  }'

# Download state file from backup
aws s3 cp "s3://${BACKEND_BUCKET}/backups/${STATE_KEY}.20260517-100000" terraform.tfstate

# Push restored state
terraform state push terraform.tfstate

# Unlock
aws dynamodb delete-item \
  --table-name platform-terraform-locks \
  --key '{"LockID": {"S": "${BACKEND_BUCKET}/${STATE_KEY}-md5"}}'
```

### S3 Bucket and State Backup

```bash
# Enable versioning on state bucket (should already be enabled)
aws s3api get-bucket-versioning --bucket "${BACKEND_BUCKET}"

# Automated state backups
aws s3api put-bucket-lifecycle-configuration \
  --bucket "${BACKEND_BUCKET}" \
  --lifecycle-configuration '{
    "Rules": [{
      "ID": "state-backup",
      "Status": "Enabled",
      "NoncurrentVersionExpiration": {
        "NoncurrentDays": 90
      }
    }]
  }'
```

### Rollback Key Infrastructure Modules

```bash
# Rollback VPC
terraform plan -target=module.vpc -destroy -out=vpc-rollback.tfplan
terraform apply vpc-rollback.tfplan

# Rollback EKS cluster
terraform plan -target=module.eks -destroy -out=eks-rollback.tfplan
terraform apply eks-rollback.tfplan

# Rollback specific module
terraform plan -target=module.rds -destroy -out=rds-rollback.tfplan
terraform apply rds-rollback.tfplan
```

---

## Kubernetes Deployment Rollback

### Rollback Deployments

```bash
# Check deployment history
kubectl rollout history deployment/aiops-engine -n aiops

# Expected output:
# deployment.apps/aiops-engine
# REVISION  CHANGE-CAUSE
# 1         <none>
# 2         kubectl apply --filename=manifests.yaml --record=true
# 3         kubectl set image deployment/aiops-engine aiops-engine=v1.0.1

# Rollback to previous revision
kubectl rollout undo deployment/aiops-engine -n aiops

# Rollback to specific revision
kubectl rollout undo deployment/aiops-engine -n aiops --to-revision=1

# Verify rollback
kubectl rollout status deployment/aiops-engine -n aiops --watch
kubectl describe deployment/aiops-engine -n aiops | grep Image
```

### Rollback DaemonSets

```bash
# Check history
kubectl rollout history daemonset/falco -n falco

# Rollback
kubectl rollout undo daemonset/falco -n falco

# Verify
kubectl rollout status daemonset/falco -n falco --watch
```

### Rollback StatefulSets

```bash
# Check history
kubectl rollout history statefulset/loki -n monitoring

# Rollback with persistence consideration
kubectl rollout undo statefulset/loki -n monitoring --to-revision=1

# Verify
kubectl rollout status statefulset/loki -n monitoring --watch
```

### Emergency Pod Replacement

```bash
# Force delete problematic pod
kubectl delete pod aiops-engine-xxxxx -n aiops --force --grace-period=0

# Scale down and up
kubectl scale deployment/aiops-engine -n aiops --replicas=0
kubectl scale deployment/aiops-engine -n aiops --replicas=3
```

---

## ArgoCD Application Rollback

### Manual Rollback via CLI

```bash
# List application history
argocd app history aiops

# Expected output:
# ID  DATE                           REVISION
# 1   2026-05-17 09:00:00 +0000 UTC  abc1234 (HEAD)
# 2   2026-05-17 08:00:00 +0000 UTC  def5678
# 3   2026-05-17 07:00:00 +0000 UTC  ghi9012

# Rollback to specific revision
argocd app rollback aiops 2

# Verify rollback
argocd app get aiops
argocd app wait aiops --health
```

### Rollback via Git Revert

```bash
# Revert the problematic commit
git revert HEAD

# Push the revert
git push origin main

# ArgoCD will automatically sync and revert the changes

# Force sync if auto-sync is off
argocd app sync aiops
```

### Disable Auto-Sync During Rollback

```bash
# Disable auto-sync before rollback
argocd app set aiops --sync-policy=none

# Perform rollback
argocd app rollback aiops 1

# Re-enable auto-sync after verification
argocd app set aiops --sync-policy=automated --auto-prune --self-heal
```

### Rollback App-of-Apps

```bash
# Rollback root application
argocd app rollback root-app 3

# Wait for child apps to reconcile
argocd app wait --health --timeout 300

# Verify child app statuses
argocd app list -o json | jq '
  .[] | select(.status.sync.status != "Synced" or .status.health.status != "Healthy") |
  .metadata.name, .status.sync.status, .status.health.status
'
```

---

## Database Rollback (RDS)

### Point-in-Time Recovery

```bash
# List available restore times
aws rds describe-db-instances \
  --db-instance-identifier platform-prod \
  --query 'DBInstances[0].EarliestRestorableTime,DBInstances[0].LatestRestorableTime'

# Restore to specific time
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier platform-prod \
  --target-db-instance-identifier platform-prod-restored \
  --restore-time "2026-05-17T08:00:00Z" \
  --db-instance-class db.r6g.xlarge \
  --multi-az \
  --vpc-security-group-ids sg-xxxxx \
  --db-subnet-group-name platform-prod

# Monitor restore
aws rds describe-db-instances \
  --db-instance-identifier platform-prod-restored \
  --query 'DBInstances[0].DBInstanceStatus'
```

### Promote Restored Database

```bash
# Once restored, validate data
aws rds describe-db-instances \
  --db-instance-identifier platform-prod-restored \
  --query 'DBInstances[0].Endpoint.Address'

# Verify data integrity using temporary connection
psql -h platform-prod-restored.xxxxx.us-west-2.rds.amazonaws.com \
  -U platform_admin -d platform \
  -c "SELECT count(*) FROM information_schema.tables;"

# Promote to primary (if read replica)
aws rds promote-read-replica \
  --db-instance-identifier platform-prod-restored

# Switch DNS/application to new instance
# Update ExternalSecret to point to new host
```

### Rollback RDS Snapshot

```bash
# List snapshots
aws rds describe-db-snapshots \
  --db-instance-identifier platform-prod \
  --query 'DBSnapshots[*].[DBSnapshotIdentifier,SnapshotCreateTime]' \
  --output table

# Restore from snapshot
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier platform-prod-rollback \
  --db-snapshot-identifier platform-prod-final-snapshot-20260517 \
  --db-instance-class db.r6g.xlarge \
  --multi-az

# Monitor and swap
aws rds wait db-instance-available \
  --db-instance-identifier platform-prod-rollback

# Update database endpoint in ExternalSecret
kubectl patch externalsecret platform-database -n aiops \
  -p '{"spec":{"data":[{"secretKey":"host","remoteRef":{"key":"/platform/prod/database-rollback","property":"host"}}]}}'
```

### Cross-Region Database Restore

```bash
# Copy snapshot to DR region
aws rds copy-db-snapshot \
  --source-db-snapshot-identifier arn:aws:rds:us-west-2:123456789012:snapshot:platform-prod-snapshot \
  --target-db-snapshot-identifier platform-prod-dr-snapshot \
  --source-region us-west-2 \
  --region us-east-1

# Restore in DR region
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier platform-prod-dr \
  --db-snapshot-identifier platform-prod-dr-snapshot \
  --db-instance-class db.r6g.xlarge \
  --region us-east-1

# Redirect DNS
aws route53 change-resource-record-sets \
  --hosted-zone-id ZXXXXXXXX \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "db.platform.example.com",
        "Type": "CNAME",
        "TTL": 60,
        "ResourceRecords": [{"Value": "platform-prod-dr.xxxxx.us-east-1.rds.amazonaws.com"}]
      }
    }]
  }'
```

### Kubernetes Database Rollback Checklist

```bash
# 1. Stop applications using database
kubectl scale deployment -n aiops --all --replicas=0
kubectl scale deployment -n default --all --replicas=0

# 2. Verify current database state
kubectl exec -n aiops deploy/aiops-engine -- \
  python3 -c "import os, psycopg2; print('connected')" 2>/dev/null || echo "already down"

# 3. Perform database restore
# (AWS CLI commands above)

# 4. Update connection string
kubectl patch externalsecret platform-database -n aiops \
  --type=json \
  -p='[{"op": "replace", "path": "/spec/data/0", "value": {
    "secretKey": "host",
    "remoteRef": {"key": "/platform/prod/database-restored", "property": "host"}
  }}]'

# 5. Restart External Secrets
kubectl rollout restart deployment external-secrets -n external-secrets

# 6. Restart applications
kubectl scale deployment -n aiops --all --replicas=1

# 7. Verify connectivity
kubectl wait --for=condition=Ready pods --all -n aiops --timeout=120s
kubectl exec -n aiops deploy/aiops-engine -- \
  python3 -c "import os, psycopg2; conn = psycopg2.connect(...); print('OK')"

# 8. Restore remaining services
kubectl scale deployment -n default --all --replicas=1
```

---

## Secrets Rollback

### Restore Previous Secret Version

```bash
# List secret versions
aws secretsmanager list-secret-version-ids \
  --secret-id /platform/prod/database

# Get specific version
aws secretsmanager get-secret-value \
  --secret-id /platform/prod/database \
  --version-id "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" \
  --query SecretString

# Restore previous version as current
aws secretsmanager update-secret-version-stage \
  --secret-id /platform/prod/database \
  --version-stage AWSCURRENT \
  --move-to-version-id "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" \
  --remove-from-version-id "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy"
```

### Trigger Secret Reconciliation

```bash
# Force ExternalSecret refresh
kubectl annotate externalsecret platform-database -n aiops \
  force-sync=$(date +%s) --overwrite

# Verify synced secret
kubectl get secret platform-database -n aiops -o json | jq '.data | map_values(@base64d)'

# Restart pods using the secret
kubectl rollout restart deployment -n aiops
```

### Emergency Secrets Rotation

```bash
# If secret is compromised
aws secretsmanager rotate-secret \
  --secret-id /platform/prod/database \
  --rotation-window-hours 1

# Or manually update
aws secretsmanager put-secret-value \
  --secret-id /platform/prod/database \
  --secret-string '{"password": "new-password-$(openssl rand -base64 32)"}'
```

---

## DNS Rollback

### Revert Route53 Changes

```bash
# Get current records
aws route53 list-resource-record-sets \
  --hosted-zone-id ZXXXXXXXX \
  --query "ResourceRecordSets[?Type=='A' || Type=='CNAME' || Type=='ALIAS']"

# Create change batch to revert to previous values
cat > dns-rollback.json << 'EOF'
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "api.platform.example.com",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "Z35SXDOTRQ7X7K",
          "DNSName": "dualstack.old-alb-xxxxx.us-west-2.elb.amazonaws.com",
          "EvaluateTargetHealth": true
        }
      }
    }
  ]
}
EOF

# Apply rollback
aws route53 change-resource-record-sets \
  --hosted-zone-id ZXXXXXXXX \
  --change-batch file://dns-rollback.json

# Verify propagation
nslookup api.platform.example.com
dig api.platform.example.com +short
```

### Rollback ExternalDNS

```bash
# If ExternalDNS created incorrect records

# Option 1: Delete the ingress/service that triggered it
kubectl delete ingress problematic-ingress

# Option 2: Fix annotation and re-sync
kubectl annotate ingress problematic-ingress \
  external-dns.alpha.kubernetes.io/ttl="60" --overwrite

# Option 3: Force ExternalDNS sync
kubectl delete pod -n external-dns -l app.kubernetes.io/name=external-dns
```

---

## Full Environment Rollback

### Complete Environment Rollback Procedure

```bash
#!/bin/bash
# full-rollback.sh - Complete environment rollback

set -euo pipefail

ENVIRONMENT="${1:-dev}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="rollback-${ENVIRONMENT}-${TIMESTAMP}.log"

log() {
    echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$LOG_FILE"
}

log "Starting full environment rollback for: ${ENVIRONMENT}"

# Phase 1: Disable GitOps auto-sync
log "Phase 1: Disabling ArgoCD auto-sync..."
for app in $(argocd app list -o name); do
    argocd app set "$app" --sync-policy=none
done

# Phase 2: Scale down applications
log "Phase 2: Scaling down applications..."
kubectl scale deployment --all --replicas=0 -A 2>/dev/null || true

# Phase 3: Rollback ArgoCD applications
log "Phase 3: Rolling back ArgoCD applications..."
argocd app rollback root-app 1 || log "WARNING: Root app rollback failed"

# Phase 4: Rollback Kubernetes resources
log "Phase 4: Rolling back Kubernetes resources..."
for ns in aiops monitoring security; do
    kubectl delete deployment -n "$ns" --all 2>/dev/null || true
done

# Phase 5: Rollback database
log "Phase 5: Rolling back database..."
# Execute RDS point-in-time recovery
# (Actual commands depend on environment)

# Phase 6: Rollback Terraform (if needed)
log "Phase 6: Rolling back infrastructure..."
# Only if infrastructure changes caused the issue

# Phase 7: Re-enable GitOps
log "Phase 7: Re-enabling ArgoCD auto-sync..."
for app in $(argocd app list -o name); do
    argocd app set "$app" --sync-policy=automated --auto-prune --self-heal
done

# Phase 8: Wait for health
log "Phase 8: Waiting for applications to stabilize..."
argocd app wait --health --timeout 300

log "Full environment rollback complete"
log "Verification: run ./scripts/validation.sh ${ENVIRONMENT}"
```

### Rollback Verification

```bash
# Run validation after rollback
./scripts/validation.sh

# Verify specific metrics
kubectl top nodes
kubectl top pods -A

# Check application health
curl -s https://api.platform.example.com/health

# Verify data integrity
# (Run specific data validation queries)
```

### Rollback Summary Report

```markdown
# Rollback Incident Report

## Metadata
- **Date**: 2026-05-17
- **Environment**: Production
- **Duration**: 45 minutes
- **Incident ID**: INC-2026-05-17-003
- **Rollback Lead**: Engineer Name

## Cause
Brief description of what triggered the rollback...

## Impact
- Services affected:
- User impact:
- Data loss:
- Duration:

## Rollback Steps Executed
1. [x] Disabled ArgoCD auto-sync
2. [x] Scaled down applications
3. [x] Rolled back ArgoCD applications to revision 3
4. [x] Rolled back database to 08:00 UTC snapshot
5. [x] Re-enabled auto-sync
6. [x] Verified application health

## Verification
- Validation suite: 35/35 tests passed
- API health: All endpoints 200
- Database: Data integrity verified
- Monitoring: All metrics nominal

## Lessons Learned
- What went well:
- What went wrong:
- Improvements needed:
```

---

## Next Steps

1. [Review full teardown procedure](08-teardown.md)
2. [Review disaster recovery plan](../operations/03-disaster-recovery.md)
3. [Update runbooks based on rollback findings](../operations/01-sre-runbook.md)
