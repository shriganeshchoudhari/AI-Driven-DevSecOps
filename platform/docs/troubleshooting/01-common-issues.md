# Common Issues Troubleshooting Guide

Diagnosis and resolution procedures for the most common platform issues.

---

## Table of Contents

- [ArgoCD Sync Failures](#argocd-sync-failures)
- [Pod Startup Failures](#pod-startup-failures)
- [Network Policy Issues](#network-policy-issues)
- [Certificate Errors](#certificate-errors)
- [OIDC Authentication Issues](#oidc-authentication-issues)
- [Database Connection Failures](#database-connection-failures)
- [Metrics Collection Gaps](#metrics-collection-gaps)
- [Falco False Positives](#falco-false-positives)
- [HPA Not Scaling](#hpa-not-scaling)
- [Karpenter Provisioning Failures](#karpenter-provisioning-failures)

---

## ArgoCD Sync Failures

### Symptoms
- Application status shows `OutOfSync` or `SyncFailed`
- ArgoCD UI shows red health status
- `argocd app list` shows non-Synced status

### Diagnostic Commands

```bash
# Check application details
argocd app get <app-name>
argocd app diff <app-name>

# Check sync status
argocd app sync <app-name> --dry-run

# View detailed sync result
argocd app get <app-name> -o json | jq '.status.operationState.syncResult'

# Check ArgoCD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=100

# Check if repo has connectivity issues
kubectl exec -n argocd deploy/argocd-repo-server -- \
  sh -c "git ls-remote https://github.com/org/repo.git"
```

### Common Causes and Fixes

| Cause | Diagnosis | Fix |
|-------|-----------|-----|
| **Invalid YAML syntax** | `argocd app diff` shows parse errors | Fix YAML in repo, push fix |
| **Missing required fields** | Kyverno blocks the resource | Check Kyverno policy report: `kubectl get policyreport -A` |
| **Resource already exists** | `AlreadyExists` error in sync result | Add `--replace` flag or delete existing resource |
| **Out of cluster resources** | Sync fails on CRD dependencies | Ensure CRDs are installed, set sync wave ordering |
| **Git credentials expired** | Repo server cannot authenticate | Update GitHub token in `argocd/values.yaml` |
| **Network policy blocking** | ArgoCD cannot reach GitHub | Check NetworkPolicy for argocd namespace |
| **Resource quota exceeded** | Sync fails with `exceeded quota` | Check resource quotas: `kubectl get resourcequota -A` |

### Resolution Steps

```bash
# 1. Manual sync with prune
argocd app sync <app-name> --prune --replace

# 2. If stuck, reset sync
argocd app terminate-op <app-name>

# 3. Force refresh
argocd app get <app-name> --refresh

# 4. Delete and recreate
argocd app delete <app-name>
kubectl delete application <app-name> -n argocd --wait=false
kubectl apply -f <app-manifest>.yaml
```

---

## Pod Startup Failures

### Symptoms
- Pod stuck in `Pending`, `CrashLoopBackOff`, or `ImagePullBackOff`
- Pod logs show errors
- `kubectl get pods` shows non-Running status

### Diagnostic Commands

```bash
# Check pod status
kubectl describe pod <pod-name> -n <namespace>

# Check pod logs
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous

# Check events
kubectl get events -n <namespace> --sort-by='.lastTimestamp' | tail -20

# Check resource availability
kubectl top nodes
kubectl describe node <node-name>

# Check if PVC is available
kubectl get pvc -n <namespace>
kubectl describe pvc <pvc-name> -n <namespace>
```

### Common Causes and Fixes

| Cause | Symptoms | Fix |
|-------|----------|-----|
| **Image pull failure** | `ImagePullBackOff` | Check ECR permissions: `aws ecr get-login-password`, verify image exists |
| **Resource insufficient** | Pod pending with `Insufficient memory/cpu` | Scale cluster: `kubectl scale --replicas=...`, check Karpenter |
| **PVC pending** | Pod pending with `PersistentVolumeClaim not found` | Check StorageClass: `kubectl get storageclass`, verify PV provisioning |
| **Init container error** | Init container CrashLoopBackOff | Check init container logs, verify dependencies |
| **Liveness probe failing** | Pod restarting with `BackOff` | Check health endpoint: `curl http://pod-ip:port/health` |
| **Secrets not found** | Pod crash with secret error | Check ExternalSecret status: `kubectl get externalsecret` |
| **Network policy blocking** | Init container cannot connect | Check NetworkPolicy egress rules |
| **Kyverno policy violation** | Pod blocked at admission | Check policy report: `kubectl get policyreport -A` |

### Resolution Steps

```bash
# 1. Check and fix image
docker pull <image>:<tag>
trivy image <image>:<tag>

# 2. Check node capacity
kubectl describe node | grep -A 10 "Capacity"
kubectl top node

# 3. Force delete stuck pod
kubectl delete pod <pod-name> -n <namespace> --grace-period=0 --force

# 4. Restart deployment
kubectl rollout restart deployment <deployment-name> -n <namespace>

# 5. Check rollout status
kubectl rollout status deployment <deployment-name> -n <namespace>
```

---

## Network Policy Issues

### Symptoms
- Pods cannot communicate with each other
- DNS resolution fails within cluster
- External connectivity failures
- Metrics scraping failures

### Diagnostic Commands

```bash
# Check network policies
kubectl get networkpolicies -A
kubectl describe networkpolicy <policy> -n <namespace>

# Test connectivity from pod
kubectl exec -it <pod> -n <namespace> -- \
  curl -s -o /dev/null -w "%{http_code}" http://<target-service>:<port>

# Check DNS resolution
kubectl exec -it <pod> -n <namespace> -- \
  nslookup <service-name>.<namespace>

# Check which policies affect a pod
kubectl get networkpolicies -A -o json | jq '
  .items[] | select(.spec.podSelector.matchLabels | to_entries[] |
  .key as $k | .value as $v |
  [inputs | .metadata.labels[$k] == $v] | any) |
  .metadata.name, .metadata.namespace
'

# Check if default-deny exists
for ns in $(kubectl get ns -o name | cut -d/ -f2); do
  policies=$(kubectl get networkpolicies -n "$ns" -o name 2>/dev/null)
  if [ -z "$policies" ]; then
    echo "WARNING: No network policies in namespace: $ns"
  fi
done
```

### Common Causes and Fixes

| Cause | Diagnosis | Fix |
|-------|-----------|-----|
| **Missing default-deny** | No network policies in namespace | Apply default-deny policy |
| **Egress rule too restrictive** | Pod cannot connect to DNS | Add egress rule for UDP 53 |
| **Ingress rule missing** | Prometheus cannot scrape | Add ingress rule for scrape port |
| **CIDR mismatch** | Cross-namespace traffic blocked | Verify namespaceSelector labels |
| **Policy ordering** | Conflicting policies | Review policy priority, combine rules |

### Resolution Steps

```bash
# 1. Allow DNS resolution
cat << EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: <namespace>
spec:
  podSelector: {}
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - port: 53
      protocol: UDP
    - port: 53
      protocol: TCP
  policyTypes:
  - Egress
EOF

# 2. Allow monitoring
cat << EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-monitoring
  namespace: <namespace>
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: <app>
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: monitoring
      podSelector:
        matchLabels:
          app.kubernetes.io/name: prometheus
  policyTypes:
  - Ingress
EOF
```

---

## Certificate Errors

### Symptoms
- Browser shows "Not Secure" or certificate warnings
- `kubectl describe certificate` shows `NotReady`
- TLS handshake failures in logs

### Diagnostic Commands

```bash
# Check certificate status
kubectl get certificate -A
kubectl describe certificate <name> -n <namespace>

# Check certificate request
kubectl get certificaterequest -A
kubectl describe certificaterequest <name> -n <namespace>

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager --tail=50

# Check ClusterIssuer
kubectl get clusterissuer
kubectl describe clusterissuer <name>

# Check certificate expiry
kubectl get certificate -A -o json | jq -r '
  .items[] | "\(.metadata.namespace)/\(.metadata.name): \(.status.notAfter)"
'

# Check ingress TLS configuration
kubectl get ingress -A -o json | jq '
  .items[] | select(.spec.tls != null) |
  {name: .metadata.name, tls: .spec.tls}
'
```

### Common Causes and Fixes

| Cause | Diagnosis | Fix |
|-------|-----------|-----|
| **DNS validation failing** | Certificate pending with DNS check | Verify DNS records for domain |
| **Rate limited** | `rateLimited` error in cert status | Wait, use staging issuer for testing |
| **Wrong secret name** | Ingress references non-existent secret | Update ingress TLS secret name |
| **ClusterIssuer not ready** | ClusterIssuer shows `NotReady` | Check AWS credentials, IAM permissions |
| **Private key expired** | Certificate not renewing | Restart cert-manager, check key permissions |

### Resolution Steps

```bash
# 1. Check DNS records
dig <domain> TXT
nslookup <domain>

# 2. Use staging issuer for testing
cat << EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: devops@example.com
    privateKeySecretRef:
      name: letsencrypt-staging-key
    solvers:
    - dns01:
        route53:
          region: us-west-2
EOF

# 3. Force renewal
kubectl delete certificate <name> -n <namespace>
# Or annotate for renewal
kubectl annotate certificate <name> -n <namespace> \
  cert-manager.io/issue-temporary-certificate="true"

# 4. Check IAM permissions for cert-manager
aws sts assume-role --role-arn "arn:aws:iam::123456789012:role/cert-manager" \
  --role-session-name test

# 5. Restart cert-manager
kubectl rollout restart deployment -n cert-manager
```

---

## OIDC Authentication Issues

### Symptoms
- Cannot authenticate to ArgoCD, Grafana, or Kubernetes API
- Error: `Unauthorized` or `token expired`
- OIDC callback errors

### Diagnostic Commands

```bash
# Check OIDC configuration
kubectl get cm -n argocd argocd-cm -o yaml | grep oidc

# Check ArgoCD dex configuration
kubectl describe configmap -n argocd argocd-dex-server

# Test OIDC token
TOKEN=<your-token>
curl -s https://accounts.example.com/userinfo -H "Authorization: Bearer $TOKEN" | jq .

# Check token expiry
echo $TOKEN | cut -d. -f2 | base64 -d 2>/dev/null | jq '.exp, .iat'

# Check ArgoCD server logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=50
```

### Common Causes and Fixes

| Cause | Diagnosis | Fix |
|-------|-----------|-----|
| **Expired token** | JWT shows expired `exp` claim | Refresh token, re-authenticate |
| **Wrong OIDC issuer** | Callback URL mismatch | Verify issuer URL in argocd-cm |
| **Client secret mismatch** | OIDC provider rejects token | Rotate client secret, update both sides |
| **Clock skew** | Token validation fails due to time diff | Check NTP sync: `timedatectl` |
| **Missing redirect URI** | OIDC callback not registered | Add redirect URI to IDP configuration |
| **RBAC mapping missing** | Authenticated but unauthorized | Check argocd-rbac-cm |

### Resolution Steps

```bash
# 1. Verify OIDC provider
# Check your IDP (Okta, Keycloak, etc.) configuration

# 2. Re-authenticate
argocd login <argocd-url> --sso
kubelogin convert-kubeconfig

# 3. Update ArgoCD OIDC config
kubectl edit configmap argocd-cm -n argocd

# 4. Restart ArgoCD server
kubectl rollout restart deployment argocd-server -n argocd

# 5. Check RBAC mapping
kubectl edit configmap argocd-rbac-cm -n argocd
# Example policy:
# g, example.com:team-admin, role:admin
# g, example.com:team-dev, role:readonly
```

---

## Database Connection Failures

### Symptoms
- Application logs show database connection errors
- High latency on database queries
- Connection pool exhaustion

### Diagnostic Commands

```bash
# Check from application pod
kubectl exec -it <pod> -n <namespace> -- \
  psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -c "SELECT 1"

# Check RDS metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=platform-prod \
  --start-time $(date -d "-1 hour" +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Maximum

# Check RDS CPU
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=platform-prod \
  --start-time $(date -d "-1 hour" +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Average

# Check connection pool
kubectl exec -it <pod> -n <namespace> -- \
  python3 -c "
import os, psycopg2
conn = psycopg2.connect(
    host=os.environ['DB_HOST'],
    port=os.environ['DB_PORT'],
    user=os.environ['DB_USER'],
    password=os.environ['DB_PASSWORD'],
    dbname=os.environ['DB_NAME']
)
cur = conn.cursor()
cur.execute(\"SELECT count(*) FROM pg_stat_activity;\")
print(f'Active connections: {cur.fetchone()[0]}')
cur.close()
conn.close()
"
```

### Common Causes and Fixes

| Cause | Diagnosis | Fix |
|-------|-----------|-----|
| **Connection pool exhausted** | `too many connections` error | Increase pool size, optimize queries |
| **Network issue** | Timeout connecting to RDS | Check security group, VPC endpoints |
| **RDS instance overloaded** | High CPU/Memory on RDS | Scale up instance, add read replicas |
| **Secret rotation** | Password changed unexpectedly | Check last secret rotation time |
| **Maintenance window** | RDS in maintenance | Check maintenance events |

---

## Metrics Collection Gaps

### Symptoms
- Grafana dashboards show gaps or No Data
- Prometheus targets show DOWN
- Alertmanager has `NoData` alerts

### Diagnostic Commands

```bash
# Check Prometheus targets
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
curl -s http://localhost:9090/api/v1/targets | jq '
  .data.activeTargets[] | select(.health != "up") |
  {job: .labels.job, instance: .labels.instance, scrapeUrl: .scrapeUrl, lastError: .lastError}
'

# Check Prometheus configuration
curl -s http://localhost:9090/api/v1/status/config | jq '.data.yaml' | head -50

# Check service monitor
kubectl get servicemonitor -A
kubectl describe servicemonitor <name> -n <namespace>

# Check Prometheus log
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus --tail=50

# Query for missing data
curl -s 'http://localhost:9090/api/v1/query?query=up' | jq '.data.result[] | select(.value[1] == "0")'
```

### Common Causes

- ServiceMonitor selector labels don't match service labels
- Network policy blocking Prometheus -> pod traffic
- Target service down or not responding on metrics port
- Relabel config dropping targets
- Prometheus resource limits reached

---

## Falco False Positives

### Symptoms
- Falco generates alerts for expected system behavior
- Alert fatigue from Falco events
- Legitimate operations flagged as suspicious

### Diagnostic Commands

```bash
# Check recent Falco events
kubectl logs -n falco daemonset/falco --tail=20

# Check Falco configuration
kubectl get configmap -n falco falco-config -o yaml

# Test Falco rule match
kubectl exec -it -n falco <pod> -- falco --print=json 2>&1 | head -20

# Check rule priority distribution
kubectl logs -n falco daemonset/falco --tail=1000 | \
  grep -oP '"priority":"\K[^"]+' | sort | uniq -c | sort -rn
```

### Resolution

```yaml
# Add exception to Falco rules
- rule: My Custom Rule
  desc: Custom rule description
  condition: >
    evt.type = execve
    and proc.name = expected_process
    and not proc.name in (known_legitimate_processes)
  output: "Custom alert (user=%user.name command=%proc.cmdline)"
  priority: WARNING
  tags: [platform, custom]

# Or add to exceptions file
falco:
  falco_exceptions:
  - name: "my-exception"
    fields:
    - proc.name
    values:
    - "kube-bench"
    - "node-exporter"
```

---

## HPA Not Scaling

### Symptoms
- CPU/memory usage high but HPA doesn't scale up
- HPA shows `<unknown>` for metrics
- Stuck at current replica count

### Diagnostic Commands

```bash
# Check HPA status
kubectl get hpa -A
kubectl describe hpa <name> -n <namespace>

# Check metrics server
kubectl get pods -n kube-system -l k8s-app=metrics-server
kubectl top nodes
kubectl top pods -A

# Check if resource requests are set
kubectl get deployment <name> -n <namespace> -o json | jq '.spec.template.spec.containers[].resources'

# Check event logs
kubectl get events -n <namespace> --field-selector involvedObject.kind=HorizontalPodAutoscaler
```

### Common Causes

- Missing resource requests/limits on containers
- Metrics server not installed or failing
- Target utilization already below threshold
- Pods have resource limits that prevent scheduling
- HPA custom metrics API not available

---

## Karpenter Provisioning Failures

### Symptoms
- Pending pods not scheduling
- No new nodes being created
- Karpenter logs show errors

### Diagnostic Commands

```bash
# Check Karpenter pods
kubectl get pods -n karpenter

# Check Karpenter logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=50

# Check NodeClaims
kubectl get nodeclaims
kubectl describe nodeclaim <name>

# Check NodePool
kubectl get nodepool
kubectl describe nodepool default

# Check EC2NodeClass
kubectl get ec2nodeclass
kubectl describe ec2nodeclass default

# Check pending pods reasons
kubectl get pods -A --field-selector=status.phase=Pending -o json | jq '
  .items[] | {
    name: .metadata.name,
    namespace: .metadata.namespace,
    reason: .status.conditions[] | select(.reason == "Unschedulable") | .message
  }
'
```

### Common Causes

- EC2NodeClass role not configured correctly
- Subnet selector tags missing
- Security group tags not matching
- Service quota reached (EC2 instance limit)
- NodePool limits reached
- AMI not found or incompatible
- IAM role permissions missing

---

## Next Steps

1. [Review escalation matrix](02-escalation-matrix.md)
2. [Review incident response procedures](../operations/02-incident-response.md)
3. [Review SRE runbook](../operations/01-sre-runbook.md)
