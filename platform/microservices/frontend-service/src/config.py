from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    VERSION: str = "1.0.0"
    ENVIRONMENT: str = "development"
    NAMESPACE: str = "frontend-service"
    LOG_LEVEL: str = "INFO"
    OTLP_ENDPOINT: str = "http://tempo.monitoring:4317"
    DATABASE_URL: str = ""
    REDIS_URL: str = ""

    AUTH_SERVICE_URL: str = "http://auth-service.frontend-service:8080"
    AUTH_API_KEY: str = ""

    PAYMENT_SERVICE_URL: str = "http://payment-service.frontend-service:8080"

    ENABLE_CIRCUIT_BREAKER: bool = True
    REQUEST_TIMEOUT: int = 30
    MAX_RETRIES: int = 3

    class Config:
        env_file = ".env"
        case_sensitive = True


@lru_cache()
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
