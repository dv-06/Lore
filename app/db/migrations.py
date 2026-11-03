from sqlalchemy import inspect
from sqlalchemy.engine import Engine

FTS5_COLUMNS = {
    "document_id",
    "extracted_text",
    "original_filename",
    "document_title",
    "category",
    "tags",
    "document_type",
    "issuer",
    "reference_number",
}


def fts5_schema_available(engine: Engine) -> bool:
    """Check for the FTS5 index without creating or altering anything.

    The index is created by the Alembic baseline migration. Startup only
    reports whether full-text search can be used.
    """
    try:
        inspector = inspect(engine)
        if "document_search" not in inspector.get_table_names():
            return False
        columns = {
            column["name"]
            for column in inspector.get_columns("document_search")
        }
        return columns == FTS5_COLUMNS
    except Exception:
        return False
