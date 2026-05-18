import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from src.app import app
from src.models.user import Base, get_db
from src.services.auth_service import AuthServiceCore, hash_password, create_access_token, decode_token

SQLALCHEMY_DATABASE_URL = "sqlite:///./test_auth.db"
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


def test_create_user():
    response = client.post("/api/v1/users", json={
        "email": "test@example.com",
        "username": "testuser",
        "password": "StrongP@ss1",
        "full_name": "Test User",
    })
    assert response.status_code == 201
    data = response.json()
    assert data["email"] == "test@example.com"
    assert data["username"] == "testuser"
    assert data["is_active"] is True
    assert "password" not in data


def test_create_duplicate_user():
    client.post("/api/v1/users", json={
        "email": "dup@example.com",
        "username": "dupuser",
        "password": "StrongP@ss1",
    })
    response = client.post("/api/v1/users", json={
        "email": "dup@example.com",
        "username": "dupuser",
        "password": "StrongP@ss1",
    })
    assert response.status_code == 409


def test_login_success():
    client.post("/api/v1/users", json={
        "email": "login@example.com",
        "username": "loginuser",
        "password": "StrongP@ss1",
    })
    response = client.post("/api/v1/auth/login", json={
        "username": "loginuser",
        "password": "StrongP@ss1",
    })
    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert "refresh_token" in data
    assert data["token_type"] == "bearer"


def test_login_invalid_password():
    client.post("/api/v1/users", json={
        "email": "fail@example.com",
        "username": "failuser",
        "password": "StrongP@ss1",
    })
    response = client.post("/api/v1/auth/login", json={
        "username": "failuser",
        "password": "wrongpassword",
    })
    assert response.status_code == 401


def test_validate_token():
    client.post("/api/v1/users", json={
        "email": "validate@example.com",
        "username": "validateuser",
        "password": "StrongP@ss1",
    })
    login_resp = client.post("/api/v1/auth/login", json={
        "username": "validateuser",
        "password": "StrongP@ss1",
    })
    token = login_resp.json()["access_token"]

    response = client.get("/api/v1/auth/validate", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
    assert response.json()["username"] == "validateuser"


def test_logout():
    client.post("/api/v1/users", json={
        "email": "logout@example.com",
        "username": "logoutuser",
        "password": "StrongP@ss1",
    })
    login_resp = client.post("/api/v1/auth/login", json={
        "username": "logoutuser",
        "password": "StrongP@ss1",
    })
    token = login_resp.json()["access_token"]

    resp = client.post("/api/v1/auth/logout", headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 200

    validate_resp = client.get("/api/v1/auth/validate", headers={"Authorization": f"Bearer {token}"})
    assert validate_resp.status_code == 401


def test_generate_api_key():
    client.post("/api/v1/users", json={
        "email": "apikey@example.com",
        "username": "apikeyuser",
        "password": "StrongP@ss1",
    })
    login_resp = client.post("/api/v1/auth/login", json={
        "username": "apikeyuser",
        "password": "StrongP@ss1",
    })
    token = login_resp.json()["access_token"]

    resp = client.post("/api/v1/auth/api-key", headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 200
    assert "api_key" in resp.json()


def test_get_user():
    create_resp = client.post("/api/v1/users", json={
        "email": "getuser@example.com",
        "username": "getuser",
        "password": "StrongP@ss1",
    })
    user_id = create_resp.json()["id"]
    response = client.get(f"/api/v1/users/{user_id}")
    assert response.status_code == 200
    assert response.json()["id"] == user_id


def test_get_user_not_found():
    response = client.get("/api/v1/users/nonexistent-id")
    assert response.status_code == 404


def test_hash_password():
    hashed = hash_password("testpass")
    assert hashed != "testpass"
    from passlib.context import CryptContext
    pwd = CryptContext(schemes=["bcrypt"])
    assert pwd.verify("testpass", hashed)


def test_create_access_token():
    token = create_access_token("user-123", "admin")
    payload = decode_token(token)
    assert payload is not None
    assert payload["sub"] == "user-123"
    assert payload["role"] == "admin"
    assert payload["type"] == "access"


def test_auth_service_core():
    db = TestingSessionLocal()
    svc = AuthServiceCore(db)
    user = svc.create_user("core@example.com", "coreuser", "TestPass1")
    assert user.email == "core@example.com"

    auth = svc.authenticate("coreuser", "TestPass1")
    assert auth is not None
    assert auth["user"]["email"] == "core@example.com"

    bad_auth = svc.authenticate("coreuser", "wrong")
    assert bad_auth is None

    fetched = svc.get_user(user.id)
    assert fetched.id == user.id

    updated = svc.update_user(user.id, {"full_name": "Updated Name"})
    assert updated.full_name == "Updated Name"

    deleted = svc.delete_user(user.id)
    assert deleted is True

    db.close()
