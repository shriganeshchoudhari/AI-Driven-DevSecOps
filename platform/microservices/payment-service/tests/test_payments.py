import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from src.app import app
from src.models.payment import Base, get_db
from src.services.payment_service import PaymentServiceCore, calculate_fee, generate_transaction_id

SQLALCHEMY_DATABASE_URL = "sqlite:///./test_payments.db"
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
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)


def test_process_payment():
    response = client.post("/api/v1/payments", json={
        "user_id": "user-123",
        "product_id": "prod-456",
        "amount": 99.99,
        "currency": "USD",
        "payment_method": "credit_card",
    })
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert data["order_id"] is not None
    assert data["payment_id"] is not None
    assert data["transaction_id"] is not None
    assert data["amount"] == 99.99
    assert data["currency"] == "USD"
    assert data["status"] == "completed"


def test_get_payment():
    create_resp = client.post("/api/v1/payments", json={
        "user_id": "user-456",
        "product_id": "prod-789",
        "amount": 49.99,
        "currency": "USD",
    })
    payment_id = create_resp.json()["payment_id"]

    response = client.get(f"/api/v1/payments/{payment_id}")
    assert response.status_code == 200
    data = response.json()
    assert data["id"] == payment_id
    assert data["amount"] == 49.99


def test_get_payment_not_found():
    response = client.get("/api/v1/payments/nonexistent-id")
    assert response.status_code == 404


def test_refund_full():
    create_resp = client.post("/api/v1/payments", json={
        "user_id": "user-refund",
        "product_id": "prod-refund",
        "amount": 100.00,
        "currency": "USD",
    })
    payment_id = create_resp.json()["payment_id"]

    response = client.post(f"/api/v1/payments/{payment_id}/refund", json={})
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert data["total_refunded"] == 100.00


def test_refund_partial():
    create_resp = client.post("/api/v1/payments", json={
        "user_id": "user-partial",
        "product_id": "prod-partial",
        "amount": 200.00,
        "currency": "USD",
    })
    payment_id = create_resp.json()["payment_id"]

    response = client.post(f"/api/v1/payments/{payment_id}/refund", json={"amount": 50.00})
    assert response.status_code == 200
    assert response.json()["total_refunded"] == 50.00


def test_refund_invalid_payment():
    response = client.post("/api/v1/payments/nonexistent/refund", json={})
    assert response.status_code == 400


def test_idempotency():
    response1 = client.post("/api/v1/payments", json={
        "user_id": "user-idem",
        "product_id": "prod-idem",
        "amount": 75.00,
        "idempotency_key": "idem-key-001",
    })
    assert response1.status_code == 200

    response2 = client.post("/api/v1/payments", json={
        "user_id": "user-idem",
        "product_id": "prod-idem",
        "amount": 75.00,
        "idempotency_key": "idem-key-001",
    })
    assert response2.status_code == 200
    assert response1.json()["payment_id"] == response2.json()["payment_id"]


def test_transaction_history():
    client.post("/api/v1/payments", json={
        "user_id": "user-hist",
        "product_id": "prod-hist-1",
        "amount": 10.00,
    })
    client.post("/api/v1/payments", json={
        "user_id": "user-hist",
        "product_id": "prod-hist-2",
        "amount": 20.00,
    })

    response = client.get("/api/v1/payments", params={"user_id": "user-hist"})
    assert response.status_code == 200
    data = response.json()
    assert data["total"] >= 2


def test_stripe_webhook():
    response = client.post("/api/v1/payments/webhooks/stripe", json={
        "type": "payment_intent.succeeded",
        "data": {"object": {"id": "pi_test_123", "amount": 5000}},
    })
    assert response.status_code == 200


def test_calculate_fee():
    fee = calculate_fee(100.00)
    expected = round(100.00 * 2.9 / 100 + 0.30, 2)
    assert fee == expected


def test_generate_transaction_id():
    txn = generate_transaction_id()
    assert txn.startswith("txn_")
    assert len(txn) > 10


def test_payment_service_core():
    db = TestingSessionLocal()
    svc = PaymentServiceCore(db)

    result = svc.process_payment(
        user_id="svc-user",
        product_id="svc-prod",
        amount=50.00,
    )
    assert result["success"] is True

    payment = svc.get_payment(result["payment_id"])
    assert payment is not None
    assert payment["amount"] == 50.00

    refund = svc.process_refund(result["payment_id"], amount=25.00)
    assert refund["success"] is True
    assert refund["amount"] == 25.00

    db.close()
