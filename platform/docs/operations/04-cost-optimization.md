# Cost Optimization Guide

Strategies, tools, and procedures for optimizing platform costs across all environments.

---

## Table of Contents

- [Cost Analysis Methodology](#cost-analysis-methodology)
- [EC2 Right-Sizing (Karpenter)](#ec2-right-sizing-karpenter)
- [RDS Instance Optimization](#rds-instance-optimization)
- [S3 Lifecycle Policies](#s3-lifecycle-policies)
- [ECR Image Cleanup](#ecr-image-cleanup)
- [Reserved Instance Strategy](#reserved-instance-strategy)
- [Spot Instance Usage](#spot-instance-usage)
- [Monitoring with AWS Cost Explorer](#monitoring-with-aws-cost-explorer)
- [Budget Alerts](#budget-alerts)
- [Monthly Cost Review Process](#monthly-cost-review-process)

---

## Cost Analysis Methodology

### Cost Attribution

All resources must be tagged for cost allocation:

```hcl
locals {
  cost_tags = {
    Environment = var.environment
    Application = var.application_name
    Team        = var.team_name
    CostCenter  = "platform-${var.environment}"
    ManagedBy   = "terraform"
    CreatedBy   = "platform-engineering"
    Project     = "aiops-platform"
  }
}
```

### Tag Enforcement

```bash
# Check for untagged resources
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Environment,Values="${ENVIRONMENT}" \
  --query 'ResourceTagMappingList[*].ResourceARN' \
  --output text | wc -l

# Report resources missing required tags
aws resourcegroupstaggingapi get-resources \
  --query "ResourceTagMappingList[?!not_null(Tags[?Key=='Environment'].Value)] | [].ResourceARN"
```

---

## EC2 Right-Sizing (Karpenter)

### Karpenter Consolidation

Karpenter automatically consolidates nodes for optimal resource utilization:

```yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: default
spec:
  disruption:
    consolidationPolicy: WhenUnderutilized
    consolidateAfter: 5m
    budgets:
    - nodes: 10%
```

### Instance Family Selection

Configure Karpenter to select cost-optimized instances:

```yaml
spec:
  template:
    spec:
      requirements:
      # Prefer Graviton (ARM) instances for 20% cost savings
      - key: "karpenter.k8s.aws/instance-family"
        operator: In
        values: ["m7g", "c7g", "r7g", "m6g", "c6g", "r6g"]
      # Allow Intel as fallback
      - key: "karpenter.k8s.aws/instance-family"
        operator: In
        values: ["m7i", "c7i", "r7i", "m6i", "c6i", "r6i"]
      - key: "karpenter.sh/capacity-type"
        operator: In
        values: ["spot", "on-demand"]
```

### Cost Savings Analysis

```bash
# Compare instance costs
echo "=== Current Instance Mix ==="
kubectl get nodes -o json | jq -r '
  .items[].metadata.labels["node.kubernetes.io/instance-type"]' |
  sort | uniq -c | sort -rn

echo "=== Potential Savings with Graviton ==="
# m5.xlarge: $0.192/hr
# m6g.xlarge: $0.154/hr (20% savings)
echo "m5.xlarge → m7g.xlarge: Save 20% per instance"
echo "c5.xlarge → c7g.xlarge: Save 20% per instance"
```

### Rightsizing Recommendations

| Current Instance | Recommended | vCPU | Memory | Hourly Savings | Monthly Savings |
|-----------------|-------------|------|--------|---------------|-----------------|
| m5.xlarge | m7i.xlarge | 4 | 16 GB | $0.038 | $27.36 |
| m5.2xlarge | m7i.2xlarge | 8 | 32 GB | $0.077 | $55.44 |
| c5.xlarge | c7i.xlarge | 4 | 8 GB | $0.034 | $24.48 |
| r5.xlarge | r7i.xlarge | 4 | 32 GB | $0.048 | $34.56 |

---

## RDS Instance Optimization

### Right-Sizing Analysis

```bash
# Check RDS metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=platform-prod \
  --start-time $(date -d "-7 days" +%Y-%m-%dT00:00:00Z) \
  --end-time $(date +%Y-%m-%dT00:00:00Z) \
  --period 3600 \
  --statistics Maximum

# Check CPU utilization
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=platform-prod \
  --start-time $(date -d "-7 days" +%Y-%m-%dT00:00:00Z) \
  --end-time $(date +%Y-%m-%dT00:00:00Z) \
  --period 3600 \
  --statistics Average
```

### RDS Optimization Decision Matrix

| Avg CPU | Max Connections | Freeable Memory | Action |
|---------|----------------|-----------------|--------|
| < 20% | < 25% | > 50% | Downsize instance |
| 20-40% | 25-50% | 25-50% | Current size OK |
| 40-60% | 50-75% | 10-25% | Monitor, plan upgrade |
| > 60% | > 75% | < 10% | Upgrade instance |

### Multi-AZ vs Single-AZ

| Environment | Configuration | Monthly Cost | Savings vs Multi-AZ |
|-------------|--------------|-------------|---------------------|
| Development | Single-AZ, db.t4g.small | $45 | -60% |
| Staging | Multi-AZ, db.r6g.large | $520 | N/A (HA required) |
| Production | Multi-AZ, db.r6g.xlarge | $960 | N/A (HA required) |

### Reserved Instance Recommendations for RDS

| Instance | Current Monthly | 1-Year Std | 3-Year Std | 1-Year All Upfront |
|----------|----------------|------------|------------|-------------------|
| db.r6g.xlarge | $960 | $672 (30%) | $480 (50%) | $384 (60%) |
| db.r6g.large | $520 | $364 (30%) | $260 (50%) | $208 (60%) |

---

## S3 Lifecycle Policies

### Lifecycle Rules

```hcl
resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "expire-logs"
    status = "Enabled"

    filter {
      prefix = "cloudtrail/"
    }

    expiration {
      days = 90
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 60
      storage_class = "GLACIER"
    }
  }

  rule {
    id     = "expire-old-backups"
    status = "Enabled"

    filter {
      prefix = "backups/"
    }

    expiration {
      days = 90
    }
  }
}
```

### Storage Class Cost Comparison

| Storage Class | Cost/GB/Month | Retrieval Cost | Use Case |
|---------------|---------------|----------------|----------|
| S3 Standard | $0.023 | Free | Active data (0-30 days) |
| S3 Intelligent-Tiering | $0.023 | Free | Unknown access patterns |
| S3 Standard-IA | $0.0125 | $0.01/GB | Infrequent access (30-60 days) |
| S3 One Zone-IA | $0.01 | $0.01/GB | Recreatable data |
| S3 Glacier | $0.004 | $0.03/GB | Archived data (60-90 days) |
| S3 Glacier Deep Archive | $0.00099 | $0.05/GB | Long-term archive (>90 days) |

### S3 Cost Savings Script

```bash
#!/bin/bash
# analyze-s3-costs.sh

echo "=== S3 Cost Analysis ==="

for bucket in $(aws s3api list-buckets --query "Buckets[*].Name" --output text); do
  echo "Bucket: $bucket"
  
  # Get bucket size
  SIZE=$(aws s3api list-objects --bucket "$bucket" --output json \
    --query "sum(Contents[].Size)" 2>/dev/null || echo "0")
  
  # Get object count
  COUNT=$(aws s3api list-objects --bucket "$bucket" --output json \
    --query "length(Contents[])" 2>/dev/null || echo "0")
  
  echo "  Size: $(numfmt --to=iec $SIZE)"
  echo "  Objects: $COUNT"
  echo "  Estimated monthly cost: $(echo "scale=2; $SIZE / 1073741824 * 0.023" | bc)"
  echo ""
done

echo "Potential savings with lifecycle policies:"
echo "- S3 Standard to Standard-IA: Save ~45%"
echo "- S3 Standard to Glacier: Save ~82%"
echo "- S3 Standard to Deep Archive: Save ~95%"
```

### S3 Cost Optimization Checklist

```
□ Enable S3 Intelligent-Tiering for buckets with unknown access patterns
□ Configure lifecycle policies to transition old data to cheaper tiers
□ Set up expiration policies for temporary data
□ Delete incomplete multipart uploads after 7 days
□ Enable S3 Object Expiration for log buckets after defined retention
□ Review and remove any public buckets (cost + security risk)
□ Enable Cost Allocation Tags on all buckets
```

---

## ECR Image Cleanup

### Lifecycle Policy

```json
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Keep latest 50 images",
      "selection": {
        "tagStatus": "any",
        "countType": "imageCountMoreThan",
        "countNumber": 50
      },
      "action": {
        "type": "expire"
      }
    },
    {
      "rulePriority": 2,
      "description": "Expire untagged images after 7 days",
      "selection": {
        "tagStatus": "untagged",
        "countType": "sinceImagePushed",
        "countUnit": "days",
        "countNumber": 7
      },
      "action": {
        "type": "expire"
      }
    }
  ]
}
```

### Manual Cleanup Script

```bash
#!/bin/bash
# cleanup-ecr.sh

DAYS_OLD=${1:-30}
REPOS=$(aws ecr describe-repositories \
  --query "repositories[?contains(repositoryName, 'platform')].repositoryName" \
  --output text)

for repo in $REPOS; do
  echo "Cleaning up ${repo}..."
  
  # List images older than DAYS_OLD
  OLD_IMAGES=$(aws ecr describe-images \
    --repository-name "$repo" \
    --query "imageDetails[?imagePushedAt < '$(date -d "-${DAYS_OLD} days" +%Y-%m-%dT%H:%M:%S)'].[imageDigest]" \
    --output text)
  
  if [ -n "$OLD_IMAGES" ]; then
    echo "  Deleting ${OLD_IMAGES} old images..."
    
    while IFS= read -r digest; do
      aws ecr batch-delete-image \
        --repository-name "$repo" \
        --image-ids "imageDigest=${digest}" > /dev/null
    done <<< "$OLD_IMAGES"
    
    echo "  Cleaned up $(echo "$OLD_IMAGES" | wc -l) images"
  else
    echo "  No old images to clean"
  fi
done

echo "ECR cleanup complete"
```

### ECR Cost Optimization

| Action | Savings | Impact |
|--------|---------|--------|
| Remove untagged images | Variable | None (untagged) |
| Keep only last 50 tagged images | ~$5-20/month | Lose older versions |
| Cross-region replication (selective only) | Variable | Higher DR cost |
| Scan on push (enabled) | Included | Security benefit |

---

## Reserved Instance Strategy

### EC2 Savings Plans vs Reserved Instances

| Purchase Option | Discount | Flexibility | Commitment |
|----------------|----------|-------------|------------|
| Compute Savings Plan | Up to 66% | Any region, instance, OS | 1 or 3 years |
| EC2 Instance Savings Plan | Up to 72% | Within region, family | 1 or 3 years |
| Standard Reserved Instance | Up to 72% | Specific AZ and instance | 1 or 3 years |
| Convertible Reserved Instance | Up to 54% | Can modify attributes | 1 or 3 years |

### Recommendations

```bash
#!/bin/bash
# Analyze purchase recommendations

echo "=== Reserved Instance / Savings Plan Analysis ==="
echo ""
echo "EC2 Usage Pattern:"
kubectl top nodes --no-headers | awk '{print $2, $3}' | column -t

echo ""
echo "Recommendation:"
echo "  - Cover 60% of baseline compute with Compute Savings Plan (3yr)"
echo "  - Cover 30% with Spot Instances (for variable workloads)"
echo "  - Keep 10% on-demand for overflow"
echo ""
echo "Estimated Annual Savings:"
echo "  - On-demand only: ~$27,168/year"
echo "  - With 3yr Savings Plan (60%): ~$16,300/year (40% savings)"
echo "  - With Spot (30%): ~$21,734 (20% additional savings)"
```

### Purchase Schedule

| Month | Action | Environment | Amount |
|-------|--------|-------------|--------|
| Jan 2026 | 3yr Compute Savings Plan | Prod + Staging | $2,500/month |
| Apr 2026 | Evaluate usage, adjust coverage | All | - |
| Jul 2026 | Purchase additional if needed | Prod | $500/month |
| Oct 2026 | Review for Q1 renewal | All | - |

---

## Spot Instance Usage

### Spot NodePool Configuration

```yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: spot-workloads
spec:
  template:
    spec:
      nodeClassRef:
        name: default
      requirements:
      - key: "karpenter.sh/capacity-type"
        operator: In
        values: ["spot"]
      - key: "karpenter.k8s.aws/instance-category"
        operator: In
        values: ["c", "m", "r"]
      - key: "karpenter.k8s.aws/instance-generation"
        operator: Gt
        values: ["4"]
  disruption:
    consolidationPolicy: WhenUnderutilized
    budgets:
    - nodes: 10%
  limits:
    cpu: 500
  # Spot interruption handling
  disruption:
    consolidationPolicy: WhenEmpty
    consolidateAfter: 5m
```

### Spot Eligibility by Workload

| Workload | Spot Eligible | Reason |
|----------|--------------|--------|
| AIOps Engine | Yes (with interruption handling) | Stateless, retry-capable |
| Analytics Workers | Yes | Batch jobs, can restart |
| Staging Environments | Yes | Non-critical |
| ArgoCD | No | Stateful, critical |
| Database | No | Stateful, critical |
| Monitoring Stack | No | Must be always available |
| Production APIs | Partial (with pod disruption budgets) | Requires minAvailable |

### Spot Savings Calculation

```bash
echo "=== Spot Savings Analysis ==="
echo ""
echo "On-Demand Cost (m5.xlarge): $0.192/hr"
echo "Spot Cost (m5.xlarge): ~$0.0576/hr (70% discount)"
echo ""
echo "With 10 spot instances running 24/7:"
echo "  On-demand: 10 × $0.192 × 730 = $1,401.60/month"
echo "  Spot: 10 × $0.0576 × 730 = $420.48/month"
echo "  Savings: $981.12/month (70%)"
echo ""
echo "With spot interruptions (~5% of instances per week):"
echo "  Additional cost of re-provisioning: ~$50/month"
echo "  Net savings: ~$931/month"
```

---

## Monitoring with AWS Cost Explorer

### Cost Explorer Queries

```bash
# Daily cost for last 7 days
aws ce get-cost-and-usage \
  --time-period Start=$(date -d "-7 days" +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity DAILY \
  --metrics "UnblendedCost" \
  --group-by Type=DIMENSION,Key=SERVICE

# Cost by environment tag
aws ce get-cost-and-usage \
  --time-period Start=$(date -d "-30 days" +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics "UnblendedCost" \
  --group-by Type=TAG,Key=Environment \
  --filter '{"Tags":{"Key":"Environment","Values":["dev","staging","prod"]}}'

# Cost by team tag
aws ce get-cost-and-usage \
  --time-period Start=$(date -d "-30 days" +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics "UnblendedCost" \
  --group-by Type=TAG,Key=Team

# Forecast for next month
aws ce get-cost-forecast \
  --time-period Start=$(date -d "-30 days" +%Y-%m-%d),End=$(date -d "+30 days" +%Y-%m-%d) \
  --granularity MONTHLY \
  --metric "UNBLENDED_COST"
```

### Cost Anomaly Detection

```python
# aiops/cost_analyzer.py
import boto3
import json
from datetime import datetime, timedelta

ce = boto3.client('ce')

def detect_cost_anomalies():
    """Detect cost anomalies compared to the previous period"""
    today = datetime.utcnow()
    
    current = ce.get_cost_and_usage(
        TimePeriod={
            'Start': (today - timedelta(hours=24)).strftime('%Y-%m-%d'),
            'End': today.strftime('%Y-%m-%d')
        },
        Granularity='DAILY',
        Metrics=['UnblendedCost'],
        GroupBy=[{'Type': 'DIMENSION', 'Key': 'SERVICE'}]
    )
    
    previous = ce.get_cost_and_usage(
        TimePeriod={
            'Start': (today - timedelta(days=2)).strftime('%Y-%m-%d'),
            'End': (today - timedelta(days=1)).strftime('%Y-%m-%d')
        },
        Granularity='DAILY',
        Metrics=['UnblendedCost'],
        GroupBy=[{'Type': 'DIMENSION', 'Key': 'SERVICE'}]
    )
    
    anomalies = []
    for curr_group in current['ResultsByTime'][0]['Groups']:
        curr_cost = float(curr_group['Metrics']['UnblendedCost']['Amount'])
        service = curr_group['Keys'][0]
        
        # Find corresponding previous cost
        prev_cost = 0
        for prev_group in previous['ResultsByTime'][0]['Groups']:
            if prev_group['Keys'][0] == service:
                prev_cost = float(prev_group['Metrics']['UnblendedCost']['Amount'])
                break
        
        if prev_cost > 0 and curr_cost > prev_cost * 1.5 and curr_cost - prev_cost > 10:
            anomalies.append({
                'service': service,
                'current_cost': curr_cost,
                'previous_cost': prev_cost,
                'increase_pct': ((curr_cost - prev_cost) / prev_cost) * 100
            })
    
    return anomalies
```

### Grafana Cost Dashboard

```json
{
  "dashboard": {
    "title": "Platform Cost Overview",
    "panels": [
      {
        "title": "Daily Cost by Environment",
        "type": "graph",
        "targets": [{
          "expr": "aws_ce_cost_by_environment{environment=\"prod\"}",
          "legendFormat": "Prod"
        }]
      },
      {
        "title": "Cost by Service",
        "type": "piechart",
        "targets": [{
          "expr": "aws_ce_cost_by_service"
        }]
      },
      {
        "title": "Cost Anomaly Score",
        "type": "singlestat",
        "targets": [{
          "expr": "aws_ce_anomaly_score"
        }]
      }
    ]
  }
}
```

---

## Budget Alerts

### Budget Configuration

```bash
#!/bin/bash
# configure-budgets.sh

ENVIRONMENT=$1
MONTHLY_LIMIT=$2

aws budgets create-budget \
  --account-id 123456789012 \
  --budget "{
    \"BudgetName\": \"platform-${ENVIRONMENT}-monthly\",
    \"BudgetType\": \"COST\",
    \"BudgetLimit\": {\"Amount\": \"${MONTHLY_LIMIT}\", \"Unit\": \"USD\"},
    \"TimePeriod\": {\"Start\": \"$(date +%Y-%m-01)T00:00:00Z\"},
    \"TimeUnit\": \"MONTHLY\",
    \"CostFilters\": {\"TagKeyValue\": [\"Environment\\$${ENVIRONMENT}\"]}
  }" \
  --notifications-with-subscribers '[
    {
      "Notification": {
        "NotificationType": "ACTUAL",
        "ComparisonOperator": "GREATER_THAN",
        "Threshold": 75,
        "ThresholdType": "PERCENTAGE"
      },
      "Subscribers": [
        {"SubscriptionType": "EMAIL", "Address": "platform-ops@example.com"},
        {"SubscriptionType": "SNS", "Address": "arn:aws:sns:us-west-2:123456789012:platform-ops-topic"}
      ]
    },
    {
      "Notification": {
        "NotificationType": "ACTUAL",
        "ComparisonOperator": "GREATER_THAN",
        "Threshold": 90,
        "ThresholdType": "PERCENTAGE"
      },
      "Subscribers": [
        {"SubscriptionType": "EMAIL", "Address": "platform-ops@example.com"},
        {"SubscriptionType": "EMAIL", "Address": "engineering-manager@example.com"}
      ]
    },
    {
      "Notification": {
        "NotificationType": "FORECASTED",
        "ComparisonOperator": "GREATER_THAN",
        "Threshold": 100,
        "ThresholdType": "PERCENTAGE"
      },
      "Subscribers": [
        {"SubscriptionType": "EMAIL", "Address": "engineering-manager@example.com"},
        {"SubscriptionType": "EMAIL", "Address": "vp-engineering@example.com"}
      ]
    }
  ]'
```

### Environment Budgets

| Environment | Monthly Budget | Alert Thresholds | Currency |
|-------------|---------------|-----------------|----------|
| Development | $500 | 75% ($375), 90% ($450) | USD |
| Staging | $1,500 | 75% ($1,125), 90% ($1,350) | USD |
| Production | $5,000 | 75% ($3,750), 90% ($4,500) | USD |
| Total Platform | $7,000 | 80% ($5,600), 95% ($6,650) | USD |

---

## Monthly Cost Review Process

### Review Checklist

```
Week 1 - Data Collection
□ [ ] Export last month's cost data from AWS Cost Explorer
□ [ ] Tag all untagged resources
□ [ ] Review and update cost allocation tags
□ [ ] Generate cost report by environment, service, and team

Week 2 - Analysis
□ [ ] Compare actual vs budgeted spend
□ [ ] Identify top cost drivers (top 5 services)
□ [ ] Calculate savings recommendations
□ [ ] Review reserved instance / savings plan coverage
□ [ ] Check for orphaned or unused resources
□ [ ] Analyze spot instance utilization

Week 3 - Optimization
□ [ ] Implement identified cost savings
□ [ ] Rightsize over-provisioned resources
□ [ ] Clean up stale resources
□ [ ] Update lifecycle policies
□ [ ] Adjust budgets if needed

Week 4 - Reporting
□ [ ] Generate monthly cost report
□ [ ] Present findings to engineering leadership
□ [ ] Update cost optimization backlog
□ [ ] Publish cost dashboard updates
```

### Monthly Cost Report Template

```markdown
# Monthly Cost Report - {Month} {Year}

## Executive Summary
- **Total Spend**: $X,XXX (XX% of budget)
- **Month-over-Month Change**: +X% / -X%
- **Year-over-Year Change**: +X% / -X%
- **Budget Status**: On track / Over budget by $X

## Cost by Environment
| Environment | Spend | Budget | % Used | Change (MoM) |
|-------------|-------|--------|--------|-------------|
| Production | $X,XXX | $X,XXX | XX% | +/- X% |
| Staging | $X,XXX | $X,XXX | XX% | +/- X% |
| Development | $X,XXX | $X,XXX | XX% | +/- X% |

## Top 5 Services by Cost
1. **EC2** - $X,XXX (XX%) - +/- X% MoM
2. **RDS** - $X,XXX (XX%) - +/- X% MoM
3. **EKS** - $X,XXX (XX%) - +/- X% MoM
4. **Data Transfer** - $X,XXX (XX%) - +/- X% MoM
5. **S3** - $X,XXX (XX%) - +/- X% MoM

## Savings Achieved This Month
- Spot instances: $XXX saved (XX% of potential)
- Reserved instances: $XXX saved (XX% coverage)
- Rightsizing: $XXX saved
- Cleanup actions: $XXX saved

## Recommended Actions
1. [ ] Purchase additional reserved instances for {service}
2. [ ] Rightsize {instance-type} instances
3. [ ] Clean up {resource-type} older than {days}
4. [ ] Review {service} usage for optimization

## Anomalies Detected
- {service}: XX% cost increase due to {reason}
- Action taken: {action}
```

### Cost Optimization Automation

```bash
#!/bin/bash
# auto-optimize.sh - Weekly cost optimization automation

echo "=== Weekly Cost Optimization ==="
echo "Date: $(date)"

# 1. Find and stop idle resources
echo "1. Checking for idle resources..."
# Find unattached EBS volumes
aws ec2 describe-volumes \
  --filters Name=status,Values=available \
  --query "Volumes[*].[VolumeId,Size,CreateTime]" \
  --output table

# Find untagged resources
aws resourcegroupstaggingapi get-resources \
  --query "ResourceTagMappingList[?!not_null(Tags[?Key=='Environment'].Value)]" \
  --output table

# 2. Clean up old snapshots
echo "2. Cleaning up old snapshots..."
aws ec2 describe-snapshots \
  --owner-ids self \
  --query "Snapshots[?StartTime<'$(date -d "-90 days" +%Y-%m-%d)'].[SnapshotId]" \
  --output text | while read snapshot; do
  aws ec2 delete-snapshot --snapshot-id "$snapshot"
done

# 3. Remove old AMIs
echo "3. Removing old AMIs..."

# 4. Check for unused load balancers
echo "4. Checking for unused load balancers..."

# 5. Generate savings report
echo "5. Generating savings report..."
echo ""
echo "=== Optimization Complete ==="
```

---

## Next Steps

1. [Review security overview](../security/01-security-overview.md)
2. [Review disaster recovery plan](03-disaster-recovery.md)
3. [Review common troubleshooting guides](../troubleshooting/01-common-issues.md)
