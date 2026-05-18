import uuid
import secrets
import hashlib
from datetime import datetime, timedelta, timezone
from typing import Optional, Dict, Any, Tuple

from sqlalchemy.orm import Session
from jose import JWTError, jwt
from passlib.context import CryptContext
from opentelemetry import trace

from src.config import settings
from src.models.user import User, RevokedToken

tracer = trace.get_tracer(__name__)
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password, hashed_password)


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def create_access_token(user_id: str, role: str) -> str:
    now = datetime.now(timezone.utc)
    payload = {
        "sub": user_id,
        "role": role,
        "iat": now,
        "exp": now + timedelta(minutes=settings.JWT_EXPIRATION_MINUTES),
        "jti": str(uuid.uuid4()),
        "type": "access",
    }
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.JWT_ALGORITHM)


def create_refresh_token(user_id: str) -> Tuple[str, datetime]:
    now = datetime.now(timezone.utc)
    exp = now + timedelta(days=settings.JWT_REFRESH_EXPIRATION_DAYS)
    payload = {
        "sub": user_id,
        "iat": now,
        "exp": exp,
        "jti": str(uuid.uuid4()),
        "type": "refresh",
    }
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.JWT_ALGORITHM), exp


def decode_token(token: str) -> Optional[Dict[str, Any]]:
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.JWT_ALGORITHM])
        return payload
    except JWTError:
        return None


def is_token_revoked(db: Session, jti: str) -> bool:
    return db.query(RevokedToken).filter(RevokedToken.jti == jti).first() is not None


def revoke_token(db: Session, jti: str, expires_at: datetime) -> None:
    revoked = RevokedToken(jti=jti, expires_at=expires_at)
    db.add(revoked)
    db.commit()


def generate_api_key() -> str:
    return secrets.token_urlsafe(settings.API_KEY_LENGTH)


def hash_api_key(api_key: str) -> str:
    return hashlib.sha256(api_key.encode()).hexdigest()


class AuthServiceCore:
    def __init__(self, db: Session):
        self.db = db

    def authenticate(self, username: str, password: str) -> Optional[Dict[str, Any]]:
        with tracer.start_as_current_span("auth.authenticate") as span:
            user = self.db.query(User).filter(
                (User.username == username) | (User.email == username)
            ).first()

            if not user:
                span.set_attribute("auth.result", "user_not_found")
                return None

            if not user.is_active:
                span.set_attribute("auth.result", "inactive_user")
                return None

            if not verify_password(password, user.hashed_password):
                user.failed_login_attempts += 1
                self.db.commit()
                span.set_attribute("auth.result", "invalid_password")
                return None

            user.failed_login_attempts = 0
            user.last_login_at = datetime.now(timezone.utc)
            self.db.commit()

            access_token = create_access_token(user.id, user.role)
            refresh_token, refresh_exp = create_refresh_token(user.id)

            span.set_attribute("auth.result", "success")
            span.set_attribute("user.id", user.id)

            return {
                "access_token": access_token,
                "refresh_token": refresh_token,
                "token_type": "bearer",
                "expires_in": settings.JWT_EXPIRATION_MINUTES * 60,
                "user": {
                    "id": user.id,
                    "email": user.email,
                    "username": user.username,
                    "full_name": user.full_name,
                    "role": user.role,
                },
            }

    def refresh_token(self, refresh_token: str) -> Optional[Dict[str, Any]]:
        with tracer.start_as_current_span("auth.refresh_token") as span:
            payload = decode_token(refresh_token)
            if not payload or payload.get("type") != "refresh":
                span.set_attribute("auth.result", "invalid_token")
                return None

            user_id = payload.get("sub")
            jti = payload.get("jti")
            exp = datetime.fromtimestamp(payload.get("exp"))

            if is_token_revoked(self.db, jti):
                span.set_attribute("auth.result", "token_revoked")
                return None

            revoke_token(self.db, jti, exp)

            user = self.db.query(User).filter(User.id == user_id).first()
            if not user or not user.is_active:
                span.set_attribute("auth.result", "user_inactive")
                return None

            new_access = create_access_token(user.id, user.role)
            new_refresh, _ = create_refresh_token(user.id)

            return {
                "access_token": new_access,
                "refresh_token": new_refresh,
                "token_type": "bearer",
                "expires_in": settings.JWT_EXPIRATION_MINUTES * 60,
            }

    def validate_token(self, token: str) -> Optional[Dict[str, Any]]:
        with tracer.start_as_current_span("auth.validate_token") as span:
            payload = decode_token(token)
            if not payload or payload.get("type") != "access":
                return None

            jti = payload.get("jti")
            if is_token_revoked(self.db, jti):
                return None

            user = self.db.query(User).filter(User.id == payload.get("sub")).first()
            if not user or not user.is_active:
                return None

            return {
                "user_id": user.id,
                "role": user.role,
                "email": user.email,
                "username": user.username,
            }

    def create_user(self, email: str, username: str, password: str, full_name: str = None) -> User:
        with tracer.start_as_current_span("auth.create_user") as span:
            existing = self.db.query(User).filter(
                (User.email == email) | (User.username == username)
            ).first()
            if existing:
                raise ValueError("User with this email or username already exists")

            user = User(
                email=email,
                username=username,
                hashed_password=hash_password(password),
                full_name=full_name,
            )
            self.db.add(user)
            self.db.commit()
            self.db.refresh(user)
            span.set_attribute("user.id", user.id)
            return user

    def get_user(self, user_id: str) -> Optional[User]:
        return self.db.query(User).filter(User.id == user_id).first()

    def update_user(self, user_id: str, updates: Dict[str, Any]) -> Optional[User]:
        user = self.get_user(user_id)
        if not user:
            return None
        for key, value in updates.items():
            if hasattr(user, key) and key not in ("id", "hashed_password", "created_at"):
                setattr(user, key, value)
        user.updated_at = datetime.now(timezone.utc)
        self.db.commit()
        self.db.refresh(user)
        return user

    def delete_user(self, user_id: str) -> bool:
        user = self.get_user(user_id)
        if not user:
            return False
        user.is_active = False
        self.db.commit()
        return True

    def list_users(self, skip: int = 0, limit: int = 100) -> list:
        return self.db.query(User).offset(skip).limit(limit).all()

    def generate_api_key(self, user_id: str) -> Optional[str]:
        user = self.get_user(user_id)
        if not user:
            return None
        api_key = generate_api_key()
        user.api_key = hash_api_key(api_key)
        self.db.commit()
        return api_key

    def validate_api_key(self, api_key: str) -> Optional[User]:
        hashed = hash_api_key(api_key)
        return self.db.query(User).filter(
            User.api_key == hashed, User.is_active == True
        ).first()

    def logout(self, token: str) -> bool:
        payload = decode_token(token)
        if not payload:
            return False
        jti = payload.get("jti")
        exp = datetime.fromtimestamp(payload.get("exp"))
        revoke_token(self.db, jti, exp)
        return True

    def cleanup_expired_tokens(self) -> int:
        count = self.db.query(RevokedToken).filter(
            RevokedToken.expires_at < datetime.now(timezone.utc)
        ).delete()
        self.db.commit()
        return count
