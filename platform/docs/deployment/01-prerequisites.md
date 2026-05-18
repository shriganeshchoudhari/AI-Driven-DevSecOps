# Deployment Prerequisites

This document details every prerequisite required to deploy the AI-Driven Secure GitOps Kubernetes Platform across any environment.

---

## Table of Contents

- [AWS Account Setup](#aws-account-setup)
- [Local Tools Installation](#local-tools-installation)
- [GitHub Repository Setup](#github-repository-setup)
- [OIDC Provider Configuration](#oidc-provider-configuration)
- [Domain Name and DNS](#domain-name-and-dns)
- [SSL Certificate (ACM)](#ssl-certificate-acm)
- [Container Registry (ECR)](#container-registry-ecr)
- [IAM Roles and Policies](#iam-roles-and-policies)
- [Service Limits to Check](#service-limits-to-check)
- [Cost Estimation Guide](#cost-estimation-guide)
- [Network Requirements](#network-requirements)
- [Compliance Prerequisites](#compliance-prerequisites)

---

## AWS Account Setup

### 1. Create or Identify Your AWS Account

```bash
# Verify AWS account access
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

### 2. Required IAM Permissions

The deploying user or role requires the following permissions:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:*",
                "eks:*",
                "iam:*",
                "s3:*",
                "dynamodb:*",
                "ecr:*",
                "kms:*",
                "acm:*",
                "route53:*",
                "elasticloadbalancing:*",
                "cloudwatch:*",
                "logs:*",
                "secretsmanager:*",
                "ssm:*",
                "karpenter:*",
                "rds:*",
                "elasticache:*",
                "wafv2:*",
                "shield:*"
            ],
            "Resource": "*"
        }
    ]
}
```

**Important**: This is broad for initial bootstrap. Post-deployment, restrict to least privilege.

### 3. AWS Organizations (Multi-account Setup)

Recommended account structure:

| Account | Purpose | Environment |
|---------|---------|-------------|
| Management | Organizations, billing | N/A |
| Security | Audit, GuardDuty, Security Hub | N/A |
| Shared Services | Git runners, artifact storage | N/A |
| Development | Dev workloads | Dev |
| Staging | Pre-production validation | Staging |
| Production | Production workloads | Prod |

### 4. Service Quotas to Verify

Navigate to AWS Service Quotas console and verify the following limits are sufficient:

| Service | Quota | Required Minimum |
|---------|-------|-----------------|
| EC2 | vCPU Limit | 100 (on-demand) |
| EKS | Clusters per Region | 5 |
| EKS | Node groups per cluster | 10 |
| VPC | VPCs per Region | 10 |
| VPC | Subnets per VPC | 100 |
| VPC | Security Groups per VPC | 100 |
| IAM | Roles per account | 300 |
| IAM | Policies per role | 10 |
| ACM | Certificates per Region | 25 |
| Route53 | Hosted zones | 50 |
| ELB | Load balancers | 50 |
| RDS | DB instances | 20 (per engine) |
| ElastiCache | Nodes | 20 |
| WAF | Web ACLs | 10 |

Request limit increases via the AWS Support Center console at least 48 hours before deployment.

---

## Local Tools Installation

### aws-cli v2

```bash
# Linux (x86)
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# macOS
brew install awscli

# Windows
# Download installer from https://awscli.amazonaws.com/AWSCLIV2.msi

# Verify
aws --version
# Expected: aws-cli/2.15.0 Python/3.11.x ...
```

Configure credentials:

```bash
aws configure
# AWS Access Key ID: [AKIA...]
# AWS Secret Access Key: [wJalrX...]
# Default region: us-west-2
# Default output format: json
```

For OIDC-based access (recommended):

```bash
aws configure set region us-west-2
aws configure set output json
# Use `aws sts assume-role-with-web-identity` for OIDC flows
```

### kubectl

```bash
# Linux
curl -LO "https://dl.k8s.io/release/v1.29.0/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# macOS
brew install kubectl

# Windows
curl.exe -LO "https://dl.k8s.io/release/v1.29.0/bin/windows/amd64/kubectl.exe"

# Verify
kubectl version --client
# Expected: Client Version: v1.29.0
```

### Terraform

```bash
# Linux
wget https://releases.hashicorp.com/terraform/1.7.0/terraform_1.7.0_linux_amd64.zip
unzip terraform_1.7.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# macOS
brew install terraform

# Windows
# Download from https://releases.hashicorp.com/terraform/1.7.0/

# Verify
terraform --version
# Expected: Terraform v1.7.0
```

### Helm

```bash
# Linux
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# macOS
brew install helm

# Windows
choco install kubernetes-helm

# Verify
helm version
# Expected: version.BuildInfo{Version:"v3.14.0"}
```

### ArgoCD CLI

```bash
# Linux
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/download/v2.10.0/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64

# macOS
brew install argocd

# Windows
choco install argocd-cli

# Verify
argocd version --client
# Expected: argocd: v2.10.0
```

### Docker

```bash
# macOS
brew install --cask docker

# Linux (Ubuntu/Debian)
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Windows
# Download from https://desktop.docker.com/win/stable/Docker%20Desktop%20Installer.exe

# Verify
docker --version
# Expected: Docker version 24.0.7
```

### Cosign

```bash
# Linux
curl -O -L "https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64"
sudo mv cosign-linux-amd64 /usr/local/bin/cosign
sudo chmod +x /usr/local/bin/cosign

# macOS
brew install cosign

# Verify
cosign version
# Expected:  GitVersion: v2.2.3
```

### Trivy

```bash
# Linux
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh

# macOS
brew install trivy

# Windows
choco install trivy

# Verify
trivy --version
# Expected: Version: 0.50.0
```

### Additional Tools

```bash
# yq - YAML processor
# macOS
brew install yq
# Linux
wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq
chmod +x /usr/local/bin/yq

# jq - JSON processor
# macOS
brew install jq
# Linux
sudo apt-get install jq

# Velero - Backup and restore
# macOS
brew install velero
# Linux
curl -LO https://github.com/vmware-tanzu/velero/releases/download/v1.13.0/velero-v1.13.0-linux-amd64.tar.gz
tar -xzf velero-v1.13.0-linux-amd64.tar.gz
sudo mv velero-v1.13.0-linux-amd64/velero /usr/local/bin/

# k9s - Kubernetes CLI dashboard (optional)
brew install k9s

# stern - Multi-pod log tailing (optional)
brew install stern

# krew - kubectl plugin manager (optional)
brew install krew

# Verify all tools
for tool in aws kubectl terraform helm argocd docker cosign trivy yq jq velero; do
    echo "=== $tool ==="
    command -v "$tool" && echo "✓ Installed" || echo "✗ MISSING"
done
```

---

## GitHub Repository Setup

### 1. Create Repositories

```bash
# Infrastructure repository (monorepo)
gh repo create org/aiops-platform --private --description "AI-Driven Secure GitOps Kubernetes Platform"

# Application repositories (examples)
gh repo create org/service-auth --private
gh repo create org/service-orders --private
gh repo create org/service-payments --private
```

### 2. Configure GitHub Environments

Create environments for deployment tracking:

```bash
# For each environment: dev, staging, prod
gh api repos/org/aiops-platform/environments/dev -X PUT
gh api repos/org/aiops-platform/environments/staging -X PUT
gh api repos/org/aiops-platform/environments/prod -X PUT
```

### 3. Configure Branch Protection

```bash
# Protect main and release branches
gh api repos/org/aiops-platform/branches/main/protection -X PUT \
  -H "Accept: application/vnd.github.v3+json" \
  --input - << 'EOF'
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "lint",
      "test",
      "security-scan",
      "terraform-plan",
      "build"
    ]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 2,
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true
  },
  "restrictions": null
}
EOF
```

### 4. Create Repository Secrets

```bash
gh secret set AWS_ACCOUNT_ID --body "123456789012"
gh secret set AWS_REGION --body "us-west-2"

# For OIDC
gh secret set ROLE_TO_ASSUME --body "arn:aws:iam::123456789012:role/github-actions-role"

# For each environment
gh secret set --env dev AWS_ROLE_ARN --body "arn:aws:iam::123456789012:role/platform-dev-deploy"
gh secret set --env staging AWS_ROLE_ARN --body "arn:aws:iam::123456789012:role/platform-staging-deploy"
gh secret set --env prod AWS_ROLE_ARN --body "arn:aws:iam::123456789012:role/platform-prod-deploy"
```

---

## OIDC Provider Configuration

### 1. Create GitHub OIDC Provider in AWS

```bash
# Create OIDC provider for GitHub Actions
OIDC_URL="https://token.actions.githubusercontent.com"
THUMBPRINT=$(echo | openssl s_client -servername token.actions.githubusercontent.com \
  -connect token.actions.githubusercontent.com:443 2>/dev/null | \
  openssl x509 -fingerprint -noout -sha1 | cut -d= -f2 | tr -d ':')

aws iam create-open-id-connect-provider \
  --url "$OIDC_URL" \
  --client-id-list "sts.amazonaws.com" \
  --thumbprint-list "$THUMBPRINT"

# Verify
aws iam list-open-id-connect-providers
```

Expected output:
```json
{
    "OpenIDConnectProviderList": [
        {
            "Arn": "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
        }
    ]
}
```

### 2. Create IAM Role for GitHub Actions

```bash
cat > github-actions-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:org/aiops-platform:*"
        }
      }
    }
  ]
}
EOF

aws iam create-role \
  --role-name github-actions-role \
  --assume-role-policy-document file://github-actions-trust-policy.json \
  --description "Role assumed by GitHub Actions for org/aiops-platform"

# Attach required policies
aws iam attach-role-policy \
  --role-name github-actions-role \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

**Note**: Restrict to specific policies for production. AdministratorAccess is for initial bootstrap only.

### 3. Environment-Specific Roles

```bash
# Create roles per environment with scoped permissions
for env in dev staging prod; do
  aws iam create-role \
    --role-name "platform-${env}-deploy" \
    --assume-role-policy-document file://github-actions-trust-policy.json \
    --description "Deployment role for ${env} environment"

  # Attach scoped policy
  aws iam put-role-policy \
    --role-name "platform-${env}-deploy" \
    --policy-name "deploy-policy" \
    --policy-document file://"deploy-policy-${env}.json"
done
```

---

## Domain Name and DNS

### 1. Register or Configure Domain

```bash
# Check if domain is available
aws route53domains check-domain-availability --domain-name platform.example.com

# If you have an existing domain in Route53
aws route53 list-hosted-zones --query "HostedZones[?Name=='example.com.']"
```

### 2. Create Route53 Hosted Zone

```bash
# Create hosted zone
aws route53 create-hosted-zone \
  --name "platform.example.com" \
  --caller-reference "$(date +%s)"

# Record the nameservers
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='platform.example.com.'].Id" --output text)
aws route53 get-hosted-zone --id "$HOSTED_ZONE_ID" \
  --query "DelegationSet.NameServers"
```

### 3. Subdomain Structure

| Subdomain | Purpose | Record Type |
|-----------|---------|-------------|
| `*.platform.example.com` | Wildcard for all services | A (Alias to ALB) |
| `argocd.platform.example.com` | ArgoCD UI | CNAME |
| `grafana.platform.example.com` | Grafana UI | CNAME |
| `api.platform.example.com` | API gateway | A (Alias to NLB) |
| `aiops.platform.example.com` | AIOps engine | A (Alias to NLB) |

Update your domain registrar's nameservers to point to the Route53 hosted zone nameservers.

---

## SSL Certificate (ACM)

### 1. Request Certificate

```bash
# Request wildcard certificate
aws acm request-certificate \
  --domain-name "*.platform.example.com" \
  --subject-alternative-names "platform.example.com" \
  --validation-method DNS \
  --region us-west-2

# Record certificate ARN
CERT_ARN=$(aws acm list-certificates \
  --query "CertificateSummaryList[?DomainName=='*.platform.example.com'].CertificateArn" \
  --output text)
echo "Certificate ARN: $CERT_ARN"
```

### 2. DNS Validation

```bash
# Get DNS validation records
aws acm describe-certificate \
  --certificate-arn "$CERT_ARN" \
  --query "Certificate.DomainValidationOptions[].ResourceRecord"

# Add CNAME records to Route53
# Validation records will look like:
# _xxxxx.platform.example.com. CNAME _yyyyy.acm-validations.aws.
```

### 3. Verify Certificate Status

```bash
aws acm describe-certificate \
  --certificate-arn "$CERT_ARN" \
  --query "Certificate.Status"
# Expected: "ISSUED"
```

---

## Container Registry (ECR)

### 1. Create ECR Repositories

```bash
# Create repositories for platform images
REPOS=(
  "aiops-engine"
  "aiops-analyzer"
  "platform-controller"
  "sidecar-injector"
)

for repo in "${REPOS[@]}"; do
  aws ecr create-repository \
    --repository-name "platform/${repo}" \
    --image-tag-mutability IMMUTABLE \
    --image-scanning-configuration scanOnPush=true \
    --encryption-configuration encryptionType=AES256

  # Enable tag immutability
  aws ecr put-image-tag-mutability \
    --repository-name "platform/${repo}" \
    --image-tag-mutability IMMUTABLE

  # Set lifecycle policy (keep last 50 images)
  cat > "lifecycle-policy-${repo}.json" << EOF
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Keep last 50 images",
      "selection": {
        "tagStatus": "any",
        "countType": "imageCountMoreThan",
        "countNumber": 50
      },
      "action": {
        "type": "expire"
      }
    }
  ]
}
EOF

  aws ecr put-lifecycle-policy \
    --repository-name "platform/${repo}" \
    --lifecycle-policy-text file://"lifecycle-policy-${repo}.json"
done
```

### 2. Authenticate Docker to ECR

```bash
aws ecr get-login-password --region us-west-2 | \
  docker login --username AWS --password-stdin \
  123456789012.dkr.ecr.us-west-2.amazonaws.com
```

### 3. Cross-Account Access (if using multi-account)

```bash
# Grant pull access from other accounts
cat > ecr-cross-account-policy.json << 'EOF'
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Sid": "CrossAccountPull",
      "Effect": "Allow",
      "Principal": {
        "AWS": [
          "arn:aws:iam::STAGING_ACCOUNT_ID:root",
          "arn:aws:iam::PROD_ACCOUNT_ID:root"
        ]
      },
      "Action": [
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer"
      ]
    }
  ]
}
EOF

aws ecr set-repository-policy \
  --repository-name "platform/aiops-engine" \
  --policy-text file://ecr-cross-account-policy.json
```

---

## IAM Roles and Policies

### 1. EKS Cluster Role

```bash
aws iam create-role \
  --role-name platform-eks-cluster-role \
  --assume-role-policy-document file://trust-policies/eks-assume-role.json

aws iam attach-role-policy \
  --role-name platform-eks-cluster-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
```

### 2. Node Instance Role

```bash
aws iam create-role \
  --role-name platform-eks-node-role \
  --assume-role-policy-document file://trust-policies/ec2-assume-role.json

# Attach required policies
aws iam attach-role-policy \
  --role-name platform-eks-node-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy

aws iam attach-role-policy \
  --role-name platform-eks-node-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy

aws iam attach-role-policy \
  --role-name platform-eks-node-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly

aws iam attach-role-policy \
  --role-name platform-eks-node-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
```

### 3. IRSA Roles (Service-Specific)

| Service | IAM Role | Permissions |
|---------|----------|-------------|
| cert-manager | cert-manager-irsa | route53:ChangeResourceRecordSets |
| External Secrets | external-secrets-irsa | secretsmanager:GetSecretValue |
| Karpenter | karpenter-irsa | ec2:*, eks:*, iam:PassRole |
| Velero | velero-irsa | s3:*, ec2:CreateSnapshot |
| Cluster Autoscaler | autoscaler-irsa | ec2:*, eks:DescribeCluster |
| ALB Ingress Controller | alb-ingress-irsa | elasticloadbalancing:*, ec2:* |
| ExternalDNS | external-dns-irsa | route53:ChangeResourceRecordSets |

Example policy for External Secrets:

```bash
cat > external-secrets-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
        "secretsmanager:ListSecrets"
      ],
      "Resource": [
        "arn:aws:secretsmanager:us-west-2:123456789012:secret:platform/*",
        "arn:aws:secretsmanager:us-west-2:123456789012:secret:platform/*-??????"
      ]
    }
  ]
}
EOF

aws iam create-policy \
  --policy-name external-secrets-access \
  --policy-document file://external-secrets-policy.json
```

---

## Service Limits to Check

### EC2 Limits

| Instance Type | Required Count | Current Limit | Action Needed |
|--------------|---------------|---------------|---------------|
| t3.medium | 3 (dev) | | |
| m5.xlarge | 5 (staging) | | |
| m5.2xlarge | 10 (prod) | | |
| c5.xlarge | 3 (prod - AI) | | |
| r5.large | 2 (prod - DB) | | |

### EKS Limits

| Resource | Limit | Required |
|----------|-------|----------|
| Clusters per region | 5 | 3 (dev/staging/prod) |
| Node groups per cluster | 10 | 3 |
| Fargate profiles | 10 | 0 (EC2 only) |

### VPC Limits

| Resource | Limit | Required |
|----------|-------|----------|
| VPCs per region | 5 | 3 (per env) |
| Subnets per VPC | 200 | 6 (3 public, 3 private) |
| Security Groups per VPC | 2500 | ~50 |
| NAT Gateways | 5 | 3 |

### How to Check Limits

```bash
# Check current limits
aws service-quotas get-service-quota \
  --service-code ec2 \
  --quota-code L-74FC7D96  # Running On-Demand Standard instances

# Request limit increase
aws service-quotas request-service-quota-increase \
  --service-code ec2 \
  --quota-code L-74FC7D96 \
  --desired-value 500
```

---

## Cost Estimation Guide

### Monthly Cost Breakdown (Production)

| Service | Configuration | Estimated Monthly Cost |
|---------|--------------|----------------------|
| **EKS Cluster** | 1 cluster, no Fargate | $73.00 |
| **EC2 (Workload)** | 3 x m5.2xlarge (8 vCPU, 32 GB) | $693.00 |
| **EC2 (System)** | 3 x t3.medium (2 vCPU, 4 GB) | $123.00 |
| **EC2 (AIOps)** | 2 x c5.xlarge (4 vCPU, 8 GB) | $306.00 |
| **Karpenter (Spot)** | 5 x m5.large (variable) | $250.00 |
| **RDS (PostgreSQL)** | 1 x db.r6g.large (2 vCPU, 16 GB) | $260.00 |
| **ElastiCache (Redis)** | 1 x cache.r6g.large (2 vCPU, 13 GB) | $186.00 |
| **ALB** | 2 x Application Load Balancer | $45.00 |
| **NAT Gateway** | 3 x NAT Gateway (HA) | $97.00 |
| **S3** | 100 GB storage + requests | $5.00 |
| **ECR** | 10 GB storage + data transfer | $3.00 |
| **CloudWatch** | Metrics + logs (50 GB ingest) | $120.00 |
| **Secrets Manager** | 20 secrets | $8.00 |
| **KMS** | 5 keys | $5.00 |
| **Data Transfer** | 1 TB egress | $90.00 |
| **Total** | | **$2,264.00** |

### Development Environment

| Service | Monthly Cost |
|---------|-------------|
| EKS + EC2 (t3.medium x 2) | $150.00 |
| RDS (db.t4g.small) | $45.00 |
| Others | $80.00 |
| **Total** | **$275.00** |

### Cost Optimization Recommendations

1. **Use Spot Instances** for non-critical workloads (save 60-70%)
2. **Enable Karpenter consolidation** for continuous right-sizing
3. **Use S3 Intelligent-Tiering** for log storage
4. **Set CloudWatch log retention** to 30 days (non-prod) / 90 days (prod)
5. **Reserved Instances** for predictable workloads (1-year: save 40%, 3-year: save 60%)
6. **Delete unused load balancers and EBS volumes**
7. **Use Graviton instances** where possible (save 10-20%)
8. **Implement HPA/VPA** to scale based on actual load

---

## Network Requirements

### Firewall Rules

| Source | Destination | Port | Protocol | Purpose |
|--------|-------------|------|----------|---------|
| Internet | ALB | 443 | TCP | HTTPS ingress |
| ALB | Private subnets | 8443 | TCP | App traffic |
| Nodes | Nodes | 10250 | TCP | kubelet |
| Nodes | API Server | 443 | TCP | Kubernetes API |
| Nodes | Internet | 443 | TCP | ECR, S3, etc. |
| Nodes | Internet | 80 | TCP | HTTP (redirect) |
| Peered VPC | EKS API | 443 | TCP | Cross-VPC access |
| VPN | Private subnets | 443 | TCP | Admin access |

### VPC CIDR Planning

| Environment | VPC CIDR | Public Subnets | Private Subnets |
|-------------|----------|----------------|-----------------|
| Dev | 10.0.0.0/16 | 10.0.1.0/24, 10.0.2.0/24, 10.0.3.0/24 | 10.0.10.0/24, 10.0.11.0/24, 10.0.12.0/24 |
| Staging | 10.1.0.0/16 | 10.1.1.0/24, 10.1.2.0/24, 10.1.3.0/24 | 10.1.10.0/24, 10.1.11.0/24, 10.1.12.0/24 |
| Prod | 10.2.0.0/16 | 10.2.1.0/24, 10.2.2.0/24, 10.2.3.0/24 | 10.2.10.0/24, 10.2.11.0/24, 10.2.12.0/24 |

Ensure these CIDRs do not overlap with existing on-premises or peered VPC CIDRs.

---

## Compliance Prerequisites

### SOC 2

- Enable AWS CloudTrail in all regions
- Enable AWS Config with recording of all resources
- Enable GuardDuty for threat detection
- Configure S3 access logs
- Enable CloudTrail Insights for unusual activity

### PCI-DSS (if handling card data)

- Enable VPC Flow Logs
- Encrypt all data at rest with KMS
- Enable WAF with OWASP rules
- Implement network segmentation
- Configure encryption in transit (TLS 1.2+)
- Enable audit logging for all access

### CIS Benchmarks

- Enable CIS Benchmark scanning via Security Hub
- Apply CIS-compliant EKS AMIs
- Configure Pod Security Standards
- Enable Kubernetes audit logging

### Prerequisites Checklist

```
[ ] AWS account created with billing enabled
[ ] IAM user/role with admin access for bootstrap
[ ] Service limit increases requested
[ ] Tools installed and verified
[ ] GitHub repository created
[ ] OIDC provider configured
[ ] Domain registered and Route53 hosted zone created
[ ] ACM certificate issued
[ ] ECR repositories created
[ ] IAM roles created
[ ] VPC CIDR plan verified (no overlaps)
[ ] Budget alerts configured
[ ] CloudTrail enabled
[ ] AWS Config enabled
[ ] Security Hub enabled
[ ] GuardDuty enabled
```

---

## Next Steps

After completing all prerequisites, proceed to [Bootstrap Sequence](02-bootstrap-sequence.md) for the step-by-step deployment guide.
