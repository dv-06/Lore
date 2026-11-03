from datetime import datetime, timezone

from sqlalchemy import (
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base

AUTH_METHOD_PAIRING = "pairing"
AUTH_METHOD_PASSWORD = "password"


class AuthSession(Base):
    __tablename__ = "auth_sessions"
    __table_args__ = (
        Index("ix_auth_sessions_expires_at", "expires_at"),
        Index("ix_auth_sessions_user_id", "user_id"),
        CheckConstraint(
            "auth_method IN ('pairing', 'password')",
            name="ck_auth_sessions_auth_method",
        ),
        # A pairing session is the transitional single-user credential and has
        # no user. Any future email/password session must belong to a user.
        CheckConstraint(
            "(auth_method = 'pairing' AND user_id IS NULL) "
            "OR (auth_method = 'password' AND user_id IS NOT NULL)",
            name="ck_auth_sessions_identity_consistency",
        ),
    )

    token_hash: Mapped[str] = mapped_column(String(64), primary_key=True)
    user_id: Mapped[str | None] = mapped_column(
        String(36),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=True,
    )
    auth_method: Mapped[str] = mapped_column(
        String(16), nullable=False, default=AUTH_METHOD_PAIRING
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
    )
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class PairingAttempt(Base):
    """Persisted failed-pairing counter so a restart cannot reset the limit."""

    __tablename__ = "pairing_attempts"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    failed_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    lockout_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    last_failed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    locked_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
