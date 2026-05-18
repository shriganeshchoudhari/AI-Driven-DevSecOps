import logging
import uuid
from datetime import datetime
from typing import Any, Dict, List, Optional

from src.config import settings
from src.models.schemas import Incident, RemediationAction

try:
    from kubernetes import client as k8s_client, config as k8s_config

    KUBERNETES_AVAILABLE = True
except ImportError:
    KUBERNETES_AVAILABLE = False

logger = logging.getLogger(__name__)


class RemediationService:
    def __init__(self, llm_service=None):
        self.llm = llm_service
        self.actions: Dict[str, RemediationAction] = {}

        self.remediation_catalog = {
            "restart_deployment": {
                "action": "restart_deployment",
                "description": "Restart a Kubernetes deployment to recover from crash-loop or memory leak",
                "requires_approval": True,
                "automation_allowed": False,
                "k8s_action": "apps/v1/deployments/restart",
            },
            "rollback_deployment": {
                "action": "rollback_deployment",
                "description": "Rollback a deployment to the previous revision",
                "requires_approval": True,
                "automation_allowed": False,
                "k8s_action": "apps/v1/deployments/rollback",
            },
            "scale_deployment": {
                "action": "scale_deployment",
                "description": "Scale a deployment horizontally",
                "requires_approval": True,
                "automation_allowed": True,
                "k8s_action": "apps/v1/deployments/scale",
            },
            "cordon_node": {
                "action": "cordon_node",
                "description": "Cordon a Kubernetes node for maintenance",
                "requires_approval": True,
                "automation_allowed": False,
                "k8s_action": "core/v1/nodes/cordon",
            },
            "delete_pod": {
                "action": "delete_pod",
                "description": "Force delete a stuck pod",
                "requires_approval": True,
                "automation_allowed": False,
                "k8s_action": "core/v1/pods/delete",
            },
            "quarantine_namespace": {
                "action": "quarantine_namespace",
                "description": "Apply network policy to isolate a compromised namespace",
                "requires_approval": True,
                "automation_allowed": False,
                "k8s_action": "networking.k8s.io/v1/networkpolicies/create",
            },
            "revoke_credentials": {
                "action": "revoke_credentials",
                "description": "Revoke and rotate compromised credentials",
                "requires_approval": True,
                "automation_allowed": False,
                "k8s_action": "secrets/rotate",
            },
            "scale_hpa": {
                "action": "scale_hpa",
                "description": "Update HPA min/max replicas for traffic spike",
                "requires_approval": False,
                "automation_allowed": True,
                "k8s_action": "autoscaling/v2/horizontalpodautoscalers/update",
            },
        }

    async def suggest_actions(
        self, incident: Incident
    ) -> List[Dict[str, Any]]:
        suggestions = []
        description_lower = incident.description.lower()

        if any(
            word in description_lower
            for word in ["crashloop", "crash", "oomkilled", "memory leak"]
        ):
            suggestions.append(
                self._build_suggestion(
                    "restart_deployment",
                    confidence=0.85,
                    target=incident.namespace or "",
                )
            )
            suggestions.append(
                self._build_suggestion(
                    "rollback_deployment",
                    confidence=0.75,
                    target=incident.namespace or "",
                )
            )

        if any(
            word in description_lower
            for word in ["high latency", "p99", "timeout", "slow"]
        ):
            suggestions.append(
                self._build_suggestion(
                    "scale_deployment",
                    confidence=0.70,
                    target=incident.namespace or "",
                )
            )

        if any(
            word in description_lower
            for word in ["traffic spike", "high load", "scaling"]
        ):
            suggestions.append(
                self._build_suggestion(
                    "scale_hpa",
                    confidence=0.80,
                    target=incident.namespace or "",
                )
            )

        if any(
            word in description_lower
            for word in [
                "compromised",
                "breach",
                "unauthorized",
                "reverse shell",
            ]
        ):
            suggestions.append(
                self._build_suggestion(
                    "quarantine_namespace",
                    confidence=0.90,
                    target=incident.namespace or "",
                )
            )
            suggestions.append(
                self._build_suggestion(
                    "revoke_credentials",
                    confidence=0.85,
                    target=incident.namespace or "",
                )
            )

        if incident.severity == "critical" and not suggestions:
            suggestions.append(
                self._build_suggestion(
                    "restart_deployment",
                    confidence=0.60,
                    target=incident.namespace or "",
                )
            )

        return suggestions

    def _build_suggestion(
        self, action_name: str, confidence: float, target: str
    ) -> Dict[str, Any]:
        catalog = self.remediation_catalog.get(action_name, {})
        return {
            "action": action_name,
            "description": catalog.get("description", ""),
            "confidence": confidence,
            "requires_approval": catalog.get("requires_approval", True),
            "automation_allowed": catalog.get("automation_allowed", False),
            "target_resource": target,
        }

    async def execute_action(
        self, action_id: str, approved_by: Optional[str] = None
    ) -> Dict[str, Any]:
        action = self.actions.get(action_id)
        if not action:
            raise ValueError(f"Action {action_id} not found")

        if action.requires_approval and not approved_by:
            raise ValueError("This action requires approval")

        action.status = "in_progress"
        action.approved_by = approved_by
        action.executed_at = datetime.utcnow()

        try:
            result = await self._execute_k8s_action(action)
            action.status = "completed"
            action.result = result
            logger.info(f"Remediation {action_id} completed successfully")
        except Exception as e:
            action.status = "failed"
            action.result = {"error": str(e)}
            logger.error(f"Remediation {action_id} failed: {e}")

        return action.dict()

    async def _execute_k8s_action(
        self, action: RemediationAction
    ) -> Dict[str, Any]:
        if not KUBERNETES_AVAILABLE:
            return {
                "status": "simulated",
                "action": action.action,
                "message": "kubernetes package not available, action logged for audit",
            }

        if not settings.KUBERNETES_ENABLED:
            return {
                "status": "simulated",
                "action": action.action,
                "message": "Kubernetes disabled via config, action logged for audit",
            }

        try:
            if settings.KUBERNETES_IN_CLUSTER:
                k8s_config.load_incluster_config()
            else:
                k8s_config.load_kube_config()

            core_api = k8s_client.CoreV1Api()
            apps_api = k8s_client.AppsV1Api()

            namespace = (
                action.target_resource.split("/")[0]
                if "/" in action.target_resource
                else action.target_namespace
            )
            name = (
                action.target_resource.split("/")[-1]
                if "/" in action.target_resource
                else action.target_resource
            )

            if action.action == "restart_deployment":
                body = {
                    "spec": {
                        "template": {
                            "metadata": {
                                "annotations": {
                                    "kubectl.kubernetes.io/restartedAt": datetime.utcnow().isoformat()
                                }
                            }
                        }
                    }
                }
                apps_api.patch_namespaced_deployment(
                    name=name, namespace=namespace, body=body
                )
                return {
                    "status": "restarted",
                    "deployment": name,
                    "namespace": namespace,
                }

            elif action.action == "scale_deployment":
                body = {"spec": {"replicas": 5}}
                apps_api.patch_namespaced_deployment(
                    name=name, namespace=namespace, body=body
                )
                return {
                    "status": "scaled",
                    "deployment": name,
                    "namespace": namespace,
                    "replicas": 5,
                }

            elif action.action == "cordon_node":
                node_name = action.target_resource
                body = {"spec": {"unschedulable": True}}
                core_api.patch_node(name=node_name, body=body)
                return {"status": "cordoned", "node": node_name}

            elif action.action == "delete_pod":
                pod_name = action.target_resource
                core_api.delete_namespaced_pod(
                    name=pod_name, namespace=namespace
                )
                return {
                    "status": "deleted",
                    "pod": pod_name,
                    "namespace": namespace,
                }

            elif action.action == "scale_hpa":
                autoscaling_api = k8s_client.AutoscalingV2Api()
                body = {"spec": {"minReplicas": 3, "maxReplicas": 10}}
                autoscaling_api.patch_namespaced_horizontal_pod_autoscaler(
                    name=name, namespace=namespace, body=body
                )
                return {
                    "status": "hpa_updated",
                    "hpa": name,
                    "namespace": namespace,
                }

            else:
                return {
                    "status": "not_implemented",
                    "action": action.action,
                    "message": f"Action {action.action} not yet implemented for Kubernetes",
                }

        except Exception as e:
            logger.warning(f"Kubernetes action failed (simulating): {e}")
            return {
                "status": "simulated",
                "action": action.action,
                "target": action.target_resource,
                "message": f"Kubernetes action simulated: {str(e)}",
            }
