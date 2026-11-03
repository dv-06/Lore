"""Explicit database migration commands.

Usage:
    python -m app.migrate upgrade
    python -m app.migrate downgrade <revision>
    python -m app.migrate current

Startup never runs these automatically. The operator chooses when the
database schema changes.
"""

import argparse

from alembic import command

from app.core.config import Settings
from app.db.schema import build_alembic_config, current_revision, head_revision
from app.db.session import create_database_engine


def upgrade_database(settings: Settings) -> None:
    _run_migration(settings, "upgrade", "head")


def downgrade_database(settings: Settings, revision: str) -> None:
    _run_migration(settings, "downgrade", revision)


def _run_migration(settings: Settings, operation: str, revision: str) -> None:
    engine = create_database_engine(settings)
    try:
        with engine.connect() as connection:
            config = build_alembic_config(settings)
            config.attributes["connection"] = connection
            if operation == "upgrade":
                command.upgrade(config, revision)
            else:
                command.downgrade(config, revision)
    finally:
        engine.dispose()


def read_current_revision(settings: Settings) -> str | None:
    engine = create_database_engine(settings)
    try:
        return current_revision(engine)
    finally:
        engine.dispose()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="python -m app.migrate",
        description="Apply or inspect LORE database migrations explicitly.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("upgrade", help="Apply all pending migrations.")
    downgrade_parser = subparsers.add_parser(
        "downgrade", help="Move to a specific revision (may destroy data)."
    )
    downgrade_parser.add_argument(
        "revision", help="Target revision, for example 0002_pairing_attempts."
    )
    subparsers.add_parser("current", help="Print the current revision.")
    args = parser.parse_args(argv)

    settings = Settings()
    if args.command == "upgrade":
        upgrade_database(settings)
        print(f"Database upgraded to {head_revision(settings)}.")
        return 0
    if args.command == "downgrade":
        downgrade_database(settings, args.revision)
        print(f"Database downgraded to {args.revision}.")
        return 0

    current = read_current_revision(settings)
    print(current or "unversioned")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
