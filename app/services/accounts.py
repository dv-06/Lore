import hashlib
import secrets
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone

from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.core.email import normalize_email
from app.core.passwords import PasswordService
from app.models.invitation import Invitation
from app.models.user import User, UserRole, UserStatus

INVALID_INVITATION_MESSAGE = "The invitation is invalid or has expired."


class AccountError(ValueError):
    """Base class for account and invitation failures."""


class OwnerAlreadyExistsError(AccountError):
    pass


class DuplicateEmailError(AccountError):
    pass


class InvalidInvitationError(AccountError):
    def __init__(self, message: str = INVALID_INVITATION_MESSAGE) -> None:
        super().__init__(message)


class InvitationExpiredError(InvalidInvitationError):
    pass


class InvitationAlreadyUsedError(InvalidInvitationError):
    pass


class InvitationRevokedError(InvalidInvitationError):
    pass


class InvitationEmailMismatchError(InvalidInvitationError):
    pass


class AccountDisabledError(AccountError):
    pass


@dataclass(frozen=True)
class CreatedInvitation:
    invitation: Invitation
    # Excluded from repr so an accidental log statement cannot leak the token.
    token: str = field(repr=False)


def hash_invitation_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


class AccountService:
    """Account and invitation operations with no HTTP surface.

    Public registration and login deliberately live outside this phase. The
    service layer exists so the owner CLI and future routes share one
    implementation, and so single-use invitation behaviour is testable now.
    """

    def __init__(
        self,
        settings: Settings,
        passwords: PasswordService | None = None,
    ) -> None:
        self.passwords = passwords or PasswordService(settings)
        self._invitation_ttl = timedelta(days=settings.invitation_ttl_days)

    def get_owner(self, db: Session) -> User | None:
        return db.scalar(select(User).where(User.role == UserRole.OWNER))

    def find_user_by_email(self, db: Session, email: str) -> User | None:
        normalized = normalize_email(email)
        return db.scalar(select(User).where(User.email == normalized))

    def create_owner(self, db: Session, email: str, password: str) -> User:
        normalized = normalize_email(email)
        self.passwords.validate(password)
        if self.get_owner(db) is not None:
            raise OwnerAlreadyExistsError("A LORE owner account already exists.")
        if db.scalar(select(User.id).where(User.email == normalized)) is not None:
            raise DuplicateEmailError("An account already exists for that email.")

        user = User(
            email=normalized,
            password_hash=self.passwords.hash(password),
            role=UserRole.OWNER,
            status=UserStatus.ACTIVE,
        )
        db.add(user)
        try:
            db.commit()
        except IntegrityError as exc:
            db.rollback()
            if self.get_owner(db) is not None:
                raise OwnerAlreadyExistsError(
                    "A LORE owner account already exists."
                ) from exc
            raise DuplicateEmailError(
                "An account already exists for that email."
            ) from exc
        db.refresh(user)
        return user

    def create_user(
        self,
        db: Session,
        email: str,
        password: str,
        *,
        role: str = UserRole.USER,
        status: str = UserStatus.ACTIVE,
    ) -> User:
        normalized = normalize_email(email)
        user = User(
            email=normalized,
            password_hash=self.passwords.hash(password),
            role=role,
            status=status,
        )
        db.add(user)
        try:
            db.commit()
        except IntegrityError as exc:
            db.rollback()
            raise DuplicateEmailError(
                "An account already exists for that email."
            ) from exc
        db.refresh(user)
        return user

    def verify_credentials(self, db: Session, email: str, password: str) -> User | None:
        """Return the active user for valid credentials, otherwise None.

        Verification always runs for an existing row, including disabled
        accounts, so an attacker cannot use timing or status to distinguish
        the two failure modes.
        """
        try:
            normalized = normalize_email(email)
        except ValueError:
            return None
        user = db.scalar(select(User).where(User.email == normalized))
        if user is None:
            return None
        if not self.passwords.verify(password, user.password_hash):
            return None
        if user.status != UserStatus.ACTIVE:
            return None
        return user

    def create_invitation(
        self,
        db: Session,
        created_by: User,
        email: str,
        *,
        expires_in: timedelta | None = None,
    ) -> CreatedInvitation:
        if created_by.role != UserRole.OWNER:
            raise PermissionError("Only the owner can create invitations.")
        normalized = normalize_email(email)
        ttl = expires_in if expires_in is not None else self._invitation_ttl
        if ttl <= timedelta(0):
            raise ValueError("Invitation expiry must be in the future.")

        token = secrets.token_urlsafe(32)
        now = datetime.now(timezone.utc)
        invitation = Invitation(
            token_hash=hash_invitation_token(token),
            email=normalized,
            created_by=created_by.id,
            created_at=now,
            expires_at=now + ttl,
        )
        db.add(invitation)
        db.commit()
        db.refresh(invitation)
        return CreatedInvitation(invitation=invitation, token=token)

    def validate_invitation(
        self,
        db: Session,
        token: str,
        email: str | None = None,
    ) -> Invitation:
        """Validate state, expiry, revocation, and optional email binding."""
        if not isinstance(token, str) or not token or len(token) > 256:
            raise InvalidInvitationError()
        normalized = normalize_email(email) if email is not None else None
        invitation = db.scalar(
            select(Invitation).where(
                Invitation.token_hash == hash_invitation_token(token)
            )
        )
        if invitation is None:
            raise InvalidInvitationError()
        if invitation.revoked_at is not None:
            raise InvitationRevokedError()
        if invitation.used_at is not None:
            raise InvitationAlreadyUsedError()
        if _as_utc(invitation.expires_at) <= datetime.now(timezone.utc):
            raise InvitationExpiredError()
        if normalized is not None and invitation.email != normalized:
            raise InvitationEmailMismatchError()
        return invitation

    def redeem_invitation(
        self,
        db: Session,
        token: str,
        email: str,
        password: str,
    ) -> User:
        """Consume an invitation and create the bound account.

        Internal only in Phase 2.1A: no route calls this yet. The conditional
        UPDATE makes consumption single-use even if two requests race.
        """
        normalized = normalize_email(email)
        self.passwords.validate(password)
        invitation = self.validate_invitation(db, token, normalized)
        if db.scalar(select(User.id).where(User.email == normalized)) is not None:
            raise DuplicateEmailError("An account already exists for that email.")

        password_hash = self.passwords.hash(password)
        user = User(
            email=normalized,
            password_hash=password_hash,
            role=UserRole.USER,
            status=UserStatus.ACTIVE,
        )
        db.add(user)
        try:
            db.flush()
            result = db.execute(
                update(Invitation)
                .where(
                    Invitation.id == invitation.id,
                    Invitation.used_at.is_(None),
                    Invitation.revoked_at.is_(None),
                )
                .values(used_at=datetime.now(timezone.utc), used_by=user.id)
                .execution_options(synchronize_session=False)
            )
            if result.rowcount != 1:
                db.rollback()
                raise InvitationAlreadyUsedError()
            db.commit()
        except IntegrityError as exc:
            db.rollback()
            raise DuplicateEmailError(
                "An account already exists for that email."
            ) from exc
        # The bulk UPDATE bypassed the identity map; drop cached copies so
        # callers observe used_at/used_by.
        db.expire_all()
        db.refresh(user)
        return user

    def revoke_invitation(self, db: Session, invitation_id: str) -> bool:
        invitation = db.get(Invitation, invitation_id)
        if invitation is None or invitation.used_at is not None:
            return False
        if invitation.revoked_at is None:
            invitation.revoked_at = datetime.now(timezone.utc)
            db.commit()
        return True

    def disable_user(self, db: Session, user_id: str) -> User:
        user = db.get(User, user_id)
        if user is None:
            raise AccountError("Account not found.")
        user.status = UserStatus.DISABLED
        db.commit()
        db.refresh(user)
        return user
