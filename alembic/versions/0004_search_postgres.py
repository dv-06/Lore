"""Add the PostgreSQL full-text search index.

Revision ID: 0004_search_postgres
Revises: 0003_accounts
Create Date: 2026-11-03

SQLite keeps its FTS5 virtual table from the baseline migration, so this
migration is a no-op there. PostgreSQL gets a regular table with a weighted
``tsvector`` column, a GIN index, and a normalized text column used to build
snippets with ``ts_headline``.

The backfill is deterministic: every existing document row is read once and
normalized with the same tokenizer the application uses at write time. It does
not modify the ``documents`` table or assign ownership.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy import inspect

from app.services.search_common import normalize_text

revision: str = "0004_search_postgres"
down_revision: Union[str, None] = "0003_accounts"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

_VECTOR_SQL = """
setweight(to_tsvector('simple', :n_extracted_text), 'D')
|| setweight(to_tsvector('simple', :n_original_filename), 'A')
|| setweight(to_tsvector('simple', :n_document_title), 'A')
|| setweight(to_tsvector('simple', :n_category), 'C')
|| setweight(to_tsvector('simple', :n_tags), 'C')
|| setweight(to_tsvector('simple', :n_document_type), 'B')
|| setweight(to_tsvector('simple', :n_issuer), 'B')
|| setweight(to_tsvector('simple', :n_reference_number), 'A')
"""

_INSERT_SQL = f"""
INSERT INTO document_search (
    document_id, extracted_text, original_filename, document_title,
    category, tags, document_type, issuer, reference_number,
    search_text, search_vector
) VALUES (
    :document_id, :extracted_text, :original_filename, :document_title,
    :category, :tags, :document_type, :issuer, :reference_number,
    :search_text, {_VECTOR_SQL}
)
ON CONFLICT (document_id) DO UPDATE SET
    extracted_text = EXCLUDED.extracted_text,
    original_filename = EXCLUDED.original_filename,
    document_title = EXCLUDED.document_title,
    category = EXCLUDED.category,
    tags = EXCLUDED.tags,
    document_type = EXCLUDED.document_type,
    issuer = EXCLUDED.issuer,
    reference_number = EXCLUDED.reference_number,
    search_text = EXCLUDED.search_text,
    search_vector = EXCLUDED.search_vector
"""

_DOCUMENT_SQL = """
SELECT
    id, extracted_text, original_filename, document_title, category, tags,
    document_type, issuer, reference_number
FROM documents
ORDER BY id
"""


def _tables(bind) -> set[str]:
    return set(inspect(bind).get_table_names())


def _columns(bind, table: str) -> set[str]:
    return {column["name"] for column in inspect(bind).get_columns(table)}


def _tag_text(raw: object) -> str:
    if isinstance(raw, list):
        return " ".join(str(tag) for tag in raw)
    return str(raw) if raw else ""


def _index_parameters(row) -> dict[str, object]:
    values = {
        "document_id": row.id,
        "extracted_text": row.extracted_text or "",
        "original_filename": row.original_filename or "",
        "document_title": row.document_title or "",
        "category": row.category or "",
        "tags": _tag_text(row.tags),
        "document_type": row.document_type or "",
        "issuer": row.issuer or "",
        "reference_number": row.reference_number or "",
    }
    normalized = {
        key: normalize_text(value)
        for key, value in values.items()
        if key != "document_id"
    }
    values.update({f"n_{key}": value for key, value in normalized.items()})
    values["search_text"] = " ".join(normalized.values())
    return values


def _create_search_table(bind) -> bool:
    if "document_search" in _tables(bind):
        return False
    op.execute(
        """
        CREATE TABLE document_search (
            document_id VARCHAR(36) PRIMARY KEY
                REFERENCES documents (id) ON DELETE CASCADE,
            extracted_text TEXT NOT NULL DEFAULT '',
            original_filename VARCHAR(255) NOT NULL DEFAULT '',
            document_title VARCHAR(120) NOT NULL DEFAULT '',
            category VARCHAR(32) NOT NULL DEFAULT '',
            tags TEXT NOT NULL DEFAULT '',
            document_type VARCHAR(100) NOT NULL DEFAULT '',
            issuer VARCHAR(255) NOT NULL DEFAULT '',
            reference_number VARCHAR(100) NOT NULL DEFAULT '',
            search_text TEXT NOT NULL DEFAULT '',
            search_vector TSVECTOR NOT NULL
        )
        """
    )
    return True


def _ensure_columns(bind) -> None:
    columns = _columns(bind, "document_search")
    additions = {
        "search_text": "ALTER TABLE document_search "
        "ADD COLUMN search_text TEXT NOT NULL DEFAULT ''",
        "search_vector": "ALTER TABLE document_search "
        "ADD COLUMN search_vector TSVECTOR NOT NULL DEFAULT ''::tsvector",
    }
    for name, statement in additions.items():
        if name not in columns:
            op.execute(statement)


def _create_gin_index() -> None:
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_document_search_vector "
        "ON document_search USING GIN (search_vector)"
    )


def _backfill(bind) -> None:
    rows = bind.execute(sa.text(_DOCUMENT_SQL))
    batch: list[dict[str, object]] = []
    for row in rows:
        batch.append(_index_parameters(row))
        if len(batch) >= 500:
            bind.execute(sa.text(_INSERT_SQL), batch)
            batch.clear()
    if batch:
        bind.execute(sa.text(_INSERT_SQL), batch)


def upgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name != "postgresql":
        # SQLite's FTS5 table is created by the baseline migration.
        return
    _create_search_table(bind)
    _ensure_columns(bind)
    _create_gin_index()
    _backfill(bind)


def downgrade() -> None:
    bind = op.get_bind()
    if bind.dialect.name != "postgresql":
        return
    if "document_search" in _tables(bind):
        op.execute("DROP INDEX IF EXISTS ix_document_search_vector")
        op.drop_table("document_search")
