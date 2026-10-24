import re
from dataclasses import dataclass
from datetime import date

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models.document import Document
from app.schemas.document import Category

CATEGORIES: tuple[Category, ...] = (
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
)
CLASSIFICATION_METHOD = "rules-v1"

_CATEGORY_TERMS: dict[Category, tuple[str, ...]] = {
    "Finance": (
        "invoice", "receipt", "bank statement", "account statement", "transaction",
        "balance due", "payment due", "tax return", "credit card", "debit card",
        "purchase order", "amount due", "subtotal", "routing number",
    ),
    "Education": (
        "transcript", "student", "university", "school", "semester", "course",
        "enrollment", "tuition", "grade report", "diploma", "academic",
    ),
    "Health": (
        "medical", "patient", "prescription", "diagnosis", "physician", "clinic",
        "hospital", "laboratory", "lab result", "health record", "dosage",
    ),
    "Identity": (
        "passport", "driver license", "driving licence", "identity card", "social security",
        "birth certificate", "national id", "residence permit",
    ),
    "Home": (
        "lease agreement", "rental agreement", "mortgage", "landlord", "tenant",
        "property deed", "utility bill", "electricity bill", "water bill", "rent",
    ),
    "Appliances": (
        "appliance", "serial number", "model number", "user manual", "installation guide",
        "warranty card", "refrigerator", "washing machine", "dishwasher",
    ),
    "Insurance": (
        "insurance", "policy number", "premium", "insured", "coverage", "claim number",
        "beneficiary", "deductible", "underwriter",
    ),
    "Travel": (
        "boarding pass", "itinerary", "flight", "airline", "hotel reservation",
        "booking confirmation", "train ticket", "departure", "arrival", "reservation",
    ),
    "Work": (
        "employment", "employer", "employee", "pay stub", "payslip", "salary",
        "job offer", "performance review", "timesheet", "payroll", "workplace",
    ),
    "Legal": (
        "agreement", "contract", "court", "legal notice", "attorney", "law firm",
        "affidavit", "non-disclosure", "terms and conditions", "statute",
    ),
    "Uncategorized": (),
}

_DOCUMENT_TYPES: tuple[tuple[str, tuple[str, ...]], ...] = (
    ("invoice", ("invoice", "amount due", "bill to")),
    ("receipt", ("receipt", "transaction", "purchase")),
    ("bank statement", ("bank statement", "account statement")),
    ("insurance policy", ("insurance policy", "policy number", "coverage")),
    ("transcript", ("transcript", "grade report")),
    ("medical record", ("medical record", "patient", "diagnosis")),
    ("identity document", ("passport", "identity card", "driver license", "birth certificate")),
    ("lease", ("lease agreement", "rental agreement", "tenant")),
    ("warranty", ("warranty", "serial number")),
    ("travel itinerary", ("itinerary", "boarding pass", "flight")),
    ("employment document", ("employment", "pay stub", "payslip", "job offer")),
    ("contract", ("contract", "agreement", "legal notice")),
)
_DATE_PATTERNS = (
    re.compile(r"\b(20\d{2}|19\d{2})-(\d{1,2})-(\d{1,2})\b"),
    re.compile(
        r"\b(January|February|March|April|May|June|July|August|September|October|November|December)"
        r"\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+((?:19|20)\d{2})\b",
        re.IGNORECASE,
    ),
    re.compile(
        r"\b(\d{1,2})\s+(January|February|March|April|May|June|July|August|September|October|November|December)"
        r"\s+((?:19|20)\d{2})\b",
        re.IGNORECASE,
    ),
    re.compile(r"\b(\d{1,2})[./-](\d{1,2})[./-]((?:19|20)\d{2})\b"),
)
_MONTHS = {
    name.lower(): index
    for index, name in enumerate(
        (
            "January", "February", "March", "April", "May", "June",
            "July", "August", "September", "October", "November", "December",
        ),
        start=1,
    )
}
_REFERENCE_PATTERNS = (
    re.compile(
        r"\b(?:invoice|policy|reference|ref|claim|account|order)\s*(?:no\.?|number|#)\s*[:#-]?\s*([A-Z0-9][A-Z0-9/-]{2,39})\b",
        re.IGNORECASE,
    ),
)
_ISSUER_PATTERNS = (
    re.compile(r"^\s*(?:issued by|issuer|from)\s*:\s*(.{2,100})\s*$", re.IGNORECASE | re.MULTILINE),
    re.compile(r"^\s*(?:prepared by|provided by)\s*:\s*(.{2,100})\s*$", re.IGNORECASE | re.MULTILINE),
)


@dataclass(frozen=True)
class Classification:
    category: Category
    confidence: float
    reasons: list[str]
    method: str
    document_title: str | None
    document_type: str | None
    document_date: date | None
    issuer: str | None
    reference_number: str | None
    tags: list[str]


def _term_matches(source: str, term: str) -> bool:
    pattern = r"(?<!\w)" + re.escape(term).replace(r"\ ", r"\s+") + r"(?!\w)"
    return re.search(pattern, source, re.IGNORECASE) is not None


