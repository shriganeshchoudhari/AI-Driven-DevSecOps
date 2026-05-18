from datetime import datetime
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, Query

from src.engine import get_engine
from src.models.schemas import FalcoAlert, SecurityAlert

router = APIRouter(prefix="/security", tags=["security"])


@router.post("/alerts")
async def ingest_security_alert(
    alert: SecurityAlert,
    engine=Depends(get_engine),
):
    await engine.process_custom_security_alert(alert)
    return {"status": "accepted", "alert_type": alert.alert_type, "severity": alert.severity}


@router.post("/alerts/falco")
async def ingest_falco_alert(
    alert: FalcoAlert,
    engine=Depends(get_engine),
):
    await engine.process_security_alert(alert)
    return {
        "status": "accepted",
        "rule": alert.rule,
        "priority": alert.priority,
    }


@router.get("/alerts")
async def list_security_alerts(
    severity: Optional[str] = Query(None),
    source: Optional[str] = Query(None),
    limit: int = Query(50, ge=1, le=500),
    engine=Depends(get_engine),
):
    alerts = list(engine.security_alerts)

    if severity:
        alerts = [a for a in alerts if a.get("severity") == severity or a.get("priority") == severity]
    if source:
        alerts = [a for a in alerts if a.get("source") == source]

    return sorted(alerts, key=lambda x: x.get("timestamp", ""), reverse=True)[:limit]


@router.get("/threats")
async def get_threat_intelligence(
    engine=Depends(get_engine),
):
    alerts = list(engine.security_alerts)
    critical = [a for a in alerts if a.get("priority") in ("emergency", "alert", "critical") or a.get("severity") == "critical"]
    high = [a for a in alerts if a.get("priority") == "error" or a.get("severity") == "high"]

    threat_summary = {
        "total_alerts": len(alerts),
        "critical_alerts": len(critical),
        "high_alerts": len(high),
        "unique_rules": len(set(a.get("rule", "") for a in alerts if a.get("rule"))),
        "affected_namespaces": list(set(a.get("namespace", "") for a in alerts if a.get("namespace"))),
        "recent_critical": [
            {
                "rule": a.get("rule", a.get("alert_type", "unknown")),
                "timestamp": a.get("timestamp", ""),
                "namespace": a.get("namespace", ""),
                "pod": a.get("pod", ""),
            }
            for a in critical[:10]
        ],
    }

    if critical and engine.llm:
        summary = await engine.llm.analyze_threats(critical[:10])
        threat_summary["ai_assessment"] = summary

    return threat_summary


@router.post("/analyze")
async def analyze_security_event(
    alert_ids: List[str],
    engine=Depends(get_engine),
):
    selected = []
    for alert in engine.security_alerts:
        alert_id = alert.get("id") or alert.get("rule", "")
        if alert_id in alert_ids or alert.get("rule") in alert_ids:
            selected.append(alert)

    if not selected:
        return {"analysis": "No matching alerts found", "alerts_analyzed": 0}

    analysis = await engine.llm.analyze_threats(selected)
    return {
        "analysis": analysis,
        "alerts_analyzed": len(selected),
    }
