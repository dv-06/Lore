from sqlalchemy import inspect, text
from sqlalchemy.engine import Engine
from sqlalchemy.exc import OperationalError


def upgrade_legacy_document_table(engine: Engine) -> None:
    """Upgrade the original MVP documents table in place when it exists."""
    inspector = inspect(engine)
    if "documents" not in inspector.get_table_names():
        return

    columns = {column["name"] for column in inspector.get_columns("documents")}
    with engine.begin() as connection:
        if "uploaded_at" not in columns:
            if "created_at" in columns:
                connection.execute(
                    text("ALTER TABLE documents RENAME COLUMN created_at TO uploaded_at")
                )
            else:
                connection.execute(
                    text("ALTER TABLE documents ADD COLUMN uploaded_at DATETIME")
                )
                connection.execute(
                    text("UPDATE documents SET uploaded_at = CURRENT_TIMESTAMP WHERE uploaded_at IS NULL")
                )

        legacy_columns = {
            "sha256": "VARCHAR(64)",
            "extracted_text": "TEXT",
            "extraction_status": "VARCHAR(32) NOT NULL DEFAULT 'failed'",
            "processing_status": "VARCHAR(32) NOT NULL DEFAULT 'failed'",
            "processing_error": "VARCHAR(500) DEFAULT 'Legacy document requires re-upload before extraction.'",
            "category": "VARCHAR(32)",
            "classification_confidence": "FLOAT",
            "classification_reasons": "JSON NOT NULL DEFAULT '[]'",
            "classification_method": "VARCHAR(32)",
            "document_title": "VARCHAR(120)",
            "document_date": "DATE",
            "document_type": "VARCHAR(100)",
            "issuer": "VARCHAR(255)",
            "reference_number": "VARCHAR(100)",
            "tags": "JSON NOT NULL DEFAULT '[]'",
        }
        for column_name, definition in legacy_columns.items():
            if column_name not in columns:
                connection.execute(
                    text(f"ALTER TABLE documents ADD COLUMN {column_name} {definition}")
                )
        connection.execute(
            text(
                "CREATE UNIQUE INDEX IF NOT EXISTS ix_documents_sha256 "
                "ON documents (sha256)"
            )
        )
        connection.execute(
            text("CREATE INDEX IF NOT EXISTS ix_documents_document_type ON documents (document_type)")
        )
        connection.execute(
            text("CREATE INDEX IF NOT EXISTS ix_documents_category ON documents (category)")
        )
        connection.execute(
            text("CREATE INDEX IF NOT EXISTS ix_documents_issuer ON documents (issuer)")
        )
        connection.execute(
            text(
                "CREATE INDEX IF NOT EXISTS ix_documents_reference_number "
                "ON documents (reference_number)"
            )
        )
        connection.execute(
            text(
                """
                CREATE TABLE IF NOT EXISTS document_relationships (
                    id VARCHAR(36) PRIMARY KEY,
                    source_document_id VARCHAR(36) NOT NULL
                        REFERENCES documents(id) ON DELETE CASCADE,
                    related_document_id VARCHAR(36) NOT NULL
                        REFERENCES documents(id) ON DELETE CASCADE,
                    relationship_type VARCHAR(40) NOT NULL,
                    score FLOAT NOT NULL,
                    explanation VARCHAR(500) NOT NULL,
                    evidence JSON NOT NULL DEFAULT '[]',
                    calculated_at DATETIME NOT NULL,
                    CONSTRAINT uq_document_relationship_pair_type UNIQUE
                        (source_document_id, related_document_id, relationship_type),
                    CONSTRAINT ck_document_relationship_normalized_pair
                        CHECK (source_document_id < related_document_id)
                )
                """
            )
        )
        connection.execute(
            text("CREATE INDEX IF NOT EXISTS ix_document_relationship_source ON document_relationships (source_document_id)")
        )
        connection.execute(
            text("CREATE INDEX IF NOT EXISTS ix_document_relationship_related ON document_relationships (related_document_id)")
        )


def initialize_fts5(engine: Engine) -> bool:
    try:
        with engine.begin() as connection:
            connection.execute(
                text(
                    """
                    CREATE VIRTUAL TABLE IF NOT EXISTS document_search
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
            )
            columns = {
                row[1]
                for row in connection.exec_driver_sql("PRAGMA table_info(document_search)")
            }
            expected_columns = {
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
            if columns != expected_columns:
                return False
        return True
    except OperationalError:
        return False
