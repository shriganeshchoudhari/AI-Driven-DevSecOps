from fastapi import APIRouter
from datetime import datetime, timezone
router = APIRouter()


@router.get("/health")
async def health():
    return {
        "status": "healthy",
        "service": "frontend-service",
        "version": "1.0.0",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@router.get("/ready")
async def readiness():
    return {"status": "ready", "timestamp": datetime.now(timezone.utc).isoformat()}
