"""Safely transfer a LORE SQLite database into an empty PostgreSQL database.

The live SQLite database is never opened writable. The tool takes a
consistent snapshot with SQLite's backup API, migrates only that snapshot,
copies documents and metadata into PostgreSQL, copies the original files,
rebuilds the search index, and then verifies both sides field by field.

Usage:
    python -m app.transfer \
        --source-sqlite data/lore.db \
        --source-data-dir data \
        --target-url postgresql://lore@host/lore \
        --target-data-dir /srv/lore-data \
        --report transfer-report.json
"""

import argparse
import hashlib
import json
import shutil
import sqlite3
import tempfile
import urllib.parse
from dataclasses import dataclass, field
from datetime import date, datetime, timezone
from pathlib import Path

from sqlalchemy import inspect, select, text
from sqlalchemy.engine import Connection, Engine

import app.models  # noqa: F401 - registers metadata
from app.core.config import Settings
from app.db.base import Base
from app.db.schema import current_revision, head_revision, verify_database_schema
from app.db.session import create_database_engine
from app.migrate import upgrade_database
from app.services.search import rebuild_search_index

TABLES = (
    "users",
    "invitations",
    "auth_sessions",
    "pairing_attempts",
    "documents",
    "document_relationships",
)
PRIMARY_KEYS = {
    "users": "id",
    "invitations": "id",
    "auth_sessions": "token_hash",
    "pairing_attempts": "id",
    "documents": "id",
    "document_relationships": "id",
}
DATETIME_COLUMNS = {
    "created_at",
    "updated_at",
    "last_login_at",
    "expires_at",
    "used_at",
    "revoked_at",
    "last_failed_at",
    "locked_until",
    "uploaded_at",
    "calculated_at",
}
DATE_COLUMNS = {"document_date"}
JSON_COLUMNS = {"classification_reasons", "tags", "evidence"}


class TransferError(RuntimeError):
    pass


@dataclass
class TransferReport:
    source_sqlite: str
    source_sha256_before: str
    source_sha256_after: str = ""
    target_url: str = ""
    target_revision: str = ""
    table_counts: dict[str, dict[str, int]] = field(default_factory=dict)
    files: dict[str, int] = field(default_factory=dict)
    ownership: dict[str, int] = field(default_factory=dict)
    checks: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    def as_dict(self) -> dict[str, object]:
        return {
            "source_sqlite": self.source_sqlite,
            "source_sha256_before": self.source_sha256_before,
            "source_sha256_after": self.source_sha256_after,
            "source_unchanged": self.source_sha256_before
            == self.source_sha256_after,
            "target_url": self.target_url,
            "target_revision": self.target_revision,
            "table_counts": self.table_counts,
            "files": self.files,
            "ownership": self.ownership,
            "checks": self.checks,
            "warnings": self.warnings,
        }


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file_obj:
        for chunk in iter(lambda: file_obj.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _mask_url(url: str) -> str:
    if "@" not in url:
        return url
    prefix, suffix = url.rsplit("@", 1)
    scheme = prefix.split("://", 1)[0]
    return f"{scheme}://***@{suffix}"


def _snapshot_sqlite(source: Path, destination: Path) -> None:
    if not source.is_file():
        raise TransferError(f"Source SQLite database does not exist: {source}")
    quoted = urllib.parse.quote(source.resolve().as_posix(), safe="/:")
    source_connection = sqlite3.connect(f"file:{quoted}?mode=ro", uri=True)
    destination_connection = sqlite3.connect(str(destination))
    try:
        source_connection.backup(destination_connection)
    finally:
        destination_connection.close()
        source_connection.close()


def _as_utc(value: object) -> datetime | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        parsed = value
    elif isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value)
        except ValueError as exc:
            raise TransferError(f"Invalid timestamp in source database: {value}") from exc
    else:
        raise TransferError(f"Unexpected timestamp value in source database: {value!r}")
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _as_date(value: object) -> date | None:
    if value is None:
        return None
    if isinstance(value, date) and not isinstance(value, datetime):
        return value
    if isinstance(value, str):
        try:
            return date.fromisoformat(value)
        except ValueError as exc:
            raise TransferError(f"Invalid date in source database: {value}") from exc
    raise TransferError(f"Unexpected date value in source database: {value!r}")


def _as_json(value: object, *, default: object) -> object:
    if value is None:
        return default
    if isinstance(value, (list, dict)):
        return value
    if isinstance(value, bytes):
        value = value.decode("utf-8")
    try:
        return json.loads(str(value))
    except json.JSONDecodeError as exc:
        raise TransferError(f"Invalid JSON value in source database: {value!r}") from exc


