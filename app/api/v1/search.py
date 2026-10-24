from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.schemas.document import Category
from app.schemas.search import SearchRebuildResponse, SearchResponse, SearchResult
from app.services.search import (
    MAX_SEARCH_RESULTS,
    SearchQueryError,
    SearchRebuildLimitError,
    SearchUnavailableError,
    rebuild_search_index,
    search_documents,
)

router = APIRouter()
DbSession = Annotated[Session, Depends(get_db)]


@router.get("", response_model=SearchResponse)
def search(
    db: DbSession,
    request: Request,
    q: Annotated[str, Query(min_length=1, max_length=256)],
    limit: Annotated[int, Query(ge=1, le=MAX_SEARCH_RESULTS)] = 20,
    offset: Annotated[int, Query(ge=0, le=100_000)] = 0,
    category: Category | None = None,
    document_type: Annotated[str | None, Query(max_length=100)] = None,
) -> SearchResponse:
    if not request.app.state.fts5_available:
        raise HTTPException(
            status_code=503,
            detail="SQLite FTS5 is unavailable or the local index requires a bounded rebuild.",
        )
    try:
        hits = search_documents(
            db,
            query=q,
            limit=limit,
            offset=offset,
            category=category,
            document_type=document_type,
        )
    except SearchQueryError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except SearchUnavailableError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    return SearchResponse(
        query=q,
        items=[SearchResult.model_validate(hit.__dict__) for hit in hits],
        limit=limit,
        offset=offset,
    )


@router.post("/rebuild", response_model=SearchRebuildResponse)
def rebuild_search(db: DbSession, request: Request) -> SearchRebuildResponse:
    try:
        count = rebuild_search_index(
            db,
            max_documents=request.app.state.settings.search_rebuild_max_documents,
        )
    except SearchRebuildLimitError as exc:
        raise HTTPException(status_code=413, detail=str(exc)) from exc
    except SearchUnavailableError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    request.app.state.fts5_available = True
    return SearchRebuildResponse(indexed_documents=count)
