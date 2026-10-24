import hashlib
import re
from dataclasses import dataclass
from datetime import datetime, timezone

from sqlalchemy import and_, delete, func, or_, select
from sqlalchemy.orm import Session

from app.models.document import Document
from app.models.relationship import DocumentRelationship

MAX_RELATIONSHIP_DOCUMENTS = 1_000
DEFAULT_RELATIONSHIP_THRESHOLD = 0.68
MAX_RELATIONSHIP_CANDIDATE_PAIRS = 20_000
MAX_RELATIONSHIP_TEXT_CHARS = 100_000_000
_IDENTIFIER_RE = re.compile(
    r"\b(?:invoice|policy|reference|ref|claim|account|order|serial|model)\s*"
    r"(?:no\.?|number|#)?\s*[:#-]?\s*([A-Z0-9][A-Z0-9/-]{3,39})\b",
    re.IGNORECASE,
)
_LABELED_ENTITY_RE = re.compile(
    r"^\s*(model|product|serial(?: number)?|brand|make)\s*[:#-]\s*(.{2,80})\s*$",
    re.IGNORECASE | re.MULTILINE,
)
_GENERIC_ENTITIES = {
    "document", "product", "appliance", "invoice", "receipt", "warranty",
    "service", "manual", "policy", "certificate", "purchase", "customer",
}
_TYPE_PATTERNS: tuple[tuple[str, tuple[str, ...]], ...] = (
    ("invoice", ("invoice", "amount due", "bill to")),
    ("receipt", ("receipt", "transaction", "purchase")),
    ("warranty", ("warranty",)),
    ("service_record", ("service receipt", "service record", "repair", "maintenance")),
    ("manual", ("user manual", "installation guide", "owner's manual")),
    ("policy", ("insurance policy", "policy number")),
    ("claim", ("claim number", "insurance claim")),
    ("statement", ("statement", "account statement")),
)
_COMPATIBLE_TYPES = {
    frozenset(("invoice", "warranty")),
    frozenset(("invoice", "receipt")),
    frozenset(("invoice", "service_record")),
    frozenset(("invoice", "manual")),
    frozenset(("receipt", "warranty")),
    frozenset(("receipt", "service_record")),
    frozenset(("warranty", "service_record")),
    frozenset(("warranty", "manual")),
    frozenset(("policy", "claim")),
    frozenset(("invoice", "statement")),
}
_COMPLEMENTARY_CATEGORIES = {
    frozenset(("Finance", "Appliances")),
    frozenset(("Finance", "Insurance")),
    frozenset(("Home", "Finance")),
    frozenset(("Appliances", "Finance")),
    frozenset(("Insurance", "Finance")),
}


@dataclass(frozen=True)
class RelationshipSuggestion:
    relationship_type: str
    score: float
    explanation: str
    evidence: list[str]


def _normalize(value: str | None) -> str:
    return re.sub(r"[^a-z0-9]", "", (value or "").casefold())


def _document_text(document: Document) -> str:
    return "\n".join(
        value or ""
        for value in (
            document.extracted_text,
            document.document_title,
            document.original_filename,
        )
    )


def _identifiers(document: Document) -> set[str]:
    values = set()
    if document.reference_number:
        normalized = _normalize(document.reference_number)
        if len(normalized) >= 5 and not re.fullmatch(r"(?:19|20)\d{2}", normalized):
            values.add(normalized)
    for match in _IDENTIFIER_RE.findall(_document_text(document)):
        normalized = _normalize(match)
        if len(normalized) >= 5 and not re.fullmatch(r"(?:19|20)\d{2}", normalized):
            values.add(normalized)
    return values


def _entities(document: Document) -> set[str]:
    entities: set[str] = set()
    for label, value in _LABELED_ENTITY_RE.findall(_document_text(document)):
        normalized = _normalize(value)
        if len(normalized) >= 4 and normalized not in _GENERIC_ENTITIES:
            entities.add(normalized)
    return entities


def _type(document: Document) -> str | None:
    source = _document_text(document).casefold()
    if "service receipt" in source or "service record" in source:
        return "service_record"
    if document.document_type:
        lowered = document.document_type.casefold()
        for name, _terms in _TYPE_PATTERNS:
            if name.replace("_", " ") in lowered:
                return name
    for name, terms in _TYPE_PATTERNS:
        if any(term in source for term in terms):
            return name
    return None


