import asyncio
import io
import sqlite3
import socket
from pathlib import Path

import httpx
import pymupdf
import pytest
from fastapi import FastAPI
from PIL import Image
from sqlalchemy import select, text

import app.services.documents as document_service
from app.core.config import Settings
from app.main import create_app
from app.models.document import Document
from app.services.ocr import OCRDependencyError
from app.services.organization import CATEGORIES, classify_document


def create_test_app(tmp_path: Path, **settings_overrides) -> FastAPI:
    options = {
        "data_dir": tmp_path / "local-data",
        "database_path": tmp_path / "local-data" / "test.db",
    }
    options.update(settings_overrides)
    return create_app(Settings(**options))


async def perform_requests(
    app: FastAPI,
    requests: list[tuple[str, str, dict]],
) -> list[httpx.Response]:
    async with app.router.lifespan_context(app):
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            return [
                await client.request(method, path, **kwargs)
                for method, path, kwargs in requests
            ]


def request(app: FastAPI, *requests: tuple[str, str, dict]) -> list[httpx.Response]:
    return asyncio.run(perform_requests(app, list(requests)))


def multipart(filename: str, content: bytes, mime: str) -> dict:
    return {"files": {"file": (filename, content, mime)}}


def pdf_bytes(text: str = "LORE local PDF test") -> bytes:
    document = pymupdf.open()
    page = document.new_page()
    page.insert_text((72, 72), text)
    output = document.tobytes()
    document.close()
    return output


def png_bytes() -> bytes:
    image = Image.new("RGB", (32, 24), color="white")
    output = io.BytesIO()
    image.save(output, format="PNG")
    return output.getvalue()


def test_root_and_system_status_initialize_database(tmp_path) -> None:
    app = create_test_app(tmp_path)
    responses = request(
        app,
        ("GET", "/", {}),
        ("GET", "/api/v1/system/status", {}),
    )

    assert responses[0].status_code == 200
    assert responses[0].json() == {"name": "LORE", "version": "0.1.0", "status": "ok"}
    assert responses[1].status_code == 200
    assert responses[1].json() == {"status": "ok", "database": "ok"}
    assert (tmp_path / "local-data" / "documents").is_dir()


def test_upload_list_metadata_download_and_extract_text(tmp_path) -> None:
    app = create_test_app(tmp_path)
    content = b"LORE plain text stays on this device."
    responses = request(
        app,
        ("POST", "/api/v1/documents", multipart(r"C:\private\notes.txt", content, "text/plain")),
    )
    uploaded = responses[0]

    assert uploaded.status_code == 201
    metadata = uploaded.json()
    assert metadata["original_filename"] == "notes.txt"
    assert metadata["media_type"] == "text/plain"
    assert metadata["size_bytes"] == len(content)
    assert len(metadata["sha256"]) == 64
    assert metadata["extraction_status"] == "extracted"
    assert metadata["processing_status"] == "completed"
    assert "extracted_text" not in metadata

    document_id = metadata["id"]
    read_responses = request(
        app,
        ("GET", "/api/v1/documents", {}),
        ("GET", f"/api/v1/documents/{document_id}", {}),
        ("GET", f"/api/v1/documents/{document_id}/download", {}),
    )
    assert read_responses[0].json()["items"][0]["id"] == document_id
    assert read_responses[1].status_code == 200
    assert read_responses[2].content == content
    assert read_responses[2].headers["cache-control"] == "no-store"
    assert read_responses[2].headers["x-content-type-options"] == "nosniff"
    assert "attachment" in read_responses[2].headers["content-disposition"]

    with app.state.session_factory() as db:
        stored = db.scalar(select(Document).where(Document.id == document_id))
        assert stored is not None
        assert stored.extracted_text == content.decode()
        assert Path(stored.storage_path).name == stored.storage_path
        assert (tmp_path / "local-data" / "documents" / stored.storage_path).is_file()


