import time
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.resources import Resource
import httpx

from src.config import settings
from src.routes import health, api

logging.basicConfig(level=getattr(logging, settings.LOG_LEVEL))
logger = logging.getLogger(__name__)

resource = Resource.create({
    "service.name": "frontend-service",
    "service.version": settings.VERSION,
    "deployment.environment": settings.ENVIRONMENT,
})

tracer_provider = TracerProvider(resource=resource)
if settings.OTLP_ENDPOINT:
    otlp_exporter = OTLPSpanExporter(endpoint=settings.OTLP_ENDPOINT, insecure=True)
    tracer_provider.add_span_processor(BatchSpanProcessor(otlp_exporter))
trace.set_tracer_provider(tracer_provider)
tracer = trace.get_tracer(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info(f"Frontend Service v{settings.VERSION} starting in {settings.ENVIRONMENT} mode")
    app.state.http_client = httpx.AsyncClient(
        timeout=30.0,
        limits=httpx.Limits(max_keepalive_connections=20, max_connections=100),
    )
    app.state.auth_url = f"http://auth-service.{settings.NAMESPACE}:8080"
    app.state.payment_url = f"http://payment-service.{settings.NAMESPACE}:8080"
    yield
    await app.state.http_client.aclose()


app = FastAPI(
    title="Frontend Service",
    version=settings.VERSION,
    lifespan=lifespan,
    docs_url="/docs" if settings.ENVIRONMENT != "prod" else None,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

FastAPIInstrumentor.instrument_app(app)
HTTPXClientInstrumentor().instrument()

app.include_router(health.router)
app.include_router(api.router, prefix="/api/v1")


@app.middleware("http")
async def add_trace_headers(request: Request, call_next):
    span = trace.get_current_span()
    trace_id = format(span.get_span_context().trace_id, "032x") if span else ""
    response = await call_next(request)
    response.headers["X-Trace-ID"] = trace_id
    return response