def _convert_row(table: str, row: dict[str, object]) -> dict[str, object]:
    converted = dict(row)
    for column, value in row.items():
        if column in DATETIME_COLUMNS:
            converted[column] = _as_utc(value)
        elif column in DATE_COLUMNS:
            converted[column] = _as_date(value)
        elif column in JSON_COLUMNS:
            converted[column] = _as_json(value, default=[])
    if table == "documents":
        # Existing documents remain unowned; the transfer never invents an owner.
        converted["owner_user_id"] = None
    return converted


def _read_sqlite_rows(connection: sqlite3.Connection, table: str) -> list[dict[str, object]]:
    cursor = connection.execute(f"SELECT * FROM {table} ORDER BY {PRIMARY_KEYS[table]}")
    return [dict(row) for row in cursor.fetchall()]


def _target_counts(connection: Connection) -> dict[str, int]:
    return {
        table: int(connection.execute(text(f"SELECT count(*) FROM {table}")).scalar() or 0)
        for table in TABLES
    }


def _assert_target_empty(connection: Connection) -> None:
    counts = _target_counts(connection)
    populated = {table: count for table, count in counts.items() if count}
    if populated:
        detail = ", ".join(f"{table}={count}" for table, count in populated.items())
        raise TransferError(
            "Target database is not empty "
            f"({detail}). Use a freshly migrated, empty database. "
            "This tool never deletes existing target rows."
        )


def _table_columns(connection: Connection, table: str) -> set[str]:
    return {column["name"] for column in inspect(connection).get_columns(table)}


def _insert_rows(
    connection: Connection,
    table: str,
    rows: list[dict[str, object]],
) -> None:
    if not rows:
        return
    columns = _table_columns(connection, table)
    missing = set(rows[0]) - columns
    if missing:
        raise TransferError(
            f"Source columns missing from target table {table}: {sorted(missing)}"
        )
    target_table = Base.metadata.tables[table]
    connection.execute(target_table.insert(), rows)


def _normalize(value: object) -> object:
    if isinstance(value, datetime):
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc).isoformat()
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, (list, dict)):
        return json.dumps(value, sort_keys=True, separators=(",", ":"))
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    if isinstance(value, float):
        return repr(value)
    return value


def _compare_table(
    source_rows: list[dict[str, object]],
    target_rows: list[dict[str, object]],
    *,
    table: str,
    exclude: set[str] | None = None,
) -> None:
    key = PRIMARY_KEYS[table]
    ignored = exclude or set()
    source_by_key = {row[key]: row for row in source_rows}
    target_by_key = {row[key]: row for row in target_rows}
    if source_by_key.keys() != target_by_key.keys():
        missing = sorted(source_by_key.keys() - target_by_key.keys())
        extra = sorted(target_by_key.keys() - source_by_key.keys())
        raise TransferError(
            f"{table} identifier mismatch; missing={missing[:5]} extra={extra[:5]}"
        )
    for row_key, source_row in source_by_key.items():
        target_row = target_by_key[row_key]
        for column, value in source_row.items():
            if column in ignored:
                continue
            if _normalize(value) != _normalize(target_row.get(column)):
                raise TransferError(
                    f"{table}.{column} differs for {row_key}: "
                    f"source={value!r} target={target_row.get(column)!r}"
                )


def _safe_document_path(root: Path, storage_path: str) -> Path:
    candidate = (root / storage_path).resolve()
    if candidate != root and root not in candidate.parents:
        raise TransferError(f"Unsafe document storage path: {storage_path}")
    return candidate


def _verify_source_files(
    reports: TransferReport,
    source_documents: list[dict[str, object]],
    source_documents_dir: Path,
) -> dict[str, str]:
    hashes: dict[str, str] = {}
    total_bytes = 0
    for document in source_documents:
        storage_path = str(document["storage_path"])
        path = _safe_document_path(source_documents_dir, storage_path)
        if not path.is_file():
            raise TransferError(f"Source document file is missing: {storage_path}")
        size = path.stat().st_size
        if size != int(document["size_bytes"]):
            raise TransferError(
                f"Source file size mismatch for {storage_path}: "
                f"database={document['size_bytes']} file={size}"
            )
        digest = _sha256_file(path)
        recorded = document.get("sha256")
        if recorded and recorded != digest:
            raise TransferError(
                f"Source file SHA-256 mismatch for {storage_path}: "
                f"database={recorded} file={digest}"
            )
        hashes[storage_path] = digest
        total_bytes += size
    reports.files["documents"] = len(source_documents)
    reports.files["total_bytes"] = total_bytes
    return hashes


