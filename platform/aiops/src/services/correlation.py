import uuid
import logging
from collections import defaultdict
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional

import numpy as np
from sklearn.cluster import DBSCAN

from src.models.schemas import FalcoAlert, Incident

logger = logging.getLogger(__name__)


class IncidentCorrelationService:
    def __init__(self):
        self.incidents: Dict[str, Incident] = {}
        self.event_index: List[Dict[str, Any]] = []
        self.k8s_events: List[Dict[str, Any]] = []

    async def ingest_k8s_event(self, events: List[Dict[str, Any]]):
        for event in events:
            self.k8s_events.append(event)
            self.event_index.append(event)
            await self._try_correlate(event)

    async def create_security_incident(self, alert: FalcoAlert) -> Incident:
        incident = Incident(
            id=str(uuid.uuid4()),
            title=f"Security: {alert.rule}",
            description=alert.output,
            severity=self._map_falco_priority(alert.priority),
            status="detected",
            alerts=[alert.dict()],
            namespace=alert.namespace,
            created_at=datetime.utcnow(),
        )

        self.incidents[incident.id] = incident
        logger.info(f"Created security incident {incident.id}: {incident.title}")
        return incident

    async def _try_correlate(self, event: Dict[str, Any]):
        window_start = datetime.utcnow() - timedelta(hours=1)

        recent_incidents = [
            inc
            for inc in self.incidents.values()
            if inc.created_at > window_start and inc.status != "closed"
        ]

        for incident in recent_incidents:
            recent_events = incident.events[-5:] if incident.events else []
            if self._events_are_related(recent_events, event):
                incident.events.append(event)
                incident.updated_at = datetime.utcnow()
                logger.debug(f"Correlated event to incident {incident.id}")
                return

        incident = Incident(
            id=str(uuid.uuid4()),
            title=f"Event correlation: {event.get('reason', 'Unknown')}",
            description=event.get("message", ""),
            severity="medium",
            status="detected",
            events=[event],
            namespace=event.get("namespace"),
            created_at=datetime.utcnow(),
        )
        self.incidents[incident.id] = incident
        logger.info(f"Created correlated incident {incident.id}: {incident.title}")

    def _events_are_related(
        self, recent_events: List[Dict[str, Any]], new_event: Dict[str, Any]
    ) -> bool:
        if not recent_events:
            return False

        for evt in recent_events:
            if evt.get("namespace") == new_event.get("namespace"):
                return True
            if evt.get("host") and evt.get("host") == new_event.get("host"):
                return True
            if evt.get("object_name") == new_event.get("object_name"):
                return True

        return False

    async def run_clustering(self) -> Dict[str, List[str]]:
        if len(self.event_index) < 10:
            return {}

        vectors = []
        ids = []
        for item in self.event_index[-1000:]:
            vec = self._event_to_vector(item)
            vectors.append(vec)
            ids.append(item.get("id", ""))

        X = np.array(vectors)
        clustering = DBSCAN(eps=0.3, min_samples=2).fit(X)

        clusters: Dict[str, List[str]] = defaultdict(list)
        for i, label in enumerate(clustering.labels_):
            if label != -1:
                clusters[f"cluster-{label}"].append(ids[i])

        logger.info(f"DBSCAN clustering found {len(clusters)} clusters")
        return dict(clusters)

    def _event_to_vector(self, event: Dict[str, Any]) -> List[float]:
        vec = [0.0] * 20
        namespace_hash = hash(event.get("namespace", "")) % 1000 / 1000.0
        reason_hash = hash(event.get("reason", "")) % 1000 / 1000.0
        vec[0] = namespace_hash
        vec[1] = reason_hash
        return vec

    async def get_incident(self, incident_id: str) -> Optional[Incident]:
        return self.incidents.get(incident_id)

    async def get_recent_incidents(
        self, limit: int = 50, status: Optional[str] = None
    ) -> List[Incident]:
        incidents = list(self.incidents.values())
        if status:
            incidents = [i for i in incidents if i.status == status]
        return sorted(incidents, key=lambda x: x.created_at, reverse=True)[:limit]

    def _map_falco_priority(self, priority: str) -> str:
        mapping = {
            "emergency": "critical",
            "alert": "critical",
            "critical": "critical",
            "error": "high",
            "warning": "medium",
            "notice": "low",
            "informational": "low",
            "debug": "low",
        }
        return mapping.get(priority, "medium")
