import uuid
import json
import secrets
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from typing import Optional, Dict, Any, List, Tuple
from sqlalchemy.orm import Session
from opentelemetry import trace

from src.config import settings
from src.models.payment import (
    Payment,
    Refund,
    IdempotencyRecord,
    PaymentStatus,
    PaymentMethod,
)

tracer = trace.get_tracer(__name__)


def generate_transaction_id() -> str:
    return f"txn_{secrets.token_hex(16)}"


def calculate_fee(amount: float) -> float:
    return round(amount * settings.PROCESSING_FEE_PERCENT / 100 + settings.PROCESSING_FEE_FLAT, 2)


def _mock_processor_charge(
    amount: float,
    currency: str,
    payment_method: str,
    idempotency_key: Optional[str] = None,
) -> Dict[str, Any]:
    success = secrets.choice([True] * 95 + [False] * 5)
    if not success:
        return {
            "success": False,
            "error": "card_declined",
            "message": "Your card was declined. Please try a different payment method.",
        }
    return {
        "success": True,
        "transaction_id": generate_transaction_id(),
        "processor": "mock_processor",
        "auth_code": secrets.token_hex(8).upper(),
        "fee": calculate_fee(amount),
    }


def _mock_processor_refund(
    transaction_id: str,
    amount: float,
) -> Dict[str, Any]:
    return {
        "success": True,
        "refund_id": f"ref_{secrets.token_hex(16)}",
        "transaction_id": transaction_id,
    }