def test_pdf_and_image_upload_validation_and_extraction_status(tmp_path) -> None:
    app = create_test_app(tmp_path)
    responses = request(
        app,
        ("POST", "/api/v1/documents", multipart("report.pdf", pdf_bytes(), "application/pdf")),
        ("POST", "/api/v1/documents", multipart("photo.png", png_bytes(), "image/png")),
    )

    assert responses[0].status_code == 201
    assert responses[0].json()["extraction_status"] == "extracted"
    with app.state.session_factory() as db:
        pdf = db.get(Document, responses[0].json()["id"])
        assert pdf is not None and "LORE local PDF test" in pdf.extracted_text

    assert responses[1].status_code == 201
    image_metadata = responses[1].json()
    assert image_metadata["extraction_status"] == "not_requested"
    assert image_metadata["processing_status"] == "completed"


def test_upload_rejects_unsupported_mime_and_malformed_content(tmp_path) -> None:
    app = create_test_app(tmp_path)
    responses = request(
        app,
        ("POST", "/api/v1/documents", multipart("archive.zip", b"data", "application/zip")),
        ("POST", "/api/v1/documents", multipart("notes.txt", b"data", "image/png")),
        ("POST", "/api/v1/documents", multipart("broken.pdf", b"%PDF-not a valid PDF", "application/pdf")),
        ("POST", "/api/v1/documents", multipart("broken.png", b"not an image", "image/png")),
        ("POST", "/api/v1/documents", multipart("binary.txt", b"\x00\x01", "text/plain")),
    )

    assert responses[0].status_code == 415
    assert responses[1].status_code == 415
    assert all(response.status_code == 422 for response in responses[2:])


def test_upload_rejects_oversize_and_duplicate_files(tmp_path) -> None:
    app = create_test_app(tmp_path, max_upload_size_bytes=8)
    responses = request(
        app,
        ("POST", "/api/v1/documents", multipart("large.txt", b"012345678", "text/plain")),
        ("POST", "/api/v1/documents", multipart("first.txt", b"same", "text/plain")),
        ("POST", "/api/v1/documents", multipart("second.txt", b"same", "text/plain")),
    )

    assert responses[0].status_code == 413
    assert responses[1].status_code == 201
    assert responses[2].status_code == 409
    assert responses[2].json()["detail"]["document_id"] == responses[1].json()["id"]
    assert len(request(app, ("GET", "/api/v1/documents", {}))[0].json()["items"]) == 1


def test_request_body_limit_rejects_large_multipart_before_file_processing(tmp_path) -> None:
    app = create_test_app(tmp_path, max_upload_size_bytes=8)
    response, = request(
        app,
        ("POST", "/api/v1/documents", multipart("large.txt", b"x" * 70_000, "text/plain")),
    )

    assert response.status_code == 413
    assert "request exceeds" in response.json()["detail"]


def test_retry_extraction_and_delete_remove_file_and_metadata(tmp_path) -> None:
    app = create_test_app(tmp_path)
    upload = request(
        app,
        ("POST", "/api/v1/documents", multipart("retry.txt", b"retry me", "text/plain")),
    )[0]
    document_id = upload.json()["id"]
    with app.state.session_factory() as db:
        stored = db.get(Document, document_id)
        assert stored is not None
        stored.extracted_text = None
        stored.extraction_status = "failed"
        stored.processing_status = "failed"
        db.commit()

    retry, = request(
        app,
        ("POST", f"/api/v1/documents/{document_id}/retry-extraction", {}),
    )
    assert retry.status_code == 200
    assert retry.json()["extraction_status"] == "extracted"
    with app.state.session_factory() as db:
        stored = db.get(Document, document_id)
        assert stored is not None
        stored_path = tmp_path / "local-data" / "documents" / stored.storage_path

    deleted, missing = request(
        app,
        ("DELETE", f"/api/v1/documents/{document_id}", {}),
        ("GET", f"/api/v1/documents/{document_id}", {}),
    )
    assert deleted.status_code == 204
    assert missing.status_code == 404
    assert not stored_path.exists()
    with app.state.session_factory() as db:
        assert db.get(Document, document_id) is None


