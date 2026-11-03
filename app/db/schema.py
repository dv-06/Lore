from pathlib import Path

from alembic.config import Config
from alembic.migration import MigrationContext
from alembic.script import ScriptDirectory
from sqlalchemy.engine import Engine

from app.core.config import Settings

PROJECT_ROOT = Path(__file__).resolve().parents[2]


class DatabaseSchemaError(RuntimeError):
    """The database is not at the schema revision this code expects."""


def build_alembic_config(settings: Settings | None = None) -> Config:
    config = Config(str(PROJECT_ROOT / "alembic.ini"))
    config.set_main_option("script_location", str(PROJECT_ROOT / "alembic"))
    if settings is not None:
        config.attributes["settings"] = settings
    return config


def head_revision(settings: Settings | None = None) -> str:
    script = ScriptDirectory.from_config(build_alembic_config(settings))
    head = script.get_current_head()
    if head is None:
        raise DatabaseSchemaError("No Alembic migrations are available.")
    return head


def current_revision(engine: Engine) -> str | None:
    with engine.connect() as connection:
        return MigrationContext.configure(connection).get_current_revision()


def verify_database_schema(
    engine: Engine, settings: Settings | None = None
) -> str:
    """Fail fast when the database is not under the expected migration revision.

    Startup never alters the schema. A pending migration must be applied
    explicitly with `python -m app.migrate upgrade` so an operator decides when
    the database changes.
    """
    current = current_revision(engine)
    head = head_revision(settings)
    if current != head:
        raise DatabaseSchemaError(
            "LORE database schema is "
            f"{current or 'unversioned'} but this build requires {head}. "
            "Run `python -m app.migrate upgrade` on the backend host. "
            "LORE will not modify the database during startup."
        )
    return head
