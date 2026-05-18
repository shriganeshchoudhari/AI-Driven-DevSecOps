import time
import logging
import json
from typing import Optional, Dict, Any
from urllib.parse import urljoin

import httpx
from opentelemetry import trace

from src.config import settings

logger = logging.getLogger(__name__)
tracer = trace.get_tracer(__name__)


class CircuitOpenError(Exception):
    pass


class PaymentService:
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
            logger.warning("Payment service circuit breaker opened for 30s")

    async def process_payment(
        self,
        user_id: str,
        product_id: str,
        quantity: int = 1,
        currency: str = "USD",
    ) -> Optional[Dict[str, Any]]:
        with tracer.start_as_current_span("payment.process_payment") as span:
            span.set_attribute("user_id", user_id)
            span.set_attribute("product_id", product_id)

            if not self._circuit_allowed():
                span.set_attribute("circuit_breaker", "open")
                raise CircuitOpenError("Payment circuit breaker is open")

            last_error = None
            for attempt in range(settings.MAX_RETRIES):
                try:
                    response = await self.client.post(
                        urljoin(self.base_url, "/api/v1/payments"),
                        json={
                            "user_id": user_id,
                            "product_id": product_id,
                            "quantity": quantity,
                            "currency": currency,
                            "amount": 0.0,
                            "payment_method": "credit_card",
                        },
                        timeout=settings.REQUEST_TIMEOUT,
                    )
                    response.raise_for_status()
                    self._record_success()
                    return response.json()
                except httpx.TimeoutException as e:
                    last_error = e
                    logger.warning(f"Payment timeout attempt {attempt + 1}/{settings.MAX_RETRIES}")
                    if attempt < settings.MAX_RETRIES - 1:
                        wait = 2 ** attempt
                        span.add_event("retry", {"attempt": attempt + 1, "delay_seconds": wait})
                except httpx.HTTPStatusError as e:
                    last_error = e
                    if e.response.status_code in (400, 402, 422):
                        try:
                            return e.response.json()
                        except Exception:
                            return {"success": False, "message": "Payment rejected"}
                    logger.error(f"Payment HTTP error: {e.response.status_code}")
                    break
                except httpx.HTTPError as e:
                    last_error = e
                    logger.error(f"Payment connection error: {e}")
                    break
                except Exception as e:
                    last_error = e
                    logger.error(f"Payment unexpected error: {e}")
                    break

            self._record_failure()
            span.record_exception(last_error)
            return {"success": False, "message": "Payment service unavailable"}

    async def get_payment(self, payment_id: str) -> Optional[Dict[str, Any]]:
        with tracer.start_as_current_span("payment.get_payment") as span:
            span.set_attribute("payment_id", payment_id)
            try:
                response = await self.client.get(
                    urljoin(self.base_url, f"/api/v1/payments/{payment_id}"),
                    timeout=settings.REQUEST_TIMEOUT,
                )
                if response.status_code == 404:
                    return None
                response.raise_for_status()
                return response.json()
            except httpx.HTTPError as e:
                span.record_exception(e)
                logger.error(f"Failed to get payment {payment_id}: {e}")
                return None

    async def get_order(self, order_id: str) -> Optional[Dict[str, Any]]:
        with tracer.start_as_current_span("payment.get_order") as span:
            span.set_attribute("order_id", order_id)
            try:
                response = await self.client.get(
                    urljoin(self.base_url, f"/api/v1/payments"),
                    params={"order_id": order_id},
                    timeout=settings.REQUEST_TIMEOUT,
                )
                response.raise_for_status()
                payments = response.json().get("transactions", [])
                for p in payments:
                    if p.get("order_id") == order_id:
                        return p
                return None
            except httpx.HTTPError as e:
                span.record_exception(e)
                logger.error(f"Failed to get order {order_id}: {e}")
                return None
