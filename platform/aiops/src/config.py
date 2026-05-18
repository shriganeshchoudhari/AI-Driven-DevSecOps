import time
from typing import List, Optional

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    VERSION: str = "1.0.0"
    BUILD_TIME: str = "2024-01-01T00:00:00Z"
    COMMIT_SHA: str = "development"
    ENVIRONMENT: str = "development"
    LOG_LEVEL: str = "INFO"
    DEBUG: bool = False
    CORS_ORIGINS: List[str] = ["*"]
    START_TIME: float = time.time()

    OPENAI_API_KEY: str = ""
    OPENAI_MODEL: str = "gpt-4"
    OLLAMA_BASE_URL: str = "http://ollama:11434"
    OLLAMA_MODEL: str = "llama2"
    LLM_PROVIDER: str = "openai"
    EMBEDDING_MODEL: str = "text-embedding-ada-002"
    MAX_TOKENS: int = 2000
    TEMPERATURE: float = 0.1

    VECTOR_DB_TYPE: str = "chroma"
    VECTOR_DB_PATH: str = "/data/vectorstore"
    COLLECTION_NAME: str = "aiops-incidents"
    CHUNK_SIZE: int = 500
    CHUNK_OVERLAP: int = 50

    LOG_INGESTION_BATCH_SIZE: int = 100
    METRIC_INGESTION_BATCH_SIZE: int = 1000
    TRACE_INGESTION_BATCH_SIZE: int = 50
    EVENT_INGESTION_BATCH_SIZE: int = 50

    ANOMALY_THRESHOLD: float = 2.0
    ANOMALY_WINDOW_SIZE: int = 60
    ANOMALY_SLIDING_STEP: int = 5

    CORRELATION_WINDOW: int = 3600
    CORRELATION_SIMILARITY_THRESHOLD: float = 0.7
    CLUSTERING_EPS: float = 0.3
    CLUSTERING_MIN_SAMPLES: int = 2

    REMEDIATION_CONFIDENCE_THRESHOLD: float = 0.8
    AUTO_REMEDIATION_ENABLED: bool = False
    MAX_REMEDIATION_ACTIONS: int = 3
    REMEDIATION_APPROVAL_REQUIRED: bool = True

    API_KEY: str = ""
    ALLOWED_HOSTS: List[str] = ["*"]

    SLACK_WEBHOOK_URL: str = ""
    PAGERDUTY_API_KEY: str = ""
    PAGERDUTY_SERVICE_ID: str = ""
    OPSGENIE_API_KEY: str = ""

    DATABASE_URL: str = "postgresql+asyncpg://postgres:postgres@postgres:5432/aiops"
    REDIS_URL: str = "redis://redis:6379/0"

    SENTRY_DSN: str = ""

    KUBERNETES_ENABLED: bool = True
    KUBERNETES_NAMESPACE: str = "aiops-engine"
    KUBERNETES_IN_CLUSTER: bool = True

    class Config:
        env_file = ".env"
        case_sensitive = True


settings = Settings()