class PaymentServiceCore:
    def __init__(self, db: Session):
        self.db = db

    def _check_idempotency(self, idempotency_key: str) -> Optional[Dict[str, Any]]:
        if not idempotency_key:
            return None
        record = self.db.query(IdempotencyRecord).filter(
            IdempotencyRecord.idempotency_key == idempotency_key,
            IdempotencyRecord.expires_at > datetime.now(timezone.utc),
        ).first()
        if record:
            return {"body": json.loads(record.response_body), "status_code": record.status_code}
        return None

    def _save_idempotency(self, key: str, body: dict, status_code: int) -> None:
        if not key:
            return
        record = IdempotencyRecord(
            idempotency_key=key,
            response_body=json.dumps(body),
            status_code=status_code,
            expires_at=datetime.now(timezone.utc) + timedelta(hours=settings.IDEMPOTENCY_TTL_HOURS),
        )
        self.db.add(record)
        self.db.commit()

    def process_payment(
        self,
        user_id: str,
        product_id: str,
        amount: float,
        currency: str = "USD",
        payment_method: str = "credit_card",
        idempotency_key: Optional[str] = None,
        description: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
        quantity: int = 1,
    ) -> Dict[str, Any]:
        with tracer.start_as_current_span("payment.process") as span:
            span.set_attribute("user.id", user_id)
            span.set_attribute("payment.amount", amount)
            span.set_attribute("payment.currency", currency)

            if idempotency_key:
                cached = self._check_idempotency(idempotency_key)
                if cached:
                    span.set_attribute("payment.idempotent", True)
                    return cached["body"]

            total_amount = round(amount * quantity, 2)
            fee = calculate_fee(total_amount)
            net = round(total_amount - fee, 2)

            order_id = str(uuid.uuid4())
            payment = Payment(
                order_id=order_id,
                user_id=user_id,
                product_id=product_id,
                amount=total_amount,
                currency=currency,
                status=PaymentStatus.PROCESSING.value,
                payment_method=payment_method,
                idempotency_key=idempotency_key,
                description=description,
                metadata_json=json.dumps(metadata) if metadata else None,
                fee_amount=fee,
                net_amount=net,
            )
            self.db.add(payment)
            self.db.commit()
            self.db.refresh(payment)

            processor_result = _mock_processor_charge(total_amount, currency, payment_method, idempotency_key)

            if processor_result["success"]:
                payment.status = PaymentStatus.COMPLETED.value
                payment.transaction_id = processor_result["transaction_id"]
                payment.processor_response = json.dumps(processor_result)
                payment.completed_at = datetime.now(timezone.utc)
                self.db.commit()

                result = {
                    "success": True,
                    "order_id": order_id,
                    "payment_id": payment.id,
                    "transaction_id": payment.transaction_id,
                    "amount": total_amount,
                    "currency": currency,
                    "fee": fee,
                    "net": net,
                    "status": payment.status,
                    "processor": processor_result.get("processor"),
                }
            else:
                payment.status = PaymentStatus.FAILED.value
                payment.processor_response = json.dumps(processor_result)
                self.db.commit()

                result = {
                    "success": False,
                    "order_id": order_id,
                    "payment_id": payment.id,
                    "amount": total_amount,
                    "currency": currency,
                    "status": payment.status,
                    "error": processor_result.get("error"),
                    "message": processor_result.get("message"),
                }

            if idempotency_key:
                status_code = 200 if result["success"] else 400
                self._save_idempotency(idempotency_key, result, status_code)

            span.set_attribute("payment.status", payment.status)
            span.set_attribute("payment.id", payment.id)
            return result

    def get_payment(self, payment_id: str) -> Optional[Dict[str, Any]]:
        with tracer.start_as_current_span("payment.get") as span:
            payment = self.db.query(Payment).filter(Payment.id == payment_id).first()
            if not payment:
                return None
            return {
                "id": payment.id,
                "order_id": payment.order_id,
                "user_id": payment.user_id,
                "product_id": payment.product_id,
                "amount": payment.amount,
                "currency": payment.currency,
                "status": payment.status,
                "payment_method": payment.payment_method,
                "transaction_id": payment.transaction_id,
                "refunded_amount": payment.refunded_amount,
                "fee_amount": payment.fee_amount,
                "net_amount": payment.net_amount,
                "description": payment.description,
                "created_at": payment.created_at.isoformat(),
                "completed_at": payment.completed_at.isoformat() if payment.completed_at else None,
            }

    def get_payment_by_order(self, order_id: str) -> Optional[Dict[str, Any]]:
        payment = self.db.query(Payment).filter(Payment.order_id == order_id).first()
        if not payment:
            return None
        return self.get_payment(payment.id)

    def process_refund(
        self,
        payment_id: str,
        amount: Optional[float] = None,
        reason: Optional[str] = None,
    ) -> Dict[str, Any]:
        with tracer.start_as_current_span("payment.refund") as span:
            payment = self.db.query(Payment).filter(Payment.id == payment_id).first()
            if not payment:
                span.set_attribute("refund.result", "payment_not_found")
                return {"success": False, "error": "Payment not found"}

            if payment.status not in (PaymentStatus.COMPLETED.value, PaymentStatus.PARTIALLY_REFUNDED.value):
                span.set_attribute("refund.result", "invalid_status")
                return {"success": False, "error": f"Cannot refund payment with status {payment.status}"}

            max_refund = payment.amount - payment.refunded_amount
            refund_amount = amount if amount else max_refund

            if refund_amount <= 0 or refund_amount > max_refund:
                span.set_attribute("refund.result", "invalid_amount")
                return {"success": False, "error": f"Refund amount must be between 0 and {max_refund}"}

            processor_result = _mock_processor_refund(payment.transaction_id, refund_amount)

            refund = Refund(
                payment_id=payment_id,
                amount=refund_amount,
                reason=reason,
                status="completed" if processor_result["success"] else "failed",
                processor_refund_id=processor_result.get("refund_id") if processor_result["success"] else None,
                completed_at=datetime.now(timezone.utc) if processor_result["success"] else None,
            )
            self.db.add(refund)

            payment.refunded_amount += refund_amount
            if payment.refunded_amount >= payment.amount:
                payment.status = PaymentStatus.REFUNDED.value
            else:
                payment.status = PaymentStatus.PARTIALLY_REFUNDED.value
            self.db.commit()

            span.set_attribute("refund.amount", refund_amount)
            span.set_attribute("refund.status", refund.status)

            return {
                "success": True,
                "refund_id": refund.id,
                "payment_id": payment_id,
                "amount": refund_amount,
                "total_refunded": payment.refunded_amount,
                "remaining": max_refund - refund_amount,
                "status": refund.status,
            }

    def get_transaction_history(
        self,
        user_id: Optional[str] = None,
        limit: int = 50,
        offset: int = 0,
    ) -> Tuple[List[Dict[str, Any]], int]:
        with tracer.start_as_current_span("payment.history") as span:
            query = self.db.query(Payment)
            if user_id:
                query = query.filter(Payment.user_id == user_id)
            total = query.count()
            payments = query.order_by(Payment.created_at.desc()).offset(offset).limit(limit).all()

            results = []
            for p in payments:
                refunds = self.db.query(Refund).filter(Refund.payment_id == p.id).all()
                results.append({
                    "id": p.id,
                    "order_id": p.order_id,
                    "user_id": p.user_id,
                    "product_id": p.product_id,
                    "amount": p.amount,
                    "currency": p.currency,
                    "status": p.status,
                    "payment_method": p.payment_method,
                    "refunded_amount": p.refunded_amount,
                    "refunds": [
                        {"id": r.id, "amount": r.amount, "reason": r.reason, "status": r.status, "created_at": r.created_at.isoformat()}
                        for r in refunds
                    ],
                    "created_at": p.created_at.isoformat(),
                    "completed_at": p.completed_at.isoformat() if p.completed_at else None,
                })
            return results, total

    def handle_webhook(self, provider: str, payload: Dict[str, Any]) -> Dict[str, Any]:
        with tracer.start_as_current_span("payment.webhook") as span:
            span.set_attribute("webhook.provider", provider)
            event_type = payload.get("type", "unknown")
            span.set_attribute("webhook.event_type", event_type)

            if provider == "stripe":
                return self._handle_stripe_webhook(payload)
            elif provider == "paypal":
                return self._handle_paypal_webhook(payload)
            else:
                return {"success": False, "error": f"Unknown provider: {provider}"}

    def _handle_stripe_webhook(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        event_type = payload.get("type", "")
        data = payload.get("data", {}).get("object", {})

        if event_type == "payment_intent.succeeded":
            payment_intent_id = data.get("id")
            txn_id = data.get("id", "")
            payment = self.db.query(Payment).filter(
                Payment.transaction_id == txn_id
            ).first()
            if payment and payment.status == PaymentStatus.PROCESSING.value:
                payment.status = PaymentStatus.COMPLETED.value
                payment.completed_at = datetime.now(timezone.utc)
                self.db.commit()
                return {"success": True, "action": "payment_confirmed"}

        elif event_type == "payment_intent.payment_failed":
            txn_id = data.get("id", "")
            payment = self.db.query(Payment).filter(
                Payment.transaction_id == txn_id
            ).first()
            if payment:
                payment.status = PaymentStatus.FAILED.value
                self.db.commit()
                return {"success": True, "action": "payment_failed"}

        return {"success": True, "action": "ignored"}

    def _handle_paypal_webhook(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        event_type = payload.get("event_type", "")
        resource = payload.get("resource", {})

        if event_type == "PAYMENT.CAPTURE.COMPLETED":
            txn_id = resource.get("id", "")
            payment = self.db.query(Payment).filter(
                Payment.transaction_id == txn_id
            ).first()
            if payment and payment.status == PaymentStatus.PROCESSING.value:
                payment.status = PaymentStatus.COMPLETED.value
                payment.completed_at = datetime.now(timezone.utc)
                self.db.commit()
                return {"success": True, "action": "payment_confirmed"}

        return {"success": True, "action": "ignored"}
