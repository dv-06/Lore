"""Bootstrap the LORE schema and adopt pre-Alembic databases.

Revision ID: 0001_baseline
Revises:
Create Date: 2026-11-03

The baseline is intentionally idempotent. A fresh database is created from
scratch; an existing database written by the pre-Alembic application is
adopted in place without dropping tables or rewriting document rows. The old
startup-time ALTER logic lived here so operators can review it.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy import inspect

revision: str = "0001_baseline"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


LEGACY_COLUMNS: dict[str, sa.Column] = {
    "sha256": sa.Column("sha256", sa.String(64)),
    "extracted_text": sa.Column("extracted_text", sa.Text()),
    "extraction_status": sa.Column(
        "extraction_status",
        sa.String(32),
        nullable=False,
        server_default="failed",
    ),
    "processing_status": sa.Column(
        "processing_status",
        sa.String(32),
        nullable=False,
        server_default="failed",
    ),
    "processing_error": sa.Column(
        "processing_error",
        sa.String(500),
        server_default="Legacy document requires re-upload before extraction.",
    ),
    "category": sa.Column("category", sa.String(32)),
    "classification_confidence": sa.Column(
        "classification_confidence", sa.Float()
    ),
    "classification_reasons": sa.Column(
        "classification_reasons",
        sa.JSON(),
        nullable=False,
        server_default=sa.text("'[]'"),
    ),
    "classification_method": sa.Column("classification_method", sa.String(32)),
    "document_title": sa.Column("document_title", sa.String(120)),
    "document_date": sa.Column("document_date", sa.Date()),
    "document_type": sa.Column("document_type", sa.String(100)),
    "issuer": sa.Column("issuer", sa.String(255)),
    "reference_number": sa.Column("reference_number", sa.String(100)),
    "tags": sa.Column(
        "tags",
        sa.JSON(),
        nullable=False,
        server_default=sa.text("'[]'"),
    ),
}


def _tables(bind) -> set[str]:
    return set(inspect(bind).get_table_names())


def _columns(bind, table: str) -> set[str]:
    return {column["name"] for column in inspect(bind).get_columns(table)}


def _create_documents() -> None:
    op.create_table(
        "documents",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("original_filename", sa.String(255), nullable=False),
        sa.Column("media_type", sa.String(255)),
        sa.Column("size_bytes", sa.Integer(), nullable=False),
        sa.Column("storage_path", sa.String(1024), nullable=False, unique=True),
        sa.Column("sha256", sa.String(64)),
        sa.Column("extracted_text", sa.Text()),
        sa.Column("extraction_status", sa.String(32), nullable=False),
        sa.Column("processing_status", sa.String(32), nullable=False),
        sa.Column("processing_error", sa.String(500)),
        sa.Column("category", sa.String(32)),
        sa.Column("classification_confidence", sa.Float()),
        sa.Column("classification_reasons", sa.JSON(), nullable=False),
        sa.Column("classification_method", sa.String(32)),
        sa.Column("document_title", sa.String(120)),
        sa.Column("document_date", sa.Date()),
        sa.Column("document_type", sa.String(100)),
        sa.Column("issuer", sa.String(255)),
        sa.Column("reference_number", sa.String(100)),
        sa.Column("tags", sa.JSON(), nullable=False),
        sa.Column("uploaded_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(
            "size_bytes >= 0", name="ck_documents_nonnegative_size"
        ),
    )


def _adopt_documents(bind) -> None:
    columns = _columns(bind, "documents")
    if "uploaded_at" not in columns:
        if "created_at" in columns:
            op.execute(
                "ALTER TABLE documents RENAME COLUMN created_at TO uploaded_at"
            )
        else:
            op.add_column(
                "documents", sa.Column("uploaded_at", sa.DateTime(timezone=True))
            )
            op.execute(
                "UPDATE documents SET uploaded_at = CURRENT_TIMESTAMP "
                "WHERE uploaded_at IS NULL"
            )
    for name, column in LEGACY_COLUMNS.items():
        if name not in columns:
            op.add_column("documents", column)


def _documents_indexes() -> None:
    op.create_index(
        "ix_documents_sha256", "documents", ["sha256"], unique=True,
        if_not_exists=True,
    )
    for name in ("document_type", "category", "issuer", "reference_number"):
        op.create_index(
            f"ix_documents_{name}", "documents", [name], if_not_exists=True
        )


def _create_relationships() -> None:
    op.create_table(
        "document_relationships",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column(
            "source_document_id",
            sa.String(36),
            sa.ForeignKey("documents.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "related_document_id",
            sa.String(36),
            sa.ForeignKey("documents.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("relationship_type", sa.String(40), nullable=False),
        sa.Column("score", sa.Float(), nullable=False),
        sa.Column("explanation", sa.String(500), nullable=False),
        sa.Column("evidence", sa.JSON(), nullable=False),
        sa.Column("calculated_at", sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint(
            "source_document_id",
            "related_document_id",
            "relationship_type",
            name="uq_document_relationship_pair_type",
        ),
        sa.CheckConstraint(
            "source_document_id < related_document_id",
            name="ck_document_relationship_normalized_pair",
        ),
    )
    op.create_index(
        "ix_document_relationship_source",
        "document_relationships",
        ["source_document_id"],
        if_not_exists=True,
    )
    op.create_index(
        "ix_document_relationship_related",
        "document_relationships",
        ["related_document_id"],
        if_not_exists=True,
    )


def _create_auth_sessions() -> None:
    # Phase 2.1A adds user_id/auth_method in 0003. Keeping the original shape
    # here means every database follows the same upgrade path.
    op.create_table(
        "auth_sessions",
        sa.Column("token_hash", sa.String(64), primary_key=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True)),
    )
    op.create_index(
        "ix_auth_sessions_expires_at",
        "auth_sessions",
        ["expires_at"],
        if_not_exists=True,
    )


def _create_fts5(bind) -> None:
    if bind.dialect.name != "sqlite":
        return
    if "document_search" in _tables(bind):
        return
    op.execute(
        """
        CREATE VIRTUAL TABLE document_search
        USING fts5(
            document_id UNINDEXED,
            extracted_text,
            original_filename,
            document_title,
            category,
            tags,
            document_type,
            issuer,
            reference_number,
            tokenize='unicode61 remove_diacritics 2'
        )
        """
    )


def upgrade() -> None:
    bind = op.get_bind()
    existing = _tables(bind)

    if "documents" not in existing:
        _create_documents()
    else:
        _adopt_documents(bind)
    _documents_indexes()

    if "document_relationships" not in existing:
        _create_relationships()
    else:
        op.create_index(
            "ix_document_relationship_source",
            "document_relationships",
            ["source_document_id"],
            if_not_exists=True,
        )
        op.create_index(
            "ix_document_relationship_related",
            "document_relationships",
            ["related_document_id"],
            if_not_exists=True,
        )

    if "auth_sessions" not in existing:
        _create_auth_sessions()

    _create_fts5(bind)


def downgrade() -> None:
    bind = op.get_bind()
    existing = _tables(bind)
    if bind.dialect.name == "sqlite" and "document_search" in existing:
        op.execute("DROP TABLE document_search")

    if "document_relationships" in existing:
        op.drop_index(
            "ix_document_relationship_related",
            table_name="document_relationships",
            if_exists=True,
        )
        op.drop_index(
            "ix_document_relationship_source",
            table_name="document_relationships",
            if_exists=True,
        )
        op.drop_table("document_relationships")

    if "auth_sessions" in existing:
        op.drop_index(
            "ix_auth_sessions_expires_at",
            table_name="auth_sessions",
            if_exists=True,
        )
        op.drop_table("auth_sessions")

    if "documents" in existing:
        for name in (
            "ix_documents_reference_number",
            "ix_documents_issuer",
            "ix_documents_category",
            "ix_documents_document_type",
            "ix_documents_sha256",
        ):
            op.drop_index(name, table_name="documents", if_exists=True)
        op.drop_table("documents")
