from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Header, Query
from pydantic import BaseModel, EmailStr
from datetime import datetime, timezone
from sqlalchemy.orm import Session

from src.models.user import get_db
from src.services.auth_service import AuthServiceCore

router = APIRouter(prefix="/api/v1/users", tags=["users"])


class UserCreate(BaseModel):
    email: str
    username: str
    password: str
    full_name: Optional[str] = None


class UserUpdate(BaseModel):
    email: Optional[str] = None
    username: Optional[str] = None
    full_name: Optional[str] = None
    role: Optional[str] = None


class UserResponse(BaseModel):
    id: str
    email: str
    username: str
    full_name: Optional[str]
    role: str
    is_active: bool
    is_verified: bool
    created_at: datetime
    updated_at: datetime


class UserListResponse(BaseModel):
    users: List[UserResponse]
    total: int


def get_auth_service(db: Session = Depends(get_db)) -> AuthServiceCore:
    return AuthServiceCore(db)


def _require_admin(authorization: str, auth: AuthServiceCore) -> None:
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(status_code=401, detail="Invalid authorization header")
    payload = auth.validate_token(token)
    if not payload:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    if payload["role"] not in ("admin", "superadmin"):
        raise HTTPException(status_code=403, detail="Admin access required")


@router.post("", response_model=UserResponse, status_code=201)
async def create_user(
    user_data: UserCreate,
    auth: AuthServiceCore = Depends(get_auth_service),
):
    try:
        user = auth.create_user(
            email=user_data.email,
            username=user_data.username,
            password=user_data.password,
            full_name=user_data.full_name,
        )
    except ValueError as e:
        raise HTTPException(status_code=409, detail=str(e))
    return UserResponse(
        id=user.id,
        email=user.email,
        username=user.username,
        full_name=user.full_name,
        role=user.role,
        is_active=user.is_active,
        is_verified=user.is_verified,
        created_at=user.created_at,
        updated_at=user.updated_at,
    )


@router.get("", response_model=UserListResponse)
async def list_users(
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=1000),
    authorization: str = Header(...),
    auth: AuthServiceCore = Depends(get_auth_service),
):
    _require_admin(authorization, auth)
    users = auth.list_users(skip=skip, limit=limit)
    return UserListResponse(
        users=[
            UserResponse(
                id=u.id,
                email=u.email,
                username=u.username,
                full_name=u.full_name,
                role=u.role,
                is_active=u.is_active,
                is_verified=u.is_verified,
                created_at=u.created_at,
                updated_at=u.updated_at,
            )
            for u in users
        ],
        total=len(users),
    )


@router.get("/{user_id}", response_model=UserResponse)
async def get_user(
    user_id: str,
    auth: AuthServiceCore = Depends(get_auth_service),
):
    user = auth.get_user(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return UserResponse(
        id=user.id,
        email=user.email,
        username=user.username,
        full_name=user.full_name,
        role=user.role,
        is_active=user.is_active,
        is_verified=user.is_verified,
        created_at=user.created_at,
        updated_at=user.updated_at,
    )


@router.put("/{user_id}", response_model=UserResponse)
async def update_user(
    user_id: str,
    updates: UserUpdate,
    authorization: str = Header(...),
    auth: AuthServiceCore = Depends(get_auth_service),
):
    _require_admin(authorization, auth)
    update_dict = {k: v for k, v in updates.dict().items() if v is not None}
    user = auth.update_user(user_id, update_dict)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return UserResponse(
        id=user.id,
        email=user.email,
        username=user.username,
        full_name=user.full_name,
        role=user.role,
        is_active=user.is_active,
        is_verified=user.is_verified,
        created_at=user.created_at,
        updated_at=user.updated_at,
    )


@router.delete("/{user_id}", status_code=204)
async def delete_user(
    user_id: str,
    authorization: str = Header(...),
    auth: AuthServiceCore = Depends(get_auth_service),
):
    _require_admin(authorization, auth)
    success = auth.delete_user(user_id)
    if not success:
        raise HTTPException(status_code=404, detail="User not found")
