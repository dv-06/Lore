from datetime import datetime

from pydantic import BaseModel, ConfigDict


class RelatedDocument(BaseModel):
    id: str
    filename: str
    title: str | None
    category: str | None
    document_type: str | None


class RelationshipSuggestionResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    relationship_type: str
    score: float
    explanation: str
    evidence: list[str]
    calculated_at: datetime
    related_document: RelatedDocument


class RelatedDocumentsResponse(BaseModel):
    document_id: str
    items: list[RelationshipSuggestionResponse]


class RelationshipDetailResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    source_document_id: str
    related_document_id: str
    relationship_type: str
    score: float
    explanation: str
    evidence: list[str]
    calculated_at: datetime


class RelationshipRebuildResponse(BaseModel):
    processed_documents: int
    relationships_created: int