def _parse_date(source: str) -> date | None:
    for index, pattern in enumerate(_DATE_PATTERNS):
        match = pattern.search(source)
        if not match:
            continue
        groups = match.groups()
        try:
            if index == 0:
                parsed = date(int(groups[0]), int(groups[1]), int(groups[2]))
            elif index == 1:
                parsed = date(int(groups[2]), _MONTHS[groups[0].lower()], int(groups[1]))
            elif index == 2:
                parsed = date(int(groups[2]), _MONTHS[groups[1].lower()], int(groups[0]))
            else:
                first, second, year = (int(value) for value in groups)
                if first <= 12 and second <= 12:
                    continue
                day, month = (first, second) if first > 12 else (second, first)
                parsed = date(year, month, day)
        except ValueError:
            continue
        return parsed
    return None


def _extract_document_type(source: str) -> str | None:
    for label, terms in _DOCUMENT_TYPES:
        if any(_term_matches(source, term) for term in terms):
            return label
    return None


def _extract_issuer(source: str) -> str | None:
    for pattern in _ISSUER_PATTERNS:
        match = pattern.search(source)
        if match:
            return match.group(1).strip()[:255]
    return None


def _extract_reference(source: str) -> str | None:
    for pattern in _REFERENCE_PATTERNS:
        match = pattern.search(source)
        if match:
            return match.group(1)[:100]
    return None


def _extract_title(filename: str, text: str) -> str | None:
    for line in text.splitlines():
        candidate = " ".join(line.split()).strip(" -_")
        if candidate and len(candidate) <= 120 and not _parse_date(candidate):
            return candidate
    stem = filename.rsplit(".", maxsplit=1)[0].replace("_", " ").replace("-", " ").strip()
    return stem[:120] or None


def classify_document(
    *,
    filename: str,
    extracted_text: str | None,
    existing_tags: list[str] | None = None,
) -> Classification:
    """Classify untrusted local text with fixed rules; never interprets or executes it."""
    text = extracted_text or ""
    source = f"{filename}\n{text}"
    scores: dict[Category, int] = {}
    reasons_by_category: dict[Category, list[str]] = {}
    for category in CATEGORIES:
        if category == "Uncategorized":
            continue
        matches = [term for term in _CATEGORY_TERMS[category] if _term_matches(source, term)]
        if matches:
            scores[category] = min(6, len(matches))
            reasons_by_category[category] = [f"Matched {term!r}" for term in matches[:3]]

    if scores:
        category = min(scores, key=lambda name: (-scores[name], CATEGORIES.index(name)))
        score = scores[category]
        confidence = min(0.95, 0.55 + 0.1 * score)
        reasons = reasons_by_category[category]
        if len(scores) > 1:
            reasons.append("Selected the category with the strongest rule score")
    else:
        category = "Uncategorized"
        confidence = 0.0
        reasons = ["No category-specific indicators were found"]

    document_type = _extract_document_type(source)
    document_date = _parse_date(text)
    issuer = _extract_issuer(text)
    reference_number = _extract_reference(text)
    tags = list(existing_tags or [])
    if category != "Uncategorized" and category.casefold() not in {
        tag.casefold() for tag in tags
    }:
        tags.insert(0, category)
    if document_type and document_type.casefold() not in {tag.casefold() for tag in tags}:
        tags.append(document_type)
    return Classification(
        category=category,
        confidence=confidence,
        reasons=reasons,
        method=CLASSIFICATION_METHOD,
        document_title=_extract_title(filename, text),
        document_type=document_type,
        document_date=document_date,
        issuer=issuer,
        reference_number=reference_number,
        tags=tags[:20],
    )


def apply_classification(document: Document) -> Document:
    if not document.original_filename:
        raise ValueError("A filename is required to classify this document.")
    result = classify_document(
        filename=document.original_filename,
        extracted_text=document.extracted_text,
        existing_tags=document.tags,
    )
    document.category = result.category
    document.classification_confidence = result.confidence
    document.classification_reasons = result.reasons
    document.classification_method = result.method
    document.document_title = result.document_title
    document.document_type = result.document_type
    document.document_date = result.document_date
    document.issuer = result.issuer
    document.reference_number = result.reference_number
    document.tags = result.tags
    return document


def count_documents_by_category(db: Session) -> dict[str, int]:
    counts = dict(
        db.execute(
            select(Document.category, func.count(Document.id))
            .group_by(Document.category)
        ).all()
    )
    counts["Uncategorized"] = counts.get("Uncategorized", 0) + counts.get(None, 0)
    return {category: counts.get(category, 0) for category in CATEGORIES}


def update_organization(
    document: Document,
    *,
    category: Category | None,
    tags: list[str] | None,
) -> Document:
    if category is not None:
        document.category = category
        document.classification_confidence = None
        document.classification_reasons = ["Category set manually by user"]
        document.classification_method = "manual"
    if tags is not None:
        document.tags = tags
    return document
