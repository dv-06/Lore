"""PostgreSQL full-text search provider using tsvector and GIN."""

from sqlalchemy import inspect, text
from sqlalchemy.engine import Engine
from sqlalchemy.exc import OperationalError, ProgrammingError
from sqlalchemy.orm import Session

from app.models.document import Document
from app.services.search_common import (
    MAX_INDEX_REBUILD_DOCUMENTS,
    SearchHit,
    SearchQueryError,
    SearchUnavailableError,
    collect_documents,
    index_values,
    matching_fields,
    normalized_index_values,
    postgres_match_query,
    validate_query,
)

UNAVAILABLE_MESSAGE = (
    "PostgreSQL full-text search is unavailable or the index requires a bounded rebuild."
)

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


def _is_search_table_unavailable(error: Exception) -> bool:
    message = str(error).casefold()
    return "document_search" in message and (
        "does not exist" in message or "undefinedtable" in message
    )


def _index_parameters(document: Document) -> dict[str, str]:
    normalized = normalized_index_values(document)
    parameters = dict(index_values(document))
    parameters.update({f"n_{key}": value for key, value in normalized.items()})
    parameters["search_text"] = " ".join(normalized.values())
    return parameters


def schema_available(engine: Engine) -> bool:
    try:
        inspector = inspect(engine)
        if "document_search" not in inspector.get_table_names():
            return False
        columns = {
            column["name"] for column in inspector.get_columns("document_search")
        }
        return {"search_vector", "search_text"} <= columns
    except Exception:
        return False


def index_document(db: Session, document: Document) -> None:
    try:
        db.execute(text(_INSERT_SQL), _index_parameters(document))
    except (OperationalError, ProgrammingError) as exc:
        if _is_search_table_unavailable(exc):
            return
        raise SearchUnavailableError(
            "PostgreSQL full-text index update failed."
        ) from exc


def remove_document_index(db: Session, document_id: str) -> None:
    try:
        db.execute(
            text("DELETE FROM document_search WHERE document_id = :document_id"),
            {"document_id": document_id},
        )
    except (OperationalError, ProgrammingError) as exc:
        if _is_search_table_unavailable(exc):
            return
        raise SearchUnavailableError(
            "PostgreSQL full-text index update failed."
        ) from exc


def rebuild_search_index(
    db: Session, *, max_documents: int = MAX_INDEX_REBUILD_DOCUMENTS
) -> int:
    documents = collect_documents(db, max_documents=max_documents)
    try:
        db.execute(text("DELETE FROM document_search"))
        if documents:
            db.execute(
                text(_INSERT_SQL),
                [_index_parameters(document) for document in documents],
            )
        db.commit()
    except (OperationalError, ProgrammingError) as exc:
        db.rollback()
        raise SearchUnavailableError(
            "PostgreSQL full-text search is not available."
        ) from exc
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
    match_query = postgres_match_query(terms)
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
        WITH q AS (
            SELECT to_tsquery('simple', :match_query) AS query
        )
        SELECT
            d.id AS document_id,
            d.original_filename AS filename,
            d.document_title AS title,
            d.category AS category,
            coalesce(
                nullif(
                    ts_headline(
                        'simple',
                        s.search_text,
                        q.query,
                        'StartSel=[, StopSel=], MaxWords=24, MinWords=8, ShortWord=2'
                    ),
                    ''
                ),
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
            ts_rank_cd(s.search_vector, q.query, 32) AS relevance,
            d.document_type AS document_type,
            CASE
                WHEN strpos(lower(d.original_filename), :exact_query) > 0 THEN 1
                WHEN strpos(lower(coalesce(d.reference_number, '')), :exact_query) > 0 THEN 2
                WHEN strpos(lower(coalesce(d.document_title, '')), :exact_query) > 0 THEN 3
                ELSE 4
            END AS exact_rank
        FROM document_search AS s
        JOIN documents AS d ON d.id = s.document_id
        CROSS JOIN q
        WHERE s.search_vector @@ q.query
        {where_filters}
        ORDER BY exact_rank ASC, relevance DESC, d.uploaded_at DESC, d.id ASC
        LIMIT :limit OFFSET :offset
        """
    )
    try:
        rows = db.execute(sql, params).mappings().all()
    except (OperationalError, ProgrammingError) as exc:
        if _is_search_table_unavailable(exc):
            raise SearchUnavailableError(
                "PostgreSQL full-text search is not available or the index is not initialized."
            ) from exc
        raise SearchQueryError("The search query could not be processed.") from exc

    results: list[SearchHit] = []
    for row in rows:
        snippet = row["snippet"] or ""
        if len(snippet) > 500:
            snippet = snippet[:499].rstrip() + "…"
        results.append(
            SearchHit(
                document_id=row["document_id"],
                filename=row["filename"],
                title=row["title"],
                category=row["category"],
                snippet=snippet,
                matching_fields=matching_fields(row, terms),
                score=max(0.0, float(row["relevance"])),
                document_type=row["document_type"],
            )
        )
    return results


__all__ = [
    "UNAVAILABLE_MESSAGE",
    "index_document",
    "remove_document_index",
    "rebuild_search_index",
    "schema_available",
    "search_documents",
]
