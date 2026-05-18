from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    VERSION: str = "1.0.0"
    ENVIRONMENT: str = "development"
    NAMESPACE: str = "notification-service"
    LOG_LEVEL: str = "INFO"
    OTLP_ENDPOINT: str = "http://tempo.monitoring:4317"

    DATABASE_URL: str = "sqlite:///./notifications.db"
    REDIS_URL: str = "redis://redis.cache:6379/0"

    SMTP_HOST: str = "mailhog.notification:1025"
    SMTP_PORT: int = 1025
    SMTP_USERNAME: str = ""
    SMTP_PASSWORD: str = ""
    SMTP_FROM_ADDRESS: str = "noreply@platform.local"
    SMTP_FROM_NAME: str = "GitOps Platform"

    AWS_SES_ENDPOINT: str = "http://localstack.notification:4566"
    AWS_SNS_ENDPOINT: str = "http://localstack.notification:4566"
    AWS_REGION: str = "us-east-1"
    AWS_ACCESS_KEY_ID: str = "mock-key"
    AWS_SECRET_ACCESS_KEY: str = "mock-secret"

    MAX_RETRIES: int = 3
    RETRY_BACKOFF_SECONDS: int = 5

    class Config:
        env_file = ".env"
        case_sensitive = True


@lru_cache()
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
