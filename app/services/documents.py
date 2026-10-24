import hashlib
import io
import logging
import uuid
from dataclasses import dataclass
from pathlib import Path

import pymupdf
from PIL import Image, UnidentifiedImageError
from sqlalchemy import or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.models.document import Document
from app.services.organization import apply_classification
from app.services.relationships import remove_document_relationships
from app.services.ocr import (
    MAX_IMAGE_PIXELS,
    OCRDependencyError,
    OCRProcessingError,
    extract_image_text,
)
from app.services.search import index_document, remove_document_index

logger = logging.getLogger(__name__)

SUPPORTED_TYPES: dict[str, tuple[str, ...]] = {
    ".pdf": ("application/pdf",),
    ".txt": ("text/plain",),
    ".png": ("image/png",),
    ".jpg": ("image/jpeg", "image/jpg"),
    ".jpeg": ("image/jpeg", "image/jpg"),
    ".gif": ("image/gif",),
    ".bmp": ("image/bmp", "image/x-ms-bmp"),
    ".tif": ("image/tiff",),
    ".tiff": ("image/tiff",),
    ".webp": ("image/webp",),
}
MIME_EXTENSION: dict[str, str] = {
    "image/jpeg": ".jpg",
    "image/jpg": ".jpg",
    "image/png": ".png",
    "image/gif": ".gif",
    "image/bmp": ".bmp",
    "image/x-ms-bmp": ".bmp",
    "image/tiff": ".tiff",
    "image/webp": ".webp",
    "application/pdf": ".pdf",
    "text/plain": ".txt",
}
class DocumentInputError(ValueError):
    pass


class DocumentNotFoundError(LookupError):
    pass


class DuplicateDocumentError(Exception):
    def __init__(self, document_id: str) -> None:
        self.document_id = document_id


class ExtractionDependencyError(RuntimeError):
    pass


class OCRDisabledError(RuntimeError):
    pass


class ExtractionError(RuntimeError):
    pass


class StorageCleanupError(RuntimeError):
    pass


@dataclass(frozen=True)
class ValidatedFile:
    filename: str
    extension: str
    media_type: str
    content: bytes
    sha256: str


class UnsupportedDocumentTypeError(DocumentInputError):
    pass


def sanitize_filename(filename: str | None) -> tuple[str, str]:
    if not filename:
        raise DocumentInputError("A filename is required.")
    leaf = filename.replace("\\", "/").rsplit("/", maxsplit=1)[-1]
    leaf = "".join(char for char in leaf if char >= " " and char != "\x7f").strip()
    if not leaf or leaf in {".", ".."} or len(leaf) > 255:
        raise DocumentInputError("The filename is invalid or too long.")
    extension = Path(leaf).suffix.lower()
    if extension not in SUPPORTED_TYPES:
        raise UnsupportedDocumentTypeError("Unsupported document extension.")
    return leaf, extension