def _copy_document_files(
    source_documents: list[dict[str, object]],
    source_documents_dir: Path,
    target_documents_dir: Path,
    hashes: dict[str, str],
) -> list[Path]:
    target_documents_dir.mkdir(parents=True, exist_ok=True)
    created: list[Path] = []
    for document in source_documents:
        relative = str(document["storage_path"])
        source_path = _safe_document_path(source_documents_dir, relative)
        target_path = _safe_document_path(target_documents_dir, relative)
        target_path.parent.mkdir(parents=True, exist_ok=True)
        if target_path.exists():
            if _sha256_file(target_path) != hashes[relative]:
                raise TransferError(
                    f"Target file already exists with different content: {relative}"
                )
            continue
        shutil.copy2(source_path, target_path)
        created.append(target_path)
        if _sha256_file(target_path) != hashes[relative]:
            raise TransferError(f"Copied file failed SHA-256 verification: {relative}")
    return created


def _verify_target_files(
    source_documents: list[dict[str, object]],
    target_documents_dir: Path,
    hashes: dict[str, str],
) -> None:
    verified = 0
    for document in source_documents:
        relative = str(document["storage_path"])
        target_path = _safe_document_path(target_documents_dir, relative)
        if not target_path.is_file():
            raise TransferError(f"Target document file is missing: {relative}")
        if target_path.stat().st_size != int(document["size_bytes"]):
            raise TransferError(f"Target file size mismatch: {relative}")
        if _sha256_file(target_path) != hashes[relative]:
            raise TransferError(f"Target file SHA-256 mismatch: {relative}")
        verified += 1
    if verified != len(source_documents):
        raise TransferError("Target document file count does not match the database")


def _rebuild_target_search(target_engine: Engine) -> int:
    from sqlalchemy.orm import sessionmaker

    factory = sessionmaker(bind=target_engine, autoflush=False, expire_on_commit=False)
    with factory() as db:
        return rebuild_search_index(db)


