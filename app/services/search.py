import json
import re
from dataclasses import dataclass

from sqlalchemy import func, select, text
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import Session

from app.models.document import Document

MAX_QUERY_LENGTH = 256
MAX_QUERY_TERMS = 12
MAX_SEARCH_RESULTS = 100
MAX_INDEX_REBUILD_DOCUMENTS = 10_000
MAX_INDEXED_TEXT_CHARS = 100_000_000
_QUERY_TERMS = re.compile(r"[^\W_]+", re.UNICODE)
_SEARCH_FIELDS = (
    "extracted_text",
    "original_filename",
    "document_title",
    "category",
    "tags",
    "document_type",
    "issuer",
    "reference_number",
)


def _is_fts_unavailable(error: OperationalError) -> bool:
    message = str(error).casefold()
    return any(
        marker in message
        for marker in ("fts5", "no such table", "no such column", "no such module")
    )


class SearchUnavailableError(RuntimeError):
    pass


class SearchQueryError(ValueError):
    pass


class SearchRebuildLimitError(ValueError):
    pass


@dataclass(frozen=True)
class SearchHit:
    document_id: str
    filename: str
    title: str | None
    category: str | None
    snippet: str
    matching_fields: list[str]
    score: float
    document_type: str | None


def _index_values(document: Document) -> dict[str, str]:
    return {
        "document_id": document.id,
        "extracted_text": document.extracted_text or "",
        "original_filename": document.original_filename or "",
        "document_title": document.document_title or "",
        "category": document.category or "",
        "tags": " ".join(document.tags or []),
        "document_type": document.document_type or "",
        "issuer": document.issuer or "",
        "reference_number": document.reference_number or "",
    }


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
            {
                **_index_values(document),
                "tags": " ".join(document.tags or []),
            },
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


def rebuild_search_index(db: Session, *, max_documents: int = MAX_INDEX_REBUILD_DOCUMENTS) -> int:
    count = db.scalar(select(func.count(Document.id))) or 0
    if count > max_documents:
        raise SearchRebuildLimitError(
            f"Search rebuild is limited to {max_documents} documents per request."
        )
    documents = []
    indexed_chars = 0
    query = db.scalars(
        select(Document)
        .order_by(Document.id)
        .execution_options(yield_per=100)
    )
    for document in query:
        indexed_chars += len(document.extracted_text or "")
        if indexed_chars > MAX_INDEXED_TEXT_CHARS:
            raise SearchRebuildLimitError(
                "Search rebuild is limited to 100 million extracted-text characters per request."
            )
        documents.append(document)
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
                [
                    {
                        **_index_values(document),
                        "tags": " ".join(document.tags or []),
                    }
                    for document in documents
                ],
            )
        db.commit()
    except OperationalError as exc:
        db.rollback()
        raise SearchUnavailableError("SQLite FTS5 is not available.") from exc
    return len(documents)


def _build_match_query(query: str) -> tuple[str, list[str]]:
    if not query.strip():
        raise SearchQueryError("Query must contain searchable text.")
    if len(query) > MAX_QUERY_LENGTH:
        raise SearchQueryError(f"Query must be at most {MAX_QUERY_LENGTH} characters.")
    terms = _QUERY_TERMS.findall(query)
    if not terms:
        raise SearchQueryError("Query must contain letters or numbers.")
    if len(terms) > MAX_QUERY_TERMS:
        raise SearchQueryError(f"Query must contain at most {MAX_QUERY_TERMS} searchable terms.")
    # Terms are extracted as Unicode word tokens and quoted to prevent FTS syntax injection.
    return " AND ".join(f'"{term.replace(chr(34), chr(34) * 2)}"*' for term in terms), terms


def search_documents(
    db: Session,
    *,
    query: str,
    limit: int,
    offset: int,
    category: str | None = None,
    document_type: str | None = None,
) -> list[SearchHit]:
    match_query, terms = _build_match_query(query)
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
            raise SearchUnavailableError("SQLite FTS5 is not available or the index is not initialized.") from exc
        raise SearchQueryError("The search query could not be processed.") from exc

    results: list[SearchHit] = []
    for row in rows:
        try:
            tags = json.loads(row["tags"] or "[]")
        except json.JSONDecodeError:
            tags = []
        if not isinstance(tags, list):
            tags = []
        searchable_values = (
            row["extracted_text"] or "",
            row["searchable_filename"] or "",
            row["searchable_title"] or "",
            row["searchable_category"] or "",
            " ".join(str(tag) for tag in tags),
            row["searchable_document_type"] or "",
            row["issuer"] or "",
            row["reference_number"] or "",
        )
        matching_fields = [
            field
            for field, value in zip(_SEARCH_FIELDS, searchable_values, strict=True)
            if any(term.casefold() in value.casefold() for term in terms)
        ]
        results.append(
            SearchHit(
                document_id=row["document_id"],
                filename=row["filename"],
                title=row["title"],
                category=row["category"],
                snippet=row["snippet"] or "",
                matching_fields=matching_fields,
                score=max(0.0, -float(row["relevance"])),
                document_type=row["document_type"],
            )
        )
    return results