def test_image_extraction_retry_requires_explicit_ocr_enablement(tmp_path) -> None:
    app = create_test_app(tmp_path)
    upload = request(
        app,
        ("POST", "/api/v1/documents", multipart("image.png", png_bytes(), "image/png")),
    )[0]
    response, = request(
        app,
        ("POST", f"/api/v1/documents/{upload.json()['id']}/retry-extraction", {}),
    )

    assert response.status_code == 409
    assert "LORE_ENABLE_OCR=true" in response.json()["detail"]


def test_missing_ocr_dependency_keeps_upload_and_marks_failure(tmp_path, monkeypatch) -> None:
    def unavailable(_content: bytes) -> str:
        raise OCRDependencyError(
            "OCR requires the optional 'ocr' extra and Tesseract installed locally."
        )

    monkeypatch.setattr(document_service, "extract_image_text", unavailable)
    app = create_test_app(tmp_path, enable_ocr=True)
    upload = request(
        app,
        ("POST", "/api/v1/documents", multipart("image.png", png_bytes(), "image/png")),
    )[0]

    assert upload.status_code == 201
    metadata = upload.json()
    assert metadata["extraction_status"] == "failed"
    assert metadata["processing_status"] == "failed"
    assert "optional 'ocr' extra" in metadata["processing_error"]
    retry, = request(
        app,
        ("POST", f"/api/v1/documents/{metadata['id']}/retry-extraction", {}),
    )
    assert retry.status_code == 503
    assert "optional 'ocr' extra" in retry.json()["detail"]
    classify, bulk_classify = request(
        app,
        ("POST", f"/api/v1/documents/{metadata['id']}/classify", {}),
        ("POST", "/api/v1/documents/reclassify", {"json": {"document_ids": [metadata["id"]]}}),
    )
    assert classify.status_code == 409
    assert bulk_classify.status_code == 409
    with app.state.session_factory() as db:
        stored = db.get(Document, metadata["id"])
        assert stored is not None
        assert (tmp_path / "local-data" / "documents" / stored.storage_path).is_file()


def test_existing_mvp_sqlite_database_is_upgraded(tmp_path) -> None:
    data_dir = tmp_path / "local-data"
    data_dir.mkdir()
    database_path = data_dir / "test.db"
    with sqlite3.connect(database_path) as connection:
        connection.execute(
            """
            CREATE TABLE documents (
                id VARCHAR(36) PRIMARY KEY,
                original_filename VARCHAR(255) NOT NULL,
                media_type VARCHAR(255),
                size_bytes INTEGER NOT NULL,
                storage_path VARCHAR(1024) NOT NULL UNIQUE,
                created_at DATETIME NOT NULL
            )
            """
        )
        connection.execute(
            """
            INSERT INTO documents
                (id, original_filename, media_type, size_bytes, storage_path, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            ("legacy-id", "legacy.txt", "text/plain", 6, "legacy.txt", "2025-01-01 00:00:00"),
        )

    app = create_test_app(tmp_path)
    response, migrated_search = request(
        app,
        ("GET", "/api/v1/documents/legacy-id", {}),
        ("GET", "/api/v1/search?q=legacy", {}),
    )

    assert response.status_code == 200
    assert response.json()["uploaded_at"].startswith("2025-01-01")
    assert response.json()["sha256"] is None
    assert response.json()["processing_status"] == "failed"
    assert response.json()["category"] is None
    assert response.json()["tags"] == []
    assert migrated_search.status_code == 200
    assert migrated_search.json()["items"][0]["document_id"] == "legacy-id"


def test_phase_two_database_is_upgraded_without_losing_extracted_text(tmp_path) -> None:
    data_dir = tmp_path / "local-data"
    data_dir.mkdir()
    database_path = data_dir / "test.db"
    with sqlite3.connect(database_path) as connection:
        connection.execute(
            """
            CREATE TABLE documents (
                id VARCHAR(36) PRIMARY KEY,
                original_filename VARCHAR(255) NOT NULL,
                media_type VARCHAR(255),
                size_bytes INTEGER NOT NULL,
                storage_path VARCHAR(1024) NOT NULL UNIQUE,
                sha256 VARCHAR(64),
                extracted_text TEXT,
                extraction_status VARCHAR(32) NOT NULL,
                processing_status VARCHAR(32) NOT NULL,
                processing_error VARCHAR(500),
                uploaded_at DATETIME NOT NULL
            )
            """
        )
        connection.execute(
            """
            INSERT INTO documents (
                id, original_filename, media_type, size_bytes, storage_path, sha256,
                extracted_text, extraction_status, processing_status, uploaded_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                "phase-two-id",
                "invoice.txt",
                "text/plain",
                18,
                "internal.txt",
                "a" * 64,
                "Invoice amount due",
                "extracted",
                "completed",
                "2026-10-01 12:00:00",
            ),
        )

    app = create_test_app(tmp_path)
    response, = request(app, ("GET", "/api/v1/documents/phase-two-id", {}))

    assert response.status_code == 200
    assert response.json()["category"] is None
    with app.state.session_factory() as db:
        migrated = db.get(Document, "phase-two-id")
        assert migrated is not None
        assert migrated.extracted_text == "Invoice amount due"
        assert migrated.sha256 == "a" * 64


