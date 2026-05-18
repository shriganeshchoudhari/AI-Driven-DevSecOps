import logging
import uuid
from datetime import datetime
from typing import Any, Dict, List

import chromadb
from chromadb.config import Settings as ChromaSettings

from src.config import settings

logger = logging.getLogger(__name__)


class DummyEmbeddingFunction:
    def __call__(self, input: List[str]) -> List[List[float]]:
        return [[0.0] * 384 for _ in input]


class VectorStoreService:
    def __init__(self):
        self.client = None
        self.incident_collection = None
        self.log_collection = None
        self.security_collection = None

    async def initialize(self):
        self.client = chromadb.PersistentClient(
            path=settings.VECTOR_DB_PATH,
            settings=ChromaSettings(
                anonymized_telemetry=False, allow_reset=False
            ),
        )

        dummy_ef = DummyEmbeddingFunction()

        self.incident_collection = self.client.get_or_create_collection(
            name="aiops-incidents",
            metadata={"description": "Historical incidents for similarity search"},
            embedding_function=dummy_ef
        )

        self.log_collection = self.client.get_or_create_collection(
            name="aiops-logs",
            metadata={"description": "Log event embeddings for context retrieval"},
            embedding_function=dummy_ef
        )

        self.security_collection = self.client.get_or_create_collection(
            name="aiops-security",
            metadata={"description": "Security event embeddings"},
            embedding_function=dummy_ef
        )

        logger.info(f"Vector store initialized at {settings.VECTOR_DB_PATH}")

    async def close(self):
        if self.client:
            self.client = None

    async def store_incident(self, incident: Dict[str, Any]) -> str:
        doc_id = str(uuid.uuid4())
        text = f"{incident.get('title', '')} {incident.get('description', '')}"

        metadata = {
            "id": incident.get("id", ""),
            "severity": incident.get("severity", "medium"),
            "status": incident.get("status", "open"),
            "service": incident.get("service", "unknown"),
            "timestamp": incident.get(
                "created_at", datetime.utcnow().isoformat()
            ),
            "type": "incident",
        }

        self.incident_collection.add(
            documents=[text], metadatas=[metadata], ids=[doc_id]
        )

        return doc_id

    async def store_logs_batch(self, logs: List[Dict[str, Any]]):
        if not logs:
            return

        documents = []
        metadatas = []
        ids = []

        for log in logs:
            doc_id = str(uuid.uuid4())
            documents.append(
                f"[{log.get('level', 'INFO')}] {log.get('service', '')}: {log.get('message', '')}"
            )
            metadatas.append(
                {
                    "service": log.get("service", ""),
                    "namespace": log.get("namespace", ""),
                    "level": log.get("level", "INFO"),
                    "timestamp": log.get("timestamp", ""),
                    "type": "log",
                }
            )
            ids.append(doc_id)

        self.log_collection.add(
            documents=documents, metadatas=metadatas, ids=ids
        )

    async def store_security_event(self, event: Dict[str, Any]) -> str:
        doc_id = str(uuid.uuid4())
        text = f"{event.get('rule', '')} {event.get('output', '')}"

        self.security_collection.add(
            documents=[text],
            metadatas=[
                {
                    "rule": event.get("rule", ""),
                    "priority": event.get("priority", ""),
                    "namespace": event.get("namespace", ""),
                    "pod": event.get("pod", ""),
                    "timestamp": event.get("timestamp", ""),
                    "type": "security",
                }
            ],
            ids=[doc_id],
        )

        return doc_id

    async def store_trace(self, trace: Dict[str, Any]) -> str:
        doc_id = str(uuid.uuid4())
        text = (
            f"Trace {trace.get('trace_id', '')}: {trace.get('service', '')} - "
            f"{trace.get('operation', '')} ({trace.get('duration_ms', 0)}ms)"
        )

        self.log_collection.add(
            documents=[text],
            metadatas=[
                {
                    "trace_id": trace.get("trace_id", ""),
                    "service": trace.get("service", ""),
                    "operation": trace.get("operation", ""),
                    "duration_ms": trace.get("duration_ms", 0),
                    "status": trace.get("status", "ok"),
                    "type": "trace",
                }
            ],
            ids=[doc_id],
        )

        return doc_id

    async def search_similar_incidents(
        self, incident, n_results: int = 5
    ) -> List[Dict[str, Any]]:
        query_text = (
            f"{incident.title} {incident.description}"
            if hasattr(incident, "title")
            else str(incident)
        )

        if not self.incident_collection:
            return []

        try:
            results = self.incident_collection.query(
                query_texts=[query_text], n_results=n_results
            )

            similar = []
            if results.get("metadatas") and results["metadatas"][0]:
                for i in range(len(results["metadatas"][0])):
                    similar.append(
                        {
                            "metadata": results["metadatas"][0][i],
                            "score": float(results["distances"][0][i])
                            if results.get("distances")
                            else 0.0,
                            "text": results["documents"][0][i]
                            if results.get("documents")
                            else "",
                        }
                    )

            return similar
        except Exception as e:
            logger.error(f"Error searching similar incidents: {e}")
            return []

    async def get_context_for_analysis(
        self, query: str, n_results: int = 5
    ) -> str:
        contexts = []

        try:
            log_results = self.log_collection.query(
                query_texts=[query], n_results=n_results
            )
            if log_results.get("documents") and log_results["documents"][0]:
                for doc in log_results["documents"][0]:
                    contexts.append(f"[Log] {doc}")
        except Exception:
            pass

        try:
            incident_results = self.incident_collection.query(
                query_texts=[query], n_results=n_results
            )
            if (
                incident_results.get("documents")
                and incident_results["documents"][0]
            ):
                for doc in incident_results["documents"][0]:
                    contexts.append(f"[Incident] {doc}")
        except Exception:
            pass

        try:
            security_results = self.security_collection.query(
                query_texts=[query], n_results=n_results
            )
            if (
                security_results.get("documents")
                and security_results["documents"][0]
            ):
                for doc in security_results["documents"][0]:
                    contexts.append(f"[Security] {doc}")
        except Exception:
            pass

        return "\n".join(contexts[:10])
