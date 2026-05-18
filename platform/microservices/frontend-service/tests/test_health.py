from fastapi.testclient import TestClient
from src.app import app

client = TestClient(app)


def test_health():
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert data["service"] == "frontend-service"


def test_ready():
    response = client.get("/ready")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "ready"


def test_health_returns_timestamp():
    response = client.get("/health")
    assert "timestamp" in response.json()
