# On-Call Runbook

## Overview
This runbook provides step‑by‑step guidance for on‑call engineers when an incident occurs in the AI‑Driven Secure GitOps platform.

## 1. Alert Ingestion
- Verify the alert in Alertmanager (`kubectl -n monitoring get alerts`).
- Identify the affected service from the `service` label.

## 2. Triage
- Pull recent logs: `kubectl -n $SERVICE logs -l app=$SERVICE --tail=500`.
- Query Prometheus for recent error rates:
  ```
  promtool query instant http://prometheus-k8s.monitoring.svc:9090 "sum(rate(http_requests_total{service=\"$SERVICE\",status=~\"5.*\"}[5m]))"
  ```

## 3. Automatic Remediation
- If the alert matches a known pattern (e.g., `KubernetesPodCrashLooping`), trigger the AIOps remediation controller:
  ```bash
  curl -X POST http://aiops-engine.aiops-engine:8080/remediate -d '{"service":"$SERVICE"}'
  ```
- Verify the pod state returns to `Running`.

## 4. Manual Intervention
- If automated remediation fails, execute a rollout rollback:
  ```bash
  argocd app rollback $SERVICE --to-revision $(argocd app history $SERVICE -o yaml | grep previous | head -1)
  ```
- Scale down the problematic deployment and investigate root cause.

## 5. Post‑mortem
- Export the incident data from the AIOps engine:
  ```bash
  curl http://aiops-engine.aiops-engine:8080/incident/$INCIDENT_ID/export > incident_$INCIDENT_ID.json
  ```
- Populate the RCA template (see `aiops/src/prompts/rca_prompt.txt`).
- Store the final report in Confluence and link it to the Jira ticket.

---
*Last updated: 2026‑05‑18*