def validate_document(
    filename: str | None,
    declared_type: str | None,
    content: bytes,
) -> ValidatedFile:
    safe_name, extension = sanitize_filename(filename)
    declared_type = (declared_type or "").split(";", maxsplit=1)[0].strip().lower()
    allowed_types = SUPPORTED_TYPES[extension]
    if declared_type not in allowed_types and declared_type != "application/octet-stream":
        raise UnsupportedDocumentTypeError(
            "The declared MIME type does not match the filename extension."
        )
    if not content:
        raise DocumentInputError("Empty documents are not supported.")

    if extension == ".pdf":
        if b"%PDF-" not in content[:1024]:
            raise DocumentInputError("The file does not have a valid PDF signature.")
        try:
            with pymupdf.open(stream=content, filetype="pdf") as pdf:
                if pdf.is_encrypted:
                    raise DocumentInputError("Encrypted PDFs are not supported.")
                if pdf.page_count > 1000:
                    raise DocumentInputError("PDFs may contain at most 1000 pages.")
        except (pymupdf.FileDataError, pymupdf.EmptyFileError, RuntimeError) as exc:
            if isinstance(exc, DocumentInputError):
                raise
            raise DocumentInputError("The PDF is malformed or unreadable.") from exc
        actual_type = "application/pdf"
    elif extension == ".txt":
        if b"\x00" in content:
            raise DocumentInputError("The text file contains binary data.")
        try:
            content.decode("utf-8-sig")
        except UnicodeDecodeError as exc:
            raise DocumentInputError("Text documents must use UTF-8 encoding.") from exc
        actual_type = "text/plain"
    else:
        try:
            with Image.open(io.BytesIO(content)) as image:
                actual_type = Image.MIME.get(image.format or "", "")
                if image.width * image.height > MAX_IMAGE_PIXELS:
                    raise DocumentInputError("The image dimensions exceed the supported limit.")
                image.verify()
        except (UnidentifiedImageError, OSError, Image.DecompressionBombError) as exc:
            raise DocumentInputError("The image is malformed or unreadable.") from exc
        extension_matches = MIME_EXTENSION.get(actual_type) == extension or (
            extension in {".jpg", ".jpeg"} and actual_type == "image/jpeg"
        ) or (extension == ".tif" and actual_type == "image/tiff")
        if not actual_type or not extension_matches:
            raise DocumentInputError("The image signature does not match its extension.")

    return ValidatedFile(
        filename=safe_name,
        extension=extension,
        media_type=actual_type,
        content=content,
        sha256=hashlib.sha256(content).hexdigest(),
    )


def documents_directory(settings: Settings) -> Path:
    return (Path(settings.data_dir).expanduser() / "documents").resolve()


def _document_path(settings: Settings, storage_path: str) -> Path:
    relative = Path(storage_path)
    root = documents_directory(settings)
    if relative.is_absolute() or len(relative.parts) != 1 or relative.name != storage_path:
        raise StorageCleanupError("Stored document path is invalid.")
    candidate = (root / relative).resolve()
    if not candidate.is_relative_to(root):
        raise StorageCleanupError("Stored document path escapes the local document directory.")
    return candidate


def extract_text(
    content: bytes,
    media_type: str,
    settings: Settings,
) -> tuple[str | None, str, str | None]:
    try:
        if media_type == "text/plain":
            text = content.decode("utf-8-sig")
        elif media_type == "application/pdf":
            with pymupdf.open(stream=content, filetype="pdf") as pdf:
                text = "\n".join(page.get_text() for page in pdf)
        elif media_type.startswith("image/"):
            if not settings.enable_ocr:
                return None, "not_requested", None
            try:
                text = extract_image_text(content)
            except OCRDependencyError as exc:
                raise ExtractionDependencyError(str(exc)) from exc
            except OCRProcessingError as exc:
                raise ExtractionError(str(exc)) from exc
        else:
            raise ExtractionError("No extractor is available for this document type.")
    except (
        pymupdf.FileDataError,
        pymupdf.EmptyFileError,
        RuntimeError,
        OSError,
        UnicodeDecodeError,
    ) as exc:
        if isinstance(exc, (ExtractionDependencyError, ExtractionError)):
            raise
        raise ExtractionError("Document text extraction failed.") from exc

    text = text[: settings.max_extracted_text_chars]
    return text, "extracted", None


