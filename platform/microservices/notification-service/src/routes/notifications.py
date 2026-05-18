from typing import Optional, Dict, Any, List
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from src.models.notification import get_db
from src.services.notification_service import NotificationServiceCore

router = APIRouter(prefix="/api/v1/notifications", tags=["notifications"])


class SendRequest(BaseModel):
    channel: str
    recipient: str
    subject: Optional[str] = None
    body: Optional[str] = None
    body_html: Optional[str] = None
    template_name: Optional[str] = None
    template_data: Optional[Dict[str, Any]] = None
    priority: str = "normal"
    metadata: Optional[Dict[str, Any]] = None


class SendResponse(BaseModel):
    success: bool
    notification_id: Optional[str] = None
    status: Optional[str] = None
    channel: Optional[str] = None
    recipient: Optional[str] = None
    error: Optional[str] = None


class NotificationDetail(BaseModel):
    id: str
    channel: str
    recipient: str
    subject: Optional[str]
    body: str
    priority: str
    status: str
    delivery_attempts: int
    last_error: Optional[str]
    provider_message_id: Optional[str]
    created_at: str
    sent_at: Optional[str]
    delivered_at: Optional[str]
    read_at: Optional[str]


class NotificationListItem(BaseModel):
    id: str
    channel: str
    recipient: str
    subject: Optional[str]
    priority: str
    status: str
    delivery_attempts: int
    created_at: str
    delivered_at: Optional[str]


class NotificationListResponse(BaseModel):
    notifications: List[NotificationListItem]
    total: int


class TemplateRequest(BaseModel):
    name: str
    channel: str
    body_template: str
    subject_template: Optional[str] = None
    body_html_template: Optional[str] = None


class TemplateResponse(BaseModel):
    success: bool
    id: Optional[str] = None
    name: Optional[str] = None
    channel: Optional[str] = None
    error: Optional[str] = None


class WebhookPayload(BaseModel):
    notification_id: str
    event_type: str = Field(..., pattern=r"^(delivered|bounced|opened|clicked)$")
    payload: Dict[str, Any] = {}


class WebhookResponse(BaseModel):
    success: bool
    event_type: Optional[str] = None


def get_notification_service(db: Session = Depends(get_db)) -> NotificationServiceCore:
    return NotificationServiceCore(db)


@router.post("/send", response_model=SendResponse)
async def send_notification(
    request: SendRequest,
    service: NotificationServiceCore = Depends(get_notification_service),
):
    if not request.body and not request.template_name:
        raise HTTPException(status_code=422, detail="Either 'body' or 'template_name' is required")
    result = service.send_notification(
        channel=request.channel,
        recipient=request.recipient,
        subject=request.subject,
        body=request.body,
        body_html=request.body_html,
        template_name=request.template_name,
        template_data=request.template_data,
        priority=request.priority,
        metadata=request.metadata,
    )
    if not result["success"]:
        raise HTTPException(status_code=400, detail=result.get("error", "Failed to send notification"))
    return SendResponse(**result)


@router.get("/{notification_id}", response_model=NotificationDetail)
async def get_notification(
    notification_id: str,
    service: NotificationServiceCore = Depends(get_notification_service),
):
    result = service.get_notification(notification_id)
    if not result:
        raise HTTPException(status_code=404, detail="Notification not found")
    return NotificationDetail(**result)


@router.get("", response_model=NotificationListResponse)
async def list_notifications(
    channel: Optional[str] = Query(None),
    status: Optional[str] = Query(None),
    recipient: Optional[str] = Query(None),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    service: NotificationServiceCore = Depends(get_notification_service),
):
    notifications, total = service.list_notifications(
        channel=channel, status=status, recipient=recipient, limit=limit, offset=offset
    )
    return NotificationListResponse(
        notifications=[NotificationListItem(**n) for n in notifications],
        total=total,
    )


@router.post("/templates", response_model=TemplateResponse)
async def create_template(
    request: TemplateRequest,
    service: NotificationServiceCore = Depends(get_notification_service),
):
    result = service.create_template(
        name=request.name,
        channel=request.channel,
        body_template=request.body_template,
        subject_template=request.subject_template,
        body_html_template=request.body_html_template,
    )
    if not result["success"]:
        raise HTTPException(status_code=409, detail=result.get("error", "Failed to create template"))
    return TemplateResponse(**result)


@router.post("/webhooks/delivery", response_model=WebhookResponse)
async def delivery_webhook(
    payload: WebhookPayload,
    service: NotificationServiceCore = Depends(get_notification_service),
):
    result = service.handle_delivery_webhook(
        notification_id=payload.notification_id,
        event_type=payload.event_type,
        payload=payload.payload,
    )
    return WebhookResponse(**result)
