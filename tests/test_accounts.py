import asyncio
import hashlib
import json
import sqlite3
from datetime import datetime, timedelta, timezone
from pathlib import Path

import httpx
import pytest
from sqlalchemy import inspect, select
from sqlalchemy.exc import IntegrityError

import app.admin as admin_module
from app.admin import create_invitation, initialize_owner
from app.core.config import Settings
from app.core.email import InvalidEmailError, normalize_email
from app.core.passwords import PasswordPolicyError, PasswordService
from app.db.schema import DatabaseSchemaError, current_revision, head_revision
from app.db.session import create_database_engine, create_session_factory
from app.main import create_app
from app.migrate import downgrade_database, upgrade_database
from app.models.auth import AuthSession
from app.models.document import Document
from app.models.invitation import Invitation
from app.models.user import User, UserRole, UserStatus
from app.services.accounts import (
    AccountService,
    DuplicateEmailError,
    InvitationAlreadyUsedError,
    InvitationEmailMismatchError,
    InvitationExpiredError,
    InvitationRevokedError,
    OwnerAlreadyExistsError,
    hash_invitation_token,
)
from app.services.auth import AuthManager

PASSWORD = "correct horse battery staple"


def make_settings(tmp_path: Path, **overrides) -> Settings:
    options = {
        "data_dir": tmp_path / "local-data",
        "database_path": tmp_path / "local-data" / "test.db",
        "database_url": None,
    }
    options.update(overrides)
    return Settings(**options)


def open_db(settings: Settings):
    engine = create_database_engine(settings)
    return engine, create_session_factory(engine)


def create_owner(settings: Settings, email: str = "owner@example.com") -> str:
    engine, factory = open_db(settings)
    try:
        with factory() as db:
            return AccountService(settings).create_owner(db, email, PASSWORD).id
    finally:
        engine.dispose()


async def http_request(app, method: str, path: str, **kwargs):
    async with app.router.lifespan_context(app):
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app), base_url="http://test"
        ) as client:
            return await client.request(method, path, **kwargs)


async def pair(app, client) -> str:
    code = json.loads(
        app.state.auth.pairing_code_path.read_text(encoding="utf-8")
    )["code"]
    response = await client.post("/api/v1/auth/pair", json={"code": code})
    assert response.status_code == 200, response.text
    return response.json()["token"]


def test_email_normalization_is_canonical_and_conservative() -> None:
    assert normalize_email("  Tester@Example.COM  ") == "tester@example.com"
    assert (
        normalize_email("Ｔｅｓｔｅｒ＠Ｅｘａｍｐｌｅ．ｃｏｍ")
        == "tester@example.com"
    )
    assert normalize_email("First.Last+tag@Example.com") == (
        "first.last+tag@example.com"
    )

    invalid = [
        "",
        "no-at-sign",
        "@example.com",
        "user@",
        "user@@example.com",
        "user@example",
        "user@.example.com",
        "user@example..com",
        ".user@example.com",
        "user.@example.com",
        "us..er@example.com",
        "user@-example.com",
        "user@example-.com",
        "user@example.123",
        "user@exam ple.com",
        "tést@example.com",
        "a" * 65 + "@example.com",
        "user@" + "a" * 250 + ".com",
    ]
    for address in invalid:
        with pytest.raises(InvalidEmailError):
            normalize_email(address)


def test_argon2id_hashes_and_rejects_malformed_values(tmp_path) -> None:
    service = PasswordService(make_settings(tmp_path))
    first = service.hash(PASSWORD)
    second = service.hash(PASSWORD)

    assert first.startswith("$argon2id$")
    assert len(first) < 255
    assert PASSWORD not in first
    assert first != second  # random salt per hash
    assert service.verify(PASSWORD, first) is True
    assert service.verify("wrong password", first) is False
    assert service.needs_rehash(first) is False

    for malformed in ("", "not-a-hash", "$argon2id$v=19$broken", first[:40]):
        assert service.verify(PASSWORD, malformed) is False