def _date_compatible(first: Document, second: Document) -> bool:
    if not first.document_date or not second.document_date:
        return False
    return abs((first.document_date - second.document_date).days) <= 365 * 5


def _compatible(first: Document, second: Document) -> bool:
    first_type = _type(first)
    second_type = _type(second)
    if not first_type or not second_type or first_type == second_type:
        return False
    return (
        frozenset((first_type, second_type)) in _COMPATIBLE_TYPES
        or frozenset((first.category or "", second.category or "")) in _COMPLEMENTARY_CATEGORIES
    )


def suggest_relationship(
    first: Document,
    second: Document,
    *,
    threshold: float = DEFAULT_RELATIONSHIP_THRESHOLD,
) -> RelationshipSuggestion | None:
    if (
        first.id == second.id
        or not (first.extracted_text or "").strip()
        or not (second.extracted_text or "").strip()
    ):
        return None

    evidence: list[str] = []
    score = 0.0
    relationship_type = "related_documents"
    shared_ids = _identifiers(first) & _identifiers(second)
    if shared_ids:
        score = 0.96
        relationship_type = "shared_reference"
        evidence.extend(f"Matching reference number {item}" for item in sorted(shared_ids))

    shared_entities = _entities(first) & _entities(second)
    if shared_entities:
        score = max(score, 0.86)
        relationship_type = "shared_product"
        evidence.extend(f"Matching labeled product/model identifier {item}" for item in sorted(shared_entities))

    first_issuer = _normalize(first.issuer)
    second_issuer = _normalize(second.issuer)
    same_issuer = bool(first_issuer and len(first_issuer) >= 4 and first_issuer == second_issuer)
    complementary = _compatible(first, second)
    if same_issuer and complementary:
        score = max(score, 0.72 if _date_compatible(first, second) else 0.68)
        relationship_type = "issuer_and_document_set"
        evidence.append(f"Matching issuer: {first.issuer}")
        evidence.append(f"Complementary document types: {_type(first)} and {_type(second)}")
        if _date_compatible(first, second):
            evidence.append("Document dates are within five years")

    if shared_entities and complementary:
        score = max(score, 0.90)
        relationship_type = "product_document_set"
        evidence.append(f"Complementary document types: {_type(first)} and {_type(second)}")

    if score < threshold:
        return None
    if relationship_type == "shared_reference":
        explanation = "Suggested because both documents contain the same labeled reference number."
    elif relationship_type in {"shared_product", "product_document_set"}:
        explanation = "Suggested because both documents identify the same product or model."
    else:
        explanation = "Suggested because the documents share an issuer and have complementary document types."
    return RelationshipSuggestion(
        relationship_type=relationship_type,
        score=round(score, 2),
        explanation=explanation,
        evidence=evidence,
    )


def _pair_key(first_id: str, second_id: str) -> tuple[str, str]:
    return tuple(sorted((first_id, second_id)))


def _stable_relationship_id(source: str, related: str, relation_type: str) -> str:
    return hashlib.sha256(f"{source}\0{related}\0{relation_type}".encode()).hexdigest()[:36]


def _candidate_pairs(documents: list[Document]) -> set[tuple[str, str]]:
    buckets: dict[tuple[str, str], list[str]] = {}
    for document in documents:
        for identifier in _identifiers(document):
            buckets.setdefault(("identifier", identifier), []).append(document.id)
        for entity in _entities(document):
            buckets.setdefault(("entity", entity), []).append(document.id)
        issuer = _normalize(document.issuer)
        if issuer and len(issuer) >= 4:
            buckets.setdefault(("issuer", issuer), []).append(document.id)

    pairs: set[tuple[str, str]] = set()
    for ids in buckets.values():
        unique_ids = sorted(set(ids))
        if len(unique_ids) > 100:
            continue
        for index, first_id in enumerate(unique_ids):
            for second_id in unique_ids[index + 1 :]:
                pairs.add((first_id, second_id))
                if len(pairs) > MAX_RELATIONSHIP_CANDIDATE_PAIRS:
                    raise ValueError(
                        "Relationship rebuild exceeded the safe candidate-pair limit."
                    )
    return pairs


def _build_relationship(
    first: Document,
    second: Document,
    suggestion: RelationshipSuggestion,
) -> DocumentRelationship:
    source, related = _pair_key(first.id, second.id)
    return DocumentRelationship(
        id=_stable_relationship_id(source, related, suggestion.relationship_type),
        source_document_id=source,
        related_document_id=related,
        relationship_type=suggestion.relationship_type,
        score=suggestion.score,
        explanation=suggestion.explanation,
        evidence=suggestion.evidence,
        calculated_at=datetime.now(timezone.utc),
    )


