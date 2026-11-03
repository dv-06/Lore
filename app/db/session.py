from collections.abc import Generator
from pathlib import Path

from fastapi import Request
from sqlalchemy import URL, create_engine, event
from sqlalchemy.engine import Engine, make_url
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.config import Settings


def normalize_database_url(url: str) -> str:
    """Return a SQLAlchemy 2.x URL, preferring the packaged psycopg driver.

    SQLAlchemy 2 removed the ``postgres://`` alias, and a bare
    ``postgresql://`` URL selects psycopg2, which LORE does not ship. Both are
    normalized to the psycopg 3 dialect so operators can paste a standard
    PostgreSQL URL.
    """
    value = url.strip()
    if value.startswith("postgres://"):
        return "postgresql+psycopg://" + value[len("postgres://") :]
    if value.startswith("postgresql://"):
        return "postgresql+psycopg://" + value[len("postgresql://") :]
    return value


def resolve_database_url(settings: Settings) -> str:
    """Return the configured URL, or derive a SQLite URL from the legacy path."""
    configured = (settings.database_url or "").strip()
    if configured:
        return normalize_database_url(configured)
    database_path = settings.database_path.expanduser()
    # render_as_string percent-encodes the path, which SQLite then treats as
    # part of the filename. A plain forward-slash path is what Alembic needs.
    return f"sqlite:///{database_path.as_posix()}"


def _create_sqlite_engine(database: str | Path | None) -> Engine:
    database_value = ":memory:" if database in (None, "") else str(database)
    database_path = Path(database_value).expanduser()
    if database_value != ":memory:":
        database_path.parent.mkdir(parents=True, exist_ok=True)

    engine_options: dict[str, object] = {
        "connect_args": {"check_same_thread": False, "timeout": 5},
    }
    if database_value == ":memory:":
        engine_options["poolclass"] = StaticPool

    engine = create_engine(
        URL.create("sqlite", database=database_value),
        **engine_options,
    )

    @event.listens_for(engine, "connect")
    def configure_sqlite_connection(connection, _record) -> None:
        cursor = connection.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()

    return engine


def create_database_engine(settings: Settings) -> Engine:
    configured = (settings.database_url or "").strip()
    if configured:
        parsed = make_url(normalize_database_url(configured))
        if parsed.get_backend_name() == "sqlite":
            return _create_sqlite_engine(parsed.database)
        return create_engine(
            parsed,
            pool_pre_ping=True,
            pool_size=settings.database_pool_size,
            max_overflow=settings.database_max_overflow,
            pool_recycle=settings.database_pool_recycle_seconds,
            connect_args={
                "connect_timeout": settings.database_connect_timeout_seconds,
                "application_name": "lore-backend",
                # Return timestamptz values in UTC regardless of host settings.
                "options": "-c timezone=UTC",
            },
        )

    return _create_sqlite_engine(settings.database_path)


def create_session_factory(engine: Engine) -> sessionmaker[Session]:
    return sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


def get_db(request: Request) -> Generator[Session, None, None]:
    session_factory: sessionmaker[Session] = request.app.state.session_factory
    with session_factory() as session:
        yield session