def test_password_policy_bounds(tmp_path) -> None:
    service = PasswordService(make_settings(tmp_path))
    with pytest.raises(PasswordPolicyError):
        service.hash("short")
    with pytest.raises(PasswordPolicyError):
        service.hash("x" * 129)
    with pytest.raises(PasswordPolicyError):
        service.hash("            ")
    with pytest.raises(PasswordPolicyError):
        service.hash(123456789012)  # type: ignore[arg-type]
    assert service.hash("x" * 12).startswith("$argon2id$")


def test_owner_creation_normalizes_email_and_prevents_a_second_owner(tmp_path) -> None:
    settings = make_settings(tmp_path)
    upgrade_database(settings)
    engine, factory = open_db(settings)
    try:
        with factory() as db:
            service = AccountService(settings)
            owner = service.create_owner(db, "  Owner@Example.COM ", PASSWORD)

            assert owner.email == "owner@example.com"
            assert owner.role == UserRole.OWNER
            assert owner.status == UserStatus.ACTIVE
            assert owner.password_hash != PASSWORD
            assert service.passwords.verify(PASSWORD, owner.password_hash)
            assert service.verify_credentials(
                db, "OWNER@example.com", PASSWORD
            ).id == owner.id

            with pytest.raises(OwnerAlreadyExistsError):
                service.create_owner(db, "other@example.com", PASSWORD)
    finally:
        engine.dispose()


def test_single_owner_is_enforced_by_a_partial_unique_index(tmp_path) -> None:
    settings = make_settings(tmp_path)
    upgrade_database(settings)
    engine, factory = open_db(settings)
    try:
        with factory() as db:
            AccountService(settings).create_owner(db, "owner@example.com", PASSWORD)
            db.add(
                User(
                    email="second-owner@example.com",
                    password_hash="unused",
                    role=UserRole.OWNER,
                )
            )
            with pytest.raises(IntegrityError):
                db.commit()
            db.rollback()
    finally:
        engine.dispose()


def test_duplicate_email_is_rejected(tmp_path) -> None:
    settings = make_settings(tmp_path)
    upgrade_database(settings)
    engine, factory = open_db(settings)
    try:
        with factory() as db:
            service = AccountService(settings)
            service.create_user(db, "member@example.com", PASSWORD)
            with pytest.raises(DuplicateEmailError):
                service.create_user(db, "MEMBER@example.com", PASSWORD)
    finally:
        engine.dispose()


def test_invitation_stores_only_the_hash_and_is_bound_to_an_email(tmp_path) -> None:
    settings = make_settings(tmp_path)
    upgrade_database(settings)
    engine, factory = open_db(settings)
    try:
        with factory() as db:
            service = AccountService(settings)
            owner = service.create_owner(db, "owner@example.com", PASSWORD)
            created = service.create_invitation(
                db, owner, "  Tester@Example.COM "
            )

            assert created.invitation.email == "tester@example.com"
            assert created.invitation.created_by == owner.id
            assert created.invitation.token_hash == hash_invitation_token(
                created.token
            )
            assert created.invitation.token_hash != created.token
            assert created.token not in repr(created)
            assert created.invitation.used_at is None
            assert created.invitation.revoked_at is None

            member = service.create_user(db, "member@example.com", PASSWORD)
            with pytest.raises(PermissionError):
                service.create_invitation(db, member, "another@example.com")
    finally:
        engine.dispose()


def test_invitation_expiry_revocation_mismatch_and_single_use(tmp_path) -> None:
    settings = make_settings(tmp_path)
    upgrade_database(settings)
    engine, factory = open_db(settings)
    try:
        with factory() as db:
            service = AccountService(settings)
            owner = service.create_owner(db, "owner@example.com", PASSWORD)

            expired = service.create_invitation(
                db, owner, "expired@example.com"
            )
            expired.invitation.expires_at = datetime.now(
                timezone.utc
            ) - timedelta(seconds=1)
            db.commit()
            with pytest.raises(InvitationExpiredError):
                service.validate_invitation(db, expired.token)

            revoked = service.create_invitation(
                db, owner, "revoked@example.com"
            )
            assert service.revoke_invitation(db, revoked.invitation.id) is True
            with pytest.raises(InvitationRevokedError):
                service.validate_invitation(db, revoked.token)

            mismatched = service.create_invitation(
                db, owner, "bound@example.com"
            )
            with pytest.raises(InvitationEmailMismatchError) as error:
                service.validate_invitation(
                    db, mismatched.token, "someone-else@example.com"
                )
            assert "bound@" not in str(error.value)
            assert str(error.value) == "The invitation is invalid or has expired."

            single = service.create_invitation(db, owner, "new@example.com")
            user = service.redeem_invitation(
                db, single.token, "new@example.com", PASSWORD
            )
            assert user.role == UserRole.USER
            assert service.verify_credentials(
                db, "new@example.com", PASSWORD
            ).id == user.id

            stored = db.get(Invitation, single.invitation.id)
            assert stored.used_at is not None
            assert stored.used_by == user.id
            with pytest.raises(InvitationAlreadyUsedError):
                service.redeem_invitation(
                    db, single.token, "new@example.com", PASSWORD
                )
            assert db.scalar(
                select(User).where(User.email == "new@example.com")
            ).id == user.id
    finally:
        engine.dispose()


