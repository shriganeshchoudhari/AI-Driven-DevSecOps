# AWS Deployment Guide

Full production deployment guide for deploying the AI-Driven Secure GitOps Platform on AWS.

---

## Table of Contents

- [Environment Strategy](#environment-strategy)
- [Workspace Management](#workspace-management)
- [VPC Design](#vpc-design)
- [EKS Cluster Sizing](#eks-cluster-sizing)
- [Node Group Configuration](#node-group-configuration)
- [Karpenter Setup](#karpenter-setup)
- [RDS Database Setup](#rds-database-setup)
- [ElastiCache Redis Setup](#elasticache-redis-setup)
- [Load Balancer Configuration](#load-balancer-configuration)
- [Route53 DNS Setup](#route53-dns-setup)
- [WAF Configuration](#waf-configuration)
- [CloudWatch Integration](#cloudwatch-integration)
- [Cost Management](#cost-management)
- [Multi-Region Considerations](#multi-region-considerations)

---

## Environment Strategy

### Environment Hierarchy

```
┌──────────────────────────────────────────────┐
│               Production                      │
│   us-west-2 (primary) / us-east-1 (DR)       │
│   Minimally 5 nines availability             │
├──────────────────────────────────────────────┤
│               Staging                         │
│   us-west-2                                   │
│   Pre-production validation                   │
├──────────────────────────────────────────────┤
│               Development                     │
│   us-west-2                                   │
│   Feature testing, chaos engineering          │
└──────────────────────────────────────────────┘
```

### Environment Configuration Matrix

| Attribute | Dev | Staging | Prod |
|-----------|-----|---------|------|
| AWS Account | Dev Account | Staging Account | Prod Account |
| Region | us-west-2 | us-west-2 | us-west-2 |
| EKS Version | 1.29 | 1.29 | 1.29 |
| Node Type | t3.medium | m5.xlarge | m5.2xlarge |
| Min Nodes | 2 | 3 | 5 |
| Max Nodes | 5 | 10 | 30 |
| RDS Instance | db.t4g.small | db.r6g.large | db.r6g.xlarge |
| RDS Multi-AZ | false | true | true |
| Redis | cache.t4g.small | cache.r6g.large | cache.r6g.xlarge |
| Backup Retention | 7 days | 14 days | 35 days |
| Deploy Strategy | Direct push | PR + approval | PR + 2 approvals + manual gate |

---

## Workspace Management

### Terraform Workspace Strategy

```bash
# List available workspaces
cd terraform/environments
ls -la */

# Create workspaces
for env in dev staging prod; do
  terraform -chdir="$env" init
  terraform -chdir="$env" workspace new "$env" || true
done

# Switch workspace
terraform workspace select dev

# List current workspace
terraform workspace show
```

### Configuration per Environment

```bash
# dev/terraform.tfvars
environment = "dev"
cluster_version = "1.29"
vpc_cidr = "10.0.0.0/16"
node_instance_types = ["t3.medium"]
node_min_size = 2
node_max_size = 5
node_desired_size = 2
rds_instance_class = "db.t4g.small"
rds_multi_az = false
redis_node_type = "cache.t4g.small"
backup_retention_days = 7

# staging/terraform.tfvars
environment = "staging"
cluster_version = "1.29"
vpc_cidr = "10.1.0.0/16"
node_instance_types = ["m5.xlarge"]
node_min_size = 3
node_max_size = 10
node_desired_size = 3
rds_instance_class = "db.r6g.large"
rds_multi_az = true
redis_node_type = "cache.r6g.large"
backup_retention_days = 14

# prod/terraform.tfvars
environment = "prod"
cluster_version = "1.29"
vpc_cidr = "10.2.0.0/16"
node_instance_types = ["m5.2xlarge", "c5.2xlarge"]
node_min_size = 5
node_max_size = 30
node_desired_size = 5
rds_instance_class = "db.r6g.xlarge"
rds_multi_az = true
redis_node_type = "cache.r6g.xlarge"
backup_retention_days = 35
```

---

## VPC Design

### VPC Architecture

```
┌───────────────────────────────────────────────────────┐
│                   VPC (10.x.0.0/16)                   │
│                                                       │
│  ┌───────────────────┐  ┌───────────────────┐        │
│  │  Public Subnets   │  │  Private Subnets  │        │
│  │  (AZ a, b, c)     │  │  (AZ a, b, c)     │        │
│  │                   │  │                    │        │
│  │  NAT Gateway      │  │  EKS Nodes        │        │
│  │  Bastion Host     │  │  RDS              │        │
│  │  ALB              │  │  ElastiCache      │        │
│  │                   │  │  Pods/Services    │        │
│  └───────────────────┘  └───────────────────┘        │
│                                                       │
│  ┌─────────────────────────────────────────┐         │
│  │  VPC Endpoints (Gateway)                │         │
│  │  - S3                                   │         │
│  │  - DynamoDB                             │         │
│  └─────────────────────────────────────────┘         │
│                                                       │
│  ┌─────────────────────────────────────────┐         │
│  │  VPC Endpoints (Interface)              │         │
│  │  - ECR (Docker, API)                    │         │
│  │  - EKS API                              │         │
│  │  - CloudWatch (Logs, Metrics)           │         │
│  │  - Secrets Manager                      │         │
│  │  - STS                                  │         │
│  │  - SQS                                  │         │
│  └─────────────────────────────────────────┘         │
└───────────────────────────────────────────────────────┘
```

### Terraform VPC Module

```hcl
module "vpc" {
  source = "../modules/vpc"

  environment = var.environment
  vpc_cidr    = var.vpc_cidr

  public_subnet_cidrs = [
    cidrsubnet(var.vpc_cidr, 4, 0),   # 10.x.0.0/20
    cidrsubnet(var.vpc_cidr, 4, 1),   # 10.x.16.0/20
    cidrsubnet(var.vpc_cidr, 4, 2),   # 10.x.32.0/20
  ]

  private_subnet_cidrs = [
    cidrsubnet(var.vpc_cidr, 4, 4),   # 10.x.64.0/20
    cidrsubnet(var.vpc_cidr, 4, 5),   # 10.x.80.0/20
    cidrsubnet(var.vpc_cidr, 4, 6),   # 10.x.96.0/20
  ]

  enable_nat_gateway     = var.environment != "dev" ? true : false
  single_nat_gateway     = var.environment == "dev" ? true : false
  enable_vpn_gateway     = false
  enable_flow_logs       = true
  flow_logs_retention    = var.environment == "prod" ? 90 : 30
}
```

### VPC Peering Considerations

```bash
# Peer with shared services VPC
aws ec2 create-vpc-peering-connection \
  --vpc-id vpc-xxxxx \
  --peer-vpc-id vpc-yyyyy \
  --peer-region us-west-2

# Accept peering connection (on peer side)
aws ec2 accept-vpc-peering-connection \
  --vpc-peering-connection-id pcx-xxxxx

# Add routes
aws ec2 create-route \
  --route-table-id rtb-xxxxx \
  --destination-cidr-block 10.100.0.0/16 \
  --vpc-peering-connection-id pcx-xxxxx

# Update security groups to allow cross-VPC traffic
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxx \
  --protocol tcp \
  --port 443 \
  --cidr 10.100.0.0/16
```

### VPC Endpoints

```hcl
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = module.vpc.vpc_id
  service_name = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = module.vpc.private_route_table_ids
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id       = module.vpc.vpc_id
  service_name = "com.amazonaws.${var.region}.ecr.api"
  vpc_endpoint_type = "Interface"
  subnet_ids   = module.vpc.private_subnet_ids
  security_group_ids = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
}
```

---

## EKS Cluster Sizing

### Cluster Configuration

```hcl
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.0"

  cluster_name    = "platform-${var.environment}"
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  cluster_endpoint_public_access  = var.environment == "production" ? false : true
  cluster_endpoint_private_access = true

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
      configuration_values = jsonencode({
        env = {
          ENABLE_POD_ENI = "true"
          WARM_ENI_TARGET = "1"
        }
      })
    }
  }

  cluster_encryption_config = {
    provider_key_arn = module.kms.key_arn
    resources       = ["secrets"]
  }
}
```

### Cluster Sizing Guidelines

| Environment | Node Count | vCPU Total | Memory Total | Estimated Pod Capacity |
|-------------|-----------|------------|--------------|----------------------|
| Dev | 2-5 | 8-20 | 32-80 GB | 40-100 |
| Staging | 3-10 | 24-80 | 96-320 GB | 120-400 |
| Prod | 5-30 | 80-480 | 320-1920 GB | 400-2400 |

### Access Entry Configuration

```hcl
resource "aws_eks_access_entry" "admin" {
  cluster_name  = module.eks.cluster_name
  principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/platform-admin"
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin" {
  cluster_name  = module.eks.cluster_name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = aws_eks_access_entry.admin.principal_arn
  access_scope {
    type = "cluster"
  }
}
```

---

## Node Group Configuration

### Managed Node Groups

```hcl
# System node group (system workloads)
resource "aws_eks_node_group" "system" {
  cluster_name    = module.eks.cluster_name
  node_group_name = "platform-${var.environment}-system"
  node_role_arn   = module.iam.node_role_arn
  subnet_ids      = module.vpc.private_subnet_ids

  instance_types = var.environment == "production" ? ["t3.medium"] : ["t3.small"]

  scaling_config {
    desired_size = var.environment == "production" ? 3 : 1
    max_size     = var.environment == "production" ? 6 : 3
    min_size     = var.environment == "production" ? 3 : 1
  }

  labels = {
    "node.kubernetes.io/role" = "system"
  }

  taint {
    key    = "node.kubernetes.io/role"
    value  = "system"
    effect = "NO_SCHEDULE"
  }

  tags = {
    "karpenter.sh/discovery" = module.eks.cluster_name
  }
}

# Application node group (general workloads)
resource "aws_eks_node_group" "application" {
  cluster_name    = module.eks.cluster_name
  node_group_name = "platform-${var.environment}-application"
  node_role_arn   = module.iam.node_role_arn
  subnet_ids      = module.vpc.private_subnet_ids

  instance_types = var.node_instance_types

  scaling_config {
    desired_size = var.node_desired_size
    max_size     = var.node_max_size
    min_size     = var.node_min_size
  }

  labels = {
    "node.kubernetes.io/role" = "application"
  }

  tags = {
    "karpenter.sh/discovery" = module.eks.cluster_name
  }
}
```

### Node Group Types per Environment

| Environment | System Nodes | App Nodes | Spot Nodes | GPU Nodes |
|-------------|-------------|-----------|------------|-----------|
| Dev | 1 x t3.small | 2 x t3.medium | 0 | 0 |
| Staging | 2 x t3.medium | 3 x m5.xlarge | 2 x m5.xlarge | 0 |
| Prod | 3 x t3.medium | 5 x m5.2xlarge | 10 x m5.2xlarge | 2 x g5.xlarge |

---

## Karpenter Setup

### Karpenter IAM

```hcl
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "20.0"

  cluster_name = module.eks.cluster_name

  irsa_name               = "karpenter"
  irsa_use_name_prefix    = false
  namespace               = "karpenter"
  service_account         = "karpenter"

  tags = {
    Environment = var.environment
  }
}
```

### EC2NodeClass

```yaml
apiVersion: karpenter.k8s.aws/v1beta1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiFamily: AL2
  role: "platform-${var.environment}-karpenter-node-role"
  subnetSelectorTerms:
  - tags:
      karpenter.sh/discovery: "platform-${var.environment}"
  securityGroupSelectorTerms:
  - tags:
      karpenter.sh/discovery: "platform-${var.environment}"
  blockDeviceMappings:
  - deviceName: /dev/xvda
    ebs:
      volumeSize: 100Gi
      volumeType: gp3
      iops: 3000
      throughput: 125
  metadataOptions:
    httpTokens: required
    httpEndpoint: enabled
    httpPutResponseHopLimit: 2
  tags:
    Environment: "${var.environment}"
    ManagedBy: karpenter
```

### NodePool Configuration

```yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      nodeClassRef:
        name: default
      requirements:
      - key: "karpenter.k8s.aws/instance-category"
        operator: In
        values: ["c", "m", "r"]
      - key: "karpenter.k8s.aws/instance-cpu"
        operator: In
        values: ["2", "4", "8", "16"]
      - key: "karpenter.k8s.aws/instance-hypervisor"
        operator: In
        values: ["nitro"]
      - key: "kubernetes.io/arch"
        operator: In
        values: ["amd64"]
      - key: "karpenter.sh/capacity-type"
        operator: In
        values: ["on-demand", "spot"]
      expireAfter: 720h
  limits:
    cpu: 1000
  disruption:
    consolidationPolicy: WhenUnderutilized
    expireAfter: 720h
```

### Spot NodePool

```yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: spot
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
      - key: "karpenter.k8s.aws/instance-cpu"
        operator: In
        values: ["4", "8", "16", "32"]
  disruption:
    consolidationPolicy: WhenUnderutilized
    expireAfter: 720h
  limits:
    cpu: 500
```

---

## RDS Database Setup

### PostgreSQL Configuration

```hcl
module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "6.0"

  identifier = "platform-${var.environment}"

  engine               = "postgres"
  engine_version       = "16.3"
  family               = "postgres16"
  major_engine_version = "16"
  instance_class       = var.rds_instance_class

  allocated_storage     = var.environment == "production" ? 200 : 50
  max_allocated_storage = 500
  storage_encrypted     = true
  storage_type          = "gp3"
  iops                  = 3000

  db_name  = "platform"
  username = "platform_admin"
  password = random_password.rds_master.result
  port     = 5432

  multi_az               = var.rds_multi_az
  subnet_ids             = module.vpc.database_subnet_ids
  vpc_security_group_ids = [aws_security_group.rds.id]

  maintenance_window      = "sun:03:00-sun:04:00"
  backup_window           = "02:00-03:00"
  backup_retention_period = var.backup_retention_days
  delete_automated_backups = false

  skip_final_snapshot     = var.environment == "production" ? false : true
  final_snapshot_identifier = "platform-${var.environment}-final-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  parameters = [
    {
      name  = "shared_preload_libraries"
      value = "pg_stat_statements,pgaudit"
    },
    {
      name  = "rds.force_ssl"
      value = "1"
    },
    {
      name  = "log_min_duration_statement"
      value = "1000"
    }
  ]

  tags = {
    Environment = var.environment
  }
}
```

### Connection via External Secrets

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: platform-database
  namespace: aiops
spec:
  refreshInterval: "1h"
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: platform-database
    creationPolicy: Owner
  data:
  - secretKey: host
    remoteRef:
      key: platform/${ENVIRONMENT}/database
      property: host
  - secretKey: port
    remoteRef:
      key: platform/${ENVIRONMENT}/database
      property: port
  - secretKey: username
    remoteRef:
      key: platform/${ENVIRONMENT}/database
      property: username
  - secretKey: password
    remoteRef:
      key: platform/${ENVIRONMENT}/database
      property: password
  - secretKey: database
    remoteRef:
      key: platform/${ENVIRONMENT}/database
      property: database
  - secretKey: connection_string
    remoteRef:
      key: platform/${ENVIRONMENT}/database
      property: connection_string
```

---

## ElastiCache Redis Setup

### Redis Configuration

```hcl
resource "aws_elasticache_subnet_group" "redis" {
  name       = "platform-${var.environment}-redis"
  subnet_ids = module.vpc.database_subnet_ids
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "platform-${var.environment}-redis"
  description         = "Redis for platform ${var.environment}"

  node_type           = var.redis_node_type
  port               = 6379
  num_cache_clusters = var.environment == "production" ? 3 : 1

  parameter_group_name = "default.redis7"
  engine_version       = "7.1"

  subnet_group_name          = aws_elasticache_subnet_group.redis.name
  security_group_ids        = [aws_security_group.redis.id]
  automatic_failover_enabled = var.environment == "production" ? true : false
  multi_az_enabled          = var.environment == "production" ? true : false

  at_rest_encryption_enabled  = true
  transit_encryption_enabled  = true
  auth_token                  = random_password.redis_auth.result

  maintenance_window = "sun:05:00-sun:06:00"

  tags = {
    Environment = var.environment
  }
}
```

---

## Load Balancer Configuration

### ALB for HTTP Applications

```yaml
apiVersion: v1
kind: Service
metadata:
  name: platform-ingress
  namespace: ingress-nginx
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "external"
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
    service.beta.kubernetes.io/aws-load-balancer-attributes: "load_balancing.cross_zone.enabled=true"
    service.beta.kubernetes.io/aws-load-balancer-ssl-cert: "arn:aws:acm:us-west-2:123456789012:certificate/xxx"
    service.beta.kubernetes.io/aws-load-balancer-ssl-ports: "443"
    service.beta.kubernetes.io/aws-load-balancer-ssl-negotiation-policy: "ELBSecurityPolicy-TLS13-1-2-2021-06"
spec:
  type: LoadBalancer
  ports:
  - port: 443
    targetPort: 443
    protocol: TCP
  - port: 80
    targetPort: 80
    protocol: TCP
  selector:
    app.kubernetes.io/name: ingress-nginx
```

### NLB for Internal Services

```yaml
apiVersion: v1
kind: Service
metadata:
  name: platform-nlb
  namespace: ingress-nginx
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb-ip"
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internal"
    service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
spec:
  type: LoadBalancer
  ports:
  - port: 443
    targetPort: 443
  selector:
    app.kubernetes.io/name: ingress-nginx
```

### SSL/TLS Configuration

```bash
# Request certificate (if not done already)
aws acm request-certificate \
  --domain-name "*.platform.example.com" \
  --validation-method DNS \
  --region us-west-2 \
  --options "CertificateTransparencyLoggingPreference=ENABLED"

# Get certificate ARN
CERT_ARN=$(aws acm list-certificates \
  --query "CertificateSummaryList[?contains(DomainName, 'platform.example.com')].CertificateArn" \
  --output text)

# Update ingress with certificate
kubectl annotate ingress platform-ingress \
  service.beta.kubernetes.io/aws-load-balancer-ssl-cert="$CERT_ARN"
```

---

## Route53 DNS Setup

### DNS Records

```bash
#!/bin/bash

HOSTED_ZONE_ID="ZXXXXXXXXXXXX"
ALB_DNS=$(kubectl get svc -n ingress-nginx platform-ingress \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Create ALIAS record for wildcard
cat > wildcard-record.json << EOF
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "*.platform.example.com",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "Z35SXDOTRQ7X7K",
          "DNSName": "${ALB_DNS}",
          "EvaluateTargetHealth": true
        }
      }
    }
  ]
}
EOF

aws route53 change-resource-record-sets \
  --hosted-zone-id "$HOSTED_ZONE_ID" \
  --change-batch file://wildcard-record.json
```

### ExternalDNS Integration

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: external-dns
  namespace: external-dns
spec:
  chart:
    spec:
      chart: external-dns
      sourceRef:
        kind: HelmRepository
        name: external-dns
        namespace: external-dns
  values:
    provider: aws
    aws:
      zoneType: public
    txtOwnerId: platform-${ENVIRONMENT}
    domainFilters:
    - platform.example.com
    policy: sync
    serviceAccount:
      annotations:
        eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/external-dns
```

---

## WAF Configuration

### Web ACL Rules

```hcl
resource "aws_wafv2_web_acl" "platform" {
  name        = "platform-${var.environment}"
  description = "WAF for platform ${var.environment}"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # AWS Managed Rules
  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 1
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
        excluded_rule {
          name = "SizeRestrictions_BODY"
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name               = "AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled  = true
    }
  }

  rule {
    name     = "AWS-AWSManagedRulesSQLiRuleSet"
    priority = 2
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name               = "AWSManagedRulesSQLiRuleSet"
      sampled_requests_enabled  = true
    }
  }

  rule {
    name     = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
    priority = 3
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name               = "AWSManagedRulesKnownBadInputsRuleSet"
      sampled_requests_enabled  = true
    }
  }

  # Rate limiting
  rule {
    name     = "RateLimit"
    priority = 4
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name               = "RateLimit"
      sampled_requests_enabled  = true
    }
  }

  # IP reputation
  rule {
    name     = "AWS-AWSManagedRulesAnonymousIpList"
    priority = 5
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAnonymousIpList"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name               = "AWSManagedRulesAnonymousIpList"
      sampled_requests_enabled  = true
    }
  }

  # IP allowlist for admin access
  dynamic "rule" {
    for_each = var.admin_ips != null ? [1] : []
    content {
      name     = "AdminIPWhitelist"
      priority = 6
      action {
        allow {}
      }
      statement {
        ip_set_reference_statement {
          arn = aws_wafv2_ip_set.admin_ips[0].arn
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name               = "AdminIPWhitelist"
        sampled_requests_enabled  = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name               = "platform-waf"
    sampled_requests_enabled  = true
  }
}
```

### Associate WAF with ALB

```hcl
resource "aws_wafv2_web_acl_association" "platform" {
  resource_arn = module.alb.arn
  web_acl_arn  = aws_wafv2_web_acl.platform.arn
}
```

---

## CloudWatch Integration

### Container Insights

```bash
# Enable Container Insights
aws eks update-cluster-config \
  --name platform-prod \
  --logging '{"clusterLogging":[{"types":["api","audit","authenticator","controllerManager","scheduler"],"enabled":true}]}'

# Install CloudWatch agent for Container Insights
helm repo add aws-observability https://aws-observability.github.io/helm-charts
helm upgrade --install aws-cloudwatch-metrics aws-observability/aws-cloudwatch-metrics \
  --namespace amazon-cloudwatch \
  --create-namespace \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=arn:aws:iam::123456789012:role/cloudwatch-metrics
```

### CloudWatch Alarms

```hcl
resource "aws_cloudwatch_metric_alarm" "eks_cpu_high" {
  alarm_name          = "platform-${var.environment}-eks-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name        = "node_cpu_utilization"
  namespace         = "ContainerInsights"
  period            = "300"
  statistic         = "Average"
  threshold         = "80"
  alarm_description = "This metric monitors EKS cluster CPU utilization"
  alarm_actions     = [aws_sns_topic.platform_alarms.arn]

  dimensions = {
    ClusterName = "platform-${var.environment}"
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  alarm_name          = "platform-${var.environment}-rds-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name        = "DatabaseConnections"
  namespace         = "AWS/RDS"
  period            = "300"
  statistic         = "Average"
  threshold         = "100"
  alarm_description = "High database connection count"
  alarm_actions     = [aws_sns_topic.platform_alarms.arn]

  dimensions = {
    DBInstanceIdentifier = module.rds.db_instance_id
  }
}
```

### Log Retention Policies

```hcl
resource "aws_cloudwatch_log_group" "platform" {
  name              = "/aws/eks/platform-${var.environment}/cluster"
  retention_in_days = var.environment == "production" ? 90 : 30

  tags = {
    Environment = var.environment
  }
}
```

### Log Insights Queries

Saved CloudWatch Logs Insights queries for common scenarios:

```sql
# Kubernetes Audit - RBAC failures
fields @timestamp, @message
| filter @logStream like /audit/
| filter @message like /Forbidden|Unauthorized/
| sort @timestamp desc
| limit 50

# API server errors
fields @timestamp, @message
| filter @logStream like /api/
| filter @message like /"level":"error"/
| sort @timestamp desc
| limit 50

# Pod lifecycle events
fields @timestamp, @message
| filter @message like /Pod.*Failed|Pod.*Killing/
| sort @timestamp desc
| limit 50
```

---

## Cost Management

### Budget Alerts

```bash
# Create budget for dev environment
aws budgets create-budget \
  --account-id 123456789012 \
  --budget '{
    "BudgetName": "platform-dev-monthly",
    "BudgetType": "COST",
    "BudgetLimit": {"Amount": "500", "Unit": "USD"},
    "TimePeriod": {"Start": "2026-01-01T00:00:00Z"},
    "TimeUnit": "MONTHLY"
  }' \
  --notifications-with-subscribers '[
    {
      "Notification": {
        "NotificationType": "ACTUAL",
        "ComparisonOperator": "GREATER_THAN",
        "Threshold": 80
      },
      "Subscribers": [{
        "SubscriptionType": "EMAIL",
        "Address": "platform-ops@example.com"
      }]
    }
  ]'

# Production budget
aws budgets create-budget \
  --account-id 123456789012 \
  --budget '{
    "BudgetName": "platform-prod-monthly",
    "BudgetType": "COST",
    "BudgetLimit": {"Amount": "5000", "Unit": "USD"},
    "TimeUnit": "MONTHLY"
  }' \
  --notifications-with-subscribers '[
    {
      "Notification": {
        "NotificationType": "ACTUAL",
        "ComparisonOperator": "GREATER_THAN",
        "Threshold": 75
      },
      "Subscribers": [{
        "SubscriptionType": "EMAIL",
        "Address": "platform-ops@example.com"
      }]
    },
    {
      "Notification": {
        "NotificationType": "ACTUAL",
        "ComparisonOperator": "GREATER_THAN",
        "Threshold": 90
      },
      "Subscribers": [
        {"SubscriptionType": "EMAIL", "Address": "platform-ops@example.com"},
        {"SubscriptionType": "EMAIL", "Address": "engineering-manager@example.com"}
      ]
    }
  ]'
```

### Cost Allocation Tags

```bash
# Activate cost allocation tags
aws ce update-cost-allocation-tags-status \
  --tags-status '[
    {"TagKey": "Environment", "Status": "Active"},
    {"TagKey": "Team", "Status": "Active"},
    {"TagKey": "Project", "Status": "Active"}
  ]'
```

### Tagging Strategy

```hcl
locals {
  common_tags = {
    Project     = "aiops-platform"
    Environment = var.environment
    ManagedBy   = "terraform"
    CreatedBy   = "platform-engineering"
    CostCenter  = "platform-${var.environment}"
    Team        = "platform-engineering"
  }
}
```

---

## Multi-Region Considerations

### Primary/DR Region Strategy

| Region | Purpose | Services |
|--------|---------|----------|
| us-west-2 | Primary | All workloads |
| us-east-1 | DR | Passive (read replicas) |

### Cross-Region Setup

```hcl
# RDS cross-region read replica
resource "aws_db_instance" "primary" {
  provider = aws.primary
  # ... primary instance config
}

resource "aws_db_instance" "replica" {
  provider = aws.dr
  identifier = "platform-dr"
  replicate_source_db = aws_db_instance.primary.arn

  instance_class = "db.r6g.large"
  skip_final_snapshot = true
  backup_retention_period = 7
}

# ECR cross-region replication
resource "aws_ecr_replication_configuration" "platform" {
  replication_configuration {
    rule {
      destination {
        region      = "us-east-1"
        registry_id = data.aws_caller_identity.current.account_id
      }
      repository_filter {
        filter      = "platform/*"
        filter_type = "PREFIX_MATCH"
      }
    }
  }
}
```

### DR Automation

```bash
#!/bin/bash
# DR failover script
ENVIRONMENT=$1
DR_REGION="us-east-1"

echo "[DR] Initiating failover to ${DR_REGION}..."

# 1. Promote RDS read replica
echo "[DR] Promoting RDS read replica..."
aws rds promote-read-replica \
  --db-instance-identifier platform-dr \
  --region ${DR_REGION}

# 2. Update DNS
echo "[DR] Updating Route53 DNS..."
aws route53 change-resource-record-sets \
  --hosted-zone-id ZXXXXXXXX \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "api.platform.example.com",
        "Type": "CNAME",
        "TTL": 60,
        "ResourceRecords": [{"Value": "dr-lb-${DR_REGION}.elb.amazonaws.com"}]
      }
    }]
  }'

# 3. Deploy infrastructure in DR region
echo "[DR] Deploying EKS cluster in DR region..."
cd terraform/environments/${ENVIRONMENT}
terraform workspace select dr
terraform apply -auto-approve

# 4. Restore Velero backup
echo "[DR] Restoring from Velero backup..."
velero restore create --from-backup latest-dr-backup --wait

echo "[DR] Failover complete. Validate services at https://api.platform.example.com/health"
```

---

## Next Steps

1. [Configure secrets management](05-secrets-bootstrap.md)
2. [Run deployment validation](06-validation-smoke-tests.md)
3. [Review rollback procedures](07-rollback-procedures.md)
