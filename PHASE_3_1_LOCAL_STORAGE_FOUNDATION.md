# Phase 3.1 — Local Storage Foundation

**Status:** complete. Local persistence and file storage are implemented, tested, and
validated in a release build on Android. The existing server-backed app, screens,
controllers, HTTP client, authentication, and backend were not modified. Phase 3.2 has
not started.

**Applies to:** `mobile/` (Flutter, Android-only target)
**Reference:** `PHASE_3_0_LOCAL_FIRST_ARCHITECTURE_AUDIT.md`

---

## 1. Scope and outcome

Phase 3.1 establishes a durable local layer for documents, metadata, relationships, and
search, plus app-private original-file storage with safe import and recovery semantics.

Delivered:

- Versioned SQLite schema v1 via Drift.
- FTS5 virtual table with trigger-based synchronization and a minimal search repository.
- App-private file storage with UUID names, staged writes, atomic rename, streaming
  SHA-256, duplicate detection, no-overwrite guarantees, and path containment checks.
- Functional repository interfaces isolated from `LoreApiClient`.
- A composition root and diagnostics that are not wired into the app shell.
- 34 focused tests (97 total with the existing suite) and an Android release-mode probe.

Deliberately not delivered in this phase: text extraction, OCR, classification,
relationship computation, Ask LORE, on-device LLM, UI/screen rewiring, local auth, server
removal, and automatic migration of server data.

---

## 2. Repository state preserved

The phase started and ended on branch `main` at
`4a16e9516685cee03cdbc659fb246e1c6b0847d8`. No reset, clean, stash, checkout, commit, or
push was performed.

### Existing modifications (present before Phase 3.1 work)

`.env.example`, `README.md`, `app/api/security.py`, `app/api/v1/auth.py`,
`app/api/v1/search.py`, `app/core/config.py`, `app/db/migrations.py`,
`app/db/session.py`, `app/main.py`, `app/models/__init__.py`, `app/models/auth.py`,
`app/models/document.py`, `app/schemas/auth.py`, `app/services/auth.py`,
`app/services/documents.py`, `app/services/search.py`,
`mobile/lib/state/auth_controller.dart`, `mobile/pubspec.yaml`, `pyproject.toml`,
`tests/test_api.py`.

### Existing untracked work (present before Phase 3.1 work)

`PHASE_2_0_ARCHITECTURE_AUDIT.md`, `PHASE_3_0_LOCAL_FIRST_ARCHITECTURE_AUDIT.md`,
`alembic.ini`, `alembic/`, `app/admin.py`, `app/core/email.py`,
`app/core/passwords.py`, `app/db/schema.py`, `app/migrate.py`,
`app/models/invitation.py`, `app/models/user.py`, `app/recovery.py`,
`app/services/accounts.py`, `app/services/search_common.py`,
`app/services/search_postgres.py`, `app/services/search_sqlite.py`,
`app/transfer.py`, `mobile/test/auth_controller_test.dart`, `tests/test_accounts.py`,
`tests/test_postgres.py`.

### Added by Phase 3.1

- `mobile/lib/data/local/local_models.dart`
- `mobile/lib/data/local/local_storage_paths.dart`
- `mobile/lib/data/local/local_database.dart`
- `mobile/lib/data/local/local_database.g.dart` (generated)
- `mobile/lib/data/local/document_repository.dart`
- `mobile/lib/data/local/local_search_repository.dart`
- `mobile/lib/data/local/relationship_repository.dart`
- `mobile/lib/data/local/document_file_store.dart`
- `mobile/lib/data/local/document_import_coordinator.dart`
- `mobile/lib/data/local/local_storage.dart`
- `mobile/test/local/local_database_test.dart`
- `mobile/test/local/document_file_store_test.dart`
- `mobile/test/local/local_storage_test.dart`
- `mobile/tool/local_storage_probe.dart`
- `PHASE_3_1_LOCAL_STORAGE_FOUNDATION.md`

### Modified by Phase 3.1

- `mobile/pubspec.yaml` — added `drift`, `path_provider`, `crypto`, `uuid`, `path`;
  added `drift_dev` and `build_runner` as dev dependencies.
- `mobile/pubspec.lock` — resolved dependency graph.

No backend file, existing screen, controller, API client, model, or asset was changed.

### Protected data verified

