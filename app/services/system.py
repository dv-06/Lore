from sqlalchemy import text
from sqlalchemy.orm import Session

from app.schemas.system import SystemStatusResponse


def get_system_status(db: Session) -> SystemStatusResponse:
    db.execute(text("SELECT 1"))
    return SystemStatusResponse(status="ok", database="ok")

