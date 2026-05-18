from fastapi import APIRouter

router = APIRouter()

from src.api import events, incidents, analysis, remediation, security  # noqa: E402, F401


@router.get("/ping")
async def ping():
    return {"status": "pong"}