| Item | Baseline | After Phase 3.1 |
|---|---|---|
| `data/lore.db` SHA-256 | `3223c49416484cd0226ba414dd5fe449eedbb2f2ec5e0ef9de1abef10d75b25e` | identical |
| `data/documents/1646d9ff-…pdf` | 601 bytes | 601 bytes, SHA-256 `4269be1ca668bde90badb1c177e34038e7489f64b174e4221024fb7d667b7d82` |
| File mtimes | 2026-11-02 | unchanged |

No server document was copied, moved, overwritten, or deleted. No automatic migration was
implemented or executed.

---

## 3. Technology and versions

| Component | Version / choice | Notes |
|---|---|---|
| Flutter | 3.41.4 stable | Dart 3.11.1 |
| Drift | 2.34.4 | Pinned; newer `drift_dev` requires an analyzer/meta version incompatible with this Flutter SDK |
| `drift_dev` | 2.34.0 | Code generation |
| `build_runner` | 2.15.1 | Code generation |
| `sqlite3` | 3.5.2 | Native asset build hook; bundles SQLite with FTS5 |
| `path_provider` | 2.1.6 | `getApplicationSupportDirectory()` |
| `crypto` | 3.0.8 | Streaming SHA-256 |
| `uuid` | 4.6.0 | UUID v4 document identifiers |
| `path` | 1.9.1 | Path normalization and containment |
| Android | API 36 emulator, `minSdk 24` | `x86_64` release validation |
| SQLite on device | 3.53.4 | Reported by the release probe |

`sqlite3_flutter_libs` was intentionally **not** added. It is end-of-life and `sqlite3`
3.x supplies the SQLite runtime through native assets. The Android release probe confirms
the bundled runtime has FTS5 compiled in.

---

## 4. Local schema v1

Database: `<app support>/lore_local/lore.sqlite`, `schemaVersion = 1`, WAL journal mode,
`PRAGMA foreign_keys = ON`, `PRAGMA synchronous = NORMAL`.

Timestamps are ISO-8601 UTC strings. Document identifiers are UUID v4 strings generated
outside the database. No user, invitation, pairing, session, ownership, or server account
table exists.

### 4.1 `categories`

| Column | Type | Constraints |
|---|---|---|
| `name` | TEXT | primary key |
| `sort_order` | INTEGER | unique, not null |

Seeded with the 11 canonical categories in order: Finance, Education, Health, Identity,
Home, Appliances, Insurance, Travel, Work, Legal, Uncategorized.

### 4.2 `documents`

| Column | Type | Constraints / default |
|---|---|---|
| `id` | TEXT | primary key |
| `original_filename` | TEXT | not null; sanitized display name |
| `stored_filename` | TEXT | not null, unique; storage reference |
| `media_type` | TEXT | not null |
| `size_bytes` | INTEGER | not null; `CHECK (size_bytes >= 0)` |
| `sha256` | TEXT | not null, unique; `CHECK (length(sha256) = 64)` |
| `extracted_text` | TEXT | default `''` |
| `extraction_status` | TEXT | default `pending`; one of `pending`, `processing`, `ready`, `failed`, `unsupported` |
| `extraction_error` | TEXT | nullable |
| `page_count` | INTEGER | nullable |
| `document_title` | TEXT | nullable |
| `category` | TEXT | nullable; FK `categories(name)` `ON DELETE SET NULL` |
| `tags_json` | TEXT | default `[]` |
| `tags_text` | TEXT | default `''`; searchable tag projection |
| `document_type` | TEXT | nullable |
| `issuer` | TEXT | nullable |
| `reference_number` | TEXT | nullable |
| `document_date` | TEXT | nullable |
| `classification_reasons_json` | TEXT | default `[]` |
| `classification_version` | TEXT | nullable |
| `is_deleted` | BOOLEAN | default false (soft delete) |
| `created_at` | TEXT | not null |
| `updated_at` | TEXT | not null |
| `deleted_at` | TEXT | nullable |

Indexes: category + deleted, created-at, deleted.

### 4.3 `document_relationships`

| Column | Type | Constraints |
|---|---|---|
| `id` | TEXT | primary key |
| `source_document_id` | TEXT | FK `documents(id)` `ON DELETE CASCADE` |
| `related_document_id` | TEXT | FK `documents(id)` `ON DELETE CASCADE` |
| `relationship_type` | TEXT | not null |
| `score` | REAL | `CHECK (score >= 0.0 AND score <= 1.0)` |
| `explanation` | TEXT | not null |
| `evidence_json` | TEXT | default `[]` |
| `calculated_at` | TEXT | not null |