def test_invitation_for_existing_account_does_not_consume_or_leak(tmp_path) -> None:
    settings = make_settings(tmp_path)
    upgrade_database(settings)
    engine, factory = open_db(settings)
    try:
        with factory() as db:
            service = AccountService(settings)
            owner = service.create_owner(db, "owner@example.com", PASSWORD)
            service.create_user(db, "existing@example.com", PASSWORD)
            created = service.create_invitation(
                db, owner, "existing@example.com"
            )
            with pytest.raises(DuplicateEmailError) as error:
                service.redeem_invitation(
                    db, created.token, "existing@example.com", PASSWORD
                )
            assert "existing@" not in str(error.value)
            assert db.get(Invitation, created.invitation.id).used_at is None
    finally:
        engine.dispose()


def test_owner_cli_initialization_and_invitation_creation(tmp_path) -> None:
    settings = make_settings(tmp_path)
    upgrade_database(settings)

    email = initialize_owner(settings, "Owner@Example.com", PASSWORD)
    assert email == "owner@example.com"

    with pytest.raises(OwnerAlreadyExistsError):
        initialize_owner(settings, "second@example.com", PASSWORD)

    token, expires_at = create_invitation(
        settings, "Tester@Example.com", expires_days=2
    )
    engine, factory = open_db(settings)
    try:
        with factory() as db:
            stored = db.scalar(
                select(Invitation).where(
                    Invitation.token_hash == hash_invitation_token(token)
                )
            )
            assert stored is not None
            assert stored.email == "tester@example.com"
            assert stored.created_by is not None
            assert stored.token_hash != token
    finally:
        engine.dispose()
    remaining = expires_at - datetime.now(timezone.utc)
    assert timedelta(days=1, hours=23) < remaining <= timedelta(days=2)


def test_cli_never_accepts_a_password_argument(tmp_path) -> None:
    with pytest.raises(SystemExit) as exit_info:
        admin_module.main(
            ["init-owner", "--email", "owner@example.com", "--password", "x"]
        )
    assert exit_info.value.code == 2


def test_admin_commands_require_a_migrated_database(tmp_path) -> None:
    settings = make_settings(tmp_path)
    with pytest.raises(DatabaseSchemaError):
        initialize_owner(settings, "owner@example.com", PASSWORD)


def test_user_sessions_belong_to_their_account_and_reject_disabled_users(
    tmp_path,
) -> None:
    settings = make_settings(tmp_path)
    upgrade_database(settings)
    engine, factory = open_db(settings)
    try:
        with factory() as db:
            service = AccountService(settings)
            owner = service.create_owner(db, "owner@example.com", PASSWORD)
            auth = AuthManager(settings)
            token, session = auth.create_user_session(db, owner)

            assert session.user_id == owner.id
            assert session.auth_method == "password"
            assert session.token_hash == AuthManager.hash_token(token)
            assert auth.authenticate(db, token).user_id == owner.id
            principal = auth.resolve_principal(db, session)
            assert principal.user.id == owner.id
            assert principal.is_legacy_pairing is False

            service.disable_user(db, owner.id)
            assert auth.authenticate(db, token) is None
            with pytest.raises(ValueError):
                auth.create_user_session(db, owner)
    finally:
        engine.dispose()


