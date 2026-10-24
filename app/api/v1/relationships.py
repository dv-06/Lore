from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.document import Document
from app.schemas.relationship import (
    RelatedDocument,
    RelatedDocumentsResponse,
    RelationshipDetailResponse,
    RelationshipRebuildResponse,
    RelationshipSuggestionResponse,
)
from app.services.documents import DocumentNotFoundError, get_document
from app.services.relationships import (
    get_relationship,
    list_document_relationships,
    recalculate_document_relationships,
    rebuild_relationships,
)

router = APIRouter()
DbSession = Annotated[Session, Depends(get_db)]


@router.get("/documents/{document_id}/related", response_model=RelatedDocumentsResponse)
def read_related_documents(
    document_id: str,
    db: DbSession,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
) -> RelatedDocumentsResponse:
    try:
        document = get_document(db, document_id)
    except DocumentNotFoundError as exc:
        raise HTTPException(status_code=404, detail="Document not found.") from exc
    if not (document.extracted_text or "").strip():
        raise HTTPException(
            status_code=409,
            detail="Document has no extracted text; retry extraction before finding related documents.",
        )
    relationships = list_document_relationships(db, document, limit=limit)
    items = []
    for relationship, related in relationships:
        items.append(
            RelationshipSuggestionResponse(
                id=relationship.id,
                relationship_type=relationship.relationship_type,
                score=relationship.score,
                explanation=relationship.explanation,
                evidence=relationship.evidence,
                calculated_at=relationship.calculated_at,
                related_document=RelatedDocument(
                    id=related.id,
                    filename=related.original_filename,
                    title=related.document_title,
                    category=related.category,
                    document_type=related.document_type,
                ),
            )
        )
    return RelatedDocumentsResponse(document_id=document.id, items=items)


@router.post("/documents/{document_id}/related/recalculate", response_model=RelatedDocumentsResponse)
def recalculate_related_documents(
    document_id: str,
    db: DbSession,
    request: Request,
) -> RelatedDocumentsResponse:
    try:
        document = get_document(db, document_id)
    except DocumentNotFoundError as exc:
        raise HTTPException(status_code=404, detail="Document not found.") from exc
    if not (document.extracted_text or "").strip():
        raise HTTPException(status_code=409, detail="Document has no extracted text.")
    try:
        recalculate_document_relationships(
            db,
            document,
            max_documents=request.app.state.settings.relationship_max_documents,
            threshold=request.app.state.settings.relationship_threshold,
        )
    except ValueError as exc:
        raise HTTPException(status_code=413, detail=str(exc)) from exc
    return read_related_documents(document_id, db)


@router.post("/relationships/rebuild", response_model=RelationshipRebuildResponse)
def rebuild_all_relationships(db: DbSession, request: Request) -> RelationshipRebuildResponse:
    try:
        count = rebuild_relationships(
            db,
            max_documents=request.app.state.settings.relationship_max_documents,
            threshold=request.app.state.settings.relationship_threshold,
        )
    except ValueError as exc:
        raise HTTPException(status_code=413, detail=str(exc)) from exc
    documents_count = db.query(Document.id).filter(Document.extracted_text.is_not(None)).count()
    return RelationshipRebuildResponse(
        processed_documents=documents_count,
        relationships_created=count,
    )


@router.get("/relationships/{relationship_id}", response_model=RelationshipDetailResponse)
def read_relationship(relationship_id: str, db: DbSession) -> RelationshipDetailResponse:
    relationship = get_relationship(db, relationship_id)
    if relationship is None:
        raise HTTPException(status_code=404, detail="Relationship not found.")
    return RelationshipDetailResponse.model_validate(relationship)
