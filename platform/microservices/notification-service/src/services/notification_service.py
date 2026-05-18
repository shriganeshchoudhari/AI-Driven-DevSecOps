import uuid
import json
import secrets
import asyncio
from datetime import datetime, timedelta, timezone
from typing import Optional, Dict, Any, List, Tuple
from string import Template

from sqlalchemy.orm import Session
from opentelemetry import trace

from src.config import settings
from src.models.notification import (
    Notification,
    NotificationTemplate,
    DeliveryWebhook,
    NotificationChannel,
    NotificationStatus,
    NotificationPriority,
)

tracer = trace.get_tracer(__name__)


def _render_template(template_str: str, data: Dict[str, Any]) -> str:
    return Template(template_str).safe_substitute(**data)


class NotificationServiceCore:
    def __init__(self, db: Session):
        self.db = db

    def _mock_send_email(
        self,
        to: str,
        subject: str,
        body: str,
        body_html: Optional[str] = None,
    ) -> Dict[str, Any]:
        success = secrets.choice([True] * 90 + [False] * 10)
        if success:
            return {
                "success": True,
                "provider_message_id": f"email_{secrets.token_hex(12)}",
                "provider": "mock_ses",
            }
        return {
            "success": False,
            "error": "simulated_email_failure",
            "message": "Simulated email delivery failure",
        }

    def _mock_send_sms(
        self,
        to: str,
        body: str,
    ) -> Dict[str, Any]:
        success = secrets.choice([True] * 95 + [False] * 5)
        if success:
            return {
                "success": True,
                "provider_message_id": f"sms_{secrets.token_hex(12)}",
                "provider": "mock_sns",
            }
        return {
            "success": False,
            "error": "simulated_sms_failure",
            "message": "Simulated SMS delivery failure",
        }

    def _mock_send_push(
        self,
        to: str,
        title: str,
        body: str,
    ) -> Dict[str, Any]:
        return {
            "success": True,
            "provider_message_id": f"push_{secrets.token_hex(12)}",
            "provider": "mock_push",
        }

    def _mock_send_webhook(
        self,
        url: str,
        payload: Dict[str, Any],
    ) -> Dict[str, Any]:
        return {
            "success": True,
            "provider_message_id": f"wh_{secrets.token_hex(12)}",
            "provider": "mock_webhook",
            "status_code": 200,
        }

    def _get_template(self, name: str, channel: str) -> Optional[NotificationTemplate]:
        return self.db.query(NotificationTemplate).filter(
            NotificationTemplate.name == name,
            NotificationTemplate.channel == channel,
        ).first()

    def send_notification(
        self,
        channel: str,
        recipient: str,
        subject: Optional[str] = None,
        body: Optional[str] = None,
        body_html: Optional[str] = None,
        template_name: Optional[str] = None,
        template_data: Optional[Dict[str, Any]] = None,
        priority: str = "normal",
        metadata: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        with tracer.start_as_current_span("notification.send") as span:
            span.set_attribute("notification.channel", channel)
            span.set_attribute("notification.recipient", recipient)
            span.set_attribute("notification.priority", priority)

            final_subject = subject
            final_body = body
            final_body_html = body_html

            if template_name:
                tpl = self._get_template(template_name, channel)
                if not tpl:
                    return {"success": False, "error": f"Template '{template_name}' not found for channel '{channel}'"}
                data = template_data or {}
                if tpl.subject_template and not final_subject:
                    final_subject = _render_template(tpl.subject_template, data)
                if tpl.body_template and not final_body:
                    final_body = _render_template(tpl.body_template, data)
                if tpl.body_html_template and not final_body_html:
                    final_body_html = _render_template(tpl.body_html_template, data) if tpl.body_html_template else None
                template_id = tpl.id
            else:
                template_id = None

            if not final_body:
                return {"success": False, "error": "Notification body is required"}

            notification = Notification(
                channel=channel,
                recipient=recipient,
                subject=final_subject,
                body=final_body,
                body_html=final_body_html,
                template_id=template_id,
                template_data=json.dumps(template_data) if template_data else None,
                priority=priority,
                status=NotificationStatus.QUEUED.value,
                metadata_json=json.dumps(metadata) if metadata else None,
                max_retries=settings.MAX_RETRIES,
            )
            self.db.add(notification)
            self.db.commit()
            self.db.refresh(notification)

            try:
                loop = asyncio.get_running_loop()
                loop.create_task(self._deliver_notification(notification.id))
            except RuntimeError:
                pass

            span.set_attribute("notification.id", notification.id)
            return {
                "success": True,
                "notification_id": notification.id,
                "status": notification.status,
                "channel": channel,
                "recipient": recipient,
            }

    async def _deliver_notification(self, notification_id: str) -> None:
        with tracer.start_as_current_span("notification.deliver") as span:
            notification = self.db.query(Notification).filter(Notification.id == notification_id).first()
            if not notification:
                return

            span.set_attribute("notification.id", notification_id)
            notification.status = NotificationStatus.SENDING.value
            notification.delivery_attempts += 1
            self.db.commit()

            if notification.channel == NotificationChannel.EMAIL.value:
                result = self._mock_send_email(
                    to=notification.recipient,
                    subject=notification.subject or "",
                    body=notification.body,
                    body_html=notification.body_html,
                )
            elif notification.channel == NotificationChannel.SMS.value:
                result = self._mock_send_sms(
                    to=notification.recipient,
                    body=notification.body,
                )
            elif notification.channel == NotificationChannel.PUSH.value:
                result = self._mock_send_push(
                    to=notification.recipient,
                    title=notification.subject or "",
                    body=notification.body,
                )
            elif notification.channel == NotificationChannel.WEBHOOK.value:
                result = self._mock_send_webhook(
                    url=notification.recipient,
                    payload={
                        "subject": notification.subject,
                        "body": notification.body,
                        "metadata": json.loads(notification.metadata_json) if notification.metadata_json else {},
                    },
                )
            else:
                result = {"success": False, "error": f"Unsupported channel: {notification.channel}"}

            if result["success"]:
                notification.status = NotificationStatus.DELIVERED.value
                notification.provider_message_id = result.get("provider_message_id")
                notification.sent_at = datetime.now(timezone.utc)
                notification.delivered_at = datetime.now(timezone.utc)
            else:
                notification.status = NotificationStatus.FAILED.value
                notification.last_error = result.get("message", result.get("error"))
                if notification.delivery_attempts < notification.max_retries:
                    notification.status = NotificationStatus.QUEUED.value

            self.db.commit()

    def get_notification(self, notification_id: str) -> Optional[Dict[str, Any]]:
        notification = self.db.query(Notification).filter(Notification.id == notification_id).first()
        if not notification:
            return None
        return {
            "id": notification.id,
            "channel": notification.channel,
            "recipient": notification.recipient,
            "subject": notification.subject,
            "body": notification.body,
            "priority": notification.priority,
            "status": notification.status,
            "delivery_attempts": notification.delivery_attempts,
            "last_error": notification.last_error,
            "provider_message_id": notification.provider_message_id,
            "created_at": notification.created_at.isoformat(),
            "sent_at": notification.sent_at.isoformat() if notification.sent_at else None,
            "delivered_at": notification.delivered_at.isoformat() if notification.delivered_at else None,
            "read_at": notification.read_at.isoformat() if notification.read_at else None,
        }

    def list_notifications(
        self,
        channel: Optional[str] = None,
        status: Optional[str] = None,
        recipient: Optional[str] = None,
        limit: int = 50,
        offset: int = 0,
    ) -> Tuple[List[Dict[str, Any]], int]:
        query = self.db.query(Notification)
        if channel:
            query = query.filter(Notification.channel == channel)
        if status:
            query = query.filter(Notification.status == status)
        if recipient:
            query = query.filter(Notification.recipient == recipient)
        total = query.count()
        notifications = query.order_by(Notification.created_at.desc()).offset(offset).limit(limit).all()
        return [
            {
                "id": n.id,
                "channel": n.channel,
                "recipient": n.recipient,
                "subject": n.subject,
                "priority": n.priority,
                "status": n.status,
                "delivery_attempts": n.delivery_attempts,
                "created_at": n.created_at.isoformat(),
                "delivered_at": n.delivered_at.isoformat() if n.delivered_at else None,
            }
            for n in notifications
        ], total

    def create_template(
        self,
        name: str,
        channel: str,
        body_template: str,
        subject_template: Optional[str] = None,
        body_html_template: Optional[str] = None,
    ) -> Dict[str, Any]:
        with tracer.start_as_current_span("notification.create_template") as span:
            existing = self.db.query(NotificationTemplate).filter(
                NotificationTemplate.name == name
            ).first()
            if existing:
                return {"success": False, "error": f"Template '{name}' already exists"}

            template = NotificationTemplate(
                name=name,
                channel=channel,
                subject_template=subject_template,
                body_template=body_template,
                body_html_template=body_html_template,
            )
            self.db.add(template)
            self.db.commit()
            self.db.refresh(template)

            span.set_attribute("template.id", template.id)
            span.set_attribute("template.name", name)
            return {
                "success": True,
                "id": template.id,
                "name": template.name,
                "channel": template.channel,
            }

    def handle_delivery_webhook(
        self,
        notification_id: str,
        event_type: str,
        payload: Dict[str, Any],
    ) -> Dict[str, Any]:
        with tracer.start_as_current_span("notification.delivery_webhook") as span:
            wh = DeliveryWebhook(
                notification_id=notification_id,
                event_type=event_type,
                payload=json.dumps(payload),
            )
            self.db.add(wh)

            notification = self.db.query(Notification).filter(Notification.id == notification_id).first()
            if notification:
                if event_type == "delivered":
                    notification.status = NotificationStatus.DELIVERED.value
                    notification.delivered_at = datetime.now(timezone.utc)
                elif event_type == "bounced":
                    notification.status = NotificationStatus.BOUNCED.value
                elif event_type == "opened":
                    notification.status = NotificationStatus.OPENED.value
                    notification.read_at = datetime.now(timezone.utc)
                elif event_type == "clicked":
                    notification.status = NotificationStatus.CLICKED.value
                self.db.commit()

            return {"success": True, "event_type": event_type}
