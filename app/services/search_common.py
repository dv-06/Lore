"""Shared search validation, result types, and document field mapping.

The SQLite and PostgreSQL providers deliberately share query validation and
result shaping so the HTTP API keeps the same contract on both databases.
"""

import json
import re
from collections.abc import Mapping
from dataclasses import dataclass

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models.document import Document

MAX_QUERY_LENGTH = 256
MAX_QUERY_TERMS = 12
MAX_SEARCH_RESULTS = 100
MAX_INDEX_REBUILD_DOCUMENTS = 10_000
MAX_INDEXED_TEXT_CHARS = 100_000_000
SEARCH_FIELDS = (
    "extracted_text",
    "original_filename",
    "document_title",
    "category",
    "tags",
    "document_type",
    "issuer",
    "reference_number",
)
_QUERY_TERMS = re.compile(r"[^\W_]+", re.UNICODE)


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


def index_values(document: Document) -> dict[str, str]:
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


def normalize_text(value: str) -> str:
    """Reduce text to whitespace-separated word tokens, preserving case.

    SQLite's unicode61 tokenizer splits hyphenated references and filenames
    into separate terms. PostgreSQL's ``simple`` parser does not always do the
    same, so the PostgreSQL provider indexes this normalized form instead.
    """
    return " ".join(_QUERY_TERMS.findall(value))


def normalized_index_values(document: Document) -> dict[str, str]:
    return {
        key: normalize_text(value)
        for key, value in index_values(document).items()
        if key != "document_id"
    }


def validate_query(query: str) -> list[str]:
    if not query.strip():
        raise SearchQueryError("Query must contain searchable text.")
    if len(query) > MAX_QUERY_LENGTH:
        raise SearchQueryError(f"Query must be at most {MAX_QUERY_LENGTH} characters.")
    terms = _QUERY_TERMS.findall(query)
    if not terms:
        raise SearchQueryError("Query must contain letters or numbers.")
    if len(terms) > MAX_QUERY_TERMS:
        raise SearchQueryError(f"Query must contain at most {MAX_QUERY_TERMS} searchable terms.")
    return terms


def sqlite_match_query(terms: list[str]) -> str:
    # Terms are extracted as Unicode word tokens and quoted to prevent FTS syntax injection.
    return " AND ".join(f'"{term.replace(chr(34), chr(34) * 2)}"*' for term in terms)


def postgres_match_query(terms: list[str]) -> str:
    # Validation restricts terms to letters/digits, so this prefix query cannot
    # inject tsquery operators. Prefix matching mirrors the SQLite provider.
    return " & ".join(f"{term}:*" for term in terms)


def parse_tags(raw: object) -> list[str]:
    if isinstance(raw, list):
        return [str(tag) for tag in raw]
    if isinstance(raw, str):
        try:
            value = json.loads(raw)
        except json.JSONDecodeError:
            return []
        if isinstance(value, list):
            return [str(tag) for tag in value]
    return []


def matching_fields(row: Mapping[str, object], terms: list[str]) -> list[str]:
    searchable_values = (
        row["extracted_text"] or "",
        row["searchable_filename"] or "",
        row["searchable_title"] or "",
        row["searchable_category"] or "",
        " ".join(parse_tags(row["tags"])),
        row["searchable_document_type"] or "",
        row["issuer"] or "",
        row["reference_number"] or "",
    )
    return [
        field
        for field, value in zip(SEARCH_FIELDS, searchable_values, strict=True)
        if any(term.casefold() in str(value).casefold() for term in terms)
    ]


def collect_documents(
    db: Session,
    *,
    max_documents: int = MAX_INDEX_REBUILD_DOCUMENTS,
) -> list[Document]:
    count = db.scalar(select(func.count(Document.id))) or 0
    if count > max_documents:
        raise SearchRebuildLimitError(
            f"Search rebuild is limited to {max_documents} documents per request."
        )
    documents: list[Document] = []
    indexed_chars = 0
    query = db.scalars(
        select(Document).order_by(Document.id).execution_options(yield_per=100)
    )
    for document in query:
        indexed_chars += len(document.extracted_text or "")
        if indexed_chars > MAX_INDEXED_TEXT_CHARS:
            raise SearchRebuildLimitError(
                "Search rebuild is limited to 100 million extracted-text characters per request."
            )
        documents.append(document)
    return documents
