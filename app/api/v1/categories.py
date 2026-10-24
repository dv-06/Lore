from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.schemas.document import CategoriesResponse
from app.services.organization import CATEGORIES, count_documents_by_category

router = APIRouter()
DbSession = Annotated[Session, Depends(get_db)]


@router.get("", response_model=CategoriesResponse)
def read_categories(db: DbSession) -> CategoriesResponse:
    counts = count_documents_by_category(db)
    return CategoriesResponse(
        items=[
            {"category": category, "document_count": counts[category]}
            for category in CATEGORIES
        ]
    )
