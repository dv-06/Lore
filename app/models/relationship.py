from datetime import datetime, timezone
from uuid import uuid4

from sqlalchemy import (
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    JSON,
    String,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class DocumentRelationship(Base):
    __tablename__ = "document_relationships"
    __table_args__ = (
        UniqueConstraint(
            "source_document_id",
            "related_document_id",
            "relationship_type",
            name="uq_document_relationship_pair_type",
        ),
        CheckConstraint(
            "source_document_id < related_document_id",
            name="ck_document_relationship_normalized_pair",
        ),
        Index("ix_document_relationship_source", "source_document_id"),
        Index("ix_document_relationship_related", "related_document_id"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    source_document_id: Mapped[str] = mapped_column(
        ForeignKey("documents.id", ondelete="CASCADE"),
        nullable=False,
    )
    related_document_id: Mapped[str] = mapped_column(
        ForeignKey("documents.id", ondelete="CASCADE"),
        nullable=False,
    )
    relationship_type: Mapped[str] = mapped_column(String(40), nullable=False)
    score: Mapped[float] = mapped_column(nullable=False)
    explanation: Mapped[str] = mapped_column(String(500), nullable=False)
    evidence: Mapped[list[str]] = mapped_column(JSON, nullable=False, default=list)
    calculated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(timezone.utc),
    )