def test_user_sessions_expire_and_can_be_revoked_per_account(tmp_path) -> None:
    settings = make_settings(tmp_path)
    upgrade_database(settings)
    engine, factory = open_db(settings)
    try:
        with factory() as db:
            service = AccountService(settings)
            auth = AuthManager(settings)
            first = service.create_user(db, "first@example.com", PASSWORD)
            second = service.create_user(db, "second@example.com", PASSWORD)
            first_token, first_session = auth.create_user_session(db, first)
            second_token, _ = auth.create_user_session(db, second)

            first_session.expires_at = datetime.now(timezone.utc) - timedelta(
                seconds=1
            )
            db.commit()
            assert auth.authenticate(db, first_token) is None
            assert auth.authenticate(db, second_token) is not None

            revoked = auth.revoke_all(db, user_id=second.id)
            assert revoked == 1
            assert auth.authenticate(db, second_token) is None
    finally:
        engine.dispose()


def test_auth_status_session_endpoint_reports_the_principal(tmp_path) -> None:
    settings = make_settings(tmp_path)
    upgrade_database(settings)
    owner_id = create_owner(settings)
    engine, factory = open_db(settings)
    try:
        with factory() as db:
            owner = db.get(User, owner_id)
            token, _ = AuthManager(settings).create_user_session(db, owner)
    finally:
        engine.dispose()

    app = create_app(settings)

    async def scenario():
        async with app.router.lifespan_context(app):
            async with httpx.AsyncClient(
                transport=httpx.ASGITransport(app=app), base_url="http://test"
            ) as client:
                response = await client.get(
                    "/api/v1/auth/session",
                    headers={"Authorization": f"Bearer {token}"},
                )
                legacy_token = await pair(app, client)
                legacy = await client.get(
                    "/api/v1/auth/session",
                    headers={"Authorization": f"Bearer {legacy_token}"},
                )
                return response, legacy

    response, legacy = asyncio.run(scenario())

    assert response.status_code == 200
    body = response.json()
    assert body["auth_method"] == "password"
    assert body["user"] == {
        "id": owner_id,
        "email": "owner@example.com",
        "role": "owner",
    }
    assert legacy.status_code == 200
    assert legacy.json()["auth_method"] == "pairing"
    assert legacy.json()["user"] is None


def test_legacy_pairing_session_is_not_converted_to_a_user(tmp_path) -> None:
    settings = make_settings(tmp_path)
    upgrade_database(settings)
    app = create_app(settings)

    async def scenario():
        async with app.router.lifespan_context(app):
            async with httpx.AsyncClient(
                transport=httpx.ASGITransport(app=app), base_url="http://test"
            ) as client:
                token = await pair(app, client)
                with app.state.session_factory() as db:
                    session = list(db.scalars(select(AuthSession)))[0]
                    return token, session

    _, session = asyncio.run(scenario())
    assert session.auth_method == "pairing"
    assert session.user_id is None


def test_migrations_create_expected_schema_and_round_trip(tmp_path) -> None:
    settings = make_settings(tmp_path)
    upgrade_database(settings)
    engine = create_database_engine(settings)
    try:
        assert current_revision(engine) == head_revision(settings) == "0004_search_postgres"
        inspector = inspect(engine)
        tables = set(inspector.get_table_names())
        assert {
            "users",
            "invitations",
            "auth_sessions",
            "documents",
            "document_relationships",
            "pairing_attempts",
            "document_search",
        } <= tables
        session_columns = {
            column["name"] for column in inspector.get_columns("auth_sessions")
        }
        assert {"user_id", "auth_method"} <= session_columns
        document_columns = {
            column["name"] for column in inspector.get_columns("documents")
        }
        assert "owner_user_id" in document_columns
    finally:
        engine.dispose()

    downgrade_database(settings, "0002_pairing_attempts")
    engine = create_database_engine(settings)
    try:
        inspector = inspect(engine)
        tables = set(inspector.get_table_names())
        assert "users" not in tables
        assert "invitations" not in tables
        assert "auth_method" not in {
            column["name"] for column in inspector.get_columns("auth_sessions")
        }
        assert "owner_user_id" not in {
            column["name"] for column in inspector.get_columns("documents")
        }
    finally:
        engine.dispose()

    downgrade_database(settings, "base")
    engine = create_database_engine(settings)
    try:
        assert "documents" not in set(inspect(engine).get_table_names())
    finally:
        engine.dispose()

    upgrade_database(settings)
    engine = create_database_engine(settings)
    try:
        assert current_revision(engine) == head_revision(settings) == "0004_search_postgres"
    finally:
        engine.dispose()


