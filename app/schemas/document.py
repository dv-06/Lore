from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


ExtractionStatus = Literal["extracted", "not_requested", "failed"]
ProcessingStatus = Literal["completed", "failed"]
Category = Literal[
    "Finance",
    "Education",
    "Health",
    "Identity",
    "Home",
    "Appliances",
    "Insurance",
    "Travel",
    "Work",
    "Legal",
    "Uncategorized",
]


class DocumentResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    original_filename: str
    media_type: str | None
    size_bytes: int
    sha256: str | None
    extraction_status: ExtractionStatus
    processing_status: ProcessingStatus
    processing_error: str | None
    uploaded_at: datetime
    category: Category | None
    classification_confidence: float | None
    classification_reasons: list[str]
    classification_method: str | None
    document_title: str | None
    document_date: date | None
    document_type: str | None
    issuer: str | None
    reference_number: str | None
    tags: list[str]


class DocumentListResponse(BaseModel):
    items: list[DocumentResponse]
    limit: int
    offset: int


class CategoryCount(BaseModel):
    category: Category
    document_count: int


class CategoriesResponse(BaseModel):
    items: list[CategoryCount]


class OrganizationUpdate(BaseModel):
    category: Category | None = None
    tags: list[str] | None = Field(default=None, max_length=20)

    @field_validator("tags")
    @classmethod
    def normalize_tags(cls, tags: list[str] | None) -> list[str] | None:
        if tags is None:
            return None
        normalized: list[str] = []
        for tag in tags:
            clean_tag = tag.strip()
            if not clean_tag or len(clean_tag) > 40:
                raise ValueError("Tags must contain 1 to 40 non-whitespace characters.")
            if clean_tag.casefold() not in {existing.casefold() for existing in normalized}:
                normalized.append(clean_tag)
        return normalized

    @model_validator(mode="after")
    def require_update(self) -> "OrganizationUpdate":
        if self.category is None and self.tags is None:
            raise ValueError("Provide a category, tags, or both.")
        return self


class ReclassifyRequest(BaseModel):
    document_ids: list[str] = Field(min_length=1, max_length=100)

    @field_validator("document_ids")
    @classmethod
    def require_unique_ids(cls, ids: list[str]) -> list[str]:
        if len(ids) != len(set(ids)):
            raise ValueError("Document IDs must be unique.")
        return ids


class ReclassifyResponse(BaseModel):
    processed_count: int
    items: list[DocumentResponse]
