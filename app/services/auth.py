import hashlib
import hmac
import json
import os
import secrets
import threading
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path

from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.models.auth import AuthSession


class PairingDisabledError(Exception):
    """Raised when a device is already paired and pairing is no longer offered."""


class InvalidPairingCodeError(Exception):
    """Raised when the supplied pairing code is missing, expired, or incorrect."""


@dataclass(frozen=True)
class PairingRecord:
    code: str
    expires_at: datetime


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
            record = self._read_pairing_record()
            if record is None:
                self._ensure_pairing_code()
                raise InvalidPairingCodeError(
                    "The pairing code is missing or has expired. Read the current code "
                    "from the LORE data directory and try again."
                )
            candidate = code.strip().lower()
            if not hmac.compare_digest(
                record.code.encode("utf-8"), candidate.encode("utf-8")
            ):
                raise InvalidPairingCodeError("The pairing code is incorrect.")

            token, session = self._new_session(db)
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
        return session

    def revoke(self, db: Session, token: str) -> bool:
        if not token:
            return False
        session = db.get(AuthSession, self.hash_token(token))
        if session is None or session.revoked_at is not None:
            return False
        session.revoked_at = self._now()
        db.commit()
        if self._active_session_count(db) == 0:
            self._ensure_pairing_code()
        return True

    def revoke_all(self, db: Session) -> int:
        now = self._now()
        result = db.execute(
            update(AuthSession)
            .where(AuthSession.revoked_at.is_(None), AuthSession.expires_at > now)
            .values(revoked_at=now)
            .execution_options(synchronize_session=False)
        )
        db.commit()
        self._ensure_pairing_code()
        return int(result.rowcount or 0)

    def _new_session(self, db: Session) -> tuple[str, AuthSession]:
        token = secrets.token_urlsafe(32)
        now = self._now()
        session = AuthSession(
            token_hash=self.hash_token(token),
            created_at=now,
            expires_at=now + self._session_ttl,
        )
        db.add(session)
        return token, session

    def _active_session_count(self, db: Session) -> int:
        now = self._now()
        return int(
            db.scalar(
                select(func.count())
                .select_from(AuthSession)
                .where(AuthSession.revoked_at.is_(None), AuthSession.expires_at > now)
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
