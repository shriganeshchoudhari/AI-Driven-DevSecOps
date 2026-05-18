import logging
from datetime import datetime, timezone
from typing import Dict, Any

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel

from src.services.auth import AuthService
from src.services.payments import PaymentService

router = APIRouter(tags=["api"])
logger = logging.getLogger(__name__)


class OrderRequest(BaseModel):
    user_id: str
    product_id: str
    quantity: int = 1
    currency: str = "USD"


class OrderResponse(BaseModel):
    order_id: str
    status: str
    amount: float
    timestamp: datetime


class UserProfile(BaseModel):
    user_id: str
    email: str
    name: str
    role: str


def get_auth_service(request: Request) -> AuthService:
    return AuthService(request.app.state.http_client, request.app.state.auth_url)


def get_payment_service(request: Request) -> PaymentService:
    return PaymentService(request.app.state.http_client, request.app.state.payment_url)


@router.get("/users/{user_id}", response_model=UserProfile)
async def get_user(
    user_id: str,
    auth: AuthService = Depends(get_auth_service),
):
    user = await auth.get_user(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return UserProfile(
        user_id=user["id"],
        email=user["email"],
        name=user.get("full_name") or user.get("username", ""),
        role=user["role"],
    )


@router.post("/orders", response_model=OrderResponse)
async def create_order(
    order: OrderRequest,
    auth: AuthService = Depends(get_auth_service),
    payment: PaymentService = Depends(get_payment_service),
):
    user = await auth.validate_user(order.user_id)
    if not user:
        raise HTTPException(status_code=401, detail="Unauthorized")

    result = await payment.process_payment(
        user_id=order.user_id,
        product_id=order.product_id,
        quantity=order.quantity,
        currency=order.currency,
    )

    if not result.get("success"):
        raise HTTPException(status_code=402, detail=result.get("message", "Payment failed"))

    return OrderResponse(
        order_id=result.get("order_id", ""),
        status=result.get("status", "pending"),
        amount=result.get("amount", 0.0),
        timestamp=datetime.now(timezone.utc),
    )


@router.get("/orders/{order_id}")
async def get_order(
    order_id: str,
    payment: PaymentService = Depends(get_payment_service),
):
    result = await payment.get_order(order_id)
    if not result:
        raise HTTPException(status_code=404, detail="Order not found")
    return result


@router.get("/payments/{payment_id}")
async def get_payment(
    payment_id: str,
    payment: PaymentService = Depends(get_payment_service),
):
    result = await payment.get_payment(payment_id)
    if not result:
        raise HTTPException(status_code=404, detail="Payment not found")
    return result
