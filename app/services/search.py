"""Dialect-aware full-text search facade.

The HTTP search contract is shared by both database backends. This module
selects the provider from the active SQLAlchemy dialect so call sites never
need to know whether SQLite FTS5 or PostgreSQL ``tsvector`` is in use.
"""

from types import ModuleType

from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session

from app.models.document import Document
from app.services import search_postgres, search_sqlite
from app.services.search_common import (
    MAX_INDEX_REBUILD_DOCUMENTS,
    MAX_QUERY_LENGTH,
    MAX_QUERY_TERMS,
    MAX_SEARCH_RESULTS,
    SearchHit,
    SearchQueryError,
    SearchRebuildLimitError,
    SearchUnavailableError,
)

__all__ = [
    "MAX_INDEX_REBUILD_DOCUMENTS",
    "MAX_QUERY_LENGTH",
    "MAX_QUERY_TERMS",
    "MAX_SEARCH_RESULTS",
    "SearchHit",
    "SearchQueryError",
    "SearchRebuildLimitError",
    "SearchUnavailableError",
    "index_document",
    "rebuild_search_index",
    "remove_document_index",
    "search_documents",
    "search_schema_available",
    "search_unavailable_message",
]


def _dialect_name(bind: Engine | Session) -> str:
    if isinstance(bind, Session):
        bind = bind.get_bind()
    return bind.dialect.name


def _provider(bind: Engine | Session) -> ModuleType:
    dialect = _dialect_name(bind)
    if dialect == "sqlite":
        return search_sqlite
    if dialect == "postgresql":
        return search_postgres
    raise SearchUnavailableError(f"Full-text search is not supported on {dialect}.")


def search_schema_available(engine: Engine) -> bool:
    try:
        return _provider(engine).schema_available(engine)
    except SearchUnavailableError:
        return False


def search_unavailable_message(bind: Engine | Session) -> str:
    try:
        provider = _provider(bind)
    except SearchUnavailableError:
        return "Full-text search is unavailable for this database."
    return provider.UNAVAILABLE_MESSAGE


def index_document(db: Session, document: Document) -> None:
    _provider(db).index_document(db, document)


def remove_document_index(db: Session, document_id: str) -> None:
    _provider(db).remove_document_index(db, document_id)


def rebuild_search_index(
    db: Session, *, max_documents: int = MAX_INDEX_REBUILD_DOCUMENTS
) -> int:
    return _provider(db).rebuild_search_index(db, max_documents=max_documents)


def search_documents(
    db: Session,
    *,
    query: str,
    limit: int,
    offset: int,
    category: str | None = None,
    document_type: str | None = None,
) -> list[SearchHit]:
    return _provider(db).search_documents(
        db,
        query=query,
        limit=limit,
        offset=offset,
        category=category,
        document_type=document_type,
    )
