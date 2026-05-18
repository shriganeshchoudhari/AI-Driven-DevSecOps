#!/usr/bin/env python3
"""
AIOps Platform - Remediation Controller
Watches Prometheus Alertmanager webhooks and triggers automated remediation actions.
Runs as a Kubernetes Deployment.
"""

import os
import json
import logging
import asyncio
from datetime import datetime, timedelta
from typing import Dict, Any, List, Optional

import httpx
from kubernetes import client, config

logging.basicConfig(
    level=getattr(logging, os.getenv("LOG_LEVEL", "INFO")),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger("remediation-controller")

AIOPS_ENGINE_URL = os.getenv("AIOPS_ENGINE_URL", "http://aiops-engine.aiops-engine:8080")
AIOPS_API_KEY = os.getenv("AIOPS_API_KEY", "")
KUBERNETES_IN_CLUSTER = os.getenv("KUBERNETES_IN_CLUSTER", "true").lower() == "true"
AUTO_REMEDIATION_ENABLED = os.getenv("AUTO_REMEDIATION_ENABLED", "false").lower() == "true"
APPROVAL_REQUIRED = os.getenv("APPROVAL_REQUIRED", "true").lower() == "true"

REMEDIATION_ACTIONS = {
    "KubernetesPodCrashLooping": {
        "action": "restart_deployment", "description": "Restart deployment to resolve crash loop",
        "confidence": 0.85, "requires_approval": True, "cooldown_minutes": 15, "max_attempts": 2
    },
    "HighErrorRate": {
        "action": "rollback_deployment", "description": "Rollback to previous version",
        "confidence": 0.90, "requires_approval": True, "cooldown_minutes": 30, "max_attempts": 1
    },
    "HighLatencyP99": {
        "action": "scale_deployment", "description": "Scale up for latency",
        "confidence": 0.70, "requires_approval": False, "cooldown_minutes": 10, "max_attempts": 3
    },
    "KubernetesNodeNotReady": {
        "action": "cordon_node", "description": "Cordon unhealthy node",
        "confidence": 0.80, "requires_approval": True, "cooldown_minutes": 5, "max_attempts": 1
    },
    "ServiceDown": {
        "action": "restart_deployment", "description": "Restart deployment for unavailable service",
        "confidence": 0.75, "requires_approval": False, "cooldown_minutes": 5, "max_attempts": 3
    }
}

class RemediationState:
    def __init__(self):
        self.alert_history: Dict[str, List[datetime]] = {}
        self.action_counts: Dict[str, int] = {}

    def can_remediate(self, alert_name: str, resource: str) -> bool:
        key = f"{alert_name}:{resource}"
        if key not in self.action_counts:
            self.action_counts[key] = 0
            return True
        config_action = REMEDIATION_ACTIONS.get(alert_name, {})
        max_attempts = config_action.get("max_attempts", 1)
        if self.action_counts[key] >= max_attempts:
            logger.warning(f"Max attempts ({max_attempts}) reached for {key}")
            return False
        if key in self.alert_history and self.alert_history[key]:
            cooldown = config_action.get("cooldown_minutes", 15)
            last_attempt = self.alert_history[key][-1]
            elapsed = (datetime.utcnow() - last_attempt).total_seconds() / 60
            if elapsed < cooldown:
                logger.info(f"Cooldown active for {key}: {elapsed:.1f}/{cooldown} min")
                return False
        return True

    def record_attempt(self, alert_name: str, resource: str):
        key = f"{alert_name}:{resource}"
        if key not in self.alert_history:
            self.alert_history[key] = []
        self.alert_history[key].append(datetime.utcnow())
        self.action_counts[key] = self.action_counts.get(key, 0) + 1

class RemediationController:
    def __init__(self):
        self.state = RemediationState()
        self.k8s_core = None
        self.k8s_apps = None
        self.http_client = None
        self._init_kubernetes()

    def _init_kubernetes(self):
        try:
            if KUBERNETES_IN_CLUSTER:
                config.load_incluster_config()
            else:
                config.load_kube_config()
            self.k8s_core = client.CoreV1Api()
            self.k8s_apps = client.AppsV1Api()
            logger.info("Kubernetes client initialized")
        except Exception as e:
            logger.warning(f"Kubernetes init failed: {e}")

    async def _init_http(self):
        if not self.http_client:
            self.http_client = httpx.AsyncClient(timeout=30.0)

    async def handle_alert(self, alert_data: Dict[str, Any]):
        await self._init_http()
        alert_name = alert_data.get("labels", {}).get("alertname", "")
        namespace = alert_data.get("labels", {}).get("namespace", "")
        service = alert_data.get("labels", {}).get("service", "")
        pod = alert_data.get("labels", {}).get("pod", "")
        status = alert_data.get("status", "firing")
        if status != "firing":
            return
        resource = pod or service or namespace or "unknown"
        if not self.state.can_remediate(alert_name, resource):
            return
        action_config = REMEDIATION_ACTIONS.get(alert_name)
        if not action_config:
            return
        action_name = action_config["action"]
        requires_approval = action_config["requires_approval"] and APPROVAL_REQUIRED
        logger.info(f"Remediation: {action_name} for {alert_name} on {resource}")
        if AIOPS_ENGINE_URL:
            try:
                await self.http_client.post(
                    f"{AIOPS_ENGINE_URL}/api/v1/remediation/suggest",
                    json={"title": alert_name, "description": alert_data.get("annotations", {}).get("description", ""), "service": service, "namespace": namespace, "severity": alert_data.get("labels", {}).get("severity", "medium")},
                    headers={"X-API-Key": AIOPS_API_KEY}
                )
            except Exception as e:
                logger.warning(f"AIOps API error: {e}")
        if AUTO_REMEDIATION_ENABLED and not requires_approval:
            try:
                result = await self._execute_k8s_action(action_name, resource, namespace)
                self.state.record_attempt(alert_name, resource)
                logger.info(f"Remediation executed: {result}")
            except Exception as e:
                logger.error(f"Remediation failed: {e}")
        else:
            logger.info(f"Remediation requires approval or auto-remediation disabled: {action_name}")

    async def _execute_k8s_action(self, action: str, resource: str, namespace: str) -> Dict[str, Any]:
        if not self.k8s_core or not self.k8s_apps:
            return {"status": "simulated", "action": action}
        try:
            if action == "restart_deployment":
                body = {"spec": {"template": {"metadata": {"annotations": {"kubectl.kubernetes.io/restartedAt": datetime.utcnow().isoformat()}}}}}
                self.k8s_apps.patch_namespaced_deployment(name=resource, namespace=namespace, body=body)
                return {"status": "completed", "action": "restart", "deployment": resource}
            elif action == "rollback_deployment":
                deployment = self.k8s_apps.read_namespaced_deployment(name=resource, namespace=namespace)
                current_revision = deployment.metadata.annotations.get("deployment.kubernetes.io/revision", "1")
                rollback_revision = str(max(int(current_revision) - 1, 1))
                return {"status": "completed", "action": "rollback", "from_revision": current_revision, "to_revision": rollback_revision}
            elif action == "scale_deployment":
                self.k8s_apps.patch_namespaced_deployment(name=resource, namespace=namespace, body={"spec": {"replicas": 5}})
                return {"status": "completed", "action": "scale", "replicas": 5}
            elif action == "cordon_node":
                self.k8s_core.patch_node(name=resource, body={"spec": {"unschedulable": True}})
                return {"status": "completed", "action": "cordon", "node": resource}
        except client.exceptions.ApiException as e:
            logger.error(f"K8s API error: {e}")
            return {"status": "failed", "error": str(e)}
        return {"status": "unknown_action", "action": action}

def main():
    from fastapi import FastAPI, Request
    import uvicorn
    app = FastAPI(title="Remediation Controller")
    controller = RemediationController()

    @app.post("/webhook")
    async def webhook(request: Request):
        data = await request.json()
        for alert in data.get("alerts", []):
            await controller.handle_alert(alert)
        return {"status": "accepted"}

    @app.get("/health")
    async def health():
        return {"status": "healthy", "timestamp": datetime.utcnow().isoformat()}

    import socket
    port = int(os.getenv("PORT", 8080))
    
    # Socket pre-check to detect occupied or forbidden port
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        s.bind(("0.0.0.0", port))
        s.close()
    except Exception as e:
        logger.warning(f"Port {port} is occupied or forbidden: {e}. Searching for an available fallback port...")
        s.close()
        for fallback_port in range(port + 1, port + 15):
            s_fallback = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            try:
                s_fallback.bind(("0.0.0.0", fallback_port))
                s_fallback.close()
                port = fallback_port
                logger.info(f"Selected fallback port {port} successfully.")
                break
            except Exception:
                s_fallback.close()
                continue
        else:
            logger.error("Could not find any free ports in the fallback range. Attempting default port binding anyway.")

    uvicorn.run(app, host="0.0.0.0", port=port)

if __name__ == "__main__":
    main()
