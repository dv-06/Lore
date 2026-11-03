"""SQLite FTS5 search provider."""

from sqlalchemy import text
from sqlalchemy.engine import Engine
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import Session

from app.db.migrations import fts5_schema_available
from app.models.document import Document
from app.services.search_common import (
    MAX_INDEX_REBUILD_DOCUMENTS,
    SearchHit,
    SearchQueryError,
    SearchRebuildLimitError,
    SearchUnavailableError,
    collect_documents,
    index_values,
    matching_fields,
    sqlite_match_query,
    validate_query,
)

UNAVAILABLE_MESSAGE = (
    "SQLite FTS5 is unavailable or the local index requires a bounded rebuild."
)


def _is_fts_unavailable(error: OperationalError) -> bool:
    message = str(error).casefold()
    return any(
        marker in message
        for marker in ("fts5", "no such table", "no such column", "no such module")
    )


def schema_available(engine: Engine) -> bool:
    return fts5_schema_available(engine)


def index_document(db: Session, document: Document) -> None:
    try:
        db.execute(
            text("DELETE FROM document_search WHERE document_id = :document_id"),
            {"document_id": document.id},
        )
        db.execute(
            text(
                """
                INSERT INTO document_search (
                    document_id, extracted_text, original_filename, document_title,
                    category, tags, document_type, issuer, reference_number
                ) VALUES (
                    :document_id, :extracted_text, :original_filename, :document_title,
                    :category, :tags, :document_type, :issuer, :reference_number
                )
                """
            ),
            index_values(document),
        )
    except OperationalError as exc:
        if _is_fts_unavailable(exc):
            return
        raise SearchUnavailableError("SQLite FTS5 index update failed.") from exc


def remove_document_index(db: Session, document_id: str) -> None:
    try:
        db.execute(
            text("DELETE FROM document_search WHERE document_id = :document_id"),
            {"document_id": document_id},
        )
    except OperationalError as exc:
        if _is_fts_unavailable(exc):
            return
        raise SearchUnavailableError("SQLite FTS5 index update failed.") from exc


def rebuild_search_index(
    db: Session, *, max_documents: int = MAX_INDEX_REBUILD_DOCUMENTS
) -> int:
    documents = collect_documents(db, max_documents=max_documents)
    try:
        db.execute(text("DELETE FROM document_search"))
        if documents:
            db.execute(
                text(
                    """
                    INSERT INTO document_search (
                        document_id, extracted_text, original_filename, document_title,
                        category, tags, document_type, issuer, reference_number
                    ) VALUES (
                        :document_id, :extracted_text, :original_filename, :document_title,
                        :category, :tags, :document_type, :issuer, :reference_number
                    )
                    """
                ),
                [index_values(document) for document in documents],
            )
        db.commit()
    except OperationalError as exc:
        db.rollback()
        raise SearchUnavailableError("SQLite FTS5 is not available.") from exc
    return len(documents)


def search_documents(
    db: Session,
    *,
    query: str,
    limit: int,
    offset: int,
    category: str | None = None,
    document_type: str | None = None,
) -> list[SearchHit]:
    terms = validate_query(query)
    match_query = sqlite_match_query(terms)
    filters = []
    params: dict[str, object] = {
        "match_query": match_query,
        "limit": limit,
        "offset": offset,
        "exact_query": query.strip().casefold(),
    }
    if category is not None:
        filters.append("d.category = :category")
        params["category"] = category
    if document_type is not None:
        filters.append("d.document_type = :document_type")
        params["document_type"] = document_type
    where_filters = f" AND {' AND '.join(filters)}" if filters else ""
    sql = text(
        f"""
        SELECT
            d.id AS document_id,
            d.original_filename AS filename,
            d.document_title AS title,
            d.category AS category,
            coalesce(
                nullif(snippet(document_search, -1, '[', ']', '…', 24), ''),
                d.document_title,
                d.original_filename
            ) AS snippet,
            d.extracted_text AS extracted_text,
            d.tags AS tags,
            d.category AS searchable_category,
            d.document_type AS searchable_document_type,
            d.issuer AS issuer,
            d.reference_number AS reference_number,
            d.document_title AS searchable_title,
            d.original_filename AS searchable_filename,
            bm25(document_search, 0.0, 2.5, 1.5, 0.8, 1.0, 1.2, 1.4, 2.5, 3.0)
                AS relevance,
            d.document_type AS document_type,
            CASE
                WHEN instr(lower(d.original_filename), :exact_query) > 0 THEN 1
                WHEN instr(lower(coalesce(d.reference_number, '')), :exact_query) > 0 THEN 2
                WHEN instr(lower(coalesce(d.document_title, '')), :exact_query) > 0 THEN 3
                ELSE 4
            END AS exact_rank
        FROM document_search
        JOIN documents AS d ON d.id = document_search.document_id
        WHERE document_search MATCH :match_query
        {where_filters}
        ORDER BY exact_rank ASC, relevance ASC, d.uploaded_at DESC, d.id ASC
        LIMIT :limit OFFSET :offset
        """
    )
    try:
        rows = db.execute(sql, params).mappings().all()
    except OperationalError as exc:
        if _is_fts_unavailable(exc):
            raise SearchUnavailableError(
                "SQLite FTS5 is not available or the index is not initialized."
            ) from exc
        raise SearchQueryError("The search query could not be processed.") from exc

    results: list[SearchHit] = []
    for row in rows:
        results.append(
            SearchHit(
                document_id=row["document_id"],
                filename=row["filename"],
                title=row["title"],
                category=row["category"],
                snippet=row["snippet"] or "",
                matching_fields=matching_fields(row, terms),
                score=max(0.0, -float(row["relevance"])),
                document_type=row["document_type"],
            )
        )
    return results


# Kept for callers that imported the limit error from this provider.
__all__ = [
    "SearchRebuildLimitError",
    "index_document",
    "remove_document_index",
    "rebuild_search_index",
    "schema_available",
    "search_documents",
]
