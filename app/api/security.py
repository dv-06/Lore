from typing import Annotated

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.auth import AuthSession
from app.services.auth import AuthManager

bearer_scheme = HTTPBearer(auto_error=False)

_AUTHENTICATION_REQUIRED = "Authentication required."


def get_auth_manager(request: Request) -> AuthManager:
    return request.app.state.auth


def require_auth(
    request: Request,
    db: Annotated[Session, Depends(get_db)],
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],
) -> AuthSession:
    manager = get_auth_manager(request)
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise _unauthorized()
    session = manager.authenticate(db, credentials.credentials)
    if session is None:
        raise _unauthorized()
    return session


def get_bearer_token(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],
) -> str:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise _unauthorized()
    return credentials.credentials


def _unauthorized() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail=_AUTHENTICATION_REQUIRED,
        headers={
            "WWW-Authenticate": "Bearer",
            "Cache-Control": "no-store",
            "X-Content-Type-Options": "nosniff",
        },
    )