def transfer(
    *,
    source_sqlite: Path,
    source_data_dir: Path,
    target_url: str,
    target_data_dir: Path,
    report_path: Path | None = None,
    keep_snapshot: bool = False,
) -> TransferReport:
    source_sqlite = source_sqlite.expanduser().resolve()
    source_data_dir = source_data_dir.expanduser().resolve()
    target_data_dir = target_data_dir.expanduser().resolve()
    if not source_sqlite.is_file():
        raise TransferError(f"Source SQLite database does not exist: {source_sqlite}")
    if not target_url.casefold().startswith(("postgresql://", "postgres://", "postgresql+psycopg://")):
        raise TransferError("The target must be a PostgreSQL URL.")

    source_documents_dir = source_data_dir / "documents"
    target_documents_dir = target_data_dir / "documents"
    if source_documents_dir.resolve() == target_documents_dir.resolve():
        raise TransferError(
            "Source and target document directories must be different; "
            "the live data directory is never modified."
        )
    if target_data_dir == source_data_dir:
        raise TransferError("The target data directory must differ from the source.")
    if target_data_dir.is_relative_to(source_data_dir) or source_data_dir.is_relative_to(
        target_data_dir
    ):
        raise TransferError(
            "Source and target data directories must not contain each other; "
            "the live data directory is never modified."
        )

    report = TransferReport(
        source_sqlite=str(source_sqlite),
        source_sha256_before=_sha256_file(source_sqlite),
        target_url=_mask_url(target_url),
    )
    target_settings = Settings(
        data_dir=target_data_dir,
        database_path=target_data_dir / "unused.db",
        database_url=target_url,
    )
    target_engine = create_database_engine(target_settings)
    snapshot_directory = Path(tempfile.mkdtemp(prefix="lore-transfer-"))
    snapshot = snapshot_directory / "source-snapshot.db"
    created_files: list[Path] = []
    try:
        verify_database_schema(target_engine, target_settings)
        report.target_revision = current_revision(target_engine) or ""
        if report.target_revision != head_revision(target_settings):
            raise TransferError("Target database is not at the current schema revision.")

        _snapshot_sqlite(source_sqlite, snapshot)

        snapshot_settings = Settings(
            data_dir=snapshot_directory,
            database_path=snapshot,
            database_url=None,
        )
        upgrade_database(snapshot_settings)

        source_connection = sqlite3.connect(str(snapshot))
        source_connection.row_factory = sqlite3.Row
        try:
            source_rows = {
                table: [
                    _convert_row(table, row)
                    for row in _read_sqlite_rows(source_connection, table)
                ]
                for table in TABLES
            }
        finally:
            source_connection.close()
        source_documents = source_rows["documents"]

        file_hashes = _verify_source_files(
            report, source_documents, source_documents_dir
        )
        created_files = _copy_document_files(
            source_documents,
            source_documents_dir,
            target_documents_dir,
            file_hashes,
        )
        _verify_target_files(
            source_documents, target_documents_dir, file_hashes
        )

        with target_engine.begin() as connection:
            _assert_target_empty(connection)
            for table in TABLES:
                _insert_rows(connection, table, source_rows[table])

        # Verification reads through a fresh transaction rather than trusting
        # the insert path.
        with target_engine.connect() as connection:
            target_counts = _target_counts(connection)
            for table in TABLES:
                report.table_counts[table] = {
                    "source": len(source_rows[table]),
                    "target": target_counts[table],
                }
                target_rows = [
                    dict(row)
                    for row in connection.execute(
                        select(Base.metadata.tables[table]).order_by(
                            Base.metadata.tables[table].c[PRIMARY_KEYS[table]]
                        )
                    ).mappings()
                ]
                _compare_table(
                    source_rows[table],
                    target_rows,
                    table=table,
                    exclude={"owner_user_id"} if table == "documents" else None,
                )
            owner_count = int(
                connection.execute(
                    text("SELECT count(*) FROM documents WHERE owner_user_id IS NOT NULL")
                ).scalar()
                or 0
            )
            report.ownership = {
                "documents": len(source_rows["documents"]),
                "unowned": len(source_rows["documents"]) - owner_count,
                "owned": owner_count,
            }
            if owner_count:
                raise TransferError("Transferred documents were assigned an owner.")

        indexed = _rebuild_target_search(target_engine)
        report.checks.append(f"search index rebuilt for {indexed} documents")
        if indexed != len(source_documents):
            raise TransferError(
                f"Search index contains {indexed} of {len(source_documents)} documents."
            )

        report.files["verified"] = len(source_documents)
        report.checks.extend(
            [
                "source snapshot was migrated to the current revision",
                "all table identifiers and fields match",
                "all document files match size and SHA-256",
                "relationship foreign keys reference transferred documents",
                "all transferred documents remain unowned",
            ]
        )
        if not report.warnings:
            report.warnings.append(
                "Search ranking and snippets follow PostgreSQL full-text semantics "
                "and can differ slightly from SQLite FTS5."
            )
    except Exception:
        for path in reversed(created_files):
            try:
                path.unlink()
            except OSError:
                pass
        raise
    finally:
        target_engine.dispose()
        report.source_sha256_after = _sha256_file(source_sqlite)
        if keep_snapshot:
            report.warnings.append(f"SQLite snapshot retained at {snapshot}")
        else:
            shutil.rmtree(snapshot_directory, ignore_errors=True)
        if report_path is not None:
            report_path.parent.mkdir(parents=True, exist_ok=True)
            report_path.write_text(
                json.dumps(report.as_dict(), indent=2, sort_keys=True),
                encoding="utf-8",
            )

    if report.source_sha256_before != report.source_sha256_after:
        raise TransferError(
            "The live SQLite database changed during the transfer. "
            "Stop the backend, keep the original, and rerun the transfer."
        )
    return report


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="python -m app.transfer",
        description=(
            "Copy a LORE SQLite database and documents into an empty, "
            "migrated PostgreSQL database without modifying the source."
        ),
    )
    parser.add_argument("--source-sqlite", type=Path, required=True)
    parser.add_argument("--source-data-dir", type=Path, required=True)
    parser.add_argument("--target-url", required=True)
    parser.add_argument("--target-data-dir", type=Path, required=True)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--keep-snapshot", action="store_true")
    args = parser.parse_args(argv)

    try:
        report = transfer(
            source_sqlite=args.source_sqlite,
            source_data_dir=args.source_data_dir,
            target_url=args.target_url,
            target_data_dir=args.target_data_dir,
            report_path=args.report,
            keep_snapshot=args.keep_snapshot,
        )
    except TransferError as exc:
        print(f"Transfer aborted: {exc}")
        return 2
    print(json.dumps(report.as_dict(), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
