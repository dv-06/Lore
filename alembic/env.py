from pathlib import Path

from alembic import context
from sqlalchemy import create_engine, pool

from app import models  # noqa: F401 - registers metadata
from app.core.config import settings as default_settings
from app.db.base import Base
from app.db.session import resolve_database_url

config = context.config

active_settings = config.attributes.get("settings", default_settings)
database_url = resolve_database_url(active_settings)


def _ensure_sqlite_parent() -> None:
    prefix = "sqlite:///"
    if not database_url.startswith(prefix):
        return
    database_path = database_url[len(prefix) :]
    if not database_path or database_path == ":memory:":
        return
    Path(database_path).expanduser().parent.mkdir(parents=True, exist_ok=True)


_ensure_sqlite_parent()
# ConfigParser interpolation treats '%' specially; escape it without changing
# the URL that is actually used to connect.
config.set_main_option("sqlalchemy.url", database_url.replace("%", "%%"))

target_metadata = Base.metadata


def run_migrations_offline() -> None:
    context.configure(
        url=database_url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        compare_type=True,
        render_as_batch=database_url.startswith("sqlite"),
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    provided_connection = config.attributes.get("connection")
    if provided_connection is not None:
        context.configure(
            connection=provided_connection,
            target_metadata=target_metadata,
            compare_type=True,
            render_as_batch=provided_connection.dialect.name == "sqlite",
        )
        with context.begin_transaction():
            context.run_migrations()
        return

    connectable = create_engine(database_url, poolclass=pool.NullPool)
    with connectable.connect() as active_connection:
        context.configure(
            connection=active_connection,
            target_metadata=target_metadata,
            compare_type=True,
            render_as_batch=active_connection.dialect.name == "sqlite",
        )
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