Additional constraints: `CHECK (source_document_id < related_document_id)` enforces one
canonical direction per pair; `UNIQUE (source_document_id, related_document_id,
relationship_type)` prevents duplicates. This table exists as storage only; no
relationship computation is implemented in Phase 3.1.

### 4.4 `app_settings` and `schema_meta`

Simple `key`/`value` text tables. Seeded metadata:

- `schema_meta.local_schema_version = 1`
- `schema_meta.fts_tokenizer = unicode61 remove_diacritics 2`
- `schema_meta.fts_schema_version = 1`
- `app_settings.local_storage_phase = 3.1`

### 4.5 Migrations

Only schema v1 exists. `onCreate` creates tables, indexes, the FTS table, triggers, and
seed rows. No v0 or downgrade path is implemented. The schema-persistence test reopens an
existing v1 file and verifies schema version, categories, metadata, and documents survive
without re-creation. Future schema changes must add an explicit Drift `MigrationStrategy`
step and increment `schemaVersion`.

### 4.6 Ask conversation tables

Not created. The Phase 3.0 audit lists Ask history tables for the later Ask milestone, and
this storage milestone does not depend on them. They remain deferred until Phase 3.7.

---

## 5. App-private file layout

Root: `getApplicationSupportDirectory()/lore_local` on Android internal storage.

```
lore_local/
  lore.sqlite            database (plus -wal/-shm while open)
  documents/             published originals
    <uuid>.<ext>         e.g. 4f1c...e2.pdf
    <uuid>               when there is no safe extension
  imports/
    <uuid>.part          staged import in progress
  recovery/
    orphaned/
      orphan_<name>      moved unreferenced published files
    incomplete/
      incomplete_<name>  moved stale .part files
```

- The stored name is the document UUID plus a lower-cased extension of at most 10
  alphanumeric characters.
- The user-facing filename is stored only in the database and never used as a path.
- No shared storage, SAF, or storage permission is used.
- Path containment is checked with `path.isWithin` before every write, rename, and read.
- Stored names must be safe leaf names; `..`, separators, empty names, and control
  characters are rejected.
- Directory creation is idempotent.

The app-private location is under the OS app sandbox. Database and files are therefore
protected by the app UID boundary and Android file-based encryption; see section 9.

---

## 6. Import sequence

`DocumentImportCoordinator.importFile` performs:

1. Validate that a non-empty media type was supplied.
2. Generate a UUID v4 document identifier.
3. Stage the source:
   - ensure storage directories exist;
   - derive a sanitized display filename and a safe stored name;
   - fail if `<uuid>.part` already exists;
   - stream source bytes to the temp file while computing SHA-256, enforcing a 20 MiB
     default cap;
   - flush and close the file handle;
   - on any staging error, delete only the temp file created by this attempt.
4. Query `documents` by SHA-256.
5. If a duplicate exists: delete the staged temp file and throw
   `DuplicateDocumentException` containing the existing document.
6. Publish: validate the leaf name and containment, require the temp file, refuse to
   overwrite an existing published file, `rename` the temp file into `documents/`, then
   verify the published byte length matches the staged length.
7. Insert the document row with `extraction_status = pending`.
8. Return the document plus published file reference.

The source file is never moved or deleted. The publication step is atomic on one
filesystem. Filesystem and database writes are intentionally not a single transaction;
section 7 defines the retention behavior when they diverge.

---

## 7. Duplicates, failures, and recovery

### Duplicate policy

Content identity is SHA-256 of the exact stored bytes. A duplicate returns the existing
document and leaves the original published file untouched. Changing the filename or media
type does not bypass duplicate detection. No second file or row is created.

### Failure behavior

| Failure point | Result |
|---|---|
| Source unreadable / size cap exceeded | Temp file removed; no DB row |
| Staging write fails | Temp file removed; no DB row |
| Duplicate lookup fails | `ImportPersistenceException`; staged `.part` retained |
| Duplicate found | Staged `.part` removed; existing document reported |
| Publish collision / unsafe path | Staged `.part` retained; no DB row |
| Publish size mismatch | Published file retained; no DB row |
| Metadata insert fails | `ImportPersistenceException`; **published original retained** |

