import time
import logging
from typing import Optional, Dict, Any

import httpx
from opentelemetry import trace

from src.config import settings

logger = logging.getLogger(__name__)
tracer = trace.get_tracer(__name__)


class CircuitOpenError(Exception):
    pass


class AuthService:
    def __init__(self, client: httpx.AsyncClient, base_url: str):
        self.client = client
        self.base_url = base_url
        self._circuit_failures = 0
        self._circuit_open_until = 0.0

    def _circuit_allowed(self) -> bool:
        if not settings.ENABLE_CIRCUIT_BREAKER:
            return True
        if time.time() < self._circuit_open_until:
            return False
        return True

    def _record_success(self) -> None:
        self._circuit_failures = 0
        self._circuit_open_until = 0.0

    def _record_failure(self) -> None:
        self._circuit_failures += 1
        if self._circuit_failures >= 5:
            self._circuit_open_until = time.time() + 30.0
            logger.warning("Auth service circuit breaker opened for 30s")

    async def get_user(self, user_id: str) -> Optional[Dict[str, Any]]:
        with tracer.start_as_current_span("auth.get_user") as span:
            span.set_attribute("user_id", user_id)
            if not self._circuit_allowed():
                span.set_attribute("circuit_breaker", "open")
                logger.error("Circuit breaker open, skipping auth request")
                return None

            last_error = None
            for attempt in range(settings.MAX_RETRIES):
                try:
                    response = await self.client.get(
                        f"{self.base_url}/api/v1/users/{user_id}",
                        headers={"X-API-Key": settings.AUTH_API_KEY},
                        timeout=settings.REQUEST_TIMEOUT,
                    )
                    if response.status_code == 404:
                        return None
                    response.raise_for_status()
                    self._record_success()
                    return response.json()
                except httpx.TimeoutException as e:
                    last_error = e
                    logger.warning(f"Auth timeout attempt {attempt + 1}/{settings.MAX_RETRIES}")
                except httpx.HTTPError as e:
                    last_error = e
                    logger.error(f"Auth HTTP error: {e}")
                    break
                except Exception as e:
                    last_error = e
                    logger.error(f"Auth unexpected error: {e}")
                    break

            self._record_failure()
            span.record_exception(last_error)
            return None

    async def validate_user(self, user_id: str) -> bool:
        user = await self.get_user(user_id)
        return user is not None and user.get("is_active", True)
