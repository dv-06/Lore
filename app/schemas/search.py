from pydantic import BaseModel


class SearchResult(BaseModel):
    document_id: str
    filename: str
    title: str | None
    category: str | None
    snippet: str
    matching_fields: list[str]
    score: float
    document_type: str | None


class SearchResponse(BaseModel):
    query: str
    items: list[SearchResult]
    limit: int
    offset: int


class SearchRebuildResponse(BaseModel):
    indexed_documents: int

