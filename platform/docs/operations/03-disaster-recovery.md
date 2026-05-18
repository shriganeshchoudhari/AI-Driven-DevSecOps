# Disaster Recovery Plan

Comprehensive disaster recovery procedures for all failure scenarios.

---

## Table of Contents

- [RPO/RTO Targets](#rpo-rto-targets)
- [Backup Strategy](#backup-strategy)
- [DR Scenarios](#dr-scenarios)
- [Recovery Steps](#recovery-steps)
- [DR Automation](#dr-automation)
- [Testing Schedule](#testing-schedule)

---

## RPO/RTO Targets

| Tier | RPO | RTO | Services | Criticality |
|------|-----|-----|----------|-------------|
| **Tier 0** | 0-5 min | 1 hour | Payments, Auth, API Gateway | Critical |
| **Tier 1** | 1 hour | 4 hours | Orders, Users, Product Catalog | High |
| **Tier 2** | 4 hours | 8 hours | History, Reports, Notifications | Medium |
| **Tier 3** | 24 hours | 24 hours | Logs, Analytics, Batch Jobs | Low |

### Tier Definitions

**Tier 0 - Critical**: Direct revenue impact, user-facing core functionality, security-related services.
**Tier 1 - High**: Important business functionality, moderate user impact.
**Tier 2 - Medium**: Supporting functionality, internal tools.
**Tier 3 - Low**: Non-critical systems, batch processing, historical data.

---

## Backup Strategy

### Database Backups

| Service | Backup Method | Frequency | Retention | RPO Achieved |
|---------|--------------|-----------|-----------|-------------|
| RDS PostgreSQL | Automated snapshots | Daily | 35 days | 24 hours |
| RDS PostgreSQL | Automated snapshots + WAL | Continuous | 7 days | 5 minutes |
| RDS PostgreSQL | Manual snapshots (pre-deploy) | Per deploy | 90 days | N/A |
| RDS PostgreSQL | Cross-region snapshot | Daily | 30 days | 24 hours |

```bash
# Verify RDS backup configuration
aws rds describe-db-instances \
  --db-instance-identifier platform-prod \
  --query 'DBInstances[0].[BackupRetentionPeriod,PreferredBackupWindow,EarliestRestorableTime]'

# Create manual snapshot before deployment
aws rds create-db-snapshot \
  --db-instance-identifier platform-prod \
  --db-snapshot-identifier "platform-prod-pre-deploy-$(date +%Y%m%d-%H%M%S)"
```

### Kubernetes Backups

| Resource | Backup Method | Frequency | Retention |
|----------|--------------|-----------|-----------|
| Cluster Resources | Velero | Every 4 hours | 30 days |
| Persistent Volumes | Velero + CSI snapshot | Every 6 hours | 14 days |
| etcd (EKS) | AWS managed | Automatic | N/A |
| Kubernetes Secrets | AWS Secrets Manager | Real-time | N/A |

```bash
# Install Velero
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.9.0 \
  --bucket platform-backups \
  --backup-location-config region=us-west-2 \
  --snapshot-location-config region=us-west-2 \
  --use-volume-snapshots=true \
  --features=EnableCSI

# Create scheduled backup
velero schedule create platform-backup \
  --schedule="0 */4 * * *" \
  --ttl=720h \
  --include-namespaces="aiops,monitoring,argocd" \
  --volume-snapshot-locations="us-west-2"

# On-demand backup
velero backup create pre-deploy-backup \
  --include-namespaces="aiops,monitoring" \
  --ttl=168h

# List backups
velero backup get

# Verify backup
velero backup describe pre-deploy-backup --details
```

### S3 Backups

| Bucket | Replication | Retention | Versioning |
|--------|------------|-----------|------------|
| platform-logs | Cross-region to us-east-1 | 90 days | Enabled |
| platform-backups | Cross-region to us-east-1 | 30 days | Enabled |
| platform-artifacts | None | Until superseded | Enabled |

```bash
# Configure cross-region replication
aws s3api put-bucket-replication \
  --bucket platform-backups \
  --replication-configuration '{
    "Role": "arn:aws:iam::123456789012:role/s3-replication-role",
    "Rules": [{
      "Status": "Enabled",
      "Priority": 1,
      "DeleteMarkerReplication": { "Status": "Disabled" },
      "Destination": {
        "Bucket": "arn:aws:s3:::platform-backups-dr",
        "Region": "us-east-1"
      }
    }]
  }'
```

### ECR Image Backups

```bash
# Replicate images to DR region
aws ecr put-replication-configuration \
  --replication-configuration '{
    "rules": [{
      "destinations": [{
        "region": "us-east-1",
        "registryId": "123456789012"
      }],
      "repositoryFilters": [{
        "filter": "platform/*",
        "filterType": "PREFIX_MATCH"
      }]
    }]
  }'
```

### Secrets Backup

```bash
# Export secrets to backup file
BACKUP_FILE="secrets-backup-$(date +%Y%m%d).enc"

# List all platform secrets
aws secretsmanager list-secrets \
  --filter Key="name",Values="/platform" \
  --query "SecretList[*].Name" \
  --output text | while read secret; do
  aws secretsmanager get-secret-value \
    --secret-id "$secret" \
    --query SecretString \
    --output text >> "$BACKUP_FILE"
done

# Encrypt backup
gpg --encrypt --recipient platform-ops@example.com "$BACKUP_FILE"
aws s3 cp "${BACKUP_FILE}.gpg" s3://platform-backups/secrets/
```

---

## DR Scenarios

### Scenario 1: Single AZ Failure

**Impact**: Partial capacity loss, some pods may be rescheduled.
**RTO**: Automatic (within minutes).
**RPO**: No data loss.

```bash
# Verification
kubectl get nodes -o wide | grep "az-"

# Wait for Kubernetes scheduler to rebalance
kubectl get pods -A --field-selector=status.phase=Pending

# Check if any PVs are stuck
kubectl get pv -o wide | grep -i "failed\|released"

# Force reschedule if needed
kubectl delete pods -A --field-selector=status.phase=Pending --grace-period=0
```

### Scenario 2: Region Failure

**Impact**: Complete loss of primary region.
**RTO**: 1-4 hours (Tier 0 - Tier 3).
**RPO**: 5 minutes - 24 hours (Tier 0 - Tier 3).

```bash
#!/bin/bash
# dr-failover.sh - Cross-region failover

set -euo pipefail

DR_REGION="us-east-1"
PRIMARY_REGION="us-west-2"
ENVIRONMENT="${1:-prod}"

echo "[DR] Initiating failover to ${DR_REGION}"
echo "[DR] Time: $(date -u)"

# Step 1: Verify DR region is healthy
echo "[DR] Verifying DR region health..."
aws ec2 describe-availability-zones --region "${DR_REGION}" > /dev/null

# Step 2: Promote RDS read replica
echo "[DR] Promoting RDS read replica..."
aws rds promote-read-replica \
  --db-instance-identifier "platform-${ENVIRONMENT}-dr" \
  --region "${DR_REGION}"

# Wait for promotion
aws rds wait db-instance-available \
  --db-instance-identifier "platform-${ENVIRONMENT}-dr" \
  --region "${DR_REGION}"

# Step 3: Update database endpoint
NEW_DB_HOST=$(aws rds describe-db-instances \
  --db-instance-identifier "platform-${ENVIRONMENT}-dr" \
  --region "${DR_REGION}" \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

aws secretsmanager put-secret-value \
  --secret-id "/platform/${ENVIRONMENT}/database" \
  --secret-string "{\"host\":\"${NEW_DB_HOST}\"}" \
  --region "${DR_REGION}"

# Step 4: Deploy EKS cluster in DR region (if not already deployed)
echo "[DR] Deploying infrastructure in DR region..."
cd terraform/environments/${ENVIRONMENT}
terraform workspace select dr
terraform apply -auto-approve -var="region=${DR_REGION}"

# Step 5: Configure kubectl for DR cluster
aws eks update-kubeconfig \
  --name "platform-${ENVIRONMENT}" \
  --region "${DR_REGION}" \
  --alias "platform-${ENVIRONMENT}-dr"

# Step 6: Restore Velero backup
echo "[DR] Restoring from latest Velero backup..."
LATEST_BACKUP=$(velero get backup -o json | jq -r '.items | max_by(.metadata.creationTimestamp) | .metadata.name')
velero restore create \
  --from-backup "${LATEST_BACKUP}" \
  --wait

# Step 7: Switch DNS
echo "[DR] Updating DNS records..."
cat > dns-switch.json << EOF
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "api.platform.example.com",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "Z35SXDOTRQ7X7K",
          "DNSName": "${DR_REGION}-alb.${DR_REGION}.elb.amazonaws.com",
          "EvaluateTargetHealth": true
        }
      }
    }
  ]
}
EOF

aws route53 change-resource-record-sets \
  --hosted-zone-id "ZXXXXXXXXXXXX" \
  --change-batch file://dns-switch.json

# Step 8: Validate health
echo "[DR] Validating service health..."
./scripts/validation.sh --region "${DR_REGION}"

echo "[DR] Failover complete. Region: ${DR_REGION}"
echo "[DR] Time: $(date -u)"
```

### Scenario 3: Data Corruption

**Impact**: Application data corrupted or deleted.
**RTO**: 1-4 hours.
**RPO**: 5 minutes (with WAL) or 24 hours (daily snapshot).

```bash
#!/bin/bash
# data-recovery.sh - Point-in-time recovery

ENVIRONMENT="${1:-prod}"
PI_TIME="${2:-}" # Format: 2026-05-17T08:00:00Z

if [ -z "$PI_TIME" ]; then
  echo "Usage: $0 <environment> <point-in-time>"
  echo "Example: $0 prod 2026-05-17T08:00:00Z"
  exit 1
fi

echo "[RECOVERY] Starting point-in-time recovery to: ${PI_TIME}"

# 1. Stop applications
kubectl scale deployment --all --replicas=0 -n aiops
kubectl scale deployment --all --replicas=0 -n applications

# 2. Restore RDS to point-in-time
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier "platform-${ENVIRONMENT}" \
  --target-db-instance-identifier "platform-${ENVIRONMENT}-recovered" \
  --restore-time "${PI_TIME}" \
  --db-instance-class db.r6g.xlarge \
  --multi-az \
  --vpc-security-group-ids sg-xxxxx \
  --db-subnet-group-name "platform-${ENVIRONMENT}"

aws rds wait db-instance-available \
  --db-instance-identifier "platform-${ENVIRONMENT}-recovered"

# 3. Verify data integrity
RECOVERED_HOST=$(aws rds describe-db-instances \
  --db-instance-identifier "platform-${ENVIRONMENT}-recovered" \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

psql -h "${RECOVERED_HOST}" -U platform_admin -d platform \
  -c "SELECT count(*) FROM information_schema.tables;"

# 4. Update secrets with new endpoint
aws secretsmanager put-secret-value \
  --secret-id "/platform/${ENVIRONMENT}/database-recovered" \
  --secret-string "{\"host\":\"${RECOVERED_HOST}\"}"

# 5. Restart applications with recovered database
kubectl patch externalsecret platform-database -n aiops \
  -p "{\"spec\":{\"data\":[{\"secretKey\":\"host\",\"remoteRef\":{\"key\":\"/platform/${ENVIRONMENT}/database-recovered\",\"property\":\"host\"}}]}}"

kubectl scale deployment --all --replicas=1 -n aiops

# 6. Validate
./scripts/validation.sh
```

### Scenario 4: Cluster Failure

**Impact**: Complete loss of Kubernetes cluster.
**RTO**: 2-4 hours.
**RPO**: 4 hours (Velero backups) / No data loss (RDS, ElastiCache external).

```bash
#!/bin/bash
# cluster-recovery.sh - Rebuild EKS Cluster from IaC

ENVIRONMENT="${1:-prod}"

echo "[RECOVERY] Rebuilding EKS cluster for ${ENVIRONMENT}"

# 1. Run Terraform to rebuild cluster
cd terraform/environments/${ENVIRONMENT}

# Remove broken cluster from state (if partially failed)
terraform state rm module.eks 2>/dev/null || true

# Apply infrastructure
terraform apply -auto-approve -target=module.eks

# 2. Configure kubectl
CLUSTER_NAME=$(terraform output -raw cluster_name)
aws eks update-kubeconfig \
  --name "${CLUSTER_NAME}" \
  --region us-west-2

# 3. Bootstrap platform services (ArgoCD, monitoring, etc.)
./scripts/bootstrap.sh --phase platform

# 4. Restore Velero backups
velero restore create \
  --from-backup latest-cluster-backup \
  --wait

# 5. Restore applications via ArgoCD
argocd app sync root-app
argocd app wait --health --timeout 300

# 6. Validate
./scripts/validation.sh
```

### Scenario 5: Secrets Compromise

**Impact**: Secrets, keys, or credentials exposed.
**RTO**: 30 minutes - 2 hours.
**RPO**: N/A (secrets should be rotated, not recovered).

```bash
#!/bin/bash
# secrets-rotation.sh - Emergency secrets rotation

ENVIRONMENT="${1:-prod}"
COMPROMISED_SECRET="${2:-}"

rotate_secret() {
  local SECRET_NAME=$1
  echo "[ROTATION] Rotating secret: ${SECRET_NAME}"
  
  aws secretsmanager rotate-secret \
    --secret-id "${SECRET_NAME}" \
    --rotation-window-hours 1
  
  echo "[ROTATION] Triggering ExternalSecret refresh..."
  kubectl annotate externalsecret --all -n aiops \
    force-sync=$(date +%s) --overwrite
  kubectl annotate externalsecret --all -n monitoring \
    force-sync=$(date +%s) --overwrite
  
  echo "[ROTATION] Restarting pods using ${SECRET_NAME}..."
  kubectl rollout restart deployment -n aiops
  kubectl rollout restart deployment -n applications
}

case $COMPROMISED_SECRET in
  database)
    rotate_secret "/platform/${ENVIRONMENT}/database"
    rotate_secret "/platform/${ENVIRONMENT}/database-master"
    ;;
  redis)
    rotate_secret "/platform/${ENVIRONMENT}/redis"
    kubectl rollout restart statefulset -n monitoring loki
    ;;
  oidc)
    rotate_secret "/platform/${ENVIRONMENT}/oidc"
    kubectl rollout restart deployment -n argocd
    ;;
  all)
    for secret in $(aws secretsmanager list-secrets \
      --filter Key="name",Values="/platform/${ENVIRONMENT}" \
      --query "SecretList[*].Name" \
      --output text); do
      rotate_secret "$secret"
    done
    ;;
  *)
    rotate_secret "/platform/${ENVIRONMENT}/${COMPROMISED_SECRET}"
    ;;
esac

echo "[ROTATION] All secrets rotated. Verify service health."
./scripts/validation.sh
```

---

## Recovery Steps

### Full Region Recovery Timeline

```
T+0min  ── Declare DR event
T+5min  ── Activate DR team
T+15min ── Assess scope of disaster
T+30min ── Begin infrastructure deployment (DR region)
T+60min ── EKS cluster operational (DR region)
T+90min ── Platform services installed (ArgoCD, monitoring)
T+120min ─ RDS promoted and verified
T+150min ─ Data restored from Velero backups
T+180min ─ Applications deployed and synced
T+210min ─ DNS switched to DR region
T+240min ─ Full validation complete
```

### Recovery Team Roles

| Role | Responsibility | Contact |
|------|---------------|---------|
| DR Lead | Overall coordination, go/no-go decisions | Director of Engineering |
| Infrastructure Lead | Infrastructure deployment (Terraform) | Platform Engineering Lead |
| Data Lead | Database recovery, data validation | Database Admin |
| Network Lead | DNS, load balancers, networking | Network Engineer |
| Security Lead | Security validation, compliance checks | Security Engineer |
| Communications Lead | Stakeholder updates, status page | Engineering Manager |

---

## DR Automation

### Automated DR Runbook

```python
# aiops/dr_automation.py - AIOps-driven DR automation

class DRAutomation:
    def __init__(self, environment):
        self.environment = environment
        self.dr_region = "us-east-1"
        self.primary_region = "us-west-2"
        
    def detect_failure(self):
        """Monitor for conditions that trigger DR"""
        checks = {
            "eks_api": self.check_eks_api(),
            "rds_health": self.check_rds(),
            "alb_health": self.check_alb(),
            "dns_resolution": self.check_dns(),
        }
        return checks
    
    def assess_impact(self, checks):
        """Determine if DR is needed"""
        critical_failures = sum(1 for v in checks.values() if not v)
        if critical_failures >= 2:
            return "DR_REQUIRED"
        elif critical_failures == 1:
            return "INVESTIGATE"
        return "HEALTHY"
    
    def execute_failover(self):
        """Execute automated failover"""
        steps = [
            "verify_dr_region",
            "promote_rds_replica",
            "deploy_infrastructure",
            "restore_backups",
            "switch_dns",
            "validate_health"
        ]
        results = {}
        for step in steps:
            results[step] = getattr(self, f"step_{step}")()
            if not results[step]:
                self.escalate(f"DR step failed: {step}")
                return False
        return True
    
    def rollback_failover(self):
        """Rollback DR if primary region recovers"""
        pass
```

### DR Status Dashboard

```bash
# Check DR status
curl -s http://aiops-engine.aiops:8000/api/v1/dr/status | jq .

# Expected output:
# {
#   "dr_region": "us-east-1",
#   "primary_region": "us-west-2",
#   "status": "HEALTHY",
#   "last_failover_test": "2026-05-10T10:00:00Z",
#   "replication_lag": "30s",
#   "backup_age": "2h",
#   "readiness": {
#     "infrastructure": "READY",
#     "data": "READY",
#     "dns": "READY",
#     "secrets": "READY"
#   }
# }
```

---

## Testing Schedule

| Test Type | Frequency | Scope | Duration | Responsible |
|-----------|-----------|-------|----------|-------------|
| **Backup Restoration** | Weekly | Restore one service from backup in dev | 1 hour | SRE Team |
| **AZ Failure** | Bi-weekly | Simulate AZ failure in staging | 2 hours | Platform Engineering |
| **Chaos Experiment** | Weekly | Automated chaos in dev | 30 min | SRE Team |
| **DR Tabletop** | Monthly | Walk through DR scenario | 1 hour | All teams |
| **Full DR Drill** | Quarterly | Complete failover to DR region | 4 hours | All teams |
| **Security Incident** | Monthly | Simulated security breach | 2 hours | Security + SRE |

### DR Drill Checklist

```
Pre-Drill
□ [ ] Announce drill schedule and scope
□ [ ] Ensure all teams are aware and available
□ [ ] Document baseline metrics
□ [ ] Verify monitoring is working
□ [ ] Create pre-drill snapshot (database)

During Drill
□ [ ] Execute failover procedure
□ [ ] Document each step and timing
□ [ ] Note any deviations from runbook
□ [ ] Track metrics at each phase

Post-Drill
□ [ ] Fail back to primary region
□ [ ] Verify all data is intact
□ [ ] Run full validation suite
□ [ ] Conduct hot wash / retrospective
□ [ ] Update runbooks based on findings
□ [ ] Publish drill report
```

### DR Drill Report Template

```markdown
# Disaster Recovery Drill Report

## Drill Information
- **Date**: 2026-05-17
- **Type**: Full Region Failover / Tabletop / Chaos
- **Scenario**: {description}
- **Duration**: {start} to {end}
- **Participants**: @engineer1, @engineer2, ...

## Results

| Metric | Target | Actual | Status |
|--------|--------|--------|--------|
| RTO (Tier 0) | 1 hour | 45 min | ✓ |
| RTO (Tier 1) | 4 hours | 2.5 hours | ✓ |
| RPO (Tier 0) | 5 min | 3 min | ✓ |
| Data Loss | 0 | 0 | ✓ |

## Timeline

| Time | Event | Duration |
|------|-------|----------|
| 10:00 | Drill started | - |
| 10:02 | DR declared | 2 min |
| 10:05 | Infrastructure deployment started | 3 min |
| 10:35 | EKS cluster operational | 35 min |
| 11:00 | Database promoted and verified | 60 min |
| 11:30 | Applications deployed | 90 min |
| 11:45 | DNS switched | 105 min |
| 12:00 | Validation complete | 120 min |

## Issues Found
1. {issue} - {resolution}
2. {issue} - {resolution}

## Improvements Needed
- [ ] Update DNS TTL for faster failover
- [ ] Automate RDS promotion step
- [ ] Add cross-region Velero backup schedule
- [ ] Create DR status dashboard

## Next Steps
- Schedule follow-up for action items
- Update runbooks with drill findings
- Plan next quarter's drill
```

---

## Next Steps

1. [Review cost optimization strategies](04-cost-optimization.md)
2. [Review security overview](../security/01-security-overview.md)
3. [Review SRE runbook](01-sre-runbook.md)
