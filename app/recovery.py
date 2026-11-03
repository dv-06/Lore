"""Operator-assisted recovery for a lost or wiped device session.

Run this on the machine that hosts LORE, with the backend stopped:

    python -m app.recovery

It revokes active backend sessions, clears any pairing lockout, and ensures a
one-time pairing code exists. Documents and metadata are not modified.
"""

from dataclasses import dataclass
from pathlib import Path

from app.core.config import Settings
from app.db.schema import verify_database_schema
from app.db.session import create_database_engine, create_session_factory
from app.services.auth import AuthManager


@dataclass(frozen=True)
class RecoveryResult:
    revoked_sessions: int
    pairing_code_path: Path


def recover_access(settings: Settings) -> RecoveryResult:
    data_dir = Path(settings.data_dir).expanduser()
    data_dir.mkdir(parents=True, exist_ok=True)
    engine = create_database_engine(settings)
    try:
        verify_database_schema(engine, settings)
        manager = AuthManager(settings)
        with create_session_factory(engine)() as db:
            revoked = manager.revoke_all(db)
            manager.clear_pairing_attempts(db)
            manager.status(db)  # ensures a pairing code exists before we print its path
        return RecoveryResult(
            revoked_sessions=revoked,
            pairing_code_path=manager.pairing_code_path,
        )
    finally:
        engine.dispose()


def main() -> int:
    result = recover_access(Settings())
    print(f"Revoked {result.revoked_sessions} active backend session(s).")
    print(f"Pairing code written to: {result.pairing_code_path}")
    print("Read that file on this machine and pair the device again.")
    print("Documents, metadata, and stored original files were not modified.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