def recalculate_document_relationships(
    db: Session,
    document: Document,
    *,
    max_documents: int = MAX_RELATIONSHIP_DOCUMENTS,
    threshold: float = DEFAULT_RELATIONSHIP_THRESHOLD,
) -> list[DocumentRelationship]:
    count = db.scalar(
        select(func.count(Document.id)).where(
            Document.id != document.id,
            Document.extracted_text.is_not(None),
        )
    ) or 0
    if count > max_documents:
        raise ValueError(f"Relationship calculation is limited to {max_documents} comparison documents.")
    documents = []
    total_chars = len(document.extracted_text or "")
    for candidate in db.scalars(
        select(Document)
        .where(Document.id != document.id, Document.extracted_text.is_not(None))
        .order_by(Document.id)
        .execution_options(yield_per=100)
    ):
        total_chars += len(candidate.extracted_text or "")
        if total_chars > MAX_RELATIONSHIP_TEXT_CHARS:
            raise ValueError("Relationship calculation is limited to 100 million text characters.")
        documents.append(candidate)

    db.execute(
        delete(DocumentRelationship).where(
            or_(
                DocumentRelationship.source_document_id == document.id,
                DocumentRelationship.related_document_id == document.id,
            )
        )
    )
    suggestions = []
    for candidate in documents:
        suggestion = suggest_relationship(document, candidate, threshold=threshold)
        if suggestion:
            suggestions.append(_build_relationship(document, candidate, suggestion))
    db.add_all(suggestions)
    db.commit()
    for relationship in suggestions:
        db.refresh(relationship)
    return suggestions


def rebuild_relationships(
    db: Session,
    *,
    max_documents: int = MAX_RELATIONSHIP_DOCUMENTS,
    threshold: float = DEFAULT_RELATIONSHIP_THRESHOLD,
) -> int:
    count = db.scalar(
        select(func.count(Document.id)).where(Document.extracted_text.is_not(None))
    ) or 0
    if count > max_documents:
        raise ValueError(f"Relationship rebuild is limited to {max_documents} documents.")
    documents = []
    total_chars = 0
    for document in db.scalars(
        select(Document)
        .where(Document.extracted_text.is_not(None))
        .order_by(Document.id)
        .execution_options(yield_per=100)
    ):
        total_chars += len(document.extracted_text or "")
        if total_chars > MAX_RELATIONSHIP_TEXT_CHARS:
            raise ValueError("Relationship rebuild is limited to 100 million text characters.")
        documents.append(document)
    by_id = {document.id: document for document in documents}
    db.execute(delete(DocumentRelationship))
    relationships: list[DocumentRelationship] = []
    for first_id, second_id in sorted(_candidate_pairs(documents)):
        suggestion = suggest_relationship(
            by_id[first_id],
            by_id[second_id],
            threshold=threshold,
        )
        if suggestion:
            relationships.append(
                _build_relationship(by_id[first_id], by_id[second_id], suggestion)
            )
    db.add_all(relationships)
    db.commit()
    return len(relationships)


def list_document_relationships(
    db: Session,
    document: Document,
    *,
    limit: int = 20,
) -> list[tuple[DocumentRelationship, Document]]:
    return list(
        db.execute(
            select(DocumentRelationship, Document)
            .join(
                Document,
                or_(
                    and_(
                        DocumentRelationship.source_document_id == document.id,
                        DocumentRelationship.related_document_id == Document.id,
                    ),
                    and_(
                        DocumentRelationship.related_document_id == document.id,
                        DocumentRelationship.source_document_id == Document.id,
                    ),
                ),
            )
            .where(
                or_(
                    DocumentRelationship.source_document_id == document.id,
                    DocumentRelationship.related_document_id == document.id,
                )
            )
            .order_by(DocumentRelationship.score.desc(), DocumentRelationship.id)
            .limit(limit)
        ).all()
    )


def get_relationship(db: Session, relationship_id: str) -> DocumentRelationship | None:
    return db.get(DocumentRelationship, relationship_id)


def remove_document_relationships(db: Session, document_id: str) -> None:
    db.execute(
        delete(DocumentRelationship).where(
            or_(
                DocumentRelationship.source_document_id == document_id,
                DocumentRelationship.related_document_id == document_id,
            )
        )
    )
