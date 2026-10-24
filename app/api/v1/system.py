from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.schemas.system import SystemStatusResponse
from app.services.system import get_system_status

router = APIRouter()


@router.get("/status", response_model=SystemStatusResponse)
def read_system_status(db: Session = Depends(get_db)) -> SystemStatusResponse:
    return get_system_status(db)

