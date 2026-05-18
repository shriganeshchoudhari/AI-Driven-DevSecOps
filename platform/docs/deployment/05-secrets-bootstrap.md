# Secrets Bootstrap

Comprehensive guide for managing secrets across the platform using AWS Secrets Manager, External Secrets Operator, Sealed Secrets, and SOPS.

---

## Table of Contents

- [Secrets Architecture](#secrets-architecture)
- [AWS Secrets Manager Setup](#aws-secrets-manager-setup)
- [External Secrets Configuration](#external-secrets-configuration)
- [Sealed Secrets for GitOps](#sealed-secrets-for-gitops)
- [SOPS Encryption Workflow](#sops-encryption-workflow)
- [Key Rotation Procedures](#key-rotation-procedures)
- [Emergency Access Procedures](#emergency-access-procedures)
- [Audit Logging](#audit-logging)

---

## Secrets Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Secret Management Layers                      │
│                                                                     │
│  Layer 1: AWS Secrets Manager (Source of Truth)                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  /platform/dev/database           - RDS credentials          │   │
│  │  /platform/dev/redis              - Redis auth token         │   │
│  │  /platform/dev/oidc               - OIDC client secrets      │   │
│  │  /platform/dev/aiops/api-keys     - LLM API keys             │   │
│  │  /platform/dev/github/token       - GitHub personal access   │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                  │                                  │
│  Layer 2: External Secrets Operator                                 │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  ClusterSecretStore → SecretStore → ExternalSecret → Secret │   │
│  │  Syncs from AWS Secrets Manager to Kubernetes Secrets       │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                  │                                  │
│  Layer 3: Sealed Secrets (GitOps Safe)                              │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  SealedSecret (encrypted with cluster public key)           │   │
│  │  → Stored in Git → Decrypted by Sealed Secrets controller   │   │
│  │  → Safe for GitOps repositories                             │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                  │                                  │
│  Layer 4: SOPS (Client-side Encryption)                             │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  SOPS + Age/AWS KMS → Encrypted YAML in Git                │   │
│  │  Pre-commit encryption, post-decode validation              │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## AWS Secrets Manager Setup

### Secret Structure

All platform secrets follow a hierarchical naming convention:

```
/platform/{environment}/{category}/{secret-name}
```

| Secret Path | Content | Used By |
|-------------|---------|---------|
| `/platform/dev/database` | RDS host, port, user, password, database | AIOps, microservices |
| `/platform/dev/redis` | Redis host, port, auth_token | AIOps, caching |
| `/platform/dev/oidc` | OIDC client_id, client_secret, issuer_url | Authentication |
| `/platform/dev/aiops/api-keys` | OpenAI, Anthropic, other LLM keys | AIOps Engine |
| `/platform/dev/github/token` | GitHub PAT for ArgoCD repo access | ArgoCD |
| `/platform/dev/alertmanager/slack` | Slack webhook URL | Alertmanager |
| `/platform/dev/velero/aws` | AWS credentials for Velero backups | Velero |
| `/platform/dev/tls/certificates` | TLS certificates (fallback) | cert-manager |

### Creating Secrets

```bash
# Database secret
aws secretsmanager create-secret \
  --name "/platform/dev/database" \
  --description "Platform PostgreSQL credentials" \
  --secret-string '{
    "host": "platform-dev-db.xxxxx.us-west-2.rds.amazonaws.com",
    "port": "5432",
    "username": "platform_admin",
    "password": "auto-generated-secure-password",
    "database": "platform",
    "connection_string": "postgresql://platform_admin:password@host:5432/platform"
  }'

# Redis secret
aws secretsmanager create-secret \
  --name "/platform/dev/redis" \
  --description "Platform Redis credentials" \
  --secret-string '{
    "host": "platform-dev-redis.xxxxx.ng.0001.usw2.cache.amazonaws.com",
    "port": "6379",
    "auth_token": "auto-generated-auth-token"
  }'

# OIDC secret
aws secretsmanager create-secret \
  --name "/platform/dev/oidc" \
  --description "OIDC provider configuration" \
  --secret-string '{
    "client_id": "platform-client",
    "client_secret": "auto-generated-client-secret",
    "issuer_url": "https://accounts.platform.example.com",
    "redirect_uris": ["https://argocd.platform.example.com/auth/callback"]
  }'

# AIOps API keys
aws secretsmanager create-secret \
  --name "/platform/dev/aiops/api-keys" \
  --description "LLM provider API keys" \
  --secret-string '{
    "openai_api_key": "sk-xxxxxxxxxxxxxxxx",
    "anthropic_api_key": "sk-ant-xxxxxxxxxxxx",
    "azure_openai_key": "xxxxxxxxxxxx",
    "azure_openai_endpoint": "https://xxxxx.openai.azure.com"
  }'

# Verify
aws secretsmanager list-secrets --filter Key="name",Values="/platform/dev"
```

### Automated Secret Generation with Terraform

```hcl
resource "random_password" "database" {
  length  = 32
  special = false
}

resource "random_password" "redis" {
  length = 24
}

resource "random_password" "oidc" {
  length = 48
}

resource "aws_secretsmanager_secret" "database" {
  name        = "/platform/${var.environment}/database"
  description = "Platform PostgreSQL credentials"
  kms_key_id  = module.kms.secrets_key_id
}

resource "aws_secretsmanager_secret_version" "database" {
  secret_id = aws_secretsmanager_secret.database.id
  secret_string = jsonencode({
    host              = module.rds.db_instance_address
    port              = "5432"
    username          = module.rds.db_instance_username
    password          = random_password.database.result
    database          = module.rds.db_instance_name
    connection_string = "postgresql://${module.rds.db_instance_username}:${random_password.database.result}@${module.rds.db_instance_address}:5432/${module.rds.db_instance_name}"
  })
}
```

### Bulk Secret Creation

```bash
#!/bin/bash
# create-secrets.sh
ENVIRONMENT=$1
REGION=${2:-us-west-2}

generate_password() {
  openssl rand -base64 32 | tr -d '/+=' | cut -c1-32
}

secrets=(
  "database:{\"username\":\"platform_admin\",\"password\":\"$(generate_password)\",\"host\":\"TBD\",\"port\":\"5432\",\"database\":\"platform\"}"
  "redis:{\"auth_token\":\"$(generate_password)\"}"
  "oidc:{\"client_id\":\"platform-${ENVIRONMENT}\",\"client_secret\":\"$(generate_password 48)\"}"
  "aiops/api-keys:{\"openai_api_key\":\"placeholder\",\"anthropic_api_key\":\"placeholder\"}"
  "alertmanager/slack:{\"webhook_url\":\"https://hooks.slack.com/services/TBD\"}"
)

for secret in "${secrets[@]}"; do
  name="${secret%%:*}"
  value="${secret#*:}"
  
  aws secretsmanager create-secret \
    --name "/platform/${ENVIRONMENT}/${name}" \
    --secret-string "${value}" \
    --region "${REGION}" \
    --kms-key-id "alias/platform-${ENVIRONMENT}-secrets"
  
  echo "Created secret: /platform/${ENVIRONMENT}/${name}"
done
```

---

## External Secrets Configuration

### ClusterSecretStore (AWS)

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-west-2
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets
```

### SecretStore (Namespaced)

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: platform-secrets
  namespace: aiops
spec:
  storeRef:
    clusterSecretStore:
      name: aws-secrets-manager
```

### ExternalSecret Examples

```yaml
# Database secret
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
    deletionPolicy: Retain
  data:
  - secretKey: host
    remoteRef:
      key: /platform/${ENVIRONMENT}/database
      property: host
  - secretKey: port
    remoteRef:
      key: /platform/${ENVIRONMENT}/database
      property: port
  - secretKey: username
    remoteRef:
      key: /platform/${ENVIRONMENT}/database
      property: username
  - secretKey: password
    remoteRef:
      key: /platform/${ENVIRONMENT}/database
      property: password
  - secretKey: database
    remoteRef:
      key: /platform/${ENVIRONMENT}/database
      property: database
  - secretKey: connection_string
    remoteRef:
      key: /platform/${ENVIRONMENT}/database
      property: connection_string
---
# AIOps API keys
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: aiops-api-keys
  namespace: aiops
spec:
  refreshInterval: "1h"
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: aiops-api-keys
    creationPolicy: Owner
  data:
  - secretKey: openai_api_key
    remoteRef:
      key: /platform/${ENVIRONMENT}/aiops/api-keys
      property: openai_api_key
  - secretKey: anthropic_api_key
    remoteRef:
      key: /platform/${ENVIRONMENT}/aiops/api-keys
      property: anthropic_api_key
  - secretKey: azure_openai_key
    remoteRef:
      key: /platform/${ENVIRONMENT}/aiops/api-keys
      property: azure_openai_key
  - secretKey: azure_openai_endpoint
    remoteRef:
      key: /platform/${ENVIRONMENT}/aiops/api-keys
      property: azure_openai_endpoint
---
# Pull all keys from a secret
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: platform-all-secrets
  namespace: default
spec:
  refreshInterval: "1h"
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: platform-config
    creationPolicy: Owner
  dataFrom:
  - extract:
      key: /platform/${ENVIRONMENT}/database
  - extract:
      key: /platform/${ENVIRONMENT}/redis
```

### Verify External Secrets

```bash
# Check ExternalSecret status
kubectl get externalsecrets -A
kubectl describe externalsecret platform-database -n aiops

# Verify created Kubernetes secret
kubectl get secret platform-database -n aiops -o json | jq '.data | map_values(@base64d)'

# Force refresh
kubectl annotate externalsecret platform-database -n aiops \
  force-sync=$(date +%s) --overwrite
```

---

## Sealed Secrets for GitOps

### Install Sealed Secrets

```bash
# Install with Helm
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm upgrade --install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace sealed-secrets \
  --create-namespace \
  --set-string podLabels."sealedsecrets\.bitnami\.com/sealed-secrets-key"=active \
  --wait

# Verify
kubectl get pods -n sealed-secrets
kubectl get crd | grep sealedsecrets
```

### Extract Public Key

```bash
# Retrieve public key for client-side encryption
kubeseed --fetch-cert > platform-sealed-secrets-public-key.pem

# Or get it via API
kubectl port-forward -n sealed-secrets svc/sealed-secrets-controller 8080:8080 &
curl -s http://localhost:8080/v1/cert.pem > public-key.pem
kill %1
```

### Create Sealed Secrets

```bash
# Option 1: From stdin
echo -n "my-super-secret-password" | kubectl create secret generic \
  my-secret --dry-run=client --from-file=password=/dev/stdin -o yaml | \
  kubeseal --format yaml > my-sealed-secret.yaml

# Option 2: From literal values
kubectl create secret generic platform-database \
  --dry-run=client \
  --from-literal=host=database.example.com \
  --from-literal=username=admin \
  --from-literal=password=s3cr3t \
  -o yaml | \
  kubeseal \
    --controller-name=sealed-secrets \
    --controller-namespace=sealed-secrets \
    --format yaml \
  > platform-database-sealed.yaml

# Option 3: Using sealed-secrets-operator naming
kubeseal < my-secret.yaml > my-sealed-secret.yaml
```

### Sealed Secret Example

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: github-token
  namespace: argocd
  annotations:
    sealedsecrets.bitnami.com/cluster-wide: "true"
spec:
  encryptedData:
    token: AgBy3i4OJSWK+PiTySYZZA9rO43cGDEq.....
  template:
    metadata:
      name: github-token
      namespace: argocd
    type: Opaque
```

### Apply Sealed Secrets

```bash
# Apply the sealed secret (safe to commit to Git)
kubectl apply -f platform-database-sealed.yaml

# Verify decrypted secret was created
kubectl get secret platform-database -o json | jq '.data | map_values(@base64d)'
```

### Rotating Sealed Secrets Key

```bash
# Delete existing key to trigger regeneration
kubectl delete secret -n sealed-secrets -l sealedsecrets.bitnami.com/sealed-secrets-key

# OR rotate with key renewal
kubectl annotate -n sealed-secrets secrets \
  -l sealedsecrets.bitnami.com/sealed-secrets-key \
  sealedsecrets.bitnami.com/rotate-keys=true

# Re-encrypt all sealed secrets with new key
for f in secrets/**/sealed-*.yaml; do
  kubeseal --re-encrypt < "$f" > "${f}.tmp"
  mv "${f}.tmp" "$f"
done
```

---

## SOPS Encryption Workflow

### Install SOPS

```bash
# Linux
wget https://github.com/getsops/sops/releases/download/v3.9.0/sops-v3.9.0.linux.amd64 -O /usr/local/bin/sops
chmod +x /usr/local/bin/sops

# macOS
brew install sops

# Verify
sops --version
```

### SOPS Configuration

```yaml
# .sops.yaml
creation_rules:
  # Dev environment
  - path_regex: secrets/dev/.*\.yaml
    kms: "arn:aws:kms:us-west-2:123456789012:key/platform-dev-sops-key"
    aws_profile: platform-dev
  # Staging environment
  - path_regex: secrets/staging/.*\.yaml
    kms: "arn:aws:kms:us-west-2:123456789012:key/platform-staging-sops-key"
    aws_profile: platform-staging
  # Production environment
  - path_regex: secrets/prod/.*\.yaml
    kms: "arn:aws:kms:us-west-2:123456789012:key/platform-prod-sops-key"
    aws_profile: platform-prod
  # Unencrypted secrets (never committed)
  - path_regex: secrets/unencrypted/.*\.yaml
    unencrypted_suffix: "_unencrypted"
```

### KMS Key for SOPS

```hcl
resource "aws_kms_key" "sops" {
  description             = "KMS key for SOPS encryption - ${var.environment}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow GitHub Actions to decrypt"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/github-actions-role"
        }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "sops" {
  name          = "alias/platform-${var.environment}-sops-key"
  target_key_id = aws_kms_key.sops.key_id
}
```

### Encrypting with SOPS

```bash
# Encrypt a file
sops --encrypt secrets/unencrypted/database.yaml > secrets/prod/database.yaml

# Encrypt in-place
sops --encrypt --in-place secrets/prod/database.yaml

# Encrypt specific values only
sops --encrypt \
  --encrypted-regex '^(password|api_key|secret|token|private_key)$' \
  secrets/prod/values.yaml

# View decrypted content
sops decrypt secrets/prod/database.yaml

# Edit encrypted file (opens editor)
sops secrets/prod/database.yaml
```

### Example SOPS-Encrypted File

```yaml
# secrets/prod/database.yaml
apiVersion: v1
kind: Secret
metadata:
  name: platform-database
  namespace: aiops
type: Opaque
stringData:
  host: ENC[AES256_GCM,data:abcdef...,iv:xxx...,tag:yyy...]
  port: ENC[AES256_GCM,data:5432...,iv:xxx...,tag:yyy...]
  username: ENC[AES256_GCM,data:admin...,iv:xxx...,tag:yyy...]
  password: ENC[AES256_GCM,data:secret...,iv:xxx...,tag:yyy...]
  database: ENC[AES256_GCM,data:platform...,iv:xxx...,tag:yyy...]
sops:
  kms:
  - arn: arn:aws:kms:us-west-2:123456789012:key/xxx
    created_at: "2026-05-17T10:00:00Z"
    enc: AQICAHiW...
  gcp_kms: []
  azure_kv: []
  hc_vault: []
  age: []
  lastmodified: "2026-05-17T10:00:00Z"
  mac: ENC[AES256_GCM,data=mac...,iv:...,tag:...]
  pgp: []
  encrypted_regex: ^(password|api_key|secret|token|private_key)$
  version: 3.9.0
```

### Git Pre-Commit Hook for SOPS

```bash
#!/bin/bash
# .git/hooks/pre-commit
# Automatically encrypt any unencrypted secret files

for file in $(git diff --cached --name-only --diff-filter=ACM | grep '^secrets/prod/.*\.yaml$'); do
  if grep -q "sops:" "$file"; then
    echo "Already encrypted: $file"
  else
    echo "Encrypting: $file"
    sops --encrypt --in-place "$file"
    git add "$file"
  fi
done
```

---

## Key Rotation Procedures

### Automatic Rotation with Lambda

```python
# lambda/rotate_secret.py
import boto3
import json
import logging
import os
import random
import string

logger = logging.getLogger()
logger.setLevel(logging.INFO)

secretsmanager = boto3.client('secretsmanager')

def generate_password(length=32):
    characters = string.ascii_letters + string.digits + "!@#$%^&*"
    return ''.join(random.choice(characters) for _ in range(length))

def lambda_handler(event, context):
    secret_id = event['SecretId']
    step = event['Step']
    
    if step == 'createSecret':
        create_secret(secret_id, event)
    elif step == 'setSecret':
        set_secret(secret_id, event)
    elif step == 'testSecret':
        test_secret(secret_id, event)
    elif step == 'finishSecret':
        finish_secret(secret_id, event)
    
    return {'Status': 'Success'}

def create_secret(secret_id, event):
    current = json.loads(secretsmanager.get_secret_value(SecretId=secret_id)['SecretString'])
    current['password'] = generate_password()
    
    pending_token = event.get('ClientRequestToken', '')
    secretsmanager.put_secret_value(
        SecretId=secret_id,
        ClientRequestToken=pending_token,
        SecretString=json.dumps(current),
        VersionStages=['AWSPENDING']
    )

def set_secret(secret_id, event):
    logger.info(f"Setting secret for {secret_id}")

def test_secret(secret_id, event):
    logger.info(f"Testing secret for {secret_id}")

def finish_secret(secret_id, event):
    pending_token = event.get('ClientRequestToken', '')
    secretsmanager.update_secret_version_stage(
        SecretId=secret_id,
        VersionStage='AWSCURRENT',
        RemoveVersionStages=['AWSPENDING'],
        MoveToVersionId=pending_token
    )
```

### Manual Rotation

```bash
# Rotate a secret manually
aws secretsmanager rotate-secret \
  --secret-id /platform/prod/database

# Check rotation status
aws secretsmanager describe-secret \
  --secret-id /platform/prod/database \
  --query 'RotationEnabled,LastRotatedDate,RotationOccurringAsSchedule'

# Force immediate rotation
aws secretsmanager rotate-secret \
  --secret-id /platform/prod/database \
  --rotation-window-hours 4
```

### Rotation Schedule

| Secret Type | Rotation Period | Method | Impact |
|-------------|----------------|--------|--------|
| Database passwords | 90 days | Lambda + RDS rotation | Rolling restart |
| Redis auth tokens | 90 days | Lambda | Cache flush |
| OIDC client secrets | 180 days | Manual | Token reissue |
| LLM API keys | 30 days | Manual | Provider-dependent |
| TLS certificates | 60 days | cert-manager | Automatic renewal |
| SSH keys | 180 days | Manual | Brief disruption |
| GitHub tokens | 90 days | Manual | ArgoCD re-sync |

---

## Emergency Access Procedures

### Break-Glass Access

```yaml
# Emergency access role
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: emergency-admin
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
    platform.emergency/justification: "Required"
    platform.emergency/expires: "2026-05-18T10:00:00Z"
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: "emergency-user"
```

### Emergency Access Process

```bash
# 1. Request approval from Engineering Director
echo "Requesting emergency access for $(whoami) - Reason: $1"
# Approved via Slack #emergency channel

# 2. Assume break-glass IAM role
aws sts assume-role \
  --role-arn "arn:aws:iam::123456789012:role/platform-emergency-access" \
  --role-session-name "emergency-$(date +%s)" \
  --duration-seconds 3600

# 3. Get current database password from Secrets Manager
aws secretsmanager get-secret-value \
  --secret-id /platform/prod/database \
  --query SecretString \
  --output text | jq .

# 4. Or bypass to master password
# (Stored in a separate, rarely accessed secret)
aws secretsmanager get-secret-value \
  --secret-id /platform/prod/database-master \
  --query SecretString \
  --output text

# 5. Document all actions
echo "Emergency access at $(date -u) by $(whoami) for: $1" >> /var/log/emergency-access.log

# 6. Rotate accessed secrets after emergency
aws secretsmanager rotate-secret \
  --secret-id /platform/prod/database
```

### Emergency Secrets Access Log

```yaml
# Example emergency access log entry
---
date: 2026-05-17T12:34:56Z
requester: "engineer@example.com"
approved_by: "director@example.com"
reason: "Production database connection failure, primary secret not rotating"
secrets_accessed:
  - "/platform/prod/database"
  - "/platform/prod/database-master"
actions_taken:
  - "Force rotated database secret"
  - "Restarted aiops-engine deployment"
duration: 45
incident_id: "INC-2026-05-17-003"
```

---

## Audit Logging

### CloudTrail for Secrets Manager

```bash
# Enable CloudTrail if not already enabled
aws cloudtrail create-trail \
  --name platform-secrets-trail \
  --s3-bucket-name platform-audit-logs \
  --is-multi-region-trail \
  --enable-log-file-validation

# Start logging
aws cloudtrail start-logging --name platform-secrets-trail
```

### Kubernetes Audit Policy for Secrets

```yaml
apiVersion: audit.k8s.io/v1
kind: Policy
metadata:
  name: platform-audit-policy
rules:
# Log all secret access
- level: RequestResponse
  resources:
  - group: ""
    resources: ["secrets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

# Log all ExternalSecret operations
- level: RequestResponse
  resources:
  - group: "external-secrets.io"
    resources: ["externalsecrets", "secretstores", "clustersecretstores"]
  verbs: ["create", "update", "patch", "delete"]

# Log RBAC changes
- level: Metadata
  resources:
  - group: "rbac.authorization.k8s.io"
    resources: ["roles", "rolebindings", "clusterroles", "clusterrolebindings"]
  verbs: ["create", "update", "patch", "delete"]
```

### Audit Queries

```bash
# Query CloudTrail for Secrets Manager access
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventSource,AttributeValue=secretsmanager.amazonaws.com \
  --start-time "2026-05-17T00:00:00Z" \
  --end-time "2026-05-17T23:59:59Z" \
  --query 'Events[?contains(CloudTrailEvent, `"GetSecretValue"`)].[EventTime,UserIdentity.Arn,CloudTrailEvent]' \
  --output table

# Query for ExternalSecret operations in Kubernetes
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets \
  --tail=100 | grep -E "Reconciled|Error|Secret"

# Check who accessed a secret
aws secretsmanager describe-secret \
  --secret-id /platform/prod/database \
  --query LastAccessedDate
```

### Monitoring Secret Access

```yaml
# Prometheus alert for unusual secret access
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: secret-access-alerts
  namespace: monitoring
spec:
  groups:
  - name: security
    rules:
    - alert: SecretsManagerBulkAccess
      expr: |
        rate(aws_secretsmanager_get_secret_value_count[5m]) > 50
      for: 1m
      labels:
        severity: critical
      annotations:
        summary: "Bulk secret access detected"
        description: "Secrets Manager accessed {{ $value }} times per second in last 5 minutes"

    - alert: ExternalSecretSyncFailure
      expr: |
        external_secrets_sync_total{status="error"} > 0
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "ExternalSecret sync failure"
        description: "ExternalSecret {{ $labels.name }} has sync errors"
```

---

## Next Steps

1. [Validate the deployment with smoke tests](06-validation-smoke-tests.md)
2. [Review rollback procedures](07-rollback-procedures.md)
3. [Set up incident response procedures](../operations/02-incident-response.md)
