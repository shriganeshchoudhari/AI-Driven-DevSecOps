from datetime import datetime
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException

from src.engine import get_engine
from src.models.schemas import Incident, RCAResult, AnomalyResult

router = APIRouter(prefix="/analysis", tags=["analysis"])


@router.post("/rca", response_model=RCAResult)
async def generate_rca(
    incident_id: str,
    engine=Depends(get_engine),
):
    incident = await engine.correlation.get_incident(incident_id)
    if not incident:
        raise HTTPException(status_code=404, detail=f"Incident {incident_id} not found")

    rca = await engine.llm.generate_rca(incident)
    return rca


@router.post("/summarize")
async def summarize_incidents(
    incident_ids: List[str],
    engine=Depends(get_engine),
):
    incidents: List[Incident] = []
    for iid in incident_ids:
        inc = await engine.correlation.get_incident(iid)
        if inc:
            incidents.append(inc)

    if not incidents:
        raise HTTPException(status_code=404, detail="No valid incidents found")

    summary = await engine.llm.summarize(incidents)
    return {"summary": summary, "incidents_analyzed": len(incidents)}


@router.post("/anomaly", response_model=List[AnomalyResult])
async def detect_anomalies(
    metric_name: str,
    service: Optional[str] = None,
    hours: int = 1,
    engine=Depends(get_engine),
):
    cutoff = datetime.utcnow().timestamp() - hours * 3600
    candidates = []

    for key, window in engine.anomaly.windows.items():
        key_name, key_service = key.split(":", 1) if ":" in key else (key, "")
        if key_name == metric_name and (not service or key_service == service):
            for val, ts in zip(window.values, window.timestamps):
                if ts.timestamp() > cutoff:
                    candidates.append({
                        "name": key_name,
                        "value": val,
                        "timestamp": ts.isoformat(),
                        "service": key_service,
                        "labels": {},
                    })

    if not candidates:
        raise HTTPException(status_code=404, detail="No metric data found for the given criteria")

    results = await engine.anomaly.detect_batch(candidates)
    return results


@router.post("/forecast")
async def forecast_metrics(
    metric_name: str,
    service: str,
    horizon_minutes: int = 30,
    engine=Depends(get_engine),
):
    key = f"{metric_name}:{service}"
    window = engine.anomaly.windows.get(key)

    if not window or len(window.values) < 10:
        raise HTTPException(
            status_code=400,
            detail=f"Insufficient data for {key}. Need at least 10 data points.",
        )

    values = list(window.values)
    n = len(values)

    # Simple linear regression forecast
    x = list(range(n))
    x_mean = sum(x) / n
    y_mean = sum(values) / n
    numerator = sum((xi - x_mean) * (yi - y_mean) for xi, yi in zip(x, values))
    denominator = sum((xi - x_mean) ** 2 for xi in x)
    slope = numerator / denominator if denominator != 0 else 0
    intercept = y_mean - slope * x_mean

    forecast_points = []
    for step in range(1, horizon_minutes + 1):
        pred = slope * (n + step - 1) + intercept
        forecast_points.append({
            "step": step,
            "predicted_value": round(pred, 4),
            "confidence_upper": round(pred + 2 * float(window.std), 4),
            "confidence_lower": round(pred - 2 * float(window.std), 4),
        })

    return {
        "metric": metric_name,
        "service": service,
        "horizon_minutes": horizon_minutes,
        "current_trend": "up" if slope > 0 else "down",
        "slope": round(slope, 6),
        "forecast": forecast_points,
    }


@router.post("/similar")
async def find_similar_incidents(
    incident_id: str,
    limit: int = 5,
    engine=Depends(get_engine),
):
    incident = await engine.correlation.get_incident(incident_id)
    if not incident:
        raise HTTPException(status_code=404, detail=f"Incident {incident_id} not found")

    similar = await engine.vectorstore.search_similar_incidents(incident, n_results=limit)
    return {"incident_id": incident_id, "similar_incidents": similar}


@router.post("/impact")
async def analyze_impact(
    incident_id: str,
    engine=Depends(get_engine),
):
    incident = await engine.correlation.get_incident(incident_id)
    if not incident:
        raise HTTPException(status_code=404, detail=f"Incident {incident_id} not found")

    affected_services = set()
    affected_namespaces = set()
    total_events = len(incident.events)
    total_alerts = len(incident.alerts)

    for evt in incident.events:
        if evt.get("service"):
            affected_services.add(evt["service"])
        if evt.get("namespace"):
            affected_namespaces.add(evt["namespace"])

    for alert in incident.alerts:
        if alert.get("namespace"):
            affected_namespaces.add(alert["namespace"])
        if alert.get("affected_resource"):
            affected_services.add(alert["affected_resource"])

    return {
        "incident_id": incident_id,
        "blast_radius": {
            "affected_services": list(affected_services),
            "affected_namespaces": list(affected_namespaces),
            "event_count": total_events,
            "alert_count": total_alerts,
        },
        "severity": incident.severity,
        "duration_hours": round(
            (datetime.utcnow() - incident.created_at).total_seconds() / 3600, 2
        ) if incident.created_at else 0,
    }
