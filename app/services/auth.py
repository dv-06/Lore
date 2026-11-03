import hashlib
import hmac
import json
import math
import os
import secrets
import threading
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path

from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.models.auth import (
    AUTH_METHOD_PAIRING,
    AUTH_METHOD_PASSWORD,
    AuthSession,
    PairingAttempt,
)
from app.models.user import User, UserStatus

_PAIRING_ATTEMPT_ID = 1


class PairingDisabledError(Exception):
    """Raised when a device is already paired and pairing is no longer offered."""


class InvalidPairingCodeError(Exception):
    """Raised when the supplied pairing code is missing, expired, or incorrect."""


class PairingRateLimitedError(Exception):
    """Raised while a temporary pairing lockout is active."""

    def __init__(self, retry_after_seconds: int) -> None:
        super().__init__("Too many failed pairing attempts. Try again later.")
        self.retry_after_seconds = max(1, retry_after_seconds)


@dataclass(frozen=True)
class PairingRecord:
    code: str
    expires_at: datetime


@dataclass(frozen=True)
class Principal:
    """An authenticated session plus the user it belongs to, if any.

    Pairing sessions are the transitional single-user credential and carry no
    user identity. They remain valid only until email/password login replaces
    pairing in a later phase.
    """

    session: AuthSession
    user: User | None

    @property
    def is_legacy_pairing(self) -> bool:
        return self.session.auth_method == AUTH_METHOD_PAIRING


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


