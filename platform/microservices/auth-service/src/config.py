from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    VERSION: str = "1.0.0"
    ENVIRONMENT: str = "development"
    NAMESPACE: str = "auth-service"
    LOG_LEVEL: str = "INFO"
    OTLP_ENDPOINT: str = "http://tempo.monitoring:4317"

    DATABASE_URL: str = "sqlite:///./auth.db"
    REDIS_URL: str = "redis://redis.cache:6379/0"
    SECRET_KEY: str = "change-me-in-production-use-a-real-secret"
    JWT_ALGORITHM: str = "HS256"
    JWT_EXPIRATION_MINUTES: int = 60
    JWT_REFRESH_EXPIRATION_DAYS: int = 7
    BCRYPT_ROUNDS: int = 12
    API_KEY_LENGTH: int = 32
    RATE_LIMIT_PER_MINUTE: int = 100

    class Config:
        env_file = ".env"
        case_sensitive = True


@lru_cache()
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