def test_search_exact_filename_reference_ranking_and_snippets(tmp_path) -> None:
    app = create_test_app(tmp_path)
    uploads = request(
        app,
        (
            "POST",
            "/api/v1/documents",
            multipart("exact-invoice.txt", b"Receipt INV-923456. This is a paper record.", "text/plain"),
        ),
        (
            "POST",
            "/api/v1/documents",
            multipart("other.txt", b"Invoice related to reference INV-923456, with unrelated details.", "text/plain"),
        ),
        (
            "POST",
            "/api/v1/documents",
            multipart("reference.txt", b"Reference No: XY-987654. A separate file.", "text/plain"),
        ),
    )
    exact_id = uploads[0].json()["id"]
    exact, reference, = request(
        app,
        ("GET", "/api/v1/search?q=exact-invoice.txt", {}),
        ("GET", "/api/v1/search?q=INV-923456", {}),
    )

    assert exact.status_code == reference.status_code == 200
    assert exact.json()["items"][0]["document_id"] == exact_id
    assert "original_filename" in exact.json()["items"][0]["matching_fields"]
    assert exact.json()["items"][0]["snippet"] != (
        "Receipt INV-923456. This is a paper record."
    )
    assert len(reference.json()["items"]) == 2
    assert all("extracted_text" in item["matching_fields"] for item in reference.json()["items"])


def test_search_category_type_filters_and_organization_index_updates(tmp_path) -> None:
    app = create_test_app(tmp_path)
    upload, = request(
        app,
        (
            "POST",
            "/api/v1/documents",
            multipart("memo.txt", b"Routine note about the cedar desk.", "text/plain"),
        ),
    )
    document_id = upload.json()["id"]
    no_matches, = request(
        app,
        ("GET", "/api/v1/search?q=archive", {}),
    )
    assert no_matches.status_code == 200 and no_matches.json()["items"] == []

    patch, = request(
        app,
        (
            "PATCH",
            f"/api/v1/documents/{document_id}/organization",
            {"json": {"category": "Home", "tags": ["household"]}},
        ),
    )
    category_match, tag_match, title_match = request(
        app,
        ("GET", "/api/v1/search?q=household&category=Home", {}),
        ("GET", "/api/v1/search?q=household&category=Finance", {}),
        ("GET", "/api/v1/search?q=cedar&document_type=invoice", {}),
    )
    assert patch.status_code == 200
    assert len(category_match.json()["items"]) == 1
    assert category_match.json()["items"][0]["matching_fields"] == ["tags"]
    assert tag_match.json()["items"] == []
    assert title_match.json()["items"] == []


