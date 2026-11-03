"""Local owner administration.

Usage:
    python -m app.admin init-owner
    python -m app.admin invite --email tester@example.com
    python -m app.admin invite --email tester@example.com --expires-days 7

Passwords are read with getpass and never accepted as command-line
arguments. Invitation secrets are printed exactly once; only their SHA-256
digest is stored.
"""

import argparse
import getpass
import sys
from datetime import datetime, timedelta, timezone

from app.core.config import Settings
from app.core.email import InvalidEmailError
from app.core.passwords import PasswordPolicyError
from app.db.schema import DatabaseSchemaError, verify_database_schema
from app.db.session import create_database_engine, create_session_factory
from app.services.accounts import (
    AccountService,
    DuplicateEmailError,
    OwnerAlreadyExistsError,
)


class AdminCommandError(RuntimeError):
    pass


def _open_session(settings: Settings):
    engine = create_database_engine(settings)
    verify_database_schema(engine, settings)
    return engine, create_session_factory(engine)


def initialize_owner(settings: Settings, email: str, password: str) -> str:
    engine, session_factory = _open_session(settings)
    try:
        with session_factory() as db:
            user = AccountService(settings).create_owner(db, email, password)
            return user.email
    finally:
        engine.dispose()


def create_invitation(
    settings: Settings,
    email: str,
    *,
    expires_days: int | None = None,
) -> tuple[str, datetime]:
    engine, session_factory = _open_session(settings)
    try:
        with session_factory() as db:
            service = AccountService(settings)
            owner = service.get_owner(db)
            if owner is None:
                raise AdminCommandError(
                    "No owner exists. Run `python -m app.admin init-owner` first."
                )
            ttl = (
                timedelta(days=expires_days)
                if expires_days is not None
                else None
            )
            created = service.create_invitation(
                db, owner, email, expires_in=ttl
            )
            expires_at = created.invitation.expires_at
            # SQLite drops tzinfo on read; report a UTC-aware value so CLI
            # output and callers never mix naive and aware timestamps.
            if expires_at.tzinfo is None:
                expires_at = expires_at.replace(tzinfo=timezone.utc)
            return created.token, expires_at
    finally:
        engine.dispose()


def _prompt_email() -> str:
    return input("Email address: ").strip()


def _prompt_password() -> str:
    password = getpass.getpass("Password: ")
    confirmation = getpass.getpass("Confirm password: ")
    if password != confirmation:
        raise AdminCommandError("Passwords do not match.")
    return password


def _run_init_owner(settings: Settings, email: str | None) -> int:
    address = email or _prompt_email()
    password = _prompt_password()
    created_email = initialize_owner(settings, address, password)
    print(f"Owner account created for {created_email}.")
    print("The password hash was stored; the password itself was not saved.")
    return 0


def _run_invite(
    settings: Settings, email: str | None, expires_days: int | None
) -> int:
    address = email or _prompt_email()
    token, expires_at = create_invitation(
        settings, address, expires_days=expires_days
    )
    print(f"Invitation for {address} created.")
    print(f"Expires at: {expires_at.isoformat()}")
    print("Share this secret with the invitee through a channel you trust.")
    print("It will not be shown again:")
    print(token)
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="python -m app.admin",
        description="Local LORE owner administration.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    init_owner = subparsers.add_parser(
        "init-owner", help="Create the single owner account."
    )
    init_owner.add_argument("--email", help="Owner email; prompted if omitted.")

    invite = subparsers.add_parser(
        "invite", help="Create a single-use invitation."
    )
    invite.add_argument("--email", help="Invitee email; prompted if omitted.")
    invite.add_argument(
        "--expires-days",
        type=int,
        help="Invitation lifetime in days (default from settings).",
    )

    args = parser.parse_args(argv)
    settings = Settings()
    try:
        if args.command == "init-owner":
            return _run_init_owner(settings, args.email)
        return _run_invite(settings, args.email, args.expires_days)
    except (
        AdminCommandError,
        DatabaseSchemaError,
        DuplicateEmailError,
        InvalidEmailError,
        OwnerAlreadyExistsError,
        PasswordPolicyError,
    ) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
