from collections.abc import Generator
from pathlib import Path

from fastapi import Request
from sqlalchemy import URL, create_engine, event
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.config import Settings


def create_database_engine(settings: Settings) -> Engine:
    database_path = settings.database_path.expanduser()
    if str(database_path) != ":memory:":
        database_path.parent.mkdir(parents=True, exist_ok=True)

    engine_options: dict[str, object] = {
        "connect_args": {"check_same_thread": False, "timeout": 5},
    }
    if str(database_path) == ":memory:":
        engine_options["poolclass"] = StaticPool

    engine = create_engine(
        URL.create("sqlite", database=str(database_path)),
        **engine_options,
    )

    @event.listens_for(engine, "connect")
    def configure_sqlite_connection(connection, _record) -> None:
        cursor = connection.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()

    return engine


def create_session_factory(engine: Engine) -> sessionmaker[Session]:
    return sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


def get_db(request: Request) -> Generator[Session, None, None]:
    session_factory: sessionmaker[Session] = request.app.state.session_factory
    with session_factory() as session:
        yield session

