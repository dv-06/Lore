from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.orm import Session

from app.api.security import get_auth_manager, get_bearer_token, require_auth
from app.db.session import get_db
from app.models.auth import AuthSession
from app.schemas.auth import (
    AuthSessionResponse,
    AuthStatusResponse,
    LogoutResponse,
    PairRequest,
    PairResponse,
    RevokeAllResponse,
)
from app.services.auth import AuthManager, InvalidPairingCodeError, PairingDisabledError

public_router = APIRouter()
protected_router = APIRouter()

DbSession = Annotated[Session, Depends(get_db)]
Manager = Annotated[AuthManager, Depends(get_auth_manager)]


@public_router.get("/status", response_model=AuthStatusResponse)
def read_auth_status(db: DbSession, manager: Manager) -> AuthStatusResponse:
    return AuthStatusResponse(**manager.status(db))


@public_router.post("/pair", response_model=PairResponse)
def pair_device(payload: PairRequest, db: DbSession, manager: Manager) -> PairResponse:
    try:
        token, session = manager.pair(db, payload.code)
    except PairingDisabledError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc
    except InvalidPairingCodeError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(exc),
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc
    return PairResponse(
        token=token,
        created_at=session.created_at,
        expires_at=session.expires_at,
    )


@protected_router.get("/session", response_model=AuthSessionResponse)
def read_auth_session(
    session: Annotated[AuthSession, Depends(require_auth)],
) -> AuthSessionResponse:
    return AuthSessionResponse(created_at=session.created_at, expires_at=session.expires_at)


@protected_router.post("/logout", response_model=LogoutResponse)
def logout(
    request: Request,
    db: DbSession,
    token: Annotated[str, Depends(get_bearer_token)],
    _session: Annotated[AuthSession, Depends(require_auth)],
) -> LogoutResponse:
    revoked = get_auth_manager(request).revoke(db, token)
    return LogoutResponse(revoked=revoked)


@protected_router.post("/revoke-all", response_model=RevokeAllResponse)
def revoke_all_sessions(
    request: Request,
    db: DbSession,
    _session: Annotated[AuthSession, Depends(require_auth)],
) -> RevokeAllResponse:
    revoked = get_auth_manager(request).revoke_all(db)
    return RevokeAllResponse(revoked=revoked)