def test_search_handles_query_validation_unicode_and_no_network(tmp_path, monkeypatch) -> None:
    app = create_test_app(tmp_path)
    uploaded, = request(
        app,
        (
            "POST",
            "/api/v1/documents",
            multipart("cafe.txt", "Café résumé 日本語".encode(), "text/plain"),
        ),
    )

    def fail_if_network(*_args, **_kwargs):
        raise AssertionError("Search attempted network access.")

    monkeypatch.setattr(socket, "create_connection", fail_if_network)
    unicode_result, punctuation, malformed, blank = request(
        app,
        ("GET", "/api/v1/search?q=café", {}),
        ("GET", "/api/v1/search?q=%21%3F%2A", {}),
        ("GET", "/api/v1/search?q=%22%29%20OR%20MATCH%20x", {}),
        ("GET", "/api/v1/search?q=%20%20", {}),
    )
    too_long, too_many_terms, invalid_limit = request(
        app,
        ("GET", f"/api/v1/search?q={'x' * 257}", {}),
        ("GET", "/api/v1/search?q=one%20two%20three%20four%20five%20six%20seven%20eight%20nine%20ten%20eleven%20twelve%20thirteen", {}),
        ("GET", "/api/v1/search?q=cafe&limit=101", {}),
    )

    assert unicode_result.status_code == 200
    assert unicode_result.json()["items"][0]["document_id"] == uploaded.json()["id"]
    assert punctuation.status_code == 422
    assert malformed.status_code == 200
    assert blank.status_code == 422
    assert too_long.status_code == too_many_terms.status_code == invalid_limit.status_code == 422
    assert unicode_result.headers["cache-control"] == "no-store"


def test_search_index_rebuild_is_idempotent_and_delete_cleans_index(tmp_path) -> None:
    app = create_test_app(tmp_path)
    upload, = request(
        app,
        ("POST", "/api/v1/documents", multipart("rebuild.txt", b"index lifecycle marker", "text/plain")),
    )
    document_id = upload.json()["id"]
    with app.state.session_factory() as db:
        db.execute(
            text("DELETE FROM document_search WHERE document_id = :document_id"),
            {"document_id": document_id},
        )
        db.commit()

    rebuilt, rebuilt_again, search_result, deleted, search_after_delete = request(
        app,
        ("POST", "/api/v1/search/rebuild", {}),
        ("POST", "/api/v1/search/rebuild", {}),
        ("GET", "/api/v1/search?q=lifecycle", {}),
        ("DELETE", f"/api/v1/documents/{document_id}", {}),
        ("GET", "/api/v1/search?q=lifecycle", {}),
    )
    assert rebuilt.json()["indexed_documents"] == 1
    assert rebuilt_again.json()["indexed_documents"] == 1
    assert len(search_result.json()["items"]) == 1
    assert deleted.status_code == 204
    assert search_after_delete.json()["items"] == []


def test_search_reports_missing_fts5_index_clearly(tmp_path) -> None:
    app = create_test_app(tmp_path)
    async def request_without_index():
        async with app.router.lifespan_context(app):
            with app.state.engine.begin() as connection:
                connection.exec_driver_sql("DROP TABLE document_search")
            async with httpx.AsyncClient(
                transport=httpx.ASGITransport(app=app),
                base_url="http://test",
            ) as client:
                return await client.get("/api/v1/search", params={"q": "invoice"})

    response = asyncio.run(request_without_index())

    assert response.status_code == 503
    assert "FTS5" in response.json()["detail"]