class AuthManager:
    """Single-user local session authentication backed by hashed bearer tokens."""

    def __init__(self, settings: Settings) -> None:
        self._data_dir = Path(settings.data_dir).expanduser()
        self._pairing_code_path = self._data_dir / "pairing-code.txt"
        self._session_ttl = timedelta(hours=settings.auth_session_ttl_hours)
        self._pairing_ttl = timedelta(minutes=settings.auth_pairing_code_ttl_minutes)
        self._pairing_max_failures = settings.auth_pairing_max_failures
        self._pairing_lockout_seconds = settings.auth_pairing_lockout_seconds
        self._pairing_max_lockout_seconds = settings.auth_pairing_max_lockout_seconds
        self._pair_lock = threading.Lock()

    @property
    def pairing_code_path(self) -> Path:
        return self._pairing_code_path

    @staticmethod
    def hash_token(token: str) -> str:
        return hashlib.sha256(token.encode("utf-8")).hexdigest()

    @staticmethod
    def _now() -> datetime:
        return datetime.now(timezone.utc)

    def bootstrap(self, db: Session) -> None:
        if self._active_session_count(db) == 0:
            self._ensure_pairing_code()
        else:
            self._remove_pairing_code()

    def status(self, db: Session) -> dict[str, object]:
        active_sessions = self._active_session_count(db)
        pairing_expires_at = None
        if active_sessions == 0:
            record = self._ensure_pairing_code()
            pairing_expires_at = record.expires_at
        return {
            "paired": active_sessions > 0,
            "pairing_required": active_sessions == 0,
            "active_sessions": active_sessions,
            "pairing_expires_at": pairing_expires_at,
        }

    def pair(self, db: Session, code: str) -> tuple[str, AuthSession]:
        with self._pair_lock:
            if self._active_session_count(db) > 0:
                raise PairingDisabledError("This LORE server is already paired with a device.")
            self._enforce_pairing_rate_limit(db)
            record = self._read_pairing_record()
            if record is None:
                self._ensure_pairing_code()
                self._record_failed_attempt(db)
                raise InvalidPairingCodeError(
                    "The pairing code is missing or has expired. Read the current code "
                    "from the LORE data directory and try again."
                )
            candidate = code.strip().lower()
            if not hmac.compare_digest(
                record.code.encode("utf-8"), candidate.encode("utf-8")
            ):
                self._record_failed_attempt(db)
                raise InvalidPairingCodeError("The pairing code is incorrect.")

            token, session = self._new_session(db)
            attempt = db.get(PairingAttempt, _PAIRING_ATTEMPT_ID)
            if attempt is not None:
                db.delete(attempt)
            db.commit()
            self._remove_pairing_code()
            return token, session

    def authenticate(self, db: Session, token: str) -> AuthSession | None:
        if not token or len(token) > 256:
            return None
        session = db.get(AuthSession, self.hash_token(token))
        if session is None or session.revoked_at is not None:
            return None
        if _as_utc(session.expires_at) <= self._now():
            return None
        # Email/password sessions must belong to an active account. A disabled
        # account therefore loses access immediately without deleting sessions.
        if session.user_id is not None:
            user = db.get(User, session.user_id)
            if user is None or user.status != UserStatus.ACTIVE:
                return None
        elif session.auth_method != AUTH_METHOD_PAIRING:
            return None
        return session

    def resolve_principal(self, db: Session, session: AuthSession) -> Principal:
        user = db.get(User, session.user_id) if session.user_id else None
        return Principal(session=session, user=user)

    def create_user_session(self, db: Session, user: User) -> tuple[str, AuthSession]:
        """Create a password-authenticated session for an active user."""
        if user.status != UserStatus.ACTIVE:
            raise ValueError("A disabled account cannot start a session.")
        token, session = self._new_session(
            db, user_id=user.id, auth_method=AUTH_METHOD_PASSWORD
        )
        db.commit()
        return token, session

    def revoke(self, db: Session, token: str) -> bool:
        if not token:
            return False
        session = db.get(AuthSession, self.hash_token(token))
        if session is None or session.revoked_at is not None:
            return False
        was_pairing = session.auth_method == AUTH_METHOD_PAIRING
        session.revoked_at = self._now()
        db.commit()
        if was_pairing and self._active_session_count(db) == 0:
            self._ensure_pairing_code()
        return True

    def revoke_all(self, db: Session, user_id: str | None = None) -> int:
        now = self._now()
        statement = update(AuthSession).where(
            AuthSession.revoked_at.is_(None), AuthSession.expires_at > now
        )
        if user_id is not None:
            statement = statement.where(AuthSession.user_id == user_id)
        result = db.execute(
            statement.values(revoked_at=now).execution_options(
                synchronize_session=False
            )
        )
        db.commit()
        # The bulk UPDATE bypassed the identity map; drop cached sessions so
        # authenticate() sees the new revoked_at instead of stale state.
        db.expire_all()
        if user_id is None:
            self._ensure_pairing_code()
        return int(result.rowcount or 0)

    def clear_pairing_attempts(self, db: Session) -> None:
        """Reset the failed-pairing counter, used by operator-assisted recovery."""
        attempt = db.get(PairingAttempt, _PAIRING_ATTEMPT_ID)
        if attempt is not None:
            db.delete(attempt)
            db.commit()

    def _enforce_pairing_rate_limit(self, db: Session) -> None:
        attempt = db.get(PairingAttempt, _PAIRING_ATTEMPT_ID)
        if attempt is None or attempt.locked_until is None:
            return
        remaining = (_as_utc(attempt.locked_until) - self._now()).total_seconds()
        if remaining > 0:
            raise PairingRateLimitedError(math.ceil(remaining))

    def _record_failed_attempt(self, db: Session) -> None:
        attempt = db.get(PairingAttempt, _PAIRING_ATTEMPT_ID)
        if attempt is None:
            attempt = PairingAttempt(id=_PAIRING_ATTEMPT_ID, failed_count=0, lockout_count=0)
            db.add(attempt)
        now = self._now()
        attempt.failed_count += 1
        attempt.last_failed_at = now
        if attempt.failed_count >= self._pairing_max_failures:
            attempt.lockout_count += 1
            # Grow the lockout gradually but cap it, so an owner is never locked
            # out permanently and an attacker gains no benefit from restarting.
            factor = 2 ** min(attempt.lockout_count - 1, 16)
            delay = min(
                self._pairing_lockout_seconds * factor,
                self._pairing_max_lockout_seconds,
            )
            attempt.locked_until = now + timedelta(seconds=delay)
            attempt.failed_count = 0
        db.commit()

    def _new_session(
        self,
        db: Session,
        *,
        user_id: str | None = None,
        auth_method: str = AUTH_METHOD_PAIRING,
    ) -> tuple[str, AuthSession]:
        token = secrets.token_urlsafe(32)
        now = self._now()
        session = AuthSession(
            token_hash=self.hash_token(token),
            user_id=user_id,
            auth_method=auth_method,
            created_at=now,
            expires_at=now + self._session_ttl,
        )
        db.add(session)
        return token, session

    def _active_session_count(self, db: Session) -> int:
        """Count legacy pairing sessions for pairing status decisions.

        User sessions are not pairing sessions; they must not silently satisfy
        the single-user pairing state machine.
        """
        now = self._now()
        return int(
            db.scalar(
                select(func.count())
                .select_from(AuthSession)
                .where(
                    AuthSession.revoked_at.is_(None),
                    AuthSession.expires_at > now,
                    AuthSession.auth_method == AUTH_METHOD_PAIRING,
                )
            )
            or 0
        )

    def _ensure_pairing_code(self) -> PairingRecord:
        record = self._read_pairing_record()
        if record is not None:
            return record

        code = secrets.token_hex(16)
        expires_at = self._now() + self._pairing_ttl
        self._data_dir.mkdir(parents=True, exist_ok=True)
        temporary = self._pairing_code_path.with_name(
            f".{self._pairing_code_path.name}.{secrets.token_hex(8)}.tmp"
        )
        payload = {"code": code, "expires_at": expires_at.isoformat()}
        with temporary.open("x", encoding="utf-8") as file_obj:
            file_obj.write(json.dumps(payload))
        try:
            os.chmod(temporary, 0o600)
        except OSError:
            pass
        temporary.replace(self._pairing_code_path)
        return PairingRecord(code=code, expires_at=expires_at)

    def _read_pairing_record(self) -> PairingRecord | None:
        try:
            payload = json.loads(self._pairing_code_path.read_text(encoding="utf-8"))
            code = payload["code"]
            expires_at = datetime.fromisoformat(payload["expires_at"])
        except (OSError, ValueError, KeyError, TypeError):
            return None
        if not isinstance(code, str) or not code:
            return None
        if _as_utc(expires_at) <= self._now():
            self._remove_pairing_code()
            return None
        return PairingRecord(code=code, expires_at=_as_utc(expires_at))

    def _remove_pairing_code(self) -> None:
        try:
            self._pairing_code_path.unlink()
        except FileNotFoundError:
            return
        except OSError:
            return
