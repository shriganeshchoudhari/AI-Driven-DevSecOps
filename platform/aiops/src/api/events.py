from fastapi import APIRouter, Depends, BackgroundTasks
from typing import List

from src.engine import get_engine
from src.models.schemas import LogEvent, MetricEvent, TraceEvent, K8sEvent, FalcoAlert, SecurityAlert

router = APIRouter(prefix="/events", tags=["events"])


@router.post("/logs")
async def ingest_logs(
    events: List[LogEvent],
    background_tasks: BackgroundTasks,
    engine=Depends(get_engine),
):
    background_tasks.add_task(engine.process_logs, events)
    return {"status": "accepted", "count": len(events)}


@router.post("/metrics")
async def ingest_metrics(
    events: List[MetricEvent],
    background_tasks: BackgroundTasks,
    engine=Depends(get_engine),
):
    background_tasks.add_task(engine.process_metrics, events)
    return {"status": "accepted", "count": len(events)}


@router.post("/traces")
async def ingest_traces(
    events: List[TraceEvent],
    background_tasks: BackgroundTasks,
    engine=Depends(get_engine),
):
    background_tasks.add_task(engine.process_traces, events)
    return {"status": "accepted", "count": len(events)}


@router.post("/kubernetes")
async def ingest_k8s_events(
    events: List[K8sEvent],
    background_tasks: BackgroundTasks,
    engine=Depends(get_engine),
):
    background_tasks.add_task(engine.process_k8s_events, events)
    return {"status": "accepted", "count": len(events)}


@router.post("/security/falco")
async def ingest_falco_alert(
    alert: FalcoAlert,
    background_tasks: BackgroundTasks,
    engine=Depends(get_engine),
):
    background_tasks.add_task(engine.process_security_alert, alert)
    return {"status": "accepted", "alert_id": alert.rule}


@router.post("/security")
async def ingest_security_alert(
    alert: SecurityAlert,
    background_tasks: BackgroundTasks,
    engine=Depends(get_engine),
):
    background_tasks.add_task(engine.process_custom_security_alert, alert)
    return {"status": "accepted", "alert_type": alert.alert_type}