def test_relationships_match_references_and_related_appliance_documents(tmp_path) -> None:
    app = create_test_app(tmp_path)
    uploads = request(
        app,
        (
            "POST",
            "/api/v1/documents",
            multipart(
                "purchase.txt",
                b"Invoice\nReference No: REF-887766\nProduct: Acme Washer W500\nDate: 2025-01-10",
                "text/plain",
            ),
        ),
        (
            "POST",
            "/api/v1/documents",
            multipart(
                "warranty.txt",
                b"Warranty certificate\nReference No: REF-887766\nProduct: Acme Washer W500\nDate: 2025-02-10",
                "text/plain",
            ),
        ),
        (
            "POST",
            "/api/v1/documents",
            multipart(
                "service.txt",
                b"Service receipt\nProduct: Acme Washer W500\nDate: 2025-03-10\nRepair complete",
                "text/plain",
            ),
        ),
    )
    first_id = uploads[0].json()["id"]
    rebuilt, related, recalculated, recalculated_again, rebuilt_again, related_again = request(
        app,
        ("POST", "/api/v1/relationships/rebuild", {}),
        ("GET", f"/api/v1/documents/{first_id}/related", {}),
        ("POST", f"/api/v1/documents/{first_id}/related/recalculate", {}),
        ("POST", f"/api/v1/documents/{first_id}/related/recalculate", {}),
        ("POST", "/api/v1/relationships/rebuild", {}),
        ("GET", f"/api/v1/documents/{first_id}/related", {}),
    )
    detail, = request(
        app,
        ("GET", f"/api/v1/relationships/{related.json()['items'][0]['id']}", {}),
    )

    assert rebuilt.status_code == 200
    assert rebuilt.json()["relationships_created"] == 3
    assert related.status_code == 200
    assert len(related.json()["items"]) == 2
    assert all(item["score"] >= 0.68 for item in related.json()["items"])
    initial_ids = {item["id"] for item in related.json()["items"]}
    assert {item["id"] for item in recalculated.json()["items"]} == initial_ids
    assert {item["id"] for item in recalculated_again.json()["items"]} == initial_ids
    assert rebuilt_again.json()["relationships_created"] == 3
    assert {item["id"] for item in related_again.json()["items"]} == initial_ids
    assert all("Suggested" in item["explanation"] for item in related.json()["items"])
    assert any(
        "ref887766" in evidence.casefold()
        for item in related.json()["items"]
        for evidence in item["evidence"]
    )
    assert detail.status_code == 200


def test_relationships_weak_evidence_empty_text_recalculate_and_idempotence(tmp_path) -> None:
    app = create_test_app(tmp_path)
    uploads = request(
        app,
        ("POST", "/api/v1/documents", multipart("first.txt", b"From: Same Provider\nMonthly report", "text/plain")),
        ("POST", "/api/v1/documents", multipart("second.txt", b"From: Same Provider\nMonthly report", "text/plain")),
        ("POST", "/api/v1/documents", multipart("empty.txt", b"  ", "text/plain")),
    )
    first_id = uploads[0].json()["id"]
    missing, empty, recalc, rebuild_one, rebuild_two, related = request(
        app,
        ("GET", "/api/v1/documents/no-such-id/related", {}),
        ("GET", f"/api/v1/documents/{uploads[2].json()['id']}/related", {}),
        ("POST", f"/api/v1/documents/{first_id}/related/recalculate", {}),
        ("POST", "/api/v1/relationships/rebuild", {}),
        ("POST", "/api/v1/relationships/rebuild", {}),
        ("GET", f"/api/v1/documents/{first_id}/related", {}),
    )

    assert missing.status_code == 404
    assert empty.status_code == 409
    assert recalc.status_code == 200
    assert recalc.json()["items"] == []
    assert rebuild_one.json()["relationships_created"] == 0
    assert rebuild_two.json()["relationships_created"] == 0
    assert related.json()["items"] == []


