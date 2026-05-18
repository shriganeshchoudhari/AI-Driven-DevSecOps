import logging
from collections import defaultdict, deque
from datetime import datetime
from typing import Any, Dict, List, Optional

import numpy as np
from sklearn.ensemble import IsolationForest
from sklearn.preprocessing import StandardScaler

from src.models.schemas import AnomalyResult

logger = logging.getLogger(__name__)


class MetricWindow:
    def __init__(self, window_size: int = 60):
        self.values: deque = deque(maxlen=window_size)
        self.timestamps: deque = deque(maxlen=window_size)

    def add(self, value: float, timestamp: datetime):
        self.values.append(value)
        self.timestamps.append(timestamp)

    @property
    def mean(self) -> float:
        if not self.values:
            return 0.0
        return float(np.mean(self.values))

    @property
    def std(self) -> float:
        if len(self.values) < 2:
            return 1.0
        return float(np.std(self.values))

    @property
    def is_ready(self) -> bool:
        return len(self.values) >= 10


class AnomalyDetectionService:
    def __init__(self):
        self.windows: Dict[str, MetricWindow] = defaultdict(lambda: MetricWindow(60))
        self.isolation_forest = IsolationForest(
            contamination=0.05, random_state=42, n_estimators=100
        )
        self.scaler = StandardScaler()
        self.training_data: List[List[float]] = []
        self.model_trained = False

    async def detect_batch(
        self, metrics: List[Dict[str, Any]]
    ) -> List[AnomalyResult]:
        results: List[AnomalyResult] = []

        for metric in metrics:
            key = f"{metric['name']}:{metric.get('service', 'unknown')}"
            ts = datetime.fromisoformat(metric["timestamp"])
            self.windows[key].add(metric["value"], ts)

            if self.windows[key].is_ready:
                result = self._detect_statistical(key, metric)
                if result:
                    results.append(result)

        if len(self.training_data) > 100:
            ml_results = await self._detect_ml_batch(metrics)
            results.extend(ml_results)

        return results

    def _detect_statistical(
        self, key: str, metric: Dict[str, Any]
    ) -> Optional[AnomalyResult]:
        window = self.windows[key]
        current = metric["value"]
        mean = window.mean
        std = window.std

        if std == 0:
            return None

        z_score = abs(current - mean) / std

        if z_score < 2.0:
            return None

        severity = "low"
        if z_score >= 5.0:
            severity = "critical"
        elif z_score >= 3.0:
            severity = "high"
        elif z_score >= 2.0:
            severity = "medium"

        return AnomalyResult(
            timestamp=datetime.fromisoformat(metric["timestamp"]),
            metric_name=metric["name"],
            current_value=current,
            expected_value=mean,
            deviation=float(z_score),
            anomaly_score=min(float(z_score) / 5.0, 1.0),
            severity=severity,
            service=metric.get("labels", {}).get("service", "unknown"),
            details={
                "method": "z-score",
                "window_size": len(window.values),
                "std": float(std),
                "mean": float(mean),
            },
        )

    async def _detect_ml_batch(
        self, metrics: List[Dict[str, Any]]
    ) -> List[AnomalyResult]:
        results: List[AnomalyResult] = []

        features = []
        for metric in metrics:
            service_hash = float(
                hash(metric.get("labels", {}).get("service", "unknown")) % 1000
            )
            features.append([metric["value"], service_hash])

        if len(features) < 10:
            return results

        X = np.array(features)

        if not self.model_trained:
            self.training_data.extend(X.tolist())
            if len(self.training_data) >= 100:
                X_train = np.array(self.training_data)
                X_scaled = self.scaler.fit_transform(X_train)
                self.isolation_forest.fit(X_scaled)
                self.model_trained = True
                logger.info("Isolation Forest model trained on %d samples", len(self.training_data))
            return results

        X_scaled = self.scaler.transform(X)
        predictions = self.isolation_forest.predict(X_scaled)

        for i, pred in enumerate(predictions):
            if pred == -1:
                scores = self.isolation_forest.score_samples(X_scaled)
                anomaly_score = min(abs(float(scores[i])) / 5.0, 1.0)

                results.append(
                    AnomalyResult(
                        timestamp=datetime.fromisoformat(metrics[i]["timestamp"]),
                        metric_name=metrics[i]["name"],
                        current_value=metrics[i]["value"],
                        expected_value=0.0,
                        deviation=0.0,
                        anomaly_score=anomaly_score,
                        severity="medium" if anomaly_score > 0.7 else "low",
                        service=metrics[i]
                        .get("labels", {})
                        .get("service", "unknown"),
                        details={
                            "method": "isolation-forest",
                            "anomaly_score": float(anomaly_score),
                        },
                    )
                )

        return results

    async def detect_metric_anomalies(
        self, events: List
    ) -> List[AnomalyResult]:
        normalized = []
        for event in events:
            normalized.append(
                {
                    "name": event.name,
                    "value": event.value,
                    "timestamp": event.timestamp.isoformat(),
                    "service": event.labels.get("service", "unknown"),
                    "labels": event.labels,
                }
            )
        return await self.detect_batch(normalized)