No code path automatically deletes a published user document because a database operation
failed. Published files are only moved during an explicit reconciliation call, and even
then they are quarantined rather than deleted.

### Reconciliation

`DocumentImportCoordinator.reconcile()`:

- reads referenced stored filenames including soft-deleted documents;
- moves unreferenced published files to `recovery/orphaned/orphan_<name>`;
- moves `.part` files older than a 24-hour grace period to
  `recovery/incomplete/incomplete_<name>`;
- leaves younger `.part` files in place as pending;
- reports referenced files that are missing without modifying their database rows;
- collects per-file errors and never deletes any file.

Reconciliation is explicit; it is not run automatically at startup in this phase.

---

## 8. FTS5 infrastructure

Virtual table `document_search`:

```sql
CREATE VIRTUAL TABLE document_search USING fts5(
  document_id UNINDEXED,
  extracted_text,
  original_filename,
  document_title,
  category,
  tags_text,
  document_type,
  issuer,
  reference_number,
  tokenize = 'unicode61 remove_diacritics 2'
);
```

The FTS `rowid` is aligned with `documents.rowid`, so triggers and joins are O(1) on the
identifier. The table stores a copy of the searchable text (it is not contentless), which
simplifies quoting and snippet generation at the cost of duplicated text on disk.

Triggers:

- `documents_search_ai` — insert after document insert when `is_deleted = 0`.
- `documents_search_au` — **single** update trigger: delete the old FTS row, then insert the
  new row when `is_deleted = 0`.
- `documents_search_ad` — delete the FTS row after document delete.

The update path deliberately uses one trigger. SQLite does not guarantee firing order
between separate triggers on the same event; an earlier two-trigger design inserted the
new row before the old row was deleted and failed with a primary-key constraint. Keeping
the delete and conditional insert in one trigger makes the ordering deterministic. This
was caught by the test suite and is covered by insert/update/soft-delete/hard-delete
tests.

`DriftLocalSearchRepository`:

- accepts a query of at most 256 characters and 12 terms;
- extracts Unicode letter/number terms and builds a quoted prefix AND expression;
- searches only `is_deleted = 0` documents;
- limits results to 1–100 (default 50);
- ranks with `bm25(document_search, 0.0, 2.5, 1.5, 0.8, 1.0, 1.2, 1.4, 2.5, 3.0)`
  in table column order;
- returns `snippet(document_search, 1, '[', ']', '…', 24)`;
- supports explicit index rebuild from active documents.

This is infrastructure only. No search screen or UI is wired to it.

---

## 9. Encryption decision

**No encrypted-database claim is made.** SQLCipher was evaluated and deferred.

- Database and originals live under app-private internal storage, protected by the Android
  app sandbox and OS file-based encryption.
- `sqlite3` 3.x can be pointed at SQLCipher through a build-hook user define, but Phase 3.1
  did not validate SQLCipher + FTS5 behavior, key derivation/escrow, migration of an
  existing plaintext database, key loss, or restore behavior.
- Introducing SQLCipher now would require a key lifecycle design and recovery policy that
  belongs with Phase 3.10 hardening.
- Android backup exclusion is also not yet configured; it is a Phase 3.10 item.

No plaintext database is described as encrypted anywhere in this implementation.

---

## 10. Interfaces and isolation from the server client

| Interface | Responsibility |
|---|---|
| `DocumentRepository` | insert, find by id/hash, list active, update extraction, soft/hard delete, counts, stored filenames |
| `LocalSearchRepository` | search, indexed count, index rebuild |
| `RelationshipRepository` | upsert, list around a document, count |
| `DocumentFileStore` | stage, publish, discard staging, resolve, list, reconcile |

Domain types in `local_models.dart` do not import Drift, HTTP, or server DTOs.
`LocalStorage.open()` is the composition root: it resolves app-private paths, opens the
database, constructs the Drift repositories and file store, and creates the import
coordinator. `LocalStorage.diagnostics()` reports database path, schema version, SQLite
version, FTS5 compile/table status, active document count, and indexed count.

None of these types is referenced by `LoreApiClient`, controllers, providers, or screens.
The app's existing behavior is unchanged.

---

## 11. Future server-to-local migration contract

No automatic migration is implemented or authorized in this phase. When migration is
scheduled, it must follow this contract:

1. **Read-only source.** Open the server SQLite database read-only and never modify,
   move, or delete `data/lore.db` or `data/documents/`.