@pytest.mark.parametrize(
    ("category", "filename", "text"),
    [
        ("Finance", "statement.txt", "Bank statement. Account statement. Transaction balance."),
        ("Education", "grades.txt", "University student transcript and semester course."),
        ("Health", "record.txt", "Patient medical record and prescription diagnosis."),
        ("Identity", "passport.txt", "Passport identity document national ID."),
        ("Home", "lease.txt", "Lease agreement for tenant rent and property."),
        ("Appliances", "manual.txt", "Appliance user manual serial number and warranty."),
        ("Insurance", "coverage.txt", "Insurance policy premium insured coverage claim."),
        ("Travel", "trip.txt", "Flight itinerary and boarding pass departure."),
        ("Work", "pay.txt", "Employer employment pay stub salary payroll."),
        ("Legal", "court.txt", "Court legal notice from attorney and statute."),
        ("Uncategorized", "misc.txt", "A collection of unrelated personal notes."),
    ],
)
def test_deterministic_classifier_representative_categories(
    category: str,
    filename: str,
    text: str,
) -> None:
    result = classify_document(filename=filename, extracted_text=text)

    assert result.category == category
    assert result.method == "rules-v1"
    assert 0 <= result.confidence <= 0.95
    assert result.reasons


def test_classifier_handles_empty_ambiguous_dates_and_repeats_deterministically() -> None:
    empty = classify_document(filename="unknown.txt", extracted_text="")
    ambiguous = classify_document(
        filename="invoice.txt",
        extracted_text="Invoice\nDate: 03/04/2024\nIssued by: Acme\nReference No: INV-12345",
    )
    invalid = classify_document(
        filename="report.txt",
        extracted_text="Summary\nDate: 2025-02-31",
    )
    repeated = classify_document(
        filename="invoice.txt",
        extracted_text="Invoice\nDate: 03/04/2024\nIssued by: Acme\nReference No: INV-12345",
    )

    assert empty.category == "Uncategorized"
    assert empty.confidence == 0
    assert ambiguous.document_date is None
    assert invalid.document_date is None
    assert ambiguous.document_title == "Invoice"
    assert ambiguous.issuer == "Acme"
    assert ambiguous.reference_number == "INV-12345"
    assert ambiguous == repeated


def test_classification_does_not_attempt_network_access(monkeypatch) -> None:
    def fail_if_network(*_args, **_kwargs):
        raise AssertionError("Classification attempted network access.")

    monkeypatch.setattr(socket, "create_connection", fail_if_network)
    result = classify_document(
        filename="bill.txt",
        extracted_text="Invoice\nInvoice number: 7777\nDate: January 15, 2025",
    )

    assert result.category == "Finance"
    assert result.document_date.isoformat() == "2025-01-15"


def test_classification_organization_api_filter_and_counts(tmp_path) -> None:
    app = create_test_app(tmp_path)
    invoice = request(
        app,
        ("POST", "/api/v1/documents", multipart("invoice.txt", b"Invoice amount due 25", "text/plain")),
        ("POST", "/api/v1/documents", multipart("bill.txt", b"Invoice amount due 26", "text/plain")),
        ("POST", "/api/v1/documents", multipart("receipt.txt", b"Invoice amount due 27", "text/plain")),
        ("POST", "/api/v1/documents", multipart("class-notes.txt", b"University student transcript", "text/plain")),
        ("POST", "/api/v1/documents", multipart("misc.txt", b"Gardening notes", "text/plain")),
    )
    finance_id = invoice[0].json()["id"]
    first_page, second_page, third_page, empty_page, education, categories = request(
        app,
        ("GET", "/api/v1/documents?category=Finance&limit=1&offset=0", {}),
        ("GET", "/api/v1/documents?category=Finance&limit=1&offset=1", {}),
        ("GET", "/api/v1/documents?category=Finance&limit=1&offset=2", {}),
        ("GET", "/api/v1/documents?category=Finance&limit=1&offset=3", {}),
        ("GET", "/api/v1/documents?category=Education&limit=1&offset=0", {}),
        ("GET", "/api/v1/categories", {}),
    )

    assert first_page.status_code == 200 and len(first_page.json()["items"]) == 1
    finance_page_ids = [
        first_page.json()["items"][0]["id"],
        second_page.json()["items"][0]["id"],
        third_page.json()["items"][0]["id"],
    ]
    assert finance_id in finance_page_ids
    assert len(set(finance_page_ids)) == 3
    assert empty_page.json()["items"] == []
    assert education.json()["items"][0]["category"] == "Education"
    category_items = categories.json()["items"]
    assert [item["category"] for item in category_items] == list(CATEGORIES)
    counts = {item["category"]: item["document_count"] for item in category_items}
    assert counts["Finance"] == 3
    assert counts["Education"] == counts["Uncategorized"] == 1


