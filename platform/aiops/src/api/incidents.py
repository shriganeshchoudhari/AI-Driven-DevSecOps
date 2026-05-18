import uuid
from datetime import datetime
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query

from src.engine import get_engine
from src.models.schemas import Incident, AnomalyResult

router = APIRouter(prefix="/incidents", tags=["incidents"])


@router.post("", response_model=Incident)
async def create_incident(
    incident: Incident,
    engine=Depends(get_engine),
):
    incident.id = incident.id or str(uuid.uuid4())
    engine.correlation.incidents[incident.id] = incident
    return incident


@router.get("", response_model=List[Incident])
async def list_incidents(
    status: Optional[str] = Query(None, description="Filter by status"),
    severity: Optional[str] = Query(None, description="Filter by severity"),
    service: Optional[str] = Query(None, description="Filter by service"),
    namespace: Optional[str] = Query(None, description="Filter by namespace"),
    limit: int = Query(50, ge=1, le=500),
    engine=Depends(get_engine),
):
    incidents = list(engine.correlation.incidents.values())

    if status:
        incidents = [i for i in incidents if i.status == status]
    if severity:
        incidents = [i for i in incidents if i.severity == severity]
    if service:
        incidents = [i for i in incidents if i.service == service]
    if namespace:
        incidents = [i for i in incidents if i.namespace == namespace]

    return sorted(incidents, key=lambda x: x.updated_at, reverse=True)[:limit]


@router.get("/{incident_id}", response_model=Incident)
async def get_incident(
    incident_id: str,
    engine=Depends(get_engine),
):
    incident = await engine.correlation.get_incident(incident_id)
    if not incident:
        raise HTTPException(status_code=404, detail=f"Incident {incident_id} not found")
    return incident


@router.post("/{incident_id}/analyze")
async def analyze_incident(
    incident_id: str,
    engine=Depends(get_engine),
):
    incident = await engine.correlation.get_incident(incident_id)
    if not incident:
        raise HTTPException(status_code=404, detail=f"Incident {incident_id} not found")

    incident.status = "analyzing"
    try:
        analysis = await engine.analyze_incident(incident_id)
        incident.ai_analysis = analysis
        incident.status = "analyzed"
    except Exception as e:
        incident.status = "detected"
        raise HTTPException(status_code=500, detail=f"Analysis failed: {str(e)}")

    return {
        "incident_id": incident_id,
        "status": "analyzed",
        "analysis": analysis,
    }


@router.post("/correlate")
async def correlate_incidents(
    engine=Depends(get_engine),
):
    clusters = await engine.correlation.run_clustering()
    return {
        "clusters_found": len(clusters),
        "clusters": clusters,
    }


@router.get("/clusters")
async def get_clusters(
    engine=Depends(get_engine),
):
    clusters = await engine.correlation.run_clustering()
    result = {}
    for cluster_id, incident_ids in clusters.items():
        result[cluster_id] = [
            {
                "id": iid,
                "title": engine.correlation.incidents.get(iid, Incident(title="unknown")).title,
                "severity": engine.correlation.incidents.get(iid, Incident(severity="low")).severity,
            }
            for iid in incident_ids
            if iid in engine.correlation.incidents
        ]
    return result


@router.get("/summary")
async def get_incident_summary(
    hours: int = Query(24, ge=1, le=720),
    engine=Depends(get_engine),
):
    cutoff = datetime.utcnow().timestamp() - hours * 3600
    recent = [
        i for i in engine.correlation.incidents.values()
        if i.created_at.timestamp() > cutoff
    ]

    by_severity: Dict[str, int] = {"critical": 0, "high": 0, "medium": 0, "low": 0}
    by_status: Dict[str, int] = {}

    for inc in recent:
        by_severity[inc.severity] = by_severity.get(inc.severity, 0) + 1
        by_status[inc.status] = by_status.get(inc.status, 0) + 1

    return {
        "total_incidents": len(recent),
        "time_range_hours": hours,
        "by_severity": by_severity,
        "by_status": by_status,
        "open_count": sum(
            1 for i in recent if i.status not in ("resolved", "closed")
        ),
    }
