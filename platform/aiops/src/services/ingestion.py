import hashlib
import json
import logging
from datetime import datetime
from typing import Any, Dict, List, Optional

from src.models.schemas import (
    FalcoAlert,
    K8sEvent,
    LogEvent,
    MetricEvent,
    TraceEvent,
)
from src.services.anomaly import AnomalyDetectionService
from src.services.correlation import IncidentCorrelationService
from src.services.vectorstore import VectorStoreService

logger = logging.getLogger(__name__)


class DeduplicationCache:
    def __init__(self, ttl_seconds: int = 300):
        self.cache: Dict[str, datetime] = {}
        self.ttl = ttl_seconds

    def is_duplicate(self, key: str) -> bool:
        now = datetime.utcnow()
        if key in self.cache:
            if (now - self.cache[key]).total_seconds() < self.ttl:
                return True
        self.cache[key] = now
        return False

    def make_key(self, event) -> str:
        raw = f"{event.timestamp.isoformat()}:{event.__class__.__name__}:{hash(str(event.dict()))}"
        return hashlib.md5(raw.encode()).hexdigest()


class EventNormalizer:
    @staticmethod
    def normalize_log(log: LogEvent) -> dict:
        return {
            "timestamp": log.timestamp.isoformat(),
            "service": log.service,
            "namespace": log.namespace,
            "pod": log.pod,
            "level": log.level.upper(),
            "message": log.message,
            "source": "kubernetes",
            "structured_data": log.structured_data,
        }

    @staticmethod
    def normalize_metric(metric: MetricEvent) -> dict:
        return {
            "timestamp": metric.timestamp.isoformat(),
            "name": metric.name,
            "value": metric.value,
            "labels": metric.labels,
            "source": "prometheus",
        }

    @staticmethod
    def normalize_trace(trace: TraceEvent) -> dict:
        return {
            "trace_id": trace.trace_id,
            "span_id": trace.span_id,
            "parent_span_id": trace.parent_span_id,
            "service": trace.service,
            "operation": trace.operation,
            "duration_ms": trace.duration_ms,
            "status": trace.status,
            "tags": trace.tags,
            "timestamp": trace.timestamp.isoformat(),
        }


class IngestionService:
    def __init__(
        self,
        anomaly_service: AnomalyDetectionService,
        correlation_service: IncidentCorrelationService,
        vectorstore: VectorStoreService,
    ):
        self.dedup = DeduplicationCache()
        self.normalizer = EventNormalizer()
        self.anomaly = anomaly_service
        self.correlation = correlation_service
        self.vectorstore = vectorstore
        self.log_buffer: List[dict] = []
        self.metric_buffer: List[dict] = []

    async def process_logs(self, events: List[LogEvent]):
        normalized = []
        for event in events:
            key = self.dedup.make_key(event)
            if not self.dedup.is_duplicate(key):
                normalized.append(self.normalizer.normalize_log(event))

        if normalized:
            self.log_buffer.extend(normalized)
            await self._flush_logs_if_needed()
            logger.debug(
                f"Ingested {len(normalized)} log events "
                f"(filtered {len(events) - len(normalized)} duplicates)"
            )

    async def process_metrics(self, events: List[MetricEvent]):
        normalized = []
        for event in events:
            key = self.dedup.make_key(event)
            if not self.dedup.is_duplicate(key):
                normalized.append(self.normalizer.normalize_metric(event))

        if normalized:
            self.metric_buffer.extend(normalized)
            await self._flush_metrics_if_needed()

    async def process_traces(self, events: List[TraceEvent]):
        for event in events:
            key = self.dedup.make_key(event)
            if not self.dedup.is_duplicate(key):
                await self.vectorstore.store_trace(self.normalizer.normalize_trace(event))

    async def process_security_alert(self, alert: FalcoAlert):
        normalized = alert.dict()
        await self.vectorstore.store_security_event(normalized)

        if alert.priority in ("emergency", "alert", "critical"):
            await self.correlation.create_security_incident(alert)

    async def _flush_logs_if_needed(self):
        if len(self.log_buffer) >= 100:
            await self.vectorstore.store_logs_batch(self.log_buffer[:100])
            self.log_buffer = self.log_buffer[100:]

    async def _flush_metrics_if_needed(self):
        if len(self.metric_buffer) >= 1000:
            self.metric_buffer.clear()
