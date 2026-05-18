from typing import Optional, List, Dict, Any
from fastapi import APIRouter, Depends, HTTPException, Header, Query
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from src.models.payment import get_db
from src.services.payment_service import PaymentServiceCore

router = APIRouter(prefix="/api/v1/payments", tags=["payments"])


class PaymentRequest(BaseModel):
    user_id: str
    product_id: str
    amount: float = Field(..., gt=0)
    currency: str = "USD"
    payment_method: str = "credit_card"
    idempotency_key: Optional[str] = None
    description: Optional[str] = None
    metadata: Optional[Dict[str, Any]] = None
    quantity: int = 1


class PaymentResponse(BaseModel):
    success: bool
    order_id: Optional[str] = None
    payment_id: Optional[str] = None
    transaction_id: Optional[str] = None
    amount: Optional[float] = None
    currency: Optional[str] = None
    status: Optional[str] = None
    error: Optional[str] = None
    message: Optional[str] = None
    fee: Optional[float] = None
    net: Optional[float] = None
    processor: Optional[str] = None


class PaymentDetail(BaseModel):
    id: str
    order_id: str
    user_id: str
    product_id: str
    amount: float
    currency: str
    status: str
    payment_method: Optional[str]
    transaction_id: Optional[str]
    refunded_amount: float
    fee_amount: Optional[float]
    net_amount: Optional[float]
    description: Optional[str]
    created_at: str
    completed_at: Optional[str]


class RefundRequest(BaseModel):
    amount: Optional[float] = None
    reason: Optional[str] = None


class RefundResponse(BaseModel):
    success: bool
    refund_id: Optional[str] = None
    payment_id: Optional[str] = None
    amount: Optional[float] = None
    total_refunded: Optional[float] = None
    remaining: Optional[float] = None
    status: Optional[str] = None
    error: Optional[str] = None


class HistoryResponse(BaseModel):
    transactions: List[Dict[str, Any]]
    total: int


class WebhookPayload(BaseModel):
    type: Optional[str] = None
    event_type: Optional[str] = None
    data: Optional[Dict[str, Any]] = None
    resource: Optional[Dict[str, Any]] = None
    id: Optional[str] = None


class WebhookResponse(BaseModel):
    success: bool
    action: Optional[str] = None
    error: Optional[str] = None


def get_payment_service(db: Session = Depends(get_db)) -> PaymentServiceCore:
    return PaymentServiceCore(db)


@router.post("", response_model=PaymentResponse)
async def process_payment(
    request: PaymentRequest,
    service: PaymentServiceCore = Depends(get_payment_service),
):
    result = service.process_payment(
        user_id=request.user_id,
        product_id=request.product_id,
        amount=request.amount,
        currency=request.currency,
        payment_method=request.payment_method,
        idempotency_key=request.idempotency_key,
        description=request.description,
        metadata=request.metadata,
        quantity=request.quantity,
    )
    status_code = 200 if result["success"] else 400
    if not result["success"]:
        raise HTTPException(status_code=status_code, detail=result.get("message", "Payment failed"))
    return PaymentResponse(**result)


@router.get("/{payment_id}", response_model=PaymentDetail)
async def get_payment(
    payment_id: str,
    service: PaymentServiceCore = Depends(get_payment_service),
):
    result = service.get_payment(payment_id)
    if not result:
        raise HTTPException(status_code=404, detail="Payment not found")
    return PaymentDetail(**result)


@router.post("/{payment_id}/refund", response_model=RefundResponse)
async def refund_payment(
    payment_id: str,
    request: RefundRequest = RefundRequest(),
    service: PaymentServiceCore = Depends(get_payment_service),
):
    result = service.process_refund(
        payment_id=payment_id,
        amount=request.amount,
        reason=request.reason,
    )
    if not result["success"]:
        raise HTTPException(status_code=400, detail=result.get("error", "Refund failed"))
    return RefundResponse(**result)


@router.get("", response_model=HistoryResponse)
async def get_history(
    user_id: Optional[str] = Query(None),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    service: PaymentServiceCore = Depends(get_payment_service),
):
    transactions, total = service.get_transaction_history(user_id=user_id, limit=limit, offset=offset)
    return HistoryResponse(transactions=transactions, total=total)


@router.post("/webhooks/{provider}", response_model=WebhookResponse)
async def webhook_handler(
    provider: str,
    payload: WebhookPayload,
    service: PaymentServiceCore = Depends(get_payment_service),
    x_webhook_signature: Optional[str] = Header(None),
):
    result = service.handle_webhook(provider, payload.dict(exclude_none=True))
    if not result["success"]:
        raise HTTPException(status_code=400, detail=result.get("error", "Webhook processing failed"))
    return WebhookResponse(**result)
