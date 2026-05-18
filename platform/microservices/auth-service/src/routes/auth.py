from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Header
from pydantic import BaseModel, EmailStr
from sqlalchemy.orm import Session

from src.models.user import get_db
from src.services.auth_service import AuthServiceCore

router = APIRouter(prefix="/api/v1/auth", tags=["auth"])


class LoginRequest(BaseModel):
    username: str
    password: str


class RefreshRequest(BaseModel):
    refresh_token: str


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str
    expires_in: int
    user: Optional[dict] = None


class ValidateResponse(BaseModel):
    user_id: str
    role: str
    email: str
    username: str


class ApiKeyResponse(BaseModel):
    api_key: str
    message: str


class LogoutResponse(BaseModel):
    message: str


def get_auth_service(db: Session = Depends(get_db)) -> AuthServiceCore:
    return AuthServiceCore(db)


@router.post("/login", response_model=TokenResponse)
async def login(request: LoginRequest, auth: AuthServiceCore = Depends(get_auth_service)):
    result = auth.authenticate(request.username, request.password)
    if not result:
        raise HTTPException(status_code=401, detail="Invalid credentials")
    return TokenResponse(**result)


@router.post("/refresh", response_model=TokenResponse)
async def refresh(request: RefreshRequest, auth: AuthServiceCore = Depends(get_auth_service)):
    result = auth.refresh_token(request.refresh_token)
    if not result:
        raise HTTPException(status_code=401, detail="Invalid or expired refresh token")
    return TokenResponse(**result)


@router.post("/logout", response_model=LogoutResponse)
async def logout(
    authorization: str = Header(...),
    auth: AuthServiceCore = Depends(get_auth_service),
):
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(status_code=401, detail="Invalid authorization header")
    success = auth.logout(token)
    if not success:
        raise HTTPException(status_code=400, detail="Failed to revoke token")
    return LogoutResponse(message="Successfully logged out")


@router.get("/validate", response_model=ValidateResponse)
async def validate_token(
    authorization: str = Header(...),
    auth: AuthServiceCore = Depends(get_auth_service),
):
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(status_code=401, detail="Invalid authorization header")
    result = auth.validate_token(token)
    if not result:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    return ValidateResponse(**result)


@router.post("/api-key", response_model=ApiKeyResponse)
async def generate_api_key(
    authorization: str = Header(...),
    auth: AuthServiceCore = Depends(get_auth_service),
):
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(status_code=401, detail="Invalid authorization header")
    payload = auth.validate_token(token)
    if not payload:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    api_key = auth.generate_api_key(payload["user_id"])
    if not api_key:
        raise HTTPException(status_code=500, detail="Failed to generate API key")
    return ApiKeyResponse(api_key=api_key, message="Store this key securely. It will not be shown again.")