def test_existing_pairing_session_survives_account_migration(tmp_path) -> None:
    settings = make_settings(tmp_path)
    upgrade_database(settings)
    token = "existing-pairing-token"
    engine, factory = open_db(settings)
    try:
        with factory() as db:
            db.add(
                AuthSession(
                    token_hash=AuthManager.hash_token(token),
                    created_at=datetime.now(timezone.utc),
                    expires_at=datetime.now(timezone.utc) + timedelta(days=1),
                    auth_method="pairing",
                )
            )
            db.commit()
    finally:
        engine.dispose()

    downgrade_database(settings, "0002_pairing_attempts")
    upgrade_database(settings)

    engine, factory = open_db(settings)
    try:
        with factory() as db:
            sessions = list(db.scalars(select(AuthSession)))
            assert len(sessions) == 1
            assert sessions[0].auth_method == "pairing"
            assert sessions[0].user_id is None
            assert AuthManager(settings).authenticate(db, token) is not None
    finally:
        engine.dispose()


def test_legacy_database_is_adopted_without_changing_rows_or_files(
    tmp_path,
) -> None:
    settings = make_settings(tmp_path)
    data_dir = settings.data_dir
    data_dir.mkdir(parents=True)
    documents_dir = data_dir / "documents"
    documents_dir.mkdir()
    original = b"Original document bytes that must not change."
    file_name = "legacy-doc.txt"
    (documents_dir / file_name).write_bytes(original)
    digest = hashlib.sha256(original).hexdigest()

    database_path = settings.database_path
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
                id, original_filename, media_type, size_bytes, storage_path,
                sha256, extracted_text, extraction_status, processing_status,
                uploaded_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                "legacy-doc-id",
                "legacy.txt",
                "text/plain",
                len(original),
                file_name,
                digest,
                "Preserved extracted text",
                "extracted",
                "completed",
                "2026-10-01 12:00:00",
            ),
        )

    upgrade_database(settings)

    assert (documents_dir / file_name).read_bytes() == original
    assert hashlib.sha256((documents_dir / file_name).read_bytes()).hexdigest() == digest

    engine, factory = open_db(settings)
    try:
        with factory() as db:
            document = db.get(Document, "legacy-doc-id")
            assert document is not None
            assert document.original_filename == "legacy.txt"
            assert document.extracted_text == "Preserved extracted text"
            assert document.sha256 == digest
            assert document.storage_path == file_name
            assert document.owner_user_id is None
    finally:
        engine.dispose()


def test_startup_refuses_an_unmigrated_database_without_altering_it(
    tmp_path,
) -> None:
    settings = make_settings(tmp_path)
    app = create_app(settings)

    async def scenario():
        async with app.router.lifespan_context(app):
            pass

    with pytest.raises(DatabaseSchemaError) as error:
        asyncio.run(scenario())
    assert "python -m app.migrate upgrade" in str(error.value)

    with sqlite3.connect(settings.database_path) as connection:
        tables = [
            row[0]
            for row in connection.execute(
                "SELECT name FROM sqlite_master WHERE type = 'table'"
            )
        ]
    assert tables == []


def test_public_registration_and_login_do_not_exist(tmp_path) -> None:
    settings = make_settings(tmp_path)
    upgrade_database(settings)
    app = create_app(settings)
    paths = {getattr(route, "path", "") for route in app.routes}
    assert "/api/v1/auth/register" not in paths
    assert "/api/v1/auth/login" not in paths

    response = asyncio.run(
        http_request(
            app,
            "POST",
            "/api/v1/auth/register",
            json={
                "invitation_code": "x",
                "email": "tester@example.com",
                "password": PASSWORD,
            },
        )
    )
    assert response.status_code == 404
