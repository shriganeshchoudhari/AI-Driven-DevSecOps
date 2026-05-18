import os
import time
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, Response
from prometheus_client import Counter, Histogram, generate_latest
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
import sentry_sdk

from src.api import router as api_router
from src.engine import AIOpsEngine, setup_engine
from src.models.schemas import HealthResponse, VersionInfo
from src.config import settings

REQUEST_COUNT = Counter("aiops_requests_total", "Total requests", ["method", "endpoint", "status"])
REQUEST_DURATION = Histogram("aiops_request_duration_seconds", "Request duration", ["method", "endpoint"])
ANOMALY_COUNT = Counter("aiops_anomaly_detected_total", "Anomalies detected", ["severity", "source"])
INCIDENT_COUNT = Counter("aiops_incidents_total", "Incidents processed", ["severity", "status"])
REMEDIATION_COUNT = Counter("aiops_remediation_actions_total", "Remediation actions", ["action", "status"])
RCA_DURATION = Histogram("aiops_rca_duration_seconds", "RCA generation duration", [])

logging.basicConfig(
    level=getattr(logging, settings.LOG_LEVEL.upper()),
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)

if settings.SENTRY_DSN:
    sentry_sdk.init(dsn=settings.SENTRY_DSN, environment=settings.ENVIRONMENT)


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info(
        f"Starting AIOps Engine v{settings.VERSION} in {settings.ENVIRONMENT} mode"
    )
    await setup_engine(app)
    yield
    logger.info("Shutting down AIOps Engine")
    if app.state.engine:
        await app.state.engine.shutdown()


app = FastAPI(
    title="AIOps Platform Engine",
    description="AI-driven operations platform for incident correlation, RCA, anomaly detection, and remediation orchestration",
    version=settings.VERSION,
    lifespan=lifespan,
    docs_url="/docs" if settings.ENVIRONMENT != "prod" else None,
    redoc_url="/redoc" if settings.ENVIRONMENT != "prod" else None,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

FastAPIInstrumentor.instrument_app(app)


@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    start = time.time()
    response = await call_next(request)
    duration = time.time() - start
    REQUEST_COUNT.labels(
        method=request.method, endpoint=request.url.path, status=response.status_code
    ).inc()
    REQUEST_DURATION.labels(
        method=request.method, endpoint=request.url.path
    ).observe(duration)
    return response


app.include_router(api_router, prefix="/api/v1")


@app.get("/health", response_model=HealthResponse)
async def health():
    return HealthResponse(
        status="healthy",
        version=settings.VERSION,
        environment=settings.ENVIRONMENT,
        uptime=time.time() - settings.START_TIME,
    )


@app.get("/ready", response_model=HealthResponse)
async def ready():
    return HealthResponse(
        status="healthy",
        version=settings.VERSION,
        environment=settings.ENVIRONMENT,
        uptime=time.time() - settings.START_TIME,
    )


@app.get("/version", response_model=VersionInfo)
async def version():
    return VersionInfo(
        version=settings.VERSION,
        build_time=settings.BUILD_TIME,
        commit_sha=settings.COMMIT_SHA,
    )


@app.get("/metrics")
async def metrics():
    return Response(content=generate_latest(), media_type="text/plain")


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.exception(f"Unhandled exception: {exc}")
    return JSONResponse(
        status_code=500,
        content={
            "detail": "Internal server error",
            "request_id": request.headers.get("X-Request-ID", ""),
        },
    )
