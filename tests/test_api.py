import asyncio
import hashlib
import io
import json
import logging
import sqlite3
import socket
from datetime import datetime, timedelta, timezone
from pathlib import Path

import httpx
import pymupdf
import pytest
from fastapi import FastAPI
from PIL import Image
from sqlalchemy import select, text

import app.services.documents as document_service
from app.core.config import Settings
from app.db.session import create_database_engine, create_session_factory
from app.main import create_app
from app.migrate import upgrade_database
from app.models.auth import AuthSession, PairingAttempt
from app.models.document import Document
from app.recovery import recover_access
from app.services.ask import ExternalAIProvider, LocalLLMProvider
from app.services.ocr import OCRDependencyError
from app.services.organization import CATEGORIES, classify_document


def create_test_app(tmp_path: Path, **settings_overrides) -> FastAPI:
    options = {
        "data_dir": tmp_path / "local-data",
        "database_path": tmp_path / "local-data" / "test.db",
        "database_url": None,
    }
    options.update(settings_overrides)
    active_settings = Settings(**options)
    upgrade_database(active_settings)
    return create_app(active_settings)


async def pair_test_client(app: FastAPI, client: httpx.AsyncClient) -> str:
    pairing_path = app.state.auth.pairing_code_path
    pairing_code = json.loads(pairing_path.read_text(encoding="utf-8"))["code"]
    response = await client.post("/api/v1/auth/pair", json={"code": pairing_code})
    assert response.status_code == 200, response.text
    return response.json()["token"]


async def perform_requests(
    app: FastAPI,
    requests: list[tuple[str, str, dict]],
    *,
    authenticated: bool = True,
) -> list[httpx.Response]:
    async with app.router.lifespan_context(app):
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app),
            base_url="http://test",
        ) as client:
            headers: dict[str, str] = {}
            if authenticated:
                token = getattr(app.state, "_test_auth_token", None)
                if token is not None:
                    with app.state.session_factory() as db:
                        if app.state.auth.authenticate(db, token) is None:
                            token = None
                if token is None:
                    token = await pair_test_client(app, client)
                    app.state._test_auth_token = token
                headers["Authorization"] = f"Bearer {token}"
            prepared = []
            for method, path, kwargs in requests:
                request_kwargs = dict(kwargs)
                request_headers = dict(request_kwargs.pop("headers", {}) or {})
                for key, value in headers.items():
                    request_headers.setdefault(key, value)
                request_kwargs["headers"] = request_headers
                prepared.append((method, path, request_kwargs))
            return [
                await client.request(method, path, **kwargs)
                for method, path, kwargs in prepared
            ]


def request(
    app: FastAPI,
    *requests: tuple[str, str, dict],
    authenticated: bool = True,
) -> list[httpx.Response]:
    return asyncio.run(perform_requests(app, list(requests), authenticated=authenticated))


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
            async with httpx.AsyncClient(
                transport=httpx.ASGITransport(app=app),
                base_url="http://test",
            ) as client:
                token = await pair_test_client(app, client)
                with app.state.engine.begin() as connection:
                    connection.exec_driver_sql("DROP TABLE document_search")
                return await client.get(
                    "/api/v1/search",
                    params={"q": "invoice"},
                    headers={"Authorization": f"Bearer {token}"},
                )

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
        ("POST", "/api/v1/documents", multipart("empty.txt", b"Contains text but is cleared for this test.", "text/plain")),
    )
    first_id = uploads[0].json()["id"]
    empty_id = uploads[2].json()["id"]
    with app.state.session_factory() as db:
        document = db.get(Document, empty_id)
        assert document is not None
        document.extracted_text = None
        document.extraction_status = "failed"
        document.processing_status = "failed"
        db.commit()
    missing, empty, recalc, rebuild_one, rebuild_two, related = request(
        app,
        ("GET", "/api/v1/documents/no-such-id/related", {}),
        ("GET", f"/api/v1/documents/{empty_id}/related", {}),
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


def test_ask_question_supports_direct_evidence_and_reports_provider_status(tmp_path, monkeypatch) -> None:
    app = create_test_app(tmp_path)

    def fail_if_network(*_args, **_kwargs):
        raise AssertionError("Ask LORE attempted external network access.")

    monkeypatch.setattr(socket, "create_connection", fail_if_network)
    upload, = request(
        app,
        (
            "POST",
            "/api/v1/documents",
            multipart(
                "invoice.txt",
                b"Invoice number: INV-8842\nAmount due $742.50\nWarranty expires 2026-01-15",
                "text/plain",
            ),
        ),
    )
    status, answer = request(
        app,
        ("GET", "/api/v1/ask/status", {}),
        ("POST", "/api/v1/ask", {"json": {"question": "What is the invoice number?", "max_sources": 5}}),
    )

    assert status.status_code == 200
    assert status.json()["selected_provider"] == "extractive"
    assert status.json()["providers"]["extractive"]["available"] is True
    assert status.json()["providers"]["local-llm"]["available"] is False
    assert answer.status_code == 200
    assert answer.json()["provider"] == "extractive"
    assert "INV-8842" in answer.json()["answer"]
    assert answer.json()["sufficient_evidence"] is True
    assert answer.json()["evidence"][0]["document_id"] == upload.json()["id"]


def test_ask_abstains_on_unsupported_question_and_rejects_invalid_limits(tmp_path) -> None:
    app = create_test_app(tmp_path)
    upload, = request(
        app,
        ("POST", "/api/v1/documents", multipart("holiday.txt", b"Office holiday calendar and team events.", "text/plain")),
    )
    unsupported, too_long, invalid_limit, missing = request(
        app,
        ("POST", "/api/v1/ask", {"json": {"question": "What is the capital of France?", "max_sources": 5}}),
        ("POST", "/api/v1/ask", {"json": {"question": "x" * 1001, "max_sources": 5}}),
        ("POST", "/api/v1/ask", {"json": {"question": "invoice number", "max_sources": 99}}),
        ("POST", f"/api/v1/documents/{upload.json()['id']}/ask", {"json": {"question": "What is the capital of France?"}}),
    )

    assert unsupported.status_code == 200
    assert unsupported.json()["sufficient_evidence"] is False
    assert "do not establish" in unsupported.json()["answer"].lower()
    assert too_long.status_code == 422
    assert invalid_limit.status_code == 422
    assert missing.status_code == 404


def test_ask_document_includes_related_documents_and_handles_conflict(tmp_path) -> None:
    app = create_test_app(tmp_path)
    uploads = request(
        app,
        (
            "POST",
            "/api/v1/documents",
            multipart(
                "purchase.txt",
                b"Invoice\nReference No: REF-998877\nProduct: Acme Washer W500\nDate: 2025-01-10",
                "text/plain",
            ),
        ),
        (
            "POST",
            "/api/v1/documents",
            multipart(
                "warranty.txt",
                b"Warranty certificate\nReference No: REF-998877\nProduct: Acme Washer W500\nWarranty expires 2027-01-30",
                "text/plain",
            ),
        ),
    )
    request(app, ("POST", "/api/v1/relationships/rebuild", {}))
    purchase_id = uploads[0].json()["id"]
    related_answer = request(
        app,
        (
            "POST",
            f"/api/v1/documents/{purchase_id}/ask",
            {"json": {"question": "When does the warranty expire?", "max_sources": 5, "include_related": True}},
        ),
    )[0]

    assert related_answer.status_code == 200
    assert related_answer.json()["provider"] == "extractive"
    assert "2027-01-30" in related_answer.json()["answer"]
    assert related_answer.json()["evidence"]
    assert any(item["document_id"] != purchase_id for item in related_answer.json()["evidence"])


def test_ask_date_question_is_not_misread_as_reference_lookup(tmp_path) -> None:
    app = create_test_app(tmp_path)
    request(
        app,
        (
            "POST",
            "/api/v1/documents",
            multipart(
                "warranty.txt",
                (
                    b"Warranty certificate\nReference No: WAR-2026-0042\n"
                    b"Product: Refrigerator R500\nThe warranty for the refrigerator ends on 1 March 2027."
                ),
                "text/plain",
            ),
        ),
    )
    answer = request(
        app,
        (
            "POST",
            "/api/v1/ask",
            {"json": {"question": "When does the refrigerator warranty end?", "max_sources": 5}},
        ),
    )[0]

    assert answer.status_code == 200
    assert answer.json()["sufficient_evidence"] is True
    assert "1 March 2027" in answer.json()["answer"]
    assert "reference" not in answer.json()["answer"].lower()


def test_ask_detects_conflicting_values_and_empty_extraction(tmp_path) -> None:
    app = create_test_app(tmp_path)
    request(
        app,
        ("POST", "/api/v1/documents", multipart("first.txt", b"Amount due $100.00", "text/plain")),
        ("POST", "/api/v1/documents", multipart("second.txt", b"Amount due $250.00", "text/plain")),
    )
    conflict, empty_upload = request(
        app,
        ("POST", "/api/v1/ask", {"json": {"question": "What amount is due?", "max_sources": 5}}),
        ("POST", "/api/v1/documents", multipart("empty-ask.txt", b"   ", "text/plain")),
    )

    assert conflict.status_code == 200
    assert conflict.json()["sufficient_evidence"] is False
    assert "conflicting" in conflict.json()["answer"].lower()
    assert empty_upload.status_code == 422


def test_assisted_mode_requires_approval_and_private_mode_falls_back_to_extractive(tmp_path) -> None:
    app = create_test_app(
        tmp_path,
        ai_mode="private",
        external_ai_endpoint="https://example.com/external",
        external_ai_api_key="secret",
    )
    upload, = request(
        app,
        (
            "POST",
            "/api/v1/documents",
            multipart("invoice.txt", b"Invoice number: INV-8842\nAmount due $742.50", "text/plain"),
        ),
    )
    status, answer = request(
        app,
        ("GET", "/api/v1/ask/status", {}),
        ("POST", "/api/v1/ask", {"json": {"question": "What is the invoice number?", "max_sources": 5}}),
    )

    assert status.status_code == 200
    assert status.json()["mode"] == "private"
    assert status.json()["selected_provider"] == "extractive"
    assert status.json()["providers"]["external"]["available"] is True
    assert answer.status_code == 200
    assert answer.json()["provider"] == "extractive"
    assert "INV-8842" in answer.json()["answer"]

    prepare, = request(
        app,
        (
            "POST",
            "/api/v1/ask/prepare",
            {"json": {"question": "What is the invoice number?", "max_sources": 5}},
        ),
    )
    assert prepare.status_code == 400


@pytest.mark.parametrize(
    ("settings_overrides", "reason_fragment"),
    [
        ({}, "LORE_EXTERNAL_AI_ENDPOINT"),
        ({"external_ai_endpoint": "https://example.com/external"}, "LORE_EXTERNAL_AI_API_KEY"),
        (
            {"external_ai_endpoint": "example.com/external", "external_ai_api_key": "secret"},
            "invalid",
        ),
        (
            {"external_ai_endpoint": "ftp://example.com/external", "external_ai_api_key": "secret"},
            "invalid",
        ),
    ],
)
def test_assisted_mode_requires_complete_and_valid_provider_configuration(
    tmp_path, settings_overrides, reason_fragment
) -> None:
    app = create_test_app(tmp_path, **settings_overrides)
    status, attempted, after = request(
        app,
        ("GET", "/api/v1/ask/status", {}),
        ("POST", "/api/v1/ask/mode", {"json": {"mode": "assisted"}}),
        ("GET", "/api/v1/ask/status", {}),
    )

    body = status.json()
    assert body["mode"] == "private"
    assert body["providers"]["external"]["available"] is False
    assert body["external_provider_configured"] is False
    assert reason_fragment.lower() in (body["providers"]["external"]["reason"] or "").lower()

    assert attempted.status_code == 503
    assert reason_fragment.lower() in attempted.json()["detail"].lower()
    assert after.json()["mode"] == "private"
    assert after.json()["external_provider_configured"] is False


@pytest.mark.parametrize(
    "endpoint",
    [
        "https://example.com/external",
        "https://example.com/external/",
        "https://api.example.com:443/v1/chat",
        "http://127.0.0.1:8080/v1/ask?model=local",
        "http://[::1]:8000/v1",
    ],
)
def test_external_provider_accepts_valid_endpoints(endpoint: str) -> None:
    provider = ExternalAIProvider(
        Settings(external_ai_endpoint=endpoint, external_ai_api_key="secret")
    )

    assert provider.configuration_error() is None
    assert provider.configured is True
    assert provider.status() == {"available": True, "reason": None}


@pytest.mark.parametrize(
    "endpoint",
    [
        "example.com/external",
        "ftp://example.com/external",
        "https:///external",
        "http://:8000/ask",
        "https://user:pass@example.com/external",
        "https://user@example.com/external",
        "https://example.com:abc/external",
        "https://example.com:70000/external",
        "https://example.com:/external",
        "https://exa mple.com/external",
        "https://example.com/external path",
        "https://[::1/external",
    ],
)
def test_external_provider_rejects_invalid_endpoints(endpoint: str) -> None:
    provider = ExternalAIProvider(
        Settings(external_ai_endpoint=endpoint, external_ai_api_key="secret")
    )
    reason = provider.configuration_error()

    assert reason is not None
    assert "invalid" in reason.lower()
    assert provider.configured is False
    assert provider.status() == {"available": False, "reason": reason}


def test_assisted_mode_can_be_enabled_only_with_valid_configuration(tmp_path) -> None:
    app = create_test_app(
        tmp_path,
        external_ai_endpoint="https://example.com/external",
        external_ai_api_key="secret",
    )
    status, enabled, enabled_status, disabled, disabled_status = request(
        app,
        ("GET", "/api/v1/ask/status", {}),
        ("POST", "/api/v1/ask/mode", {"json": {"mode": "assisted"}}),
        ("GET", "/api/v1/ask/status", {}),
        ("POST", "/api/v1/ask/mode", {"json": {"mode": "private"}}),
        ("GET", "/api/v1/ask/status", {}),
    )

    assert status.json()["providers"]["external"]["available"] is True
    assert status.json()["providers"]["external"]["reason"] is None
    assert status.json()["external_provider_configured"] is True

    assert enabled.status_code == 200
    assert enabled.json()["mode"] == "assisted"
    assert enabled.json()["available"] is True
    assert enabled_status.json()["mode"] == "assisted"
    assert enabled_status.json()["available"] is True
    assert enabled_status.json()["external_provider_configured"] is True

    assert disabled.status_code == 200
    assert disabled.json()["mode"] == "private"
    assert disabled.json()["available"] is True
    assert disabled_status.json()["mode"] == "private"
    assert disabled_status.json()["external_provider_configured"] is True


def test_assisted_mode_reports_available_when_the_assisted_provider_is_selected(tmp_path) -> None:
    app = create_test_app(
        tmp_path,
        ai_mode="assisted",
        ask_provider="assisted",
        external_ai_endpoint="https://example.com/external",
        external_ai_api_key="secret",
    )
    status, mode = request(
        app,
        ("GET", "/api/v1/ask/status", {}),
        ("POST", "/api/v1/ask/mode", {"json": {"mode": "assisted"}}),
    )

    assert status.json()["selected_provider"] == "assisted"
    assert status.json()["providers"]["external"]["available"] is True
    assert status.json()["available"] is True
    assert mode.status_code == 200
    assert mode.json()["selected_provider"] == "assisted"
    assert mode.json()["available"] is True


def test_assisted_mode_started_without_valid_provider_is_not_reported_available(tmp_path) -> None:
    app = create_test_app(
        tmp_path,
        ai_mode="assisted",
        external_ai_endpoint="https://example.com/external",
    )
    status = request(app, ("GET", "/api/v1/ask/status", {}))[0]
    body = status.json()

    assert body["mode"] == "assisted"
    assert body["available"] is False
    assert body["providers"]["external"]["available"] is False
    assert body["external_provider_configured"] is False
    assert "LORE_EXTERNAL_AI_API_KEY" in body["providers"]["external"]["reason"]


def test_prepare_requires_valid_provider_configuration(tmp_path) -> None:
    app = create_test_app(
        tmp_path,
        ai_mode="assisted",
        external_ai_endpoint="https://example.com/external",
    )
    response = request(
        app,
        ("POST", "/api/v1/ask/prepare", {"json": {"question": "What is due?", "max_sources": 5}}),
    )[0]

    assert response.status_code == 503
    assert "LORE_EXTERNAL_AI_API_KEY" in response.json()["detail"]


def test_prepare_confirm_flow_restricts_external_transmission_until_approval(tmp_path, monkeypatch) -> None:
    app = create_test_app(
        tmp_path,
        ai_mode="assisted",
        external_ai_endpoint="https://example.com/external",
        external_ai_api_key="secret",
    )
    upload, = request(
        app,
        (
            "POST",
            "/api/v1/documents",
            multipart("invoice.txt", b"Invoice number: INV-8842\nWarranty expires 2026-01-15", "text/plain"),
        ),
    )

    class FakeResponse:
        def __init__(self, payload: dict) -> None:
            self._payload = payload
            self.content = b"{}"

        def raise_for_status(self) -> None:
            return None

        def json(self) -> dict:
            return self._payload

    calls: list[dict] = []

    def fake_post(url: str, **kwargs):
        calls.append({"url": url, "json": kwargs.get("json")})
        return FakeResponse({"answer": "The invoice number is INV-8842.", "citations": [upload.json()["id"]]})

    monkeypatch.setattr("app.services.ask.httpx.post", fake_post)
    prepare = request(
        app,
        (
            "POST",
            "/api/v1/ask/prepare",
            {"json": {"question": "What is the invoice number?", "max_sources": 5}},
        ),
    )[0]
    assert prepare.status_code == 200
    prepared = prepare.json()
    assert prepared["provider"] == "external"
    assert prepared["question"] == "What is the invoice number?"
    assert prepared["proposed_excerpts"]

    rejected = request(
        app,
        (
            "POST",
            "/api/v1/ask/confirm",
            {"json": {"request_id": prepared["request_id"], "approved": False, "question": "What is the invoice number?", "excerpts": prepared["proposed_excerpts"]}},
        ),
    )[0]
    assert rejected.status_code == 200
    assert rejected.json()["approved"] is False
    assert calls == []

    prepare_again = request(
        app,
        (
            "POST",
            "/api/v1/ask/prepare",
            {"json": {"question": "What is the invoice number?", "max_sources": 5}},
        ),
    )[0]
    approved = request(
        app,
        (
            "POST",
            "/api/v1/ask/confirm",
            {"json": {"request_id": prepare_again.json()["request_id"], "approved": True, "question": "What is the invoice number?", "excerpts": prepare_again.json()["proposed_excerpts"]}},
        ),
    )[0]
    assert approved.status_code == 200
    assert approved.json()["approved"] is True
    assert calls and calls[0]["json"]["question"] == "What is the invoice number?"
    assert approved.json()["answer"] == "The invoice number is INV-8842."


def test_local_llm_rejects_invalid_citations_and_does_not_tamper_with_evidence(tmp_path, monkeypatch) -> None:
    app = create_test_app(tmp_path, ai_mode="private", local_llm_model_name="mistral", local_llm_endpoint="http://127.0.0.1:11434")
    upload, = request(
        app,
        (
            "POST",
            "/api/v1/documents",
            multipart("invoice.txt", b"Invoice number: INV-8842\nAmount due $742.50", "text/plain"),
        ),
    )
    document_id = upload.json()["id"]

    class FakeTagsResponse:
        def __init__(self, payload: dict) -> None:
            self._payload = payload
            self.content = b"{}"

        def raise_for_status(self) -> None:
            return None

        def json(self) -> dict:
            return self._payload

    def fake_get(*_args, **_kwargs):
        return FakeTagsResponse({"models": [{"name": "mistral"}]})

    class FakeGenerateResponse:
        def __init__(self, payload: dict) -> None:
            self._payload = payload
            self.content = b"{}"

        def raise_for_status(self) -> None:
            return None

        def json(self) -> dict:
            return self._payload

    def fake_post(*_args, **_kwargs):
        return FakeGenerateResponse({"response": f"The answer is not supported by evidence [NOT_REAL] and [{document_id}]", "citations": ["NOT_REAL", document_id]})

    monkeypatch.setattr("app.services.ask.httpx.Client.get", fake_get)
    monkeypatch.setattr("app.services.ask.httpx.Client.post", fake_post)

    with app.state.session_factory() as db:
        document = db.get(Document, document_id)
        assert document is not None
        result = LocalLLMProvider(app.state.settings).answer("What is the invoice number?", [document], max_sources=5)

    assert result.provider == "local-llm"
    assert result.sufficient_evidence is True
    assert result.evidence[0].document_id == document_id


def test_private_endpoints_reject_unauthenticated_requests(tmp_path) -> None:
    app = create_test_app(tmp_path)
    protected_requests = [
        ("GET", "/api/v1/documents", {}),
        ("POST", "/api/v1/documents", multipart("notes.txt", b"LORE private", "text/plain")),
        ("GET", "/api/v1/documents/missing", {}),
        ("GET", "/api/v1/documents/missing/download", {}),
        ("DELETE", "/api/v1/documents/missing", {}),
        ("GET", "/api/v1/documents/missing/related", {}),
        ("POST", "/api/v1/documents/missing/related/recalculate", {}),
        ("POST", "/api/v1/relationships/rebuild", {}),
        ("GET", "/api/v1/relationships/missing", {}),
        ("GET", "/api/v1/search", {"params": {"q": "LORE"}}),
        ("POST", "/api/v1/search/rebuild", {}),
        ("GET", "/api/v1/categories", {}),
        ("GET", "/api/v1/ask/status", {}),
        ("POST", "/api/v1/ask", {"json": {"question": "Where is LORE?"}}),
        ("POST", "/api/v1/ask/mode", {"json": {"mode": "private"}}),
        ("POST", "/api/v1/ask/prepare", {"json": {"question": "Where is LORE?"}}),
        ("POST", "/api/v1/ask/confirm", {"json": {"request_id": "missing", "approved": False}}),
        ("POST", "/api/v1/ask/cancel", {"params": {"request_id": "missing"}}),
        ("POST", "/api/v1/ask/revoke-consent", {}),
        ("GET", "/api/v1/auth/session", {}),
        ("POST", "/api/v1/auth/logout", {}),
        ("POST", "/api/v1/auth/revoke-all", {}),
    ]

    responses = request(app, *protected_requests, authenticated=False)

    assert [response.status_code for response in responses] == [401] * len(protected_requests)
    for response in responses:
        assert response.json() == {"detail": "Authentication required."}
        assert response.headers["www-authenticate"] == "Bearer"
        assert response.headers["cache-control"] == "no-store"
        assert response.headers["x-content-type-options"] == "nosniff"

    malformed = request(
        app,
        ("GET", "/api/v1/documents", {"headers": {"Authorization": "Bearer not-a-session"}}),
        ("GET", "/api/v1/documents", {"headers": {"Authorization": "Basic abc"}}),
        authenticated=False,
    )
    assert [response.status_code for response in malformed] == [401, 401]


def test_public_endpoints_remain_available_before_pairing(tmp_path) -> None:
    app = create_test_app(tmp_path)
    responses = request(
        app,
        ("GET", "/", {}),
        ("GET", "/api/v1/system/status", {}),
        ("GET", "/api/v1/auth/status", {}),
        authenticated=False,
    )

    assert [response.status_code for response in responses] == [200, 200, 200]
    status = responses[2].json()
    assert status["paired"] is False
    assert status["pairing_required"] is True
    assert status["active_sessions"] == 0
    assert status["pairing_expires_at"] is not None
    assert "token" not in status
    assert responses[2].headers["cache-control"] == "no-store"


def test_pairing_hashes_session_tokens_and_disables_further_pairing(tmp_path) -> None:
    app = create_test_app(tmp_path)

    async def scenario():
        async with app.router.lifespan_context(app):
            async with httpx.AsyncClient(
                transport=httpx.ASGITransport(app=app),
                base_url="http://test",
            ) as client:
                pairing_path = app.state.auth.pairing_code_path
                pairing_code = json.loads(pairing_path.read_text(encoding="utf-8"))["code"]
                paired = await client.post("/api/v1/auth/pair", json={"code": pairing_code})
                assert paired.status_code == 200, paired.text
                token = paired.json()["token"]
                assert paired.headers["cache-control"] == "no-store"
                assert not pairing_path.exists()

                session = await client.get(
                    "/api/v1/auth/session",
                    headers={"Authorization": f"Bearer {token}"},
                )
                assert session.status_code == 200
                assert session.json()["authenticated"] is True

                repeated = await client.post(
                    "/api/v1/auth/pair", json={"code": pairing_code}
                )
                assert repeated.status_code == 409

                status = await client.get("/api/v1/auth/status")
                assert status.json()["paired"] is True
                assert status.json()["pairing_required"] is False

                with app.state.session_factory() as db:
                    sessions = list(db.scalars(select(AuthSession)))
                    assert len(sessions) == 1
                    assert sessions[0].token_hash == hashlib.sha256(token.encode()).hexdigest()
                    assert sessions[0].token_hash != token

    asyncio.run(scenario())


def test_pairing_rejects_wrong_or_expired_codes_and_rotates_expired_code(tmp_path) -> None:
    app = create_test_app(tmp_path)

    async def scenario():
        async with app.router.lifespan_context(app):
            async with httpx.AsyncClient(
                transport=httpx.ASGITransport(app=app),
                base_url="http://test",
            ) as client:
                pairing_path = app.state.auth.pairing_code_path
                original = json.loads(pairing_path.read_text(encoding="utf-8"))

                wrong_code = "0" * 32
                wrong = await client.post("/api/v1/auth/pair", json={"code": wrong_code})
                assert wrong.status_code == 401
                assert wrong_code not in wrong.text
                assert pairing_path.exists()
                assert json.loads(pairing_path.read_text(encoding="utf-8")) == original

                expired_code = "a" * 32
                expired_at = datetime.now(timezone.utc) - timedelta(minutes=1)
                pairing_path.write_text(
                    json.dumps(
                        {"code": expired_code, "expires_at": expired_at.isoformat()}
                    ),
                    encoding="utf-8",
                )
                expired = await client.post(
                    "/api/v1/auth/pair", json={"code": expired_code}
                )
                assert expired.status_code == 401
                assert "expired" in expired.json()["detail"].lower()

                rotated = json.loads(pairing_path.read_text(encoding="utf-8"))["code"]
                assert rotated != expired_code
                accepted = await client.post("/api/v1/auth/pair", json={"code": rotated})
                assert accepted.status_code == 200

    asyncio.run(scenario())


def _expire_pairing_lockout(settings: Settings) -> None:
    engine = create_database_engine(settings)
    try:
        with create_session_factory(engine)() as db:
            attempt = db.get(PairingAttempt, 1)
            assert attempt is not None
            attempt.locked_until = datetime.now(timezone.utc) - timedelta(seconds=1)
            db.commit()
    finally:
        engine.dispose()


def _pairing_attempt(settings: Settings) -> PairingAttempt | None:
    engine = create_database_engine(settings)
    try:
        with create_session_factory(engine)() as db:
            return db.get(PairingAttempt, 1)
    finally:
        engine.dispose()


def test_pairing_lockout_persists_across_restart_and_resets_after_success(
    tmp_path,
) -> None:
    settings = Settings(
        data_dir=tmp_path / "local-data",
        database_path=tmp_path / "local-data" / "test.db",
        auth_pairing_max_failures=3,
        auth_pairing_lockout_seconds=60,
        auth_pairing_max_lockout_seconds=120,
    )
    upgrade_database(settings)
    app = create_app(settings)

    failures = request(
        app,
        *[
            ("POST", "/api/v1/auth/pair", {"json": {"code": f"{index}" * 32}})
            for index in range(3)
        ],
        authenticated=False,
    )
    assert [response.status_code for response in failures] == [401, 401, 401]

    pairing_path = app.state.auth.pairing_code_path
    valid_code = json.loads(pairing_path.read_text(encoding="utf-8"))["code"]
    limited = request(
        app,
        ("POST", "/api/v1/auth/pair", {"json": {"code": valid_code}}),
        authenticated=False,
    )[0]
    assert limited.status_code == 429
    assert 1 <= int(limited.headers["retry-after"]) <= 60
    assert limited.headers["cache-control"] == "no-store"
    assert valid_code not in limited.text
    assert _pairing_attempt(settings) is not None

    upgrade_database(settings)
    restarted = create_app(settings)
    still_limited = request(
        restarted,
        ("POST", "/api/v1/auth/pair", {"json": {"code": valid_code}}),
        authenticated=False,
    )[0]
    assert still_limited.status_code == 429

    _expire_pairing_lockout(settings)
    paired = request(
        restarted,
        ("POST", "/api/v1/auth/pair", {"json": {"code": valid_code}}),
        authenticated=False,
    )[0]
    assert paired.status_code == 200
    token = paired.json()["token"]
    assert _pairing_attempt(settings) is None

    logout = request(
        restarted,
        (
            "POST",
            "/api/v1/auth/logout",
            {"headers": {"Authorization": f"Bearer {token}"}},
        ),
        authenticated=False,
    )[0]
    assert logout.status_code == 200

    fresh_code = json.loads(pairing_path.read_text(encoding="utf-8"))["code"]
    single_failure = request(
        restarted,
        ("POST", "/api/v1/auth/pair", {"json": {"code": "f" * 32}}),
        authenticated=False,
    )[0]
    assert single_failure.status_code == 401
    recovered = request(
        restarted,
        ("POST", "/api/v1/auth/pair", {"json": {"code": fresh_code}}),
        authenticated=False,
    )[0]
    assert recovered.status_code == 200
    assert _pairing_attempt(settings) is None


def test_pairing_lockout_grows_gradually_but_is_capped(tmp_path) -> None:
    settings = Settings(
        data_dir=tmp_path / "local-data",
        database_path=tmp_path / "local-data" / "test.db",
        auth_pairing_max_failures=1,
        auth_pairing_lockout_seconds=10,
        auth_pairing_max_lockout_seconds=20,
    )
    upgrade_database(settings)
    app = create_app(settings)

    deltas = []
    for _ in range(3):
        failure = request(
            app,
            ("POST", "/api/v1/auth/pair", {"json": {"code": "0" * 32}}),
            authenticated=False,
        )[0]
        assert failure.status_code == 401
        limited = request(
            app,
            ("POST", "/api/v1/auth/pair", {"json": {"code": "0" * 32}}),
            authenticated=False,
        )[0]
        assert limited.status_code == 429
        deltas.append(int(limited.headers["retry-after"]))
        _expire_pairing_lockout(settings)

    assert 1 <= deltas[0] <= 10
    assert 11 <= deltas[1] <= 20
    assert 11 <= deltas[2] <= 20
    assert _pairing_attempt(settings).lockout_count == 3


def test_missing_pairing_code_failures_count_towards_the_lockout(tmp_path) -> None:
    app = create_test_app(
        tmp_path,
        auth_pairing_max_failures=2,
        auth_pairing_lockout_seconds=60,
    )

    async def scenario():
        async with app.router.lifespan_context(app):
            async with httpx.AsyncClient(
                transport=httpx.ASGITransport(app=app),
                base_url="http://test",
            ) as client:
                pairing_path = app.state.auth.pairing_code_path
                for _ in range(2):
                    pairing_path.unlink()
                    response = await client.post(
                        "/api/v1/auth/pair", json={"code": "0" * 32}
                    )
                    assert response.status_code == 401

                valid_code = json.loads(
                    pairing_path.read_text(encoding="utf-8")
                )["code"]
                limited = await client.post(
                    "/api/v1/auth/pair", json={"code": valid_code}
                )
                assert limited.status_code == 429
                assert limited.headers["retry-after"]
                assert valid_code not in limited.text

    asyncio.run(scenario())


def test_pairing_codes_and_tokens_are_never_written_to_logs(tmp_path, caplog) -> None:
    app = create_test_app(
        tmp_path,
        auth_pairing_max_failures=2,
        auth_pairing_lockout_seconds=60,
    )
    caplog.set_level(logging.DEBUG)

    wrong = request(
        app,
        ("POST", "/api/v1/auth/pair", {"json": {"code": "a" * 32}}),
        authenticated=False,
    )[0]
    assert wrong.status_code == 401

    pairing_path = app.state.auth.pairing_code_path
    pairing_code = json.loads(pairing_path.read_text(encoding="utf-8"))["code"]
    paired = request(
        app,
        ("POST", "/api/v1/auth/pair", {"json": {"code": pairing_code}}),
        authenticated=False,
    )[0]
    assert paired.status_code == 200
    token = paired.json()["token"]

    logged = caplog.text
    assert pairing_code not in logged
    assert token not in logged
    assert "a" * 32 not in logged


def test_expired_logged_out_and_revoked_tokens_are_rejected(tmp_path) -> None:
    app = create_test_app(tmp_path)
    first = request(app, ("GET", "/api/v1/auth/session", {}))[0]
    assert first.status_code == 200
    expired_token = app.state._test_auth_token

    with app.state.session_factory() as db:
        sessions = list(db.scalars(select(AuthSession)))
        assert len(sessions) == 1
        sessions[0].expires_at = datetime.now(timezone.utc) - timedelta(seconds=1)
        db.commit()

    expired = request(
        app,
        (
            "GET",
            "/api/v1/documents",
            {"headers": {"Authorization": f"Bearer {expired_token}"}},
        ),
        authenticated=False,
    )[0]
    assert expired.status_code == 401

    renewed = request(app, ("GET", "/api/v1/documents", {}))[0]
    assert renewed.status_code == 200
    logged_out_token = app.state._test_auth_token
    logout = request(app, ("POST", "/api/v1/auth/logout", {}))[0]
    assert logout.status_code == 200
    assert logout.json() == {"revoked": True}

    after_logout = request(
        app,
        (
            "GET",
            "/api/v1/documents",
            {"headers": {"Authorization": f"Bearer {logged_out_token}"}},
        ),
        authenticated=False,
    )[0]
    assert after_logout.status_code == 401

    status_after_logout = request(
        app, ("GET", "/api/v1/auth/status", {}), authenticated=False
    )[0]
    assert status_after_logout.json()["pairing_required"] is True
    assert app.state.auth.pairing_code_path.is_file()

    renewed_again = request(app, ("GET", "/api/v1/documents", {}))[0]
    assert renewed_again.status_code == 200
    revoked_token = app.state._test_auth_token
    revoked = request(app, ("POST", "/api/v1/auth/revoke-all", {}))[0]
    assert revoked.status_code == 200
    assert revoked.json()["revoked"] >= 1
    assert revoked.json()["pairing_required"] is True

    after_revoke = request(
        app,
        (
            "GET",
            "/api/v1/documents",
            {"headers": {"Authorization": f"Bearer {revoked_token}"}},
        ),
        authenticated=False,
    )[0]
    assert after_revoke.status_code == 401

    status_after_revoke = request(
        app, ("GET", "/api/v1/auth/status", {}), authenticated=False
    )[0]
    assert status_after_revoke.json()["pairing_required"] is True

    paired_again = request(app, ("GET", "/api/v1/documents", {}))[0]
    assert paired_again.status_code == 200


def test_authenticated_download_serves_unchanged_original_pdf(tmp_path) -> None:
    app = create_test_app(tmp_path)
    content = pdf_bytes("Original PDF content that was uploaded.")
    upload = request(
        app,
        ("POST", "/api/v1/documents", multipart("original.pdf", content, "application/pdf")),
    )[0]
    assert upload.status_code == 201
    document_id = upload.json()["id"]

    with app.state.session_factory() as db:
        stored = db.get(Document, document_id)
        assert stored is not None
        assert len(Path(stored.storage_path).parts) == 1
        assert Path(stored.storage_path).name == stored.storage_path
        stored_file = tmp_path / "local-data" / "documents" / stored.storage_path
        assert stored_file.read_bytes() == content
        assert stored.extracted_text is not None
        assert stored.extracted_text != content.decode("utf-8", errors="ignore")

    downloaded = request(app, ("GET", f"/api/v1/documents/{document_id}/download", {}))[0]
    assert downloaded.status_code == 200
    assert downloaded.content == content
    assert downloaded.headers["content-type"].startswith("application/pdf")
    assert "attachment" in downloaded.headers["content-disposition"]

    unauthenticated = request(
        app,
        ("GET", f"/api/v1/documents/{document_id}/download", {}),
        authenticated=False,
    )[0]
    assert unauthenticated.status_code == 401
    assert unauthenticated.content != content


def test_download_rejects_traversal_storage_paths(tmp_path) -> None:
    app = create_test_app(tmp_path)
    upload = request(
        app,
        ("POST", "/api/v1/documents", multipart("notes.txt", b"Original notes", "text/plain")),
    )[0]
    document_id = upload.json()["id"]
    outside_file = tmp_path / "outside.txt"
    outside_file.write_bytes(b"outside-secret")

    for bad_path in ("../outside.txt", str(outside_file.resolve())):
        with app.state.session_factory() as db:
            stored = db.get(Document, document_id)
            assert stored is not None
            stored.storage_path = bad_path
            db.commit()

        response = request(
            app, ("GET", f"/api/v1/documents/{document_id}/download", {})
        )[0]

        assert response.status_code == 500
        assert b"outside-secret" not in response.content


def test_existing_documents_remain_accessible_after_auth_is_enabled(tmp_path) -> None:
    app = create_test_app(tmp_path)
    content = b"Existing document survives authentication."
    upload = request(
        app,
        ("POST", "/api/v1/documents", multipart("existing.txt", content, "text/plain")),
    )[0]
    assert upload.status_code == 201
    document_id = upload.json()["id"]

    with app.state.session_factory() as db:
        db.execute(text("DELETE FROM auth_sessions"))
        db.commit()

    upgraded = create_test_app(tmp_path)
    responses = request(
        upgraded,
        ("GET", "/api/v1/documents", {}),
        ("GET", f"/api/v1/documents/{document_id}/download", {}),
    )

    assert responses[0].status_code == 200
    assert [item["id"] for item in responses[0].json()["items"]] == [document_id]
    assert responses[1].status_code == 200
    assert responses[1].content == content


def test_operator_recovery_revokes_sessions_and_preserves_documents(tmp_path) -> None:
    settings = Settings(
        data_dir=tmp_path / "local-data",
        database_path=tmp_path / "local-data" / "test.db",
    )
    upgrade_database(settings)
    app = create_app(settings)
    content = b"Recovery must not remove this document."
    upload = request(
        app,
        ("POST", "/api/v1/documents", multipart("recover.txt", content, "text/plain")),
    )[0]
    assert upload.status_code == 201
    document_id = upload.json()["id"]
    old_token = app.state._test_auth_token

    with app.state.session_factory() as db:
        stored = db.get(Document, document_id)
        assert stored is not None
        stored_filename = Path(stored.storage_path).name

    result = recover_access(settings)
    assert result.revoked_sessions == 1
    assert result.pairing_code_path.is_file()

    denied = request(
        app,
        (
            "GET",
            f"/api/v1/documents/{document_id}",
            {"headers": {"Authorization": f"Bearer {old_token}"}},
        ),
        authenticated=False,
    )[0]
    assert denied.status_code == 401

    listing = request(app, ("GET", "/api/v1/documents", {}))[0]
    assert listing.status_code == 200
    assert [item["id"] for item in listing.json()["items"]] == [document_id]
    stored_file = tmp_path / "local-data" / "documents" / stored_filename
    assert stored_file.read_bytes() == content


def test_operator_recovery_handles_expired_sessions(tmp_path) -> None:
    settings = Settings(
        data_dir=tmp_path / "local-data",
        database_path=tmp_path / "local-data" / "test.db",
    )
    upgrade_database(settings)
    app = create_app(settings)
    upload = request(
        app,
        ("POST", "/api/v1/documents", multipart("expired.txt", b"Still here.", "text/plain")),
    )[0]
    assert upload.status_code == 201
    document_id = upload.json()["id"]
    token = app.state._test_auth_token

    with app.state.session_factory() as db:
        sessions = list(db.scalars(select(AuthSession)))
        assert len(sessions) == 1
        sessions[0].expires_at = datetime.now(timezone.utc) - timedelta(seconds=1)
        db.commit()

    pairing_path = tmp_path / "local-data" / "pairing-code.txt"
    assert not pairing_path.exists()
    expired = request(
        app,
        (
            "GET",
            "/api/v1/documents",
            {"headers": {"Authorization": f"Bearer {token}"}},
        ),
        authenticated=False,
    )[0]
    assert expired.status_code == 401

    result = recover_access(settings)
    assert result.revoked_sessions == 0
    assert result.pairing_code_path.is_file()

    listing = request(app, ("GET", "/api/v1/documents", {}))[0]
    assert listing.status_code == 200
    assert [item["id"] for item in listing.json()["items"]] == [document_id]


def test_operator_recovery_handles_revoked_sessions_and_clears_pairing_lockout(
    tmp_path,
) -> None:
    settings = Settings(
        data_dir=tmp_path / "local-data",
        database_path=tmp_path / "local-data" / "test.db",
        auth_pairing_max_failures=1,
        auth_pairing_lockout_seconds=300,
    )
    upgrade_database(settings)
    app = create_app(settings)
    upload = request(
        app,
        ("POST", "/api/v1/documents", multipart("revoked.txt", b"Still here.", "text/plain")),
    )[0]
    assert upload.status_code == 201
    document_id = upload.json()["id"]
    token = app.state._test_auth_token

    logout = request(
        app,
        (
            "POST",
            "/api/v1/auth/logout",
            {"headers": {"Authorization": f"Bearer {token}"}},
        ),
        authenticated=False,
    )[0]
    assert logout.status_code == 200
    assert logout.json() == {"revoked": True}

    with app.state.session_factory() as db:
        sessions = list(db.scalars(select(AuthSession)))
        assert len(sessions) == 1
        assert sessions[0].revoked_at is not None

    pairing_path = tmp_path / "local-data" / "pairing-code.txt"
    valid_code = json.loads(pairing_path.read_text(encoding="utf-8"))["code"]
    wrong = request(
        app,
        ("POST", "/api/v1/auth/pair", {"json": {"code": "0" * 32}}),
        authenticated=False,
    )[0]
    assert wrong.status_code == 401
    blocked = request(
        app,
        ("POST", "/api/v1/auth/pair", {"json": {"code": valid_code}}),
        authenticated=False,
    )[0]
    assert blocked.status_code == 429

    result = recover_access(settings)
    assert result.revoked_sessions == 0
    assert result.pairing_code_path.is_file()
    assert _pairing_attempt(settings) is None

    paired = request(
        app,
        ("POST", "/api/v1/auth/pair", {"json": {"code": valid_code}}),
        authenticated=False,
    )[0]
    assert paired.status_code == 200

    listing = request(
        app,
        (
            "GET",
            "/api/v1/documents",
            {"headers": {"Authorization": f"Bearer {paired.json()['token']}"}},
        ),
        authenticated=False,
    )[0]
    assert listing.status_code == 200
    assert [item["id"] for item in listing.json()["items"]] == [document_id]
