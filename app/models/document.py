from datetime import date, datetime, timezone
from uuid import uuid4

from sqlalchemy import CheckConstraint, Date, DateTime, Float, JSON, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class Document(Base):
    __tablename__ = "documents"
    __table_args__ = (
        CheckConstraint("size_bytes >= 0", name="ck_documents_nonnegative_size"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    original_filename: Mapped[str] = mapped_column(String(255), nullable=False)
    media_type: Mapped[str | None] = mapped_column(String(255), nullable=True)
    size_bytes: Mapped[int] = mapped_column(nullable=False)
    storage_path: Mapped[str] = mapped_column(String(1024), nullable=False, unique=True)
    sha256: Mapped[str | None] = mapped_column(String(64), nullable=True, unique=True, index=True)
    extracted_text: Mapped[str | None] = mapped_column(Text, nullable=True)
    extraction_status: Mapped[str] = mapped_column(String(32), nullable=False)
    processing_status: Mapped[str] = mapped_column(String(32), nullable=False)
    processing_error: Mapped[str | None] = mapped_column(String(500), nullable=True)
    category: Mapped[str | None] = mapped_column(String(32), nullable=True, index=True)
    classification_confidence: Mapped[float | None] = mapped_column(Float, nullable=True)
    classification_reasons: Mapped[list[str]] = mapped_column(JSON, nullable=False, default=list)
    classification_method: Mapped[str | None] = mapped_column(String(32), nullable=True)
    document_title: Mapped[str | None] = mapped_column(String(120), nullable=True)
    document_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    document_type: Mapped[str | None] = mapped_column(String(100), nullable=True, index=True)
    issuer: Mapped[str | None] = mapped_column(String(255), nullable=True, index=True)
    reference_number: Mapped[str | None] = mapped_column(String(100), nullable=True, index=True)
    tags: Mapped[list[str]] = mapped_column(JSON, nullable=False, default=list)
    uploaded_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
    )