def upload_document(
    db: Session,
    settings: Settings,
    filename: str | None,
    declared_type: str | None,
    content: bytes,
) -> Document:
    validated = validate_document(filename, declared_type, content)
    existing = db.scalar(select(Document).where(Document.sha256 == validated.sha256))
    if existing:
        raise DuplicateDocumentError(existing.id)

    document_id = str(uuid.uuid4())
    storage_name = f"{document_id}{validated.extension}"
    target = _document_path(settings, storage_name)
    temporary = _document_path(settings, f".{document_id}.upload")
    target.parent.mkdir(parents=True, exist_ok=True)
    try:
        with temporary.open("xb") as file_obj:
            file_obj.write(validated.content)
            file_obj.flush()
        temporary.replace(target)
        try:
            text, extraction_status, processing_error = extract_text(
                validated.content,
                validated.media_type,
                settings,
            )
        except ExtractionDependencyError as exc:
            text, extraction_status, processing_error = None, "failed", str(exc)
        except ExtractionError as exc:
            text, extraction_status, processing_error = None, "failed", str(exc)

        document = Document(
            id=document_id,
            original_filename=validated.filename,
            media_type=validated.media_type,
            size_bytes=len(validated.content),
            storage_path=storage_name,
            sha256=validated.sha256,
            extracted_text=text,
            extraction_status=extraction_status,
            processing_status="failed" if processing_error else "completed",
            processing_error=processing_error,
        )
        apply_classification(document)
        db.add(document)
        index_document(db, document)
        db.commit()
        db.refresh(document)
        return document
    except IntegrityError as exc:
        db.rollback()
        target.unlink(missing_ok=True)
        duplicate = db.scalar(select(Document).where(Document.sha256 == validated.sha256))
        if duplicate:
            raise DuplicateDocumentError(duplicate.id) from exc
        raise
    except Exception:
        db.rollback()
        target.unlink(missing_ok=True)
        raise
    finally:
        temporary.unlink(missing_ok=True)


def list_documents(
    db: Session,
    limit: int,
    offset: int,
    category: str | None = None,
) -> list[Document]:
    statement = select(Document)
    if category is not None:
        if category == "Uncategorized":
            statement = statement.where(
                or_(Document.category == category, Document.category.is_(None))
            )
        else:
            statement = statement.where(Document.category == category)
    return list(db.scalars(statement.order_by(Document.uploaded_at.desc(), Document.id).limit(limit).offset(offset)))


def get_document(db: Session, document_id: str) -> Document:
    document = db.get(Document, document_id)
    if document is None:
        raise DocumentNotFoundError(document_id)
    return document


def get_document_file(settings: Settings, document: Document) -> Path:
    path = _document_path(settings, document.storage_path)
    if not path.is_file():
        raise DocumentNotFoundError(document.id)
    return path


def delete_document(db: Session, settings: Settings, document: Document) -> None:
    path = _document_path(settings, document.storage_path)
    tombstone = _document_path(settings, f".{uuid.uuid4().hex}.deleting")
    moved_file = False
    if path.exists():
        path.replace(tombstone)
        moved_file = True
    try:
        remove_document_index(db, document.id)
        db.delete(document)
        db.commit()
    except Exception:
        db.rollback()
        if moved_file and tombstone.exists():
            tombstone.replace(path)
        raise
    if moved_file:
        try:
            tombstone.unlink()
        except OSError as exc:
            logger.exception("Deleted document metadata but failed to remove stored file")
            raise StorageCleanupError(
                "Document metadata was deleted, but the stored file could not be removed."
            ) from exc


def retry_document_extraction(
    db: Session,
    settings: Settings,
    document: Document,
) -> Document:
    if document.media_type and document.media_type.startswith("image/") and not settings.enable_ocr:
        raise OCRDisabledError(
            "Image extraction is disabled; set LORE_ENABLE_OCR=true and install the OCR requirements."
        )
    path = get_document_file(settings, document)
    try:
        content = path.read_bytes()
        text, extraction_status, processing_error = extract_text(
            content,
            document.media_type,
            settings,
        )
    except ExtractionDependencyError as exc:
        document.extracted_text = None
        document.extraction_status = "failed"
        document.processing_status = "failed"
        document.processing_error = str(exc)
        db.commit()
        raise
    except ExtractionError as exc:
        document.extracted_text = None
        document.extraction_status = "failed"
        document.processing_status = "failed"
        document.processing_error = str(exc)
        db.commit()
        raise

    document.extracted_text = text
    document.extraction_status = extraction_status
    document.processing_status = "failed" if processing_error else "completed"
    document.processing_error = processing_error
    index_document(db, document)
    remove_document_relationships(db, document.id)
    db.commit()
    db.refresh(document)
    return document
