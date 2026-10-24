from typing import Annotated

from fastapi import APIRouter, Depends, File, HTTPException, Query, Request, UploadFile
from fastapi.responses import FileResponse, Response
from sqlalchemy.orm import Session
from starlette.concurrency import run_in_threadpool

from app.core.config import Settings
from app.db.session import get_db
from app.models.document import Document
from app.schemas.document import (
    Category,
    DocumentListResponse,
    DocumentResponse,
    OrganizationUpdate,
    ReclassifyRequest,
    ReclassifyResponse,
)
from app.services.documents import (
    DocumentInputError,
    DocumentNotFoundError,
    DuplicateDocumentError,
    ExtractionDependencyError,
    ExtractionError,
    OCRDisabledError,
    StorageCleanupError,
    UnsupportedDocumentTypeError,
    delete_document,
    get_document,
    get_document_file,
    list_documents,
    retry_document_extraction,
    upload_document,
)
from app.services.organization import (
    apply_classification,
    update_organization,
)
from app.services.search import index_document
from app.services.relationships import remove_document_relationships

router = APIRouter()
DbSession = Annotated[Session, Depends(get_db)]


def get_settings(request: Request) -> Settings:
    return request.app.state.settings


@router.post(
    "",
    response_model=DocumentResponse,
    status_code=201,
)
async def create_document(
    file: Annotated[UploadFile, File(...)],
    db: DbSession,
    request_settings: Annotated[Settings, Depends(get_settings)],
) -> DocumentResponse:
    try:
        content = await file.read(request_settings.max_upload_size_bytes + 1)
        if len(content) > request_settings.max_upload_size_bytes:
            raise HTTPException(
                status_code=413,
                detail="The uploaded file exceeds the configured size limit.",
            )
        document = await run_in_threadpool(
            upload_document,
            db,
            request_settings,
            file.filename,
            file.content_type,
            content,
        )
        return DocumentResponse.model_validate(document)
    except UnsupportedDocumentTypeError as exc:
        raise HTTPException(status_code=415, detail=str(exc)) from exc
    except DocumentInputError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except DuplicateDocumentError as exc:
        raise HTTPException(
            status_code=409,
            detail={"message": "This document has already been uploaded.", "document_id": exc.document_id},
        ) from exc
    except ExtractionDependencyError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    finally:
        await file.close()


@router.post("/reclassify", response_model=ReclassifyResponse)
def reclassify_documents(payload: ReclassifyRequest, db: DbSession) -> ReclassifyResponse:
    documents = [db.get(Document, item_id) for item_id in payload.document_ids]
    missing_ids = [
        item_id
        for item_id, document in zip(payload.document_ids, documents, strict=True)
        if document is None
    ]
    if missing_ids:
        raise HTTPException(
            status_code=404,
            detail={"message": "One or more documents were not found.", "document_ids": missing_ids},
        )
    typed_documents = [document for document in documents if document is not None]
    failed_ids = [
        document.id
        for document in typed_documents
        if document.extraction_status == "failed" and not (document.extracted_text or "").strip()
    ]
    if failed_ids:
        raise HTTPException(
            status_code=409,
            detail={
                "message": "Retry text extraction before classifying these documents.",
                "document_ids": failed_ids,
            },
        )
    try:
        for document in typed_documents:
            apply_classification(document)
            index_document(db, document)
            remove_document_relationships(db, document.id)
    except ValueError as exc:
        db.rollback()
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    db.commit()
    for document in typed_documents:
        db.refresh(document)
    return ReclassifyResponse(
        processed_count=len(typed_documents),
        items=[DocumentResponse.model_validate(document) for document in typed_documents],
    )


@router.get("", response_model=DocumentListResponse)
def read_documents(
    db: DbSession,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
    category: Category | None = None,
) -> DocumentListResponse:
    items = list_documents(db, limit, offset, category)
    return DocumentListResponse(
        items=[DocumentResponse.model_validate(item) for item in items],
        limit=limit,
        offset=offset,
    )


@router.post("/{document_id}/classify", response_model=DocumentResponse)
def classify_document(document_id: str, db: DbSession) -> DocumentResponse:
    try:
        document = get_document(db, document_id)
    except DocumentNotFoundError as exc:
        raise HTTPException(status_code=404, detail="Document not found.") from exc
    if document.extraction_status == "failed" and not (document.extracted_text or "").strip():
        raise HTTPException(
            status_code=409,
            detail="Document text extraction failed; retry extraction before classification.",
        )
    try:
        apply_classification(document)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    index_document(db, document)
    remove_document_relationships(db, document.id)
    db.commit()
    db.refresh(document)
    return DocumentResponse.model_validate(document)


@router.patch("/{document_id}/organization", response_model=DocumentResponse)
def patch_document_organization(
    document_id: str,
    payload: OrganizationUpdate,
    db: DbSession,
) -> DocumentResponse:
    try:
        document = get_document(db, document_id)
    except DocumentNotFoundError as exc:
        raise HTTPException(status_code=404, detail="Document not found.") from exc
    update_organization(document, category=payload.category, tags=payload.tags)
    index_document(db, document)
    remove_document_relationships(db, document.id)
    db.commit()
    db.refresh(document)
    return DocumentResponse.model_validate(document)


@router.get("/{document_id}", response_model=DocumentResponse)
def read_document(document_id: str, db: DbSession) -> DocumentResponse:
    try:
        return DocumentResponse.model_validate(get_document(db, document_id))
    except DocumentNotFoundError as exc:
        raise HTTPException(status_code=404, detail="Document not found.") from exc


@router.get("/{document_id}/download")
def download_document(
    document_id: str,
    db: DbSession,
    request_settings: Annotated[Settings, Depends(get_settings)],
) -> FileResponse:
    try:
        document = get_document(db, document_id)
        path = get_document_file(request_settings, document)
    except DocumentNotFoundError as exc:
        raise HTTPException(status_code=404, detail="Document or stored file not found.") from exc
    except StorageCleanupError as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc
    return FileResponse(
        path,
        media_type=document.media_type,
        filename=document.original_filename,
    )


@router.delete("/{document_id}", status_code=204)
def remove_document(
    document_id: str,
    db: DbSession,
    request_settings: Annotated[Settings, Depends(get_settings)],
) -> Response:
    try:
        document = get_document(db, document_id)
        delete_document(db, request_settings, document)
    except DocumentNotFoundError as exc:
        raise HTTPException(status_code=404, detail="Document not found.") from exc
    except StorageCleanupError as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc
    return Response(status_code=204)


@router.post("/{document_id}/retry-extraction", response_model=DocumentResponse)
def retry_extraction(
    document_id: str,
    db: DbSession,
    request_settings: Annotated[Settings, Depends(get_settings)],
) -> DocumentResponse:
    try:
        document = get_document(db, document_id)
        return DocumentResponse.model_validate(
            retry_document_extraction(db, request_settings, document)
        )
    except DocumentNotFoundError as exc:
        raise HTTPException(status_code=404, detail="Document or stored file not found.") from exc
    except OCRDisabledError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    except ExtractionDependencyError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except ExtractionError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except StorageCleanupError as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc
