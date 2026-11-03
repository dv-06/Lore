"""PostgreSQL-specific verification.

These tests run only when ``LORE_TEST_POSTGRES_URL`` points at an administrative
connection (for example ``postgresql://user:pass@127.0.0.1:55432/postgres``).
Each test creates and drops its own disposable database.
"""

import asyncio
import hashlib
import json
import os
import sqlite3
import uuid
from pathlib import Path

import httpx
import psycopg
import pytest
from sqlalchemy import inspect, text
from sqlalchemy.engine import make_url

from app.core.config import Settings
from app.db.schema import current_revision, head_revision
from app.db.session import create_database_engine, create_session_factory
from app.main import create_app
from app.migrate import downgrade_database, upgrade_database
from app.services.accounts import AccountService
from app.transfer import transfer

ADMIN_URL = os.environ.get("LORE_TEST_POSTGRES_URL")
pytestmark = pytest.mark.skipif(
    not ADMIN_URL,
    reason="Set LORE_TEST_POSTGRES_URL to run PostgreSQL integration tests.",
)

PASSWORD = "correct horse battery staple"


@pytest.fixture()
def pg_url() -> str:
    admin = make_url(ADMIN_URL)
    admin_url = admin.set(database="postgres").render_as_string(hide_password=False)
    database_name = f"lore_test_{uuid.uuid4().hex[:12]}"
    with psycopg.connect(admin_url, autocommit=True) as connection:
        connection.execute(f'CREATE DATABASE "{database_name}"')
    target_url = admin.set(database=database_name).render_as_string(
        hide_password=False
    )
    try:
        yield target_url
    finally:
        with psycopg.connect(admin_url, autocommit=True) as connection:
            connection.execute(
                f'DROP DATABASE IF EXISTS "{database_name}" WITH (FORCE)'
            )


def postgres_settings(pg_url: str, data_dir: Path) -> Settings:
    return Settings(
        data_dir=data_dir,
        database_path=data_dir / "unused.db",
        database_url=pg_url,
    )


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tree_hashes(root: Path) -> dict[str, str]:
    return {
        path.relative_to(root).as_posix(): sha256(path)
        for path in sorted(root.rglob("*"))
        if path.is_file()
    }


async def pair_client(app, client: httpx.AsyncClient) -> str:
    code = json.loads(app.state.auth.pairing_code_path.read_text(encoding="utf-8"))[
        "code"
    ]
    response = await client.post("/api/v1/auth/pair", json={"code": code})
    assert response.status_code == 200, response.text
    return response.json()["token"]


async def upload(
    client: httpx.AsyncClient,
    headers: dict[str, str],
    filename: str,
    content: bytes,
    media_type: str = "text/plain",
) -> dict:
    response = await client.post(
        "/api/v1/documents",
        files={"file": (filename, content, media_type)},
        headers=headers,
    )
    assert response.status_code == 201, response.text
    return response.json()


def test_fresh_postgres_schema_search_contract(
    pg_url, tmp_path, monkeypatch
) -> None:
    from app.services import documents as documents_service

    original_extract = documents_service.extract_text

    def conditional_extract(content, media_type, settings):
        if content == b"TRIGGER-EXTRACTION-FAILURE":
            raise documents_service.ExtractionError("simulated extraction failure")
        return original_extract(content, media_type, settings)

    monkeypatch.setattr(documents_service, "extract_text", conditional_extract)
    settings = postgres_settings(pg_url, tmp_path / "data")
    upgrade_database(settings)
    engine = create_database_engine(settings)
    try:
        assert current_revision(engine) == head_revision(settings)
        inspector = inspect(engine)
        search_columns = {
            column["name"] for column in inspector.get_columns("document_search")
        }
        assert {"search_text", "search_vector"} <= search_columns
        with engine.connect() as connection:
            index_definitions = [
                row[0]
                for row in connection.execute(
                    text(
                        "SELECT indexdef FROM pg_indexes "
                        "WHERE tablename = 'document_search'"
                    )
                )
            ]
        assert any(
            "using gin" in definition.casefold() and "search_vector" in definition
            for definition in index_definitions
        )
    finally:
        engine.dispose()

    app = create_app(settings)

    async def scenario() -> None:
        async with app.router.lifespan_context(app):
            assert app.state.search_available is True
            async with httpx.AsyncClient(
                transport=httpx.ASGITransport(app=app), base_url="http://test"
            ) as client:
                token = await pair_client(app, client)
                headers = {"Authorization": f"Bearer {token}"}
                purchase = await upload(
                    client,
                    headers,
                    "purchase.txt",
                    b"Invoice\nReference No: REF-887766\nProduct: Acme Washer W500",
                )
                await upload(
                    client,
                    headers,
                    "warranty.txt",
                    b"Warranty certificate\nReference No: REF-887766\nProduct: Acme Washer W500",
                )
                cafe = await upload(
                    client,
                    headers,
                    "cafe.txt",
                    "Café résumé 日本語".encode(),
                )
                failed = await upload(
                    client,
                    headers,
                    "unreadable.txt",
                    b"TRIGGER-EXTRACTION-FAILURE",
                )
                assert failed["processing_status"] == "failed"
                assert failed["extraction_status"] == "failed"
                assert failed["processing_error"] == "simulated extraction failure"

                exact = await client.get(
                    "/api/v1/search", params={"q": "purchase.txt"}, headers=headers
                )
                assert exact.status_code == 200, exact.text
                assert exact.json()["items"][0]["document_id"] == purchase["id"]
                assert (
                    "original_filename"
                    in exact.json()["items"][0]["matching_fields"]
                )

                reference = await client.get(
                    "/api/v1/search", params={"q": "REF-887766"}, headers=headers
                )
                assert reference.status_code == 200
                assert len(reference.json()["items"]) == 2
                assert all(
                    "extracted_text" in item["matching_fields"]
                    for item in reference.json()["items"]
                )

                unicode_result = await client.get(
                    "/api/v1/search", params={"q": "café"}, headers=headers
                )
                assert unicode_result.status_code == 200
                assert unicode_result.json()["items"][0]["document_id"] == cafe["id"]
                assert unicode_result.headers["cache-control"] == "no-store"

                punctuation = await client.get(
                    "/api/v1/search", params={"q": "!?*"}, headers=headers
                )
                malformed = await client.get(
                    "/api/v1/search",
                    params={"q": '") OR MATCH x'},
                    headers=headers,
                )
                blank = await client.get(
                    "/api/v1/search", params={"q": "  "}, headers=headers
                )
                too_long = await client.get(
                    "/api/v1/search",
                    params={"q": "x" * 257},
                    headers=headers,
                )
                too_many = await client.get(
                    "/api/v1/search",
                    params={"q": " ".join(f"term{index}" for index in range(13))},
                    headers=headers,
                )
                bad_limit = await client.get(
                    "/api/v1/search",
                    params={"q": "cafe", "limit": 101},
                    headers=headers,
                )
                assert punctuation.status_code == 422
                assert malformed.status_code == 200
                assert blank.status_code == 422
                assert too_long.status_code == 422
                assert too_many.status_code == 422
                assert bad_limit.status_code == 422

                updated = await client.patch(
                    f"/api/v1/documents/{purchase['id']}/organization",
                    json={"category": "Home", "tags": ["household"]},
                    headers=headers,
                )
                assert updated.status_code == 200
                category_match = await client.get(
                    "/api/v1/search",
                    params={"q": "household", "category": "Home"},
                    headers=headers,
                )
                category_miss = await client.get(
                    "/api/v1/search",
                    params={"q": "household", "category": "Finance"},
                    headers=headers,
                )
                assert len(category_match.json()["items"]) == 1
                assert category_match.json()["items"][0]["matching_fields"] == [
                    "tags"
                ]
                assert category_miss.json()["items"] == []

                rebuild = await client.post(
                    "/api/v1/search/rebuild", headers=headers
                )
                rebuild_again = await client.post(
                    "/api/v1/search/rebuild", headers=headers
                )
                assert rebuild.status_code == rebuild_again.status_code == 200
                assert rebuild.json()["indexed_documents"] == 4

                deleted = await client.delete(
                    f"/api/v1/documents/{purchase['id']}", headers=headers
                )
                after_delete = await client.get(
                    "/api/v1/search", params={"q": "purchase.txt"}, headers=headers
                )
                assert deleted.status_code == 204
                assert after_delete.json()["items"] == []

                with app.state.engine.begin() as connection:
                    connection.exec_driver_sql("DROP TABLE document_search")
                unavailable = await client.get(
                    "/api/v1/search", params={"q": "invoice"}, headers=headers
                )
                assert unavailable.status_code == 503
                assert "PostgreSQL" in unavailable.json()["detail"]

    asyncio.run(scenario())


def test_postgres_relationships_rebuild_and_deletion(pg_url, tmp_path) -> None:
    settings = postgres_settings(pg_url, tmp_path / "data")
    upgrade_database(settings)
    app = create_app(settings)

    async def scenario() -> None:
        async with app.router.lifespan_context(app):
            async with httpx.AsyncClient(
                transport=httpx.ASGITransport(app=app), base_url="http://test"
            ) as client:
                token = await pair_client(app, client)
                headers = {"Authorization": f"Bearer {token}"}
                purchase = await upload(
                    client,
                    headers,
                    "purchase.txt",
                    b"Invoice\nReference No: REF-887766\nProduct: Acme Washer W500",
                )
                await upload(
                    client,
                    headers,
                    "warranty.txt",
                    b"Warranty certificate\nReference No: REF-887766\nProduct: Acme Washer W500",
                )
                first = await client.post(
                    "/api/v1/relationships/rebuild", headers=headers
                )
                second = await client.post(
                    "/api/v1/relationships/rebuild", headers=headers
                )
                assert first.status_code == second.status_code == 200
                assert first.json()["relationships_created"] == 1
                assert second.json()["relationships_created"] == 1

                related = await client.get(
                    f"/api/v1/documents/{purchase['id']}/related",
                    headers=headers,
                )
                assert related.status_code == 200
                assert len(related.json()["items"]) == 1
                assert related.json()["items"][0]["relationship_type"]

                deleted = await client.delete(
                    f"/api/v1/documents/{purchase['id']}", headers=headers
                )
                missing = await client.get(
                    f"/api/v1/documents/{purchase['id']}", headers=headers
                )
                assert deleted.status_code == 204
                assert missing.status_code == 404

                with app.state.session_factory() as db:
                    assert (
                        db.execute(
                            text("SELECT count(*) FROM document_relationships")
                        ).scalar()
                        == 0
                    )

    asyncio.run(scenario())


def test_transfer_from_sqlite_copy_preserves_data(pg_url, tmp_path) -> None:
    source_data = tmp_path / "source-data"
    source_settings = Settings(
        data_dir=source_data,
        database_path=source_data / "lore.db",
        database_url=None,
    )
    upgrade_database(source_settings)
    source_app = create_app(source_settings)
    token_holder: dict[str, str] = {}

    async def populate() -> None:
        async with source_app.router.lifespan_context(source_app):
            async with httpx.AsyncClient(
                transport=httpx.ASGITransport(app=source_app),
                base_url="http://test",
            ) as client:
                token = await pair_client(source_app, client)
                token_holder["token"] = token
                headers = {"Authorization": f"Bearer {token}"}
                for filename, content in (
                    (
                        "purchase.txt",
                        b"Invoice\nReference No: REF-887766\nProduct: Acme Washer W500",
                    ),
                    (
                        "warranty.txt",
                        b"Warranty certificate\nReference No: REF-887766\nProduct: Acme Washer W500",
                    ),
                ):
                    await upload(client, headers, filename, content)
                rebuilt = await client.post(
                    "/api/v1/relationships/rebuild", headers=headers
                )
                assert rebuilt.json()["relationships_created"] == 1

    asyncio.run(populate())

    engine = create_database_engine(source_settings)
    factory = create_session_factory(engine)
    with factory() as db:
        accounts = AccountService(source_settings)
        owner = accounts.create_owner(db, "owner@example.com", PASSWORD)
        invitation = accounts.create_invitation(db, owner, "friend@example.com")
        invitation_id = invitation.invitation.id
    engine.dispose()

    source_database = source_data / "lore.db"
    source_hash = sha256(source_database)
    source_files = tree_hashes(source_data)

    target_settings = postgres_settings(pg_url, tmp_path / "target-data")
    upgrade_database(target_settings)
    report = transfer(
        source_sqlite=source_database,
        source_data_dir=source_data,
        target_url=pg_url,
        target_data_dir=tmp_path / "target-data",
        report_path=tmp_path / "report.json",
    )

    assert sha256(source_database) == source_hash
    assert tree_hashes(source_data) == source_files
    assert report.table_counts["documents"] == {"source": 2, "target": 2}
    assert report.table_counts["users"] == {"source": 1, "target": 1}
    assert report.table_counts["invitations"] == {"source": 1, "target": 1}
    assert report.table_counts["document_relationships"] == {
        "source": 1,
        "target": 1,
    }
    assert report.table_counts["auth_sessions"] == {"source": 1, "target": 1}
    assert report.ownership == {"documents": 2, "unowned": 2, "owned": 0}
    assert report.files["verified"] == 2
    assert report.source_sha256_before == report.source_sha256_after
    written_report = json.loads((tmp_path / "report.json").read_text())
    assert written_report["source_unchanged"] is True

    target_app = create_app(target_settings)

    async def verify() -> None:
        async with target_app.router.lifespan_context(target_app):
            assert target_app.state.search_available is True
            async with httpx.AsyncClient(
                transport=httpx.ASGITransport(app=target_app),
                base_url="http://test",
            ) as client:
                headers = {"Authorization": f"Bearer {token_holder['token']}"}
                status = await client.get("/api/v1/auth/status")
                assert status.json()["paired"] is True
                documents = await client.get("/api/v1/documents", headers=headers)
                assert documents.status_code == 200
                assert len(documents.json()["items"]) == 2
                purchase_id = next(
                    item["id"]
                    for item in documents.json()["items"]
                    if item["original_filename"] == "purchase.txt"
                )
                search = await client.get(
                    "/api/v1/search", params={"q": "REF-887766"}, headers=headers
                )
                assert search.status_code == 200
                assert len(search.json()["items"]) == 2
                related = await client.get(
                    f"/api/v1/documents/{purchase_id}/related", headers=headers
                )
                assert len(related.json()["items"]) == 1
                download = await client.get(
                    f"/api/v1/documents/{purchase_id}/download", headers=headers
                )
                assert download.status_code == 200
                assert b"REF-887766" in download.content
                with target_app.state.session_factory() as db:
                    assert (
                        db.execute(
                            text(
                                "SELECT count(*) FROM documents "
                                "WHERE owner_user_id IS NOT NULL"
                            )
                        ).scalar()
                        == 0
                    )
                    assert (
                        db.execute(
                            text("SELECT count(*) FROM invitations WHERE id = :id"),
                            {"id": invitation_id},
                        ).scalar()
                        == 1
                    )

    asyncio.run(verify())


def test_legacy_sqlite_copy_migrates_to_postgres(pg_url, tmp_path) -> None:
    source_data = tmp_path / "legacy-data"
    documents_dir = source_data / "documents"
    documents_dir.mkdir(parents=True)
    content = b"legacy invoice text"
    (documents_dir / "legacy.txt").write_bytes(content)
    database_path = source_data / "lore.db"
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
            (
                "legacy-id",
                "legacy.txt",
                "text/plain",
                len(content),
                "legacy.txt",
                "2025-01-01 00:00:00",
            ),
        )
    source_hash = sha256(database_path)

    target_data = tmp_path / "legacy-target"
    target_settings = postgres_settings(pg_url, target_data)
    upgrade_database(target_settings)
    report = transfer(
        source_sqlite=database_path,
        source_data_dir=source_data,
        target_url=pg_url,
        target_data_dir=target_data,
    )
    assert sha256(database_path) == source_hash
    assert report.table_counts["documents"] == {"source": 1, "target": 1}
    assert report.ownership == {"documents": 1, "unowned": 1, "owned": 0}

    app = create_app(target_settings)

    async def verify() -> None:
        async with app.router.lifespan_context(app):
            async with httpx.AsyncClient(
                transport=httpx.ASGITransport(app=app), base_url="http://test"
            ) as client:
                token = await pair_client(app, client)
                headers = {"Authorization": f"Bearer {token}"}
                document = await client.get(
                    "/api/v1/documents/legacy-id", headers=headers
                )
                assert document.status_code == 200
                assert document.json()["sha256"] is None
                assert document.json()["processing_status"] == "failed"
                with app.state.session_factory() as db:
                    assert (
                        db.execute(
                            text(
                                "SELECT owner_user_id FROM documents "
                                "WHERE id = 'legacy-id'"
                            )
                        ).scalar()
                        is None
                    )
                search = await client.get(
                    "/api/v1/search", params={"q": "legacy"}, headers=headers
                )
                assert search.status_code == 200
                assert search.json()["items"][0]["document_id"] == "legacy-id"
                download = await client.get(
                    "/api/v1/documents/legacy-id/download", headers=headers
                )
                assert download.content == content

    asyncio.run(verify())


def test_postgres_0004_downgrade_and_upgrade(pg_url, tmp_path) -> None:
    settings = postgres_settings(pg_url, tmp_path / "data")
    upgrade_database(settings)
    downgrade_database(settings, "0003_accounts")
    engine = create_database_engine(settings)
    try:
        assert "document_search" not in inspect(engine).get_table_names()
    finally:
        engine.dispose()
    upgrade_database(settings)
    engine = create_database_engine(settings)
    try:
        assert current_revision(engine) == "0004_search_postgres"
        assert "search_vector" in {
            column["name"]
            for column in inspect(engine).get_columns("document_search")
        }
    finally:
        engine.dispose()
