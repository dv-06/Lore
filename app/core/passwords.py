from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError
from argon2.low_level import Type

from app.core.config import Settings


class PasswordPolicyError(ValueError):
    """Raised when a candidate password does not meet the configured policy."""


class PasswordService:
    """Argon2id hashing and verification.

    The encoded hash (including its salt and parameters) is the only value
    stored. Plaintext passwords are never logged or persisted.
    """

    def __init__(self, settings: Settings) -> None:
        self.min_length = settings.auth_password_min_length
        self.max_length = settings.auth_password_max_length
        self._hasher = PasswordHasher(
            time_cost=settings.auth_password_time_cost,
            memory_cost=settings.auth_password_memory_kib,
            parallelism=settings.auth_password_parallelism,
            hash_len=32,
            salt_len=16,
            type=Type.ID,
        )

    def validate(self, password: str) -> None:
        if not isinstance(password, str):
            raise PasswordPolicyError("Password must be text.")
        if len(password) < self.min_length:
            raise PasswordPolicyError(
                f"Password must be at least {self.min_length} characters."
            )
        if len(password) > self.max_length:
            raise PasswordPolicyError(
                f"Password must be at most {self.max_length} characters."
            )
        if not password.strip():
            raise PasswordPolicyError("Password cannot be only whitespace.")

    def hash(self, password: str) -> str:
        self.validate(password)
        return self._hasher.hash(password)

    def verify(self, password: str, encoded_hash: str) -> bool:
        if not isinstance(password, str) or not isinstance(encoded_hash, str):
            return False
        try:
            return self._hasher.verify(encoded_hash, password)
        except (VerificationError, InvalidHashError, ValueError, TypeError):
            # A malformed or truncated stored hash is a failed verification,
            # not an exception the caller has to handle.
            return False

    def needs_rehash(self, encoded_hash: str) -> bool:
        try:
            return self._hasher.check_needs_rehash(encoded_hash)
        except (InvalidHashError, VerificationError, ValueError, TypeError):
            return True
