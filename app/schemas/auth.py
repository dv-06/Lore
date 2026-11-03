from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


class PairRequest(BaseModel):
    code: str = Field(min_length=1, max_length=256)


class PairResponse(BaseModel):
    token: str
    created_at: datetime
    expires_at: datetime


class AuthStatusResponse(BaseModel):
    paired: bool
    pairing_required: bool
    active_sessions: int
    pairing_expires_at: datetime | None = None


class AuthUserResponse(BaseModel):
    id: str
    email: str
    role: str


class AuthSessionResponse(BaseModel):
    authenticated: Literal[True] = True
    created_at: datetime
    expires_at: datetime
    auth_method: Literal["pairing", "password"] = "pairing"
    user: AuthUserResponse | None = None


class LogoutResponse(BaseModel):
    revoked: bool


class RevokeAllResponse(BaseModel):
    revoked: int
    pairing_required: bool = True
