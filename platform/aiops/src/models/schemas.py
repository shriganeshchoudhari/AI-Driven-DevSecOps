from datetime import datetime
from typing import Any, Dict, List, Literal, Optional

from pydantic import BaseModel, Field


class LogEvent(BaseModel):
    timestamp: datetime
    service: str
    namespace: str
    pod: Optional[str] = None
    container: Optional[str] = None
    level: str = "info"
    message: str
    structured_data: Optional[Dict[str, Any]] = None
    source: str = "kubernetes"


class MetricEvent(BaseModel):
    timestamp: datetime
    name: str
    value: float
    labels: Dict[str, str] = {}
    source: str = "prometheus"


class TraceEvent(BaseModel):
    trace_id: str
    span_id: str
    parent_span_id: Optional[str] = None
    service: str
    operation: str
    duration_ms: float
    status: Literal["ok", "error"] = "ok"
    tags: Dict[str, str] = {}
    timestamp: datetime


class K8sEvent(BaseModel):
    timestamp: datetime
    type: Literal["Normal", "Warning"] = "Normal"
    reason: str
    message: str
    object_kind: str
    object_name: str
    namespace: str
    component: str
    host: Optional[str] = None


class FalcoAlert(BaseModel):
    timestamp: datetime
    rule: str
    priority: Literal[
        "emergency", "alert", "critical", "error", "warning", "notice", "informational", "debug"
    ]
    output: str
    source: str = "falco"
    namespace: Optional[str] = None
    pod: Optional[str] = None
    container: Optional[str] = None
    hostname: Optional[str] = None
    tags: List[str] = []
    raw: Optional[Dict[str, Any]] = None


class SecurityAlert(BaseModel):
    timestamp: datetime
    alert_type: str
    severity: Literal["critical", "high", "medium", "low"]
    title: str
    description: str
    source: str
    affected_resource: str
    namespace: Optional[str] = None
    raw_data: Optional[Dict[str, Any]] = None
    mitre_technique_id: Optional[str] = None


class Incident(BaseModel):
    id: Optional[str] = None
    title: str
    description: str
    severity: Literal["critical", "high", "medium", "low"]
    status: Literal[
        "detected", "analyzing", "analyzed", "remediating", "remediated", "resolved", "closed"
    ]
    service: Optional[str] = None
    namespace: Optional[str] = None
    events: List[Dict[str, Any]] = []
    alerts: List[Dict[str, Any]] = []
    ai_analysis: Optional[Dict[str, Any]] = None
    remediation: Optional[Dict[str, Any]] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)
    resolved_at: Optional[datetime] = None
    cluster_id: Optional[str] = None


class AnomalyResult(BaseModel):
    timestamp: datetime
    metric_name: str
    current_value: float
    expected_value: float
    deviation: float
    anomaly_score: float
    severity: Literal["low", "medium", "high", "critical"]
    service: str
    details: Dict[str, Any] = {}


class RemediationAction(BaseModel):
    id: Optional[str] = None
    incident_id: str
    action: str
    description: str
    confidence: float
    target_resource: str
    target_namespace: str
    status: Literal[
        "pending", "approved", "rejected", "in_progress", "completed", "failed", "rolled_back"
    ]
    automation_allowed: bool = False
    requires_approval: bool = True
    created_by: str = "aiops-engine"
    approved_by: Optional[str] = None
    result: Optional[Dict[str, Any]] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)
    executed_at: Optional[datetime] = None


class RCAResult(BaseModel):
    incident_id: str
    root_cause: str
    confidence: float
    contributing_factors: List[str]
    timeline: List[Dict[str, Any]]
    affected_services: List[str]
    recommendations: List[str]
    similar_incidents: List[Dict[str, Any]]
    generated_at: datetime = Field(default_factory=datetime.utcnow)


class HealthResponse(BaseModel):
    status: str
    version: str
    environment: str
    uptime: float


class VersionInfo(BaseModel):
    version: str
    build_time: str
    commit_sha: str
