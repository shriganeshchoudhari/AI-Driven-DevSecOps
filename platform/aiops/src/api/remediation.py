import uuid
from datetime import datetime
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query

from src.engine import get_engine
from src.models.schemas import RemediationAction

router = APIRouter(prefix="/remediation", tags=["remediation"])


@router.post("/suggest")
async def suggest_remediation(
    incident_id: str,
    engine=Depends(get_engine),
):
    incident = await engine.correlation.get_incident(incident_id)
    if not incident:
        raise HTTPException(status_code=404, detail=f"Incident {incident_id} not found")

    suggestions = await engine.remediation.suggest_actions(incident)

    # Persist suggestions as pending actions
    for s in suggestions:
        action = RemediationAction(
            id=str(uuid.uuid4()),
            incident_id=incident_id,
            action=s["action"],
            description=s["description"],
            confidence=s["confidence"],
            target_resource=s.get("target_resource", ""),
            target_namespace=incident.namespace or "",
            status="pending",
            requires_approval=s.get("requires_approval", True),
            automation_allowed=s.get("automation_allowed", False),
        )
        engine.remediation.actions[action.id] = action
        s["action_id"] = action.id

    return {
        "incident_id": incident_id,
        "suggestions": suggestions,
        "count": len(suggestions),
    }


@router.post("/execute")
async def execute_remediation(
    action_id: str,
    approved_by: Optional[str] = None,
    engine=Depends(get_engine),
):
    action = engine.remediation.actions.get(action_id)
    if not action:
        raise HTTPException(status_code=404, detail=f"Action {action_id} not found")

    if action.requires_approval and not approved_by:
        raise HTTPException(
            status_code=400,
            detail="This action requires approval. Provide approved_by parameter.",
        )

    result = await engine.remediation.execute_action(action_id, approved_by)
    return result


@router.get("/actions")
async def list_actions(
    engine=Depends(get_engine),
):
    return [
        {
            "action": name,
            "description": info["description"],
            "requires_approval": info["requires_approval"],
            "automation_allowed": info["automation_allowed"],
        }
        for name, info in engine.remediation.remediation_catalog.items()
    ]


@router.get("/history")
async def get_remediation_history(
    incident_id: Optional[str] = Query(None),
    status: Optional[str] = Query(None),
    limit: int = Query(50, ge=1, le=500),
    engine=Depends(get_engine),
):
    actions = list(engine.remediation.actions.values())

    if incident_id:
        actions = [a for a in actions if a.incident_id == incident_id]
    if status:
        actions = [a for a in actions if a.status == status]

    return sorted(actions, key=lambda x: x.created_at, reverse=True)[:limit]


@router.post("/approve")
async def approve_remediation(
    action_id: str,
    approved_by: str,
    engine=Depends(get_engine),
):
    action = engine.remediation.actions.get(action_id)
    if not action:
        raise HTTPException(status_code=404, detail=f"Action {action_id} not found")

    if action.status != "pending":
        raise HTTPException(
            status_code=400,
            detail=f"Action is in status '{action.status}', expected 'pending'",
        )

    action.status = "approved"
    action.approved_by = approved_by
    return {
        "action_id": action_id,
        "status": "approved",
        "approved_by": approved_by,
    }


@router.post("/rollback")
async def rollback_remediation(
    action_id: str,
    engine=Depends(get_engine),
):
    action = engine.remediation.actions.get(action_id)
    if not action:
        raise HTTPException(status_code=404, detail=f"Action {action_id} not found")

    if action.status not in ("completed", "in_progress"):
        raise HTTPException(
            status_code=400,
            detail=f"Action status '{action.status}' cannot be rolled back",
        )

    action.status = "rolled_back"
    return {
        "action_id": action_id,
        "previous_status": action.status,
        "status": "rolled_back",
    }
