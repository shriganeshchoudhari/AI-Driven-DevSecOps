import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from src.app import app
from src.models.notification import Base, get_db
from src.services.notification_service import NotificationServiceCore

SQLALCHEMY_DATABASE_URL = "sqlite:///./test_notifications.db"
engine = create_engine(SQLALCHEMY_DATABASE_URL, connect_args={"check_same_thread": False})
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base.metadata.create_all(bind=engine)


def override_get_db():
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()


app.dependency_overrides[get_db] = override_get_db
client = TestClient(app)


@pytest.fixture(autouse=True)
def clean_db():
    session = TestingSessionLocal()
    try:
        for table in reversed(Base.metadata.sorted_tables):
            session.execute(table.delete())
        session.commit()
    finally:
        session.close()


def test_send_email():
    response = client.post("/api/v1/notifications/send", json={
        "channel": "email",
        "recipient": "user@example.com",
        "subject": "Test Email",
        "body": "This is a test email body.",
        "priority": "normal",
    })
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert data["notification_id"] is not None
    assert data["channel"] == "email"
    assert data["status"] == "queued"


def test_send_sms():
    response = client.post("/api/v1/notifications/send", json={
        "channel": "sms",
        "recipient": "+1234567890",
        "body": "Your verification code is 123456",
        "priority": "high",
    })
    assert response.status_code == 200
    assert response.json()["success"] is True
    assert response.json()["channel"] == "sms"


def test_send_missing_body():
    response = client.post("/api/v1/notifications/send", json={
        "channel": "email",
        "recipient": "test@example.com",
    })
    assert response.status_code == 422


def test_get_notification():
    send_resp = client.post("/api/v1/notifications/send", json={
        "channel": "email",
        "recipient": "get@example.com",
        "subject": "Get Test",
        "body": "Test body for get.",
    })
    nid = send_resp.json()["notification_id"]

    response = client.get(f"/api/v1/notifications/{nid}")
    assert response.status_code == 200
    data = response.json()
    assert data["id"] == nid
    assert data["recipient"] == "get@example.com"
    assert data["channel"] == "email"


def test_get_notification_not_found():
    response = client.get("/api/v1/notifications/nonexistent-id")
    assert response.status_code == 404


def test_list_notifications():
    for i in range(3):
        client.post("/api/v1/notifications/send", json={
            "channel": "email",
            "recipient": f"list{i}@example.com",
            "subject": f"List Test {i}",
            "body": f"Body {i}",
        })

    response = client.get("/api/v1/notifications", params={"limit": 10})
    assert response.status_code == 200
    data = response.json()
    assert data["total"] >= 3
    assert len(data["notifications"]) >= 3


def test_filter_by_channel():
    client.post("/api/v1/notifications/send", json={
        "channel": "email",
        "recipient": "filter@example.com",
        "subject": "Email",
        "body": "Email body",
    })
    client.post("/api/v1/notifications/send", json={
        "channel": "sms",
        "recipient": "+1111111111",
        "body": "SMS body",
    })

    email_resp = client.get("/api/v1/notifications", params={"channel": "email"})
    assert email_resp.status_code == 200
    for n in email_resp.json()["notifications"]:
        assert n["channel"] == "email"


def test_create_template():
    response = client.post("/api/v1/notifications/templates", json={
        "name": "welcome_email",
        "channel": "email",
        "subject_template": "Welcome ${name}!",
        "body_template": "Hello ${name}, welcome to our platform!",
        "body_html_template": "<h1>Welcome ${name}!</h1>",
    })
    assert response.status_code == 200
    assert response.json()["success"] is True
    assert response.json()["name"] == "welcome_email"


def test_create_duplicate_template():
    client.post("/api/v1/notifications/templates", json={
        "name": "dup_template",
        "channel": "email",
        "body_template": "Body",
    })
    response = client.post("/api/v1/notifications/templates", json={
        "name": "dup_template",
        "channel": "email",
        "body_template": "Body",
    })
    assert response.status_code == 409


def test_send_with_template():
    client.post("/api/v1/notifications/templates", json={
        "name": "test_template",
        "channel": "email",
        "subject_template": "Hello ${first_name}",
        "body_template": "Dear ${first_name} ${last_name}, this is a test.",
    })
    response = client.post("/api/v1/notifications/send", json={
        "channel": "email",
        "recipient": "template@example.com",
        "template_name": "test_template",
        "template_data": {"first_name": "John", "last_name": "Doe"},
    })
    assert response.status_code == 200
    assert response.json()["success"] is True


def test_delivery_webhook():
    send_resp = client.post("/api/v1/notifications/send", json={
        "channel": "email",
        "recipient": "webhook@example.com",
        "subject": "Webhook Test",
        "body": "Test",
    })
    nid = send_resp.json()["notification_id"]

    response = client.post("/api/v1/notifications/webhooks/delivery", json={
        "notification_id": nid,
        "event_type": "delivered",
        "payload": {"timestamp": "2024-01-01T00:00:00Z"},
    })
    assert response.status_code == 200
    assert response.json()["success"] is True

    notif = client.get(f"/api/v1/notifications/{nid}").json()
    assert notif["status"] == "delivered"


def test_notification_service_core():
    db = TestingSessionLocal()
    svc = NotificationServiceCore(db)

    result = svc.send_notification(
        channel="email",
        recipient="core@example.com",
        subject="Core Test",
        body="Core body",
    )
    assert result["success"] is True

    notif = svc.get_notification(result["notification_id"])
    assert notif is not None
    assert notif["recipient"] == "core@example.com"

    tmpl = svc.create_template(
        name="core_template",
        channel="email",
        body_template="Hello ${user}!",
    )
    assert tmpl["success"] is True

    notifications, total = svc.list_notifications(channel="email")
    assert total >= 1

    db.close()