2. **Manifest first.** Produce a manifest of every source document with its server ID,
   filename, size, SHA-256, category, extraction state, and metadata before copying.
3. **Per-document staging.** Copy each original through the same staged-write path used by
   local import: temp file, streaming SHA-256, flush, atomic publish, no overwrite.
4. **Integrity validation.** Recompute and compare size and SHA-256 after copy. Abort that
   document if they differ; never substitute the source file.
5. **Metadata mapping.** Preserve title, category, tags, document type, issuer, reference
   number, document date, extraction text/status, page count, and classification version.
   Map category names onto the 11 seeded local categories; unknown names become
   `Uncategorized` and are reported.
6. **Idempotency.** A retry must detect the same source document (source ID plus hash) and
   skip or reconcile it rather than creating duplicates. This may require a future schema
   migration for provenance columns; do not overload current fields.
7. **Reporting.** Emit per-document success/skip/failure with reasons plus aggregate count
   and hash totals. A dry run must be available.
8. **No destructive recovery.** Failed items leave the source untouched and either retain
   the staged file or quarantine it through reconciliation. No automatic deletion of
   source or destination documents.
9. **Post-migration verification.** Compare manifest counts and hashes with local rows and
   files, and report missing/unreferenced files through reconciliation.
10. **Server remains available.** The server path is not removed until Phase 3.9.

---

## 12. Tests

Test files: `mobile/test/local/local_database_test.dart`,
`mobile/test/local/document_file_store_test.dart`,
`mobile/test/local/local_storage_test.dart`.

Commands:

```bash
flutter analyze            # No issues found
flutter test               # 97 tests passed (34 new local-storage tests)
```

Required coverage and where it lives:

| Requirement | Test |
|---|---|
| Database initialization | schema version, seed categories/metadata, FTS table/trigger presence |
| Schema version | `schemaVersion == 1`, persisted in `schema_meta` |
| Schema migrations | v1 file reopen preserves data and metadata; future changes require explicit steps (documented) |
| Document metadata CRUD | insert, find by id/hash, list, update extraction, soft delete, hard delete |
| Foreign-key integrity | unknown category/endpoints rejected, cascade relationship delete, category `SET NULL` |
| File import | stage/publish, import metadata, source untouched |
| Original byte preservation | binary payload equality before/after publish and on resolve |
| SHA-256 correctness | streaming digest compared with `crypto` over source bytes |
| Duplicate detection | duplicate content rejected, existing ID returned, one file/row retained |
| Interrupted import | missing staged file throws, no document inserted, stale `.part` quarantined after grace |
| Missing file handling | `resolve` returns null; missing referenced file reported without row changes |
| Orphan-file reconciliation | orphan moved to recovery, referenced file kept, young `.part` pending, nothing deleted |
| FTS5 synchronization | insert/update/soft delete/hard delete, prefix match, snippet, rebuild, deleted rows excluded |
| Transaction rollback | failed relationship insert rolls back document and FTS rows |
| Additional safeguards | max size, unsafe IDs/paths, tampered staged names, no overwrite, filename sanitization, retained published/staged files on failures |

Windows execution note: this machine's Flutter SDK path contains a space, which breaks the
`pdfium_dart` native-asset hook compile when launched through the shell wrapper. The suite
was run with `flutter.bat` from a space-free junction to the SDK. That is a machine-local
tooling workaround; it does not change project files. It also means Windows tests alone do
not validate Android FTS5, which is why the device probe below exists.

---

## 13. Android release validation

Build and run:

```bash
flutter build apk --release -t tool/local_storage_probe.dart
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb shell am start -n com.lore.lore_mobile/.MainActivity
```

Environment: Pixel 6 emulator, Android 16 (API 36), `x86_64`, release APK signed with the
existing debug-key configuration. The probe is a separate entrypoint under `tool/`; it is
not part of the production app entrypoint and does not alter any screen.

On-device result captured from the probe report and logcat:

```
checks: 18 passed, 0 failed
PASS Android release uses SQLite with FTS5 compiled
  sqlite 3.53.4
PASS FTS5 virtual table exists after migration
PASS Schema version is 1
PASS Fresh database starts empty
PASS Imported file preserves original bytes
  (1024 bytes)
PASS Imported file SHA-256 matches source
PASS Duplicate content is rejected
PASS Duplicate leaves a single document
PASS FTS5 MATCH finds indexed extracted text
PASS FTS5 prefix search works in release mode
PASS FTS5 returns a highlighted snippet
  Quarterly insurance [premium] statement and policy QIP-4471.
PASS Soft delete removes the document from search
PASS Soft delete removes the FTS row
PASS Hard delete keeps the index consistent
PASS Failed transaction rolls back metadata and FTS rows
PASS Reconciliation quarantines orphaned files without deleting them
PASS Database and files survive an app-process reopen
PASS Reopened diagnostics remain healthy
```

This validates FTS5 in a release build on Android, not merely on Windows. Limitation:
validation used an `x86_64` emulator; a physical ARM device should be added before
release. `adb screenshots` returned black frames on this emulator, so the evidence is the
on-device report file and logcat, both quoted above.

Release APK permissions remain unchanged:

- `android.permission.INTERNET`
- `android.permission.USE_BIOMETRIC`
- `android.permission.USE_FINGERPRINT`
- generated `com.lore.lore_mobile.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`

No storage permission was added. The probe app run is not the final production build; the
normal app entrypoint still controls release packaging.

---

## 14. Limitations

- The local layer is not wired into the app; users cannot yet import or browse through UI.
- No extraction, OCR, classification, relationship computation, Ask, or local LLM.
- Ask history tables are deferred.
- No server-to-local migration and no automatic reconciliation at startup.
- Search is infrastructure-only and indexes copied text, increasing database size.
- Search query handling is deliberately simple (prefix AND terms, no operators).
- SQLCipher and Android backup exclusion are not implemented.
- Release signing still uses the pre-existing debug-key configuration.
- Android validation was on an `x86_64` emulator, not physical ARM hardware.
- Import defaults to a 20 MiB cap; larger files require an explicit policy decision.
- Filesystem and metadata writes are not a single atomic transaction; the failure table in
  section 7 defines the retention behavior instead.
- Relationship rows have no computation pipeline yet.
- No performance benchmark at 1,000+ documents was run in this phase.

---

## 15. Next milestone

**Phase 3.2 — Local import and file store integration** (not started).

Recommended scope, consistent with the audit:

- Connect `DocumentImportCoordinator` to a user-reachable import flow while keeping the
  existing server path intact.
- Add local list/open/delete read paths and their tests.
- Keep extraction, OCR, classification, relationship computation, Ask, and server removal
  out of scope.
- Validate picker MIME/size handling, atomicity under cancellation, and behavior when
  storage is nearly full.
- Keep all new work behind the local layer so the server-backed app remains functional.

## 16. Completion report

1. **Local schema v1 implemented:** documents, categories, relationships, extraction
   fields/status, timestamps, metadata, UUID IDs, storage references, size, SHA-256, and
   search index; no user/session/ownership tables.
2. **FTS5 implemented and synchronized:** aligned rowids, deterministic trigger ordering,
   insert/update/soft-delete/hard-delete sync, BM25 ranking, snippets, rebuild, and
   minimal search repository.
3. **App-private file store implemented:** UUID names, sanitized metadata, staged `.part`
   writes, flush and atomic rename, streaming SHA-256, size cap, no overwrite, and
   containment checks.
4. **Duplicate handling implemented:** content-hash detection, clear domain exception,
   staged-file cleanup, and no second row or file.
5. **Failure retention implemented:** published originals retained on database failure;
   staged files retained on lookup/publish failure; reconciliation quarantines without
   deleting.
6. **Interfaces isolated:** repositories and storage contracts are independent of
   `LoreApiClient`; no controller, provider, screen, or app composition change.
7. **Existing data preserved:** server DB hash and 601-byte PDF unchanged; no automatic
   migration; future migration contract documented with integrity validation.
8. **Tests:** 34 focused local tests added; full suite 97 tests passed;
   `flutter analyze` reports no issues.
9. **Android release validation:** 18/18 checks passed on a release APK on Android 16 with
   SQLite 3.53.4 and FTS5; evidence is on-device report and logcat.
10. **Encryption decision:** no SQLCipher; app-private storage plus OS file-based
    encryption; encrypted-storage claim explicitly not made; SQLCipher deferred to
    hardening.
11. **Phase boundaries respected:** no Phase 3.2 work, no UI rewiring, no server changes,
    no document deletion, no commit or push. Phase 3.2 remains unstarted.
