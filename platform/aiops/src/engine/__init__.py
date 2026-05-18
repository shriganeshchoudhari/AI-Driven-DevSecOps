import asyncio
import logging
from typing import Any, Dict, List, Optional

from src.config import settings
from src.models.schemas import (
    FalcoAlert,
    Incident,
    K8sEvent,
    LogEvent,
    MetricEvent,
    SecurityAlert,
    TraceEvent,
)
from src.services.anomaly import AnomalyDetectionService
from src.services.correlation import IncidentCorrelationService
from src.services.ingestion import IngestionService
from src.services.llm import LLMService
from src.services.remediation import RemediationService
from src.services.vectorstore import VectorStoreService

logger = logging.getLogger(__name__)

_engine_instance = None


class AIOpsEngine:
    def __init__(self):
        self.ingestion: Optional[IngestionService] = None
        self.anomaly: Optional[AnomalyDetectionService] = None
        self.correlation: Optional[IncidentCorrelationService] = None
        self.vectorstore: Optional[VectorStoreService] = None
        self.llm: Optional[LLMService] = None
        self.remediation: Optional[RemediationService] = None
        self.security_alerts: List[Dict[str, Any]] = []
        self.initialized = False

    async def initialize(self):
        logger.info("Initializing AIOps Engine components...")

        self.vectorstore = VectorStoreService()
        await self.vectorstore.initialize()

        self.anomaly = AnomalyDetectionService()
        self.correlation = IncidentCorrelationService()

        self.ingestion = IngestionService(
            anomaly_service=self.anomaly,
            correlation_service=self.correlation,
            vectorstore=self.vectorstore,
        )

        self.llm = LLMService(vectorstore=self.vectorstore)

        self.remediation = RemediationService(llm_service=self.llm)

        self.initialized = True
        logger.info("AIOps Engine initialized successfully")

    async def shutdown(self):
        logger.info("Shutting down AIOps Engine")
        if self.vectorstore:
            await self.vectorstore.close()

    async def process_logs(self, events: List[LogEvent]):
        if not self.initialized:
            return
        await self.ingestion.process_logs(events)

    async def process_metrics(self, events: List[MetricEvent]):
        if not self.initialized:
            return
        anomalies = await self.anomaly.detect_metric_anomalies(events)
        if anomalies:
            logger.info(f"Detected {len(anomalies)} metric anomalies")

    async def process_traces(self, events: List[TraceEvent]):
        if not self.initialized:
            return
        await self.ingestion.process_traces(events)

    async def process_k8s_events(self, events: List[K8sEvent]):
        if not self.initialized:
            return
        await self.correlation.ingest_k8s_event(events)

    async def process_security_alert(self, alert: FalcoAlert):
        if not self.initialized:
            return
        alert_dict = alert.dict()
        self.security_alerts.append(alert_dict)
        await self.ingestion.process_security_alert(alert)

    async def process_custom_security_alert(self, alert: SecurityAlert):
        if not self.initialized:
            return
        alert_dict = alert.dict()
        self.security_alerts.append(alert_dict)
        if alert.severity in ("critical", "high"):
            falco_alert = FalcoAlert(
                timestamp=alert.timestamp,
                rule=alert.alert_type,
                priority="critical" if alert.severity == "critical" else "error",
                output=alert.description,
                namespace=alert.namespace,
                tags=[alert.source],
            )
            await self.correlation.create_security_incident(falco_alert)

    async def analyze_incident(self, incident_id: str) -> Dict[str, Any]:
        incident = await self.correlation.get_incident(incident_id)
        if not incident:
            raise ValueError(f"Incident {incident_id} not found")

        rca = await self.llm.generate_rca(incident)
        similar = await self.vectorstore.search_similar_incidents(incident)

        return {
            "rca": rca.dict() if hasattr(rca, "dict") else rca,
            "similar_incidents": similar,
            "incident": incident.dict() if hasattr(incident, "dict") else incident,
        }

    async def suggest_remediation(self, incident_id: str) -> List[Dict[str, Any]]:
        incident = await self.correlation.get_incident(incident_id)
        if not incident:
            raise ValueError(f"Incident {incident_id} not found")

        return await self.remediation.suggest_actions(incident)

    async def execute_remediation(
        self, action_id: str, approved_by: Optional[str] = None
    ):
        return await self.remediation.execute_action(action_id, approved_by)


def get_engine() -> AIOpsEngine:
    global _engine_instance
    return _engine_instance


async def setup_engine(app):
    global _engine_instance
    _engine_instance = AIOpsEngine()
    await _engine_instance.initialize()
    app.state.engine = _engine_instance