def test_manual_organization_update_and_classify_endpoints(tmp_path) -> None:
    app = create_test_app(tmp_path)
    uploaded, = request(
        app,
        ("POST", "/api/v1/documents", multipart("custom.txt", b"Personal note", "text/plain")),
    )
    document_id = uploaded.json()["id"]
    with app.state.session_factory() as db:
        source_path = tmp_path / "local-data" / "documents" / db.get(Document, document_id).storage_path
        original_bytes = source_path.read_bytes()
        original_hash = db.get(Document, document_id).sha256

    updated, classified, classified_again = request(
        app,
        (
            "PATCH",
            f"/api/v1/documents/{document_id}/organization",
            {"json": {"category": "Travel", "tags": [" trip ", "Trip", "holiday"]}},
        ),
        ("POST", f"/api/v1/documents/{document_id}/classify", {}),
        ("POST", f"/api/v1/documents/{document_id}/classify", {}),
    )
    assert updated.status_code == 200
    assert updated.json()["category"] == "Travel"
    assert updated.json()["classification_method"] == "manual"
    assert updated.json()["classification_confidence"] is None
    assert updated.json()["tags"] == ["trip", "holiday"]
    assert classified.status_code == 200
    assert classified.json()["category"] == "Uncategorized"
    assert classified.json()["classification_method"] == "rules-v1"
    assert classified_again.json() == classified.json()
    with app.state.session_factory() as db:
        stored = db.get(Document, document_id)
        assert stored is not None and stored.sha256 == original_hash
        assert source_path.read_bytes() == original_bytes

    invalid_id, invalid_body, repeated_tags = request(
        app,
        ("POST", "/api/v1/documents/not-a-real-id/classify", {}),
        ("PATCH", f"/api/v1/documents/{document_id}/organization", {"json": {}}),
        (
            "PATCH",
            f"/api/v1/documents/{document_id}/organization",
            {"json": {"tags": [" "]}},
        ),
    )
    assert invalid_id.status_code == 404
    assert invalid_body.status_code == 422
    assert repeated_tags.status_code == 422


def test_reclassify_validates_ids_and_limits(tmp_path) -> None:
    app = create_test_app(tmp_path)
    uploads = request(
        app,
        ("POST", "/api/v1/documents", multipart("one.txt", b"Invoice due 5", "text/plain")),
        ("POST", "/api/v1/documents", multipart("two.txt", b"University student", "text/plain")),
    )
    ids = [response.json()["id"] for response in uploads]
    reclassified, missing, duplicate_ids, empty_ids, too_many = request(
        app,
        ("POST", "/api/v1/documents/reclassify", {"json": {"document_ids": ids}}),
        (
            "POST",
            "/api/v1/documents/reclassify",
            {"json": {"document_ids": [ids[0], "missing"]}},
        ),
        (
            "POST",
            "/api/v1/documents/reclassify",
            {"json": {"document_ids": [ids[0], ids[0]]}},
        ),
        ("POST", "/api/v1/documents/reclassify", {"json": {"document_ids": []}}),
        ("POST", "/api/v1/documents/reclassify", {"json": {"document_ids": ["x"] * 101}}),
    )

    assert reclassified.status_code == 200
    assert reclassified.json()["processed_count"] == 2
    assert [item["category"] for item in reclassified.json()["items"]] == ["Finance", "Education"]
    assert missing.status_code == 404
    assert duplicate_ids.status_code == empty_ids.status_code == too_many.status_code == 422
