from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    VERSION: str = "1.0.0"
    ENVIRONMENT: str = "development"
    NAMESPACE: str = "payment-service"
    LOG_LEVEL: str = "INFO"
    OTLP_ENDPOINT: str = "http://tempo.monitoring:4317"

    DATABASE_URL: str = "sqlite:///./payments.db"
    REDIS_URL: str = "redis://redis.cache:6379/0"

    STRIPE_API_KEY: str = "sk_test_mock_stripe_key"
    STRIPE_WEBHOOK_SECRET: str = "whsec_mock_webhook_secret"
    PAYPAL_CLIENT_ID: str = "mock_paypal_client"
    PAYPAL_CLIENT_SECRET: str = "mock_paypal_secret"

    DEFAULT_CURRENCY: str = "USD"
    MAX_REFUND_DAYS: int = 90
    IDEMPOTENCY_TTL_HOURS: int = 24
    PROCESSING_FEE_PERCENT: float = 2.9
    PROCESSING_FEE_FLAT: float = 0.30

    class Config:
        env_file = ".env"
        case_sensitive = True


@lru_cache()
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
