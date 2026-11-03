# LORE — Phase 2.0: Multi-User Architecture Audit & Migration Plan

**Project:** `D:\Dishanth-Project\Lore`
**Audit date:** 2026-11-02
**Baseline:** Phase 1.3 — Security Hardening (uncommitted working tree)
**Mode:** read-only architecture audit. No source file, schema, stored document, dependency, cloud resource, or Flutter screen was changed. The only file created by this phase is this report.

> **Honesty statement.** Everything described below as a design is a proposal. Nothing in the multi-user, invitation, PostgreSQL, storage-provider, or hosting sections is implemented. The implementation-status table in §1.5 separates what exists today from what is planned.

---

## 0. Task 0 — Verification of the current project

### 0.1 Git state

| Item | Observed value |
|---|---|
| Current branch | `main` |
| `main` commit | `4a16e95` — `feat: secure LORE with session auth, app lock, and original viewer` |
| Remote tracking | `origin/main` at the same commit |
| Other local branch | `lore-phase-4-checkpoint` at `01eb029` (also on origin) |
| Working tree | Dirty; Phase 1.3 changes are not committed |

Modified files:

```
 M .env.example
 M README.md
 M app/api/v1/auth.py
 M app/core/config.py
 M app/models/__init__.py
 M app/models/auth.py
 M app/services/auth.py
 M mobile/lib/state/auth_controller.dart
 M tests/test_api.py
```

Untracked files:

```
?? app/recovery.py
?? mobile/test/auth_controller_test.dart
```

Nothing was reset, cleaned, stashed, discarded, committed, or pushed. The dirty tree is preserved exactly as found.

### 0.2 What is and is not checkpointed

- **Phase 1.2 is checkpointed** in `4a16e95` and pushed: session authentication, pairing, Android app lock, secure token storage, and the original document viewer.
- **Phase 1.3 is not checkpointed.** The persisted pairing limiter, operator recovery CLI, Flutter session-lifecycle hardening, documentation, and the new tests exist only in the dirty working tree.
- A clean checkpoint is appropriate after owner approval, for example:
  `feat: harden pairing, recovery, and mobile session lifecycle`
  Do not commit or push it without explicit permission.

### 0.3 Test baseline

| Suite | Command | Result |
|---|---|---|
| Backend | `python -m pytest -q` | **82 passed** in 9.88 s |
| Flutter tests | `flutter test` | **63 passed** |
| Flutter analysis | `flutter analyze` | **No issues found** |

The Flutter test run required a temporary directory junction because the SDK path contains a space; the junction was removed immediately afterwards and no project file changed. The backend suite uses temporary SQLite databases and temporary data directories, so it did not alter the real data described below.

### 0.4 Current data and storage locations

Defaults come from `app/core/config.py:18-19` and `.env.example`:

| Data | Default location | Observed on disk |
|---|---|---|
| SQLite database | `data/lore.db` (`LORE_DATABASE_PATH`) | 98,304 bytes |
| Original files | `data/documents/` under `LORE_DATA_DIR` | 1 file, 601 bytes |
| Pairing code | `data/pairing-code.txt` | Present, 94 bytes |
| Environment overrides | `.env` (git-ignored) | Not inspected for secrets |

Read-only SQLite inspection (URI `mode=ro`) found:

- Tables: `auth_sessions`, `documents`, `document_relationships`, and the FTS5 virtual table plus its shadow tables.
- `documents`: **1 row** — `sample-doc.pdf`, 601 bytes, extraction `extracted`, processing `completed`, category `Uncategorized`, SHA-256 present.
- `document_relationships`: **0 rows**.
- `document_search`: **1 row**, consistent with the single document.
- `auth_sessions`: **2 rows**, both already revoked and expired on 2026-12-02.
- `pairing_attempts`: **table absent**. The on-disk database predates the Phase 1.3 model; startup would currently add the table through `Base.metadata.create_all`. This is direct evidence of the schema-management weakness discussed in §6.
- No `users`, `invitations`, or `user_settings` tables exist.

The original PDF is untouched. It is the only real document and must remain byte-identical through every future migration. Its SHA-256 value in `documents.sha256` is the file-integrity check to reuse during migration verification.

### 0.5 Constraints carried into Phase 2.1

1. Preserve the dirty working tree and the real document.
2. Do not rely on `pairing_attempts` existing in the real database until the backend has started once with the Phase 1.3 code.
3. Treat `data/lore.db` as production data even though it is small. Back it up before any future migration.
4. The current database has no original-file manifest beyond `storage_path` and `sha256`; the future migration must build one before moving anything.
5. The project has no migration framework. `Base.metadata.create_all` plus hand-written `ALTER TABLE` statements is the current mechanism.

---

## 1. Current architecture

### 1.1 Current architecture diagram

```
┌──────────────────────────────── Android phone ────────────────────────────────┐
│ Flutter app (Archival Precision UI)                                           │
│  AuthGate → LockScreen / PairingScreen / AppShell                             │
│  AuthController: device biometric → secure storage → bearer token             │
│  DocumentsController / AskController / AppState                               │
│  No local document database, no local extraction, no local search             │
└───────────────────────────────┬───────────────────────────────────────────────┘
                                │ HTTP (debug: 10.0.2.2), HTTPS only if a proxy
                                │ Bearer token (SHA-256 hash stored server-side)
┌───────────────────────────────▼───────────────────────────────────────────────┐
│ FastAPI process (single-user local backend)                                   │
│  /api/v1/auth/*        pairing + session lifecycle                            │
│  /api/v1/documents/*   upload, list, get, download, delete, classify, retry   │
│  /api/v1/search/*      FTS5 search + rebuild                                  │
│  /api/v1/relationships/* suggestions + rebuild                                │
│  /api/v1/categories    global counts                                          │
│  /api/v1/ask/*         extractive / local LLM / assisted approval workflow    │
│  /api/v1/system/status public health check                                    │
│  Middleware: upload body limit, no-store/nosniff on private paths              │
└───────────────┬───────────────────────────────┬───────────────────────────────┘
                │                               │
      ┌─────────▼─────────┐          ┌──────────▼──────────┐
      │ SQLite + FTS5     │          │ data/documents/      │
      │ auth_sessions     │          │ <uuid>.<ext>         │
      │ documents         │          │ originals, unchanged │
      │ relationships     │          └──────────────────────┘
      │ document_search   │
      └───────────────────┘
                │
      ┌─────────▼──────────────────────────────────────────┐
      │ Process-local state:                               │
      │  _ASSISTED_REQUESTS dict (no user identity)        │
      │  settings.ai_mode (mutable process-global setting) │
      │  pairing file on disk                              │
      └────────────────────────────────────────────────────┘
                │ optional, only when configured
      ┌─────────▼──────────────────┐   ┌────────────────────────────┐
      │ Local LLM endpoint         │   │ External AI provider       │
      │ default 127.0.0.1:11434    │   │ only after explicit consent│
      └────────────────────────────┘   └────────────────────────────┘
```

### 1.2 Component inventory

| Component | Key files | Current responsibility |
|---|---|---|
| App factory / lifespan | `app/main.py:23-96` | Create data dirs, engine, schema, auth manager, FTS5, middleware |
| Configuration | `app/core/config.py:7-50` | One global `Settings` object from `LORE_*` environment |
| Database session | `app/db/session.py:13-45` | SQLite engine, foreign keys on, no Postgres support |
| Schema management | `app/db/migrations.py:6-97`, `app/main.py:36-37` | Legacy `ALTER TABLE` upgrade plus `create_all`; no versioned migrations |
| FTS5 | `app/db/migrations.py:100-141`, `app/services/search.py` | One global `document_search` virtual table |
| Auth | `app/models/auth.py`, `app/services/auth.py`, `app/api/security.py` | One deployment-wide pairing session; bearer tokens hashed with SHA-256 |
| Documents | `app/models/document.py`, `app/services/documents.py` | One global document namespace, content-addressed duplicate check |
| Relationships | `app/models/relationship.py`, `app/services/relationships.py` | One global relationship graph |
| Categories | `app/services/organization.py` | Fixed vocabulary; global counts |
| Ask | `app/services/ask.py`, `app/api/v1/ask.py` | Global search/fallback evidence; process-global AI mode and consent state |
| System | `app/services/system.py`, `app/api/v1/system.py` | Public `SELECT 1` health check |
| Flutter auth/lock | `mobile/lib/state/auth_controller.dart`, `mobile/lib/screens/auth_gate.dart` | Pairing, biometric unlock, token lifecycle |
| Flutter data | `mobile/lib/data/api_client.dart`, controllers | All content comes from the backend; no local index |
| Android platform | `mobile/android/app/src/main/AndroidManifest.xml`, `MainActivity.kt` | Internet + biometric permissions, `FLAG_SECURE`, release cleartext blocked |

### 1.3 Current request lifecycle

1. The backend starts, runs `upgrade_legacy_document_table`, `create_all`, and creates a pairing code if no active session exists.
2. The phone pairs once by reading `data/pairing-code.txt`; the backend stores only the SHA-256 hash of the bearer token.
3. Every protected route receives `AuthSession` through `require_auth` (`app/api/security.py:20-31`).
4. The session proves “this deployment is authenticated,” not “this is user X.” Every query is therefore global.
5. The Flutter app unlocks locally with biometrics, installs the token only after local authentication, and clears in-memory state on lock/logout.
6. Documents are uploaded to the backend, extracted and indexed there, and downloaded through authenticated endpoints.

### 1.4 Security strengths to preserve

These existing controls are real and should not be weakened:

- 256-bit random bearer tokens; only SHA-256 hashes stored (`app/services/auth.py:191-200`).
- Pairing code is one-time, short-lived, atomically written, deleted on success.
- Persisted progressive pairing lockout with `Retry-After`; never permanent, capped, survives restart.
- Private responses carry `Cache-Control: no-store` and `X-Content-Type-Options: nosniff` (`app/api/middleware.py:90-127`).
- Upload body limit and per-file size limit; MIME/extension/content validation; UUID storage names.
- Storage path traversal rejection (`app/services/documents.py:174-182`) and an explicit download test.
- Deterministic local classification; no network access from classifier tests.
- Extractive answers by default; Assisted Mode requires explicit prepare/confirm approval and payload-hash validation.
- Flutter secure storage backed by Android Keystore; token not installed before device authentication; explicit 401 handling; `FLAG_SECURE` in `MainActivity.kt:10`.
- Existing tests for auth boundaries, path traversal, original download integrity, and log secrecy.

### 1.5 Implementation status (what is actually present)

| Capability | Status | Evidence |
|---|---|---|
| Single-user bearer auth | **Present** | `app/services/auth.py`, `app/api/security.py` |
| Pairing rate limiting and recovery | **Present (uncommitted)** | `app/services/auth.py:155-189`, `app/recovery.py` |
| Multi-user accounts | **Absent** | No `users` table or user identity on sessions |
| Invitation-only registration | **Absent** | No invitation model, service, or endpoint |
| Password authentication / Argon2id | **Absent** | No password field or hashing dependency |
| Per-user document isolation | **Absent** | No `user_id` on documents or queries |
| Per-user FTS isolation | **Absent** | `document_search` has no owner column |
| Per-user relationships | **Absent** | Relationships reference documents only |
| Per-user Ask / AI mode | **Absent** | Global settings and global evidence search |
| Assisted-request ownership | **Absent** | One process-global dictionary |
| PostgreSQL support | **Absent** | SQLite-only engine and FTS5 SQL |
| Cloud object storage | **Absent** | Local filesystem only |
| True on-device local mode | **Absent** | No local DB, extractor, index, or Ask engine in Flutter |
| Email sending / verification | **Absent** | No email provider |
| Admin roles / audit log | **Absent** | One deployment-wide session |
| HTTPS in the repository | **Not configured** | Documentation examples only; no active proxy |
| Encryption at rest by LORE | **Absent** | README already states this honestly |
| End-to-end encryption | **Absent** | No client-side key management |

---

## 2. Existing single-user assumptions

For each component: **current behavior**, **required multi-user behavior**, **migration risk**, **required tests**. File references are to the current code.

### 2.1 Authentication and sessions

**Current behavior**
- `AuthSession` has only `token_hash`, `created_at`, `expires_at`, `revoked_at` (`app/models/auth.py:9-20`). There is no user identity.
- `require_auth` returns the session object only (`app/api/security.py:20-31`).
- Pairing is deployment-wide: pairing is available only when zero active sessions exist (`app/services/auth.py:74-119`).
- `revoke_all` revokes every session on the deployment (`app/services/auth.py:143-153`).
- Session lifetime is a single global 720-hour (30-day) value (`app/core/config.py:43`).
- The mobile app stores exactly one token under one key (`mobile/lib/core/auth_store.dart:15-18`).

**Required multi-user behavior**
- `auth_sessions.user_id NOT NULL` referencing `users.id`.
- Login creates a session for one user; `require_auth` returns a `CurrentUser` or `AuthSession` with a loaded user.
- Pairing is removed from the normal account flow or isolated behind an explicit self-hosted mode flag.
- `revoke-all` becomes “revoke my sessions”; deployment-wide revocation becomes an admin/operator operation.
- Session metadata includes device label, last-used time, and user agent (display only).
- Session lifetime and idle timeout are configurable and enforced per session.

**Migration risk**
- Existing revoked sessions have no user; they cannot be meaningfully assigned. Safest: revoke and delete all pre-migration sessions, forcing one re-login after cutover.
- The existing pairing bootstrap logic counts all sessions; after users exist, it must not run in account mode.
- Any route that currently relies on `AuthSession` alone will start returning `401` or the wrong user if the dependency is changed midway. Change all routes atomically.

**Required tests**
- Token maps to exactly one user.
- User A’s token cannot authenticate as user B.
- Revoked, expired, disabled-user, and deleted-user sessions are rejected.
- Logout revokes only the current session; logout-all revokes only that user’s sessions.
- Session token is never logged; only its hash is stored.

### 2.2 Document ownership and storage

**Current behavior**
- `Document` has no `user_id` (`app/models/document.py:10-40`).
- `sha256` is **globally unique** (`app/models/document.py:21`), and upload rejects any duplicate hash regardless of who uploaded it (`app/services/documents.py:230-232`).
- `storage_path` is globally unique and must be a single filename (`app/models/document.py:20`, `app/services/documents.py:174-182`).
- `list_documents`, `get_document`, `delete_document`, and `retry_document_extraction` operate on the global table (`app/services/documents.py:288-385`).
- Every document route looks up by raw ID with no owner check (`app/api/v1/documents.py:152-307`).
- Original files live in one flat directory, `data/documents/<uuid>.<ext>`.

**Required multi-user behavior**
- `documents.user_id NOT NULL` with an index; every query filters by the authenticated user.
- Unique constraint becomes `(user_id, sha256)`, allowing two users to own the same content without a cross-account duplicate oracle.
- Storage keys become per-user, e.g. `users/<user_id>/documents/<document_id><ext>`.
- `get_document(db, user_id, document_id)` returns 404 for another user’s ID.
- Upload, list, metadata, download, delete, classify, retry, reclassify, and organization update all require the owner.
- A per-user storage quota becomes possible and is recommended before testers.

**Migration risk**
- Backfilling `user_id` is mandatory and must be `NOT NULL`.
- The flat storage path validator rejects nested paths today; per-user directories require a deliberate path rewrite that still rejects traversal.
- The global `sha256` unique index must be replaced carefully; a failed index swap can make existing rows unverifiable.
- Cross-tenant duplicate detection must not disclose the other user’s document ID.
- File moves are destructive if done in place; copy first, verify hashes, then switch.

**Required tests**
- Two users upload the same bytes: both succeed, each sees only their own row.
- User B cannot GET, download, PATCH, classify, retry, or DELETE user A’s document ID.
- Listing and category filters never include another user’s rows.
- Stored file path cannot escape the user’s directory.
- Original bytes and SHA-256 remain identical after upload/download.
- Duplicate upload within one account still returns that account’s document ID.

### 2.3 Full-text search and index

**Current behavior**
- `document_search` is a single FTS5 table with `document_id UNINDEXED` and content fields, but no owner (`app/db/migrations.py:100-141`).
- `search_documents` joins on `d.id = document_search.document_id` only (`app/services/search.py:204-240`).
- `rebuild_search_index` deletes the entire index and reindexes every document (`app/services/search.py:116-163`).
- `index_document` and `remove_document_index` key only on document ID (`app/services/search.py:75-114`).

**Required multi-user behavior**
- Every search query filters by the authenticated user, ideally in both the FTS relation and the joined `documents` row.
- `document_search` gains an owner column, or a per-user index strategy is chosen. A single table with `user_id UNINDEXED` plus mandatory `d.user_id = :user_id` is acceptable for the tester scale.
- Rebuild is either per-user (user-triggered) or admin-only (global). One user must not be able to delete or rebuild another user’s index.
- Search snippets must be generated only from the requesting user’s rows.
- Index repair at startup must not reveal counts across users to a user-facing endpoint.

**Migration risk**
- A missed predicate in the FTS query leaks content through snippets, even if the final document rows are later filtered.
- FTS5 has no row-level security; application scoping is the only SQLite control.
- PostgreSQL will replace FTS5 with `tsvector`/`tsquery`; ranking and prefix behavior will differ.
- Rebuilding the index while users are active can create temporary cross-user exposure if scoping is wrong.

**Required tests**
- User A’s query never returns user B’s document, snippet, filename, or metadata.
- Identical filenames/content across users produce only the requester’s hit.
- Category/type filters remain owner-scoped.
- Rebuild as user A affects only A’s index (or is rejected as admin-only).
- Snippet text is always a substring attributable to A’s document.
- Missing FTS table still returns the documented `503` without leaking data.

### 2.4 Related-document relationships

**Current behavior**
- `DocumentRelationship` has no owner and references two documents by ID (`app/models/relationship.py:18-52`).
- `recalculate_document_relationships` compares a document against **all** documents in the database (`app/services/relationships.py:250-295`).
- `rebuild_relationships` deletes every relationship and rebuilds across all documents (`app/services/relationships.py:298-336`).
- `get_relationship` returns any relationship by ID (`app/services/relationships.py:373-374`).
- `list_document_relationships` joins by document ID only (`app/services/relationships.py:339-370`).

**Required multi-user behavior**
- Relationships gain `user_id`, and both documents must belong to that user.
- Enforce with composite foreign keys `(user_id, source_document_id)` and `(user_id, related_document_id)` referencing `documents(user_id, id)`, plus `UNIQUE(user_id, id)` on documents. This makes a cross-user relationship impossible at the database layer.
- Candidate generation, rebuild, list, and get are all owner-scoped.
- Rebuild-all becomes admin-only or per-user.
- Stable relationship IDs should include the owner or be globally unique UUIDs; the existing SHA-256-derived ID is globally unique because document UUIDs are, but adding the owner to the input is clearer.

**Migration risk**
- Backfilling relationships requires choosing the owner; if legacy data ever contains a cross-user pair, the migration must reject or drop it rather than guess.
- The current `CHECK (source < related)` must coexist with the new owner constraints.
- Rebuild limits (`max_documents`) become per-user limits; otherwise one large account can block another.

**Required tests**
- Cross-user pair insertion fails at the database layer.
- User A’s related list never contains B’s document.
- Guessing a relationship ID from another user returns 404.
- Recalculate/rebuild only touches the requester’s graph.
- Deleting a document cascades only within the owner’s relationships.

### 2.5 Categories and organization

**Current behavior**
- Categories are a fixed vocabulary, not a user-owned table (`app/services/organization.py:11-23`).
- `count_documents_by_category` counts every document globally (`app/services/organization.py:274-282`).
- The categories endpoint returns global counts (`app/api/v1/categories.py:14-22`).
- Classification is deterministic and content-derived; no user data is involved.

**Required multi-user behavior**
- Keep the shared vocabulary for the MVP; scope every count to the authenticated user.
- Manual organization updates already operate on a fetched document; that fetch must be owner-scoped.
- If custom per-user categories are introduced later, add a `categories` table with `user_id`; do not overload the current string column without a migration.

**Migration risk**
- A global count endpoint is a low-severity metadata leak, but it still violates the isolation promise.
- Reclassification of raw IDs (`app/api/v1/documents.py:93-134`) is currently an IDOR; it must fetch within the owner scope and reject mixed ownership atomically.

**Required tests**
- Category counts equal only the requester’s documents.
- Mixed-owner reclassify request returns 404 and changes nothing.
- Manual category/tag update on another user’s document returns 404.
- Tags remain bounded and normalized as today.

### 2.6 Ask LORE and evidence retrieval

**Current behavior**
- `get_relevant_documents` uses global search and a global fallback list of latest documents (`app/services/ask.py:887-927`).
- `get_document` inside it is unscoped.
- `answer_question` and provider selection use global settings (`app/services/ask.py:930-999`).
- Extractive and local-LLM answers contain evidence snippets from whatever documents were retrieved.
- Ask conversations are session-only in Flutter and are cleared on lock/logout (`mobile/lib/state/ask_controller.dart:34-107`).

**Required multi-user behavior**
- All retrieval functions require `user_id`.
- Document-specific Ask must verify ownership before retrieval; another user’s document ID returns 404.
- Related-document expansion must remain within the owner because relationships are owner-constrained.
- Fallback “latest documents” must be the requester’s latest documents only.
- Evidence snippets and citations must never reference another user.
- Per-user AI mode and provider preference; server-level provider credentials remain admin-controlled.
- Ask cost/rate limits per user are recommended.

**Migration risk**
- This is the highest-risk leak surface because snippets are returned directly and can contain sensitive text even when the document ID is not shown.
- A single missing scope in either search or fallback leaks content silently.
- Local LLM prompts would include other users’ text if retrieval is not scoped; the consent UI would not catch it.

**Required tests**
- User A asks a question whose only match is B’s document: no evidence, no snippet, and no citation.
- Document-specific Ask on B’s ID returns 404.
- Fallback with an empty search returns only A’s recent documents.
- Related expansion cannot cross users.
- AI mode changes by A do not affect B.
- Assisted prepare/confirm by A cannot see or approve B’s excerpts.

### 2.7 Assisted Mode and approval workflow

**Current behavior**
- `_ASSISTED_REQUESTS` is one process-global dictionary (`app/services/ask.py:87`).
- Prepare stores question, excerpts, hash, expiry, and `approved` with no user (`app/services/ask.py:547-605`).
- Confirm/cancel/revoke operate by request ID only (`app/services/ask.py:608-666`).
- `revoke_assisted_requests` clears every pending request for the whole deployment (`app/services/ask.py:615-618`).
- `POST /ask/mode` mutates `settings.ai_mode` for the entire process (`app/api/v1/ask.py:78-100`).

**Required multi-user behavior**
- Every prepared request records `user_id`; confirm/cancel/revoke enforce ownership.
- `revoke-consent` revokes only the requester’s pending requests.
- Pending requests move to a database table (recommended) or remain in memory only under a documented single-worker constraint.
- AI mode becomes a per-user setting (`user_settings.ai_mode`), with a server-level policy that permits or forbids Assisted Mode.
- The external provider API key stays server-side; users never supply or see it in the MVP.
- Audit consent events without storing excerpt content in logs.

**Migration risk**
- In-memory state is lost on restart and is incompatible with multiple uvicorn workers.
- A global mode mutation lets one user change another user’s privacy posture.
- Request IDs are unguessable UUIDs, but ownership must still be enforced; never rely on ID secrecy.

**Required tests**
- User B cannot confirm, cancel, or revoke A’s prepared request.
- A’s revoke-consent leaves B’s requests intact.
- A’s mode change does not change B’s mode.
- Prepared request expiry is enforced per user.
- Excerpt tampering is still rejected by the payload hash.
- No excerpt text or API key appears in logs.

### 2.8 System status, configuration, and operations

**Current behavior**
- `GET /api/v1/system/status` is public and returns `{"status":"ok","database":"ok"}` (`app/api/router.py:19`, `app/services/system.py:7-9`).
- All configuration is process-global environment state (`app/core/config.py:7-50`).
- Operator recovery is a local CLI (`app/recovery.py`).
- Logs are JSON with timestamp, level, logger, message, and exception; no request/user correlation.
- There is no audit log, no per-user quota, no admin role, and no backup tooling.

**Required multi-user behavior**
- Keep the health endpoint minimal; consider requiring auth or returning only liveness in production.
- Separate deployment configuration (admin) from user preferences (per-user).
- Add audit records for admin actions: invitation created/revoked, user disabled/enabled, password reset, session revocation.
- Add request IDs and user IDs (not email addresses) to logs.
- Add quotas and rate limits for uploads, Ask, search rebuild, and login.
- Add backup/restore and monitoring procedures before inviting testers.

**Migration risk**
- Global settings that are currently mutated at runtime are easy to overlook; `ai_mode` is the known one.
- Admin actions without audit make abuse investigation impossible.
- Free-tier hosting has no managed backup guarantee; the operator must own this.

**Required tests**
- Admin endpoints reject non-admin users.
- Audit records exist for each admin action and contain no document content.
- Logs never contain tokens, passwords, invitation codes, document text, or snippets.
- Health endpoint reveals no user or document counts.
- Quota/rate-limit responses are explicit and do not leak other users’ data.

### 2.9 Flutter assumptions

**Current behavior**
- `AuthGate` has exactly four states: initializing, pairing required, locked, unlocked (`mobile/lib/screens/auth_gate.dart:62-71`).
- `AuthController` owns pairing and local biometric unlock; there is no login or registration.
- Secure storage uses global keys `lore.auth.session_token` and `lore.auth.auto_lock_seconds` (`mobile/lib/core/auth_store.dart:16-17`).
- `AppState` exposes a backend-global `aiMode` (`mobile/lib/state/app_state.dart:34-46`).
- `DocumentsController` caches up to 1,000 documents in memory and resets on session close.
- Ask conversations are memory-only and reset on session close.
- The pairing screen instructs the user to read a file on the backend (`mobile/lib/screens/lock_screen.dart:314-329`).

**Required multi-user behavior**
- Add welcome, invitation registration, login, account settings, recovery, and storage-mode selection states.
- Keep biometric unlock as a second, local gate after account authentication.
- Store the account identity and server origin alongside the token; never send a token to a different origin.
- Clear all user-scoped state on logout or account switch.
- Replace pairing UX for normal users; retain it only as an explicit self-hosted/developer path if the product needs it.
- Per-user AI mode and storage mode come from the backend, not process state.

**Migration risk**
- A token left installed during account switch can be sent with the next user’s request.
- Cached documents/conversations from the previous account can remain visible if reset is incomplete.
- The pairing screen’s text becomes misleading in a cloud multi-user deployment.
- Redesigning the whole app into a chat-style UI would violate the Archival Precision direction; add flows without replacing the shell.

**Required tests**
- No private screen mounts before authentication.
- Registration/login errors are shown without leaking account existence.
- Biometric unlock cannot install the token before device authentication.
- Logout/account switch clears documents, search, Ask, status, and secure storage.
- A 401 returns to login, not silently to cached content.
- Storage-mode selection is persisted and visible in Settings.

---

## 3. Proposed multi-user architecture

### 3.1 Proposed architecture diagram

```
┌──────────────────────────── Android phone ─────────────────────────────┐
│ Flutter app                                                            │
│  Welcome → Register (invite) / Login → Biometric unlock → AppShell     │
│  AuthController: account session + local biometric gate                │
│  Account-bound secure storage: token + user id + server origin         │
│  Per-user in-memory caches; cleared on logout/account switch           │
│  Optional future: on-device local database (not in this phase)         │
└───────────────────────────────┬────────────────────────────────────────┘
                                │ HTTPS only in release
                                │ Bearer token; opaque, hashed server-side
┌───────────────────────────────▼────────────────────────────────────────┐
│ Caddy / TLS reverse proxy                                              │
│  HSTS, request size limits, access logs without secrets                │
└───────────────────────────────┬────────────────────────────────────────┘
                                │ 127.0.0.1:8000
┌───────────────────────────────▼────────────────────────────────────────┐
│ FastAPI backend (accounts mode)                                        │
│  Public: /auth/register, /auth/login, /auth/password/reset, /health    │
│  User:   /auth/me, sessions, documents, search, relationships, ask     │
│  Admin:  /admin/invitations, /admin/users, /admin/audit                │
│  CurrentUser dependency → every service/query is owner-scoped           │
│  Rate limits: login, register, reset, ask, upload, rebuild              │
└───────┬───────────────────────┬───────────────────────┬────────────────┘
        │                       │                       │
┌───────▼────────┐   ┌──────────▼──────────┐   ┌────────▼───────────────┐
│ PostgreSQL     │   │ Storage provider    │   │ Optional AI providers  │
│ users          │   │ LocalFilesystem     │   │ Local LLM (server)     │
│ invitations    │   │  users/<id>/docs    │   │ External (consent)     │
│ sessions       │   │ CloudObjectStorage  │   │ Per-user mode setting  │
│ documents      │   │  private bucket     │   └────────────────────────┘
│ relationships  │   └─────────────────────┘
│ FTS tsvector   │
│ settings       │   ┌─────────────────────────────────────────────────┐
│ assisted reqs  │   │ Admin CLI: owner bootstrap, invitations, reset  │
│ audit log      │   │ Backups: encrypted pg_dump + document manifest  │
└────────────────┘   └─────────────────────────────────────────────────┘
```

### 3.2 Target data model (ERD)

```
users 1 ──── * auth_sessions
  │ 1
  ├──── 1 user_settings
  ├──── * invitations (created_by)
  ├──── * password_resets
  ├──── * documents (user_id) 1 ──── * document_relationships
  │                                  │
  │                                  └── both endpoints must share user_id
  ├──── * document_search (user_id)
  ├──── * assisted_requests (user_id)
  └──── * audit_log (actor_user_id)
```

Key constraints:

- `documents (user_id, sha256)` unique; `documents (user_id, id)` unique.
- `document_relationships.user_id` plus composite foreign keys to `documents(user_id, id)` for both endpoints.
- `document_search.user_id` plus mandatory owner predicate in every query.
- `auth_sessions.user_id` indexed; token hash remains the primary key.
- `invitations.token_hash` unique; plaintext token never stored.
- `users.email_normalized` unique.
- `user_settings.user_id` primary key.
- `assisted_requests.user_id` indexed; status and expiry indexed.

### 3.3 Target request flow

1. **Register:** invite token + email + password → validate invite → create user + settings → consume invite → create session (or require login).
2. **Login:** normalized email + password → Argon2id verify → create opaque session token → return token once.
3. **Every API call:** `Authorization: Bearer …` → hash token → load session + user → reject revoked/expired/disabled → pass `CurrentUser` to the route.
4. **Every data access:** service receives `user_id` from `CurrentUser`, never from the request body or query string.
5. **Every response:** only the current user’s rows; cross-user IDs return `404`, not `403`, to avoid confirming existence.
6. **Every mutating admin action:** `require_admin` plus an audit row.

### 3.4 What must not change

- Original uploaded files remain byte-identical and are never re-encoded.
- Extracted text remains server-side in cloud/backend mode and never leaves the chosen boundary.
- Private Mode never calls an external AI provider.
- Assisted Mode still requires explicit per-request approval.
- Archival Precision visual language, navigation shell, and document viewer remain.
- Existing single-user self-hosted behavior can be preserved behind a mode flag if desired.

---

## 4. Invitation-only authentication design

### 4.1 Principles

1. No public self-registration. An account exists only because an admin created an invitation.
2. Email is the login identity, normalized once and stored in a canonical form.
3. Passwords are hashed with Argon2id; plaintext never reaches the database, logs, or analytics.
4. Invitation tokens are random, single-use, time-limited, and stored only as hashes.
5. Error messages are deliberately generic where they could reveal account existence.
6. Every authentication event that matters is auditable without storing secrets or document content.
7. No real email is sent in Phase 2.0 or the first tester MVP; the admin delivers invitations out of band.

### 4.2 Account and invitation data model

| Table | Important columns | Notes |
|---|---|---|
| `users` | `id UUID PK`, `email_normalized UNIQUE`, `email_display`, `password_hash`, `role`, `status`, `email_verified_at`, `failed_login_count`, `locked_until`, `last_login_at`, `created_at`, `updated_at` | `role` in `owner/admin/user`; `status` in `active/disabled` |
| `invitations` | `id UUID PK`, `token_hash CHAR(64) UNIQUE`, `email_normalized`, `created_by`, `created_at`, `expires_at`, `used_at`, `used_by`, `revoked_at` | Email-bound; token hash only |
| `password_resets` | `id UUID PK`, `token_hash UNIQUE`, `user_id`, `created_by`, `expires_at`, `used_at`, `revoked_at` | Admin-assisted reset in MVP |
| `auth_sessions` | existing columns + `user_id`, `device_label`, `last_used_at` | `last_used_at` optional, updated at most once per minute |
| `user_settings` | `user_id PK`, `ai_mode`, `storage_mode`, `created_at`, `updated_at` | Per-user privacy posture |
| `audit_log` | `id`, `actor_user_id`, `action`, `target_type`, `target_id`, `created_at`, `metadata JSON` | No document text or secrets |

### 4.3 Invitation lifecycle

1. **Create (admin only).** Generate `secrets.token_urlsafe(32)` (~256 bits). Store only SHA-256. Bind to a normalized email. Expire after 7 days by default (configurable, e.g. 1 hour–30 days). Return the plaintext token exactly once in the response/CLI output.
2. **Deliver out of band.** The owner sends the code through a channel they already trust. No email provider in the MVP.
3. **Register.** Normalize the submitted email, compare it to the invitation’s bound email, verify the token hash, expiry, unused state, and admin revocation state.
4. **Consume atomically.** `UPDATE invitations SET used_at = now(), used_by = :user_id WHERE id = :id AND used_at IS NULL` must affect exactly one row. Two concurrent registrations with the same token: exactly one succeeds.
5. **Revoke (admin).** Set `revoked_at`; unused invitations become invalid immediately.
6. **Audit.** Record creation, revocation, successful use, and failed attempts (without the plaintext code).

Recommended MVP defaults:

| Setting | Value | Rationale |
|---|---|---|
| Invitation entropy | 32 random bytes | Brute force is infeasible |
| Invitation TTL | 7 days | Enough for a tester to act; short enough to limit exposure |
| Invitations per admin action | 1 code per email | Simple, auditable |
| Outstanding invitations | Configurable cap (e.g. 50) | Prevents accidental mass creation |
| Registration attempt limit | e.g. 10/hour/IP | Defense in depth; entropy is the primary control |

### 4.4 Registration

**Endpoint:** `POST /api/v1/auth/register`

```json
{
  "invitation_code": "…",
  "email": "tester@example.com",
  "password": "…",
  "device_label": "Pixel 6"
}
```

**Validation order (important for uniform behavior):**

1. Reject malformed request shape with a generic `422` that does not echo secrets.
2. Normalize email: trim, Unicode NFKC, lowercase, maximum 254 characters; validate syntax with a library (for implementation, `email-validator` with `check_deliverability=False` so no DNS/network call is made). Do not strip plus tags or apply Gmail dot folding.
3. Hash the invitation token and look it up. Invalid, expired, used, or revoked → generic `400 “The invitation is invalid or has expired.”`
4. Compare the normalized email to the invitation’s bound email. Mismatch → the same generic message; do not reveal the bound address.
5. Validate password: minimum 12 characters, maximum 128, no composition rules, no truncation. Reject only if it exceeds limits or contains no printable characters. Do not normalize passwords before hashing; hash the exact UTF-8 bytes.
6. Create the user in a transaction, consume the invitation conditionally, create default `user_settings`, and create the first session.
7. Return the same session shape as login. Do not return the password hash.

**Account existence behavior:** If a *valid* invitation is presented for an email that already has an account, return `409 “An account already exists for this invitation. Sign in instead.”` This reveals existence only to someone holding a valid invitation bound to that address, which is the legitimate owner or the admin who created it. For an invalid invitation, never reveal whether the email exists.

### 4.5 Login

**Endpoint:** `POST /api/v1/auth/login`

1. Normalize email identically to registration.
2. Look up the user. If absent, verify the password against a fixed dummy Argon2id hash so response time does not trivially reveal existence. Then return a generic error.
3. If the account is disabled, still run the dummy/real verification path and return the same generic error. Record an audit event.
4. Enforce per-account and per-IP rate limits before expensive verification where possible.
5. Verify Argon2id. On failure, increment counters and return `401 “Email or password is incorrect.”`
6. On success, reset counters, update `last_login_at`, create a session, and optionally rehash if Argon2 parameters changed.
7. Return the opaque token once. Do not return it in a cookie; the mobile client sends it as a bearer header.

**Rate-limit recommendation:** persist per-IP and per-account attempt counters. Example: 10 failures per 15 minutes → 15-minute lockout, doubling to a cap; successful login resets the account counter. Do not use a process-global singleton like the current pairing limiter; that design was correct for one deployment, not for many users.

### 4.6 Password hashing

- Algorithm: **Argon2id** via `argon2-cffi`.
- Initial parameters to benchmark on the target host: `memory_cost=64 MiB`, `time_cost=3`, `parallelism=4`, `hash_len=32`, `salt_len=16`. OWASP’s minimum is lower (19 MiB, t=2, p=1); choose the strongest settings that keep login latency acceptable on a 2 OCPU VM. Target roughly 100–500 ms.
- Store the full encoded string (`$argon2id$v=19$m=…,t=…,p=…$…`). Verify with the library; rehash on successful login when parameters or library defaults change.
- Never log the password, the hash, or the Argon2 parameters together with an email.
- No client-side password hashing in the MVP; TLS protects transport, and client-side hashing adds complexity without replacing server hashing.
- No password pepper initially. If a pepper is added later, document that rotating or losing it invalidates all passwords and design a rotation path.

### 4.7 Sessions

- Token: 32 random bytes (`secrets.token_urlsafe(32)`), returned once.
- Storage: SHA-256 hash only, exactly like the current session design.
- Lifetime: recommend 30 days absolute and 7 days idle for mobile convenience; both configurable. The current 30-day absolute value can be retained.
- Session fields: `user_id`, `device_label` (sanitized, display only), `created_at`, `last_used_at`, `expires_at`, `revoked_at`.
- On 401, the client clears the token and returns to login. On logout, revoke the current session. On “sign out everywhere,” revoke all of the user’s sessions.
- Password change revokes all other sessions and keeps the current one. Password reset revokes all sessions.
- Account disable revokes all sessions immediately.
- Cap concurrent sessions per user (e.g. 5) and show them in Account Settings. Do not silently evict without telling the user; either refuse the new login with a clear message or evict the oldest with an audit event.

### 4.8 Password change and recovery

**Change (authenticated):** require the current password, validate the new password, hash it, update `password_changed_at`, revoke all other sessions, keep the current session, audit the event.

**Recovery without email (MVP):** admin-assisted reset.

1. Admin runs a local CLI (`python -m app.admin reset-password --email …`) or calls an admin-only endpoint.
2. The backend creates a one-time reset code (same entropy/hash rules as invitations, 30-minute TTL) and returns it once to the admin.
3. The admin delivers it out of band.
4. `POST /auth/password/reset` accepts `reset_code` + `new_password`, consumes the code atomically, updates the hash, revokes all sessions, and audits the event.

**No public “forgot password” endpoint in the MVP.** A public endpoint that always says “if an account exists, an email was sent” is acceptable only once a real email provider exists; without email it creates a false promise.

**Future production:** email reset tokens hashed at rest, 30-minute TTL, single use, bound to user, constant response regardless of account existence, rate limited, revoke all sessions, notify the user by email (a second channel).

### 4.9 Account deactivation and deletion

- **Deactivation (admin, MVP):** set `status = 'disabled'`, revoke all sessions, keep documents and metadata. Login returns the generic failure. Reactivation is an admin action.
- **Self-service deletion (future):** explicit confirmation, re-authentication, a grace period, then purge documents, original files, extracted text, relationships, index rows, sessions, invitations, settings, and audit references. Document the retention policy before offering it.
- **Do not cascade-delete users by accident.** Use `ON DELETE RESTRICT` from documents to users and an explicit purge routine.

### 4.10 Enumeration and brute-force defenses

| Attack | Control |
|---|---|
| Invitation brute force | 256-bit codes; hashed lookup; generic invalid response; per-IP attempt limit |
| Account enumeration via registration | Generic invalid-invite response; existence revealed only with a valid email-bound invite |
| Account enumeration via login | Generic `401`; dummy Argon2 verification for unknown emails; uniform response body |
| Password guessing | Per-account/per-IP rate limit; temporary lockout; audit events |
| Credential stuffing | Rate limits, breach-list check at registration (future), optional MFA (future) |
| Timing leaks | Dummy hash verification; avoid early returns that skip expensive work for unknown users |
| Invitation sharing | Email-bound invitations; admin can revoke; audit use |
| Invite code in logs | Never log the plaintext; log only invitation ID and actor |
| Admin endpoint abuse | `require_admin`, audit log, separate route group, no document content endpoints |

### 4.11 Is email verification necessary for the first tester group?

**No, not for the invitation-only MVP**, provided:

- Every invitation is bound to a specific email address.
- The invitation is delivered out of band by the owner to a person they know.
- The admin confirms the tester’s identity and email before creating the invitation.
- Registration is closed to everyone without a valid invitation.

In this model, **the invitation is the verification**: possession of a code sent to a known address is stronger evidence of control than a self-asserted email. Set `email_verified_at` at registration with a note that verification method was `invitation`, or leave it null and document the distinction.

Residual risks: a mistyped invite email, a forwarded code, or a shared inbox. Mitigate with email binding, short expiry, and manual confirmation. **Add real email verification before any public signup**, along with an email provider, bounce handling, SPF/DKIM/DMARC, and a deliverability policy.

### 4.12 MVP vs future production

| Capability | First tester MVP | Production requirement |
|---|---|---|
| Invitation creation | Admin CLI | Admin UI + audit |
| Invitation delivery | Manual/out-of-band | Transactional email provider |
| Email verification | Invitation-as-verification | Dedicated verification token |
| Password hashing | Argon2id | Argon2id with reviewed parameters |
| Login | Email + password | Email + password; optional MFA |
| Sessions | Opaque bearer, 30d/7d | Same + device management |
| Password reset | Admin-assisted code | Self-service email reset |
| Account deactivation | Admin | Admin + user request workflow |
| Account deletion/export | Not offered | Implemented with retention policy |
| Abuse controls | Per-IP/per-account limits | Adaptive abuse detection |
| Audit | Admin actions | Broader security event retention |
| Email sending | None | Provider with SPF/DKIM/DMARC |

### 4.13 API sketch (design only)

**Public**

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/api/v1/auth/config` | Minimal deployment flags: registration open, assisted available |
| `POST` | `/api/v1/auth/register` | Invitation + email + password |
| `POST` | `/api/v1/auth/login` | Email + password |
| `POST` | `/api/v1/auth/password/reset` | Admin-issued reset code + new password |
| `GET` | `/api/v1/health` | Liveness only |

**Authenticated**

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/api/v1/auth/me` | Current user profile |
| `GET` | `/api/v1/auth/session` | Current session metadata (kept for compatibility) |
| `POST` | `/api/v1/auth/logout` | Revoke current session |
| `POST` | `/api/v1/auth/logout-all` | Revoke all of my sessions |
| `POST` | `/api/v1/auth/password/change` | Current + new password |
| `GET` | `/api/v1/auth/sessions` | List my sessions |
| `DELETE` | `/api/v1/auth/sessions/{id}` | Revoke one of my sessions |

**Admin only**

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/api/v1/admin/invitations` | Create email-bound invitation |
| `GET` | `/api/v1/admin/invitations` | List invitations (no plaintext codes) |
| `POST` | `/api/v1/admin/invitations/{id}/revoke` | Revoke |
| `GET` | `/api/v1/admin/users` | List account metadata |
| `POST` | `/api/v1/admin/users/{id}/disable` | Disable + revoke sessions |
| `POST` | `/api/v1/admin/users/{id}/enable` | Re-enable |
| `POST` | `/api/v1/admin/users/{id}/reset-password` | Issue one-time reset code |
| `POST` | `/api/v1/admin/users/{id}/revoke-sessions` | Revoke all sessions |
| `GET` | `/api/v1/admin/audit` | Audit events (no content) |

**Legacy/self-hosted only:** keep `POST /api/v1/auth/pair` behind an explicit flag such as `LORE_AUTH_MODE=accounts|pairing`. In accounts mode it should return `404` or `410`, not remain an alternate global backdoor.

### 4.14 Explicit non-goals for the first tester MVP

- No real email sending.
- No public signup.
- No OAuth/social login.
- No MFA (design for it, do not block on it).
- No per-document sharing or collaborative access.
- No admin browsing of user documents.
- No account deletion flow until the retention policy is written.
- No BYOK AI keys per user.

---

## 5. User isolation strategy

### 5.1 Enforcement layers

Authorization must be enforced at **all** of these layers. Flutter-side filtering is never authorization.

1. **Route dependency:** every protected route depends on `require_current_user`, which loads `session.user_id` and the user record, rejects disabled users, and returns a typed `CurrentUser`.
2. **Service signature:** every service function that touches user data takes `user_id` (or `CurrentUser`) as a required argument. Do not make it optional and do not default it.
3. **Query predicate:** every SELECT/UPDATE/DELETE includes `user_id = :current_user_id`. Centralize document access in an owner-scoped repository to reduce the chance of a missed predicate.
4. **Database constraint:** ownership columns are `NOT NULL`; composite foreign keys prevent cross-user relationships; unique constraints are per user.
5. **Response behavior:** another user’s ID returns `404` for documents, relationships, and assisted requests. A missing owner-scoped row and a nonexistent row are indistinguishable.
6. **PostgreSQL RLS (defense in depth):** after the PostgreSQL migration, enable row-level security on owner-scoped tables and set `app.user_id` per transaction. Treat RLS as a second layer, not a substitute for scoped queries. Document the pooling and admin-bypass caveats.
7. **Storage:** keys include the owner; the server generates keys; the client never supplies a path.
8. **Logs/audit:** user ID only, never email or content; never log tokens, codes, passwords, snippets, or filenames unless explicitly required and redacted.

### 5.2 Ownership matrix

| Data | Owner column | Constraint / query rule |
|---|---|---|
| Documents | `documents.user_id` | Indexed; all queries scoped; `(user_id, sha256)` unique |
| Original files | Path prefix `users/<user_id>/` | Server-generated; path validator rejects escape |
| Extracted text | Part of `documents` | Never returned by metadata APIs; scoped with document |
| Categories | Fixed vocabulary; counts scoped | No separate table in MVP |
| FTS index | `document_search.user_id` | Both FTS and joined document predicate |
| Relationships | `document_relationships.user_id` | Composite FKs to documents; both endpoints same owner |
| Ask evidence | Derived from scoped search/documents | No storage of conversations in backend |
| Assisted requests | `assisted_requests.user_id` | Confirm/cancel/revoke enforce owner |
| User settings / AI mode | `user_settings.user_id` PK | Never process-global |
| Sessions | `auth_sessions.user_id` | Token hash primary key; user indexed |
| Invitations | `invitations.created_by` + bound email | Admin-only creation; single-use |
| Audit log | `actor_user_id` | No content; admin read only |

### 5.3 Query rules

- Never accept `user_id` from the request body, query string, or header. It comes only from the authenticated session.
- Never call `db.get(Document, id)` directly in a route. Use `get_owned_document(db, user_id, id)`.
- Never run an unscoped `select(Document)` outside admin/maintenance code.
- Never let a client-provided list of IDs (reclassify) bypass ownership; fetch each ID with the owner predicate and reject the whole request if any ID is missing.
- Never return a `409` that includes another user’s document ID.
- Never run global rebuilds from a normal user route. Make them admin-only or per-user.
- Never let an empty search fall back to “all recent documents” without an owner predicate.
- Never trust relationship endpoints to infer ownership from the relationship ID alone.

### 5.4 Database constraints

Minimum target constraints:

```
users(email_normalized) UNIQUE
documents(user_id, id) UNIQUE
documents(user_id, sha256) UNIQUE
document_relationships(user_id, source_document_id, related_document_id, type) UNIQUE
document_relationships(user_id, source_document_id) REFERENCES documents(user_id, id)
document_relationships(user_id, related_document_id) REFERENCES documents(user_id, id)
CHECK (source_document_id < related_document_id)
document_search(document_id) UNIQUE; document_search.user_id NOT NULL
auth_sessions(user_id) NOT NULL + index
```

The composite foreign keys are the strongest guarantee: even a buggy service cannot insert a relationship that crosses users, because the parent row `(user_id, document_id)` must exist. PostgreSQL supports this directly. SQLite supports it when the parent columns have a unique index, and foreign keys are already enabled (`app/db/session.py:29-33`).

### 5.5 Storage isolation

- New layout: `LORE_DATA_DIR/users/<user_id>/documents/<document_id><ext>`.
- The current validator requires a single path component (`app/services/documents.py:174-182`); it must be replaced with a validator that accepts an expected relative subpath but rejects absolute paths, `..`, symlinks, and any resolved path outside `users/<user_id>/`.
- Store the relative key (without the root) in `documents.storage_path`; keep `(user_id, storage_path)` unique even if keys already contain the user ID.
- Use server-generated UUID filenames only. Never use the original filename for storage.
- Deletion must verify the path is inside the owner’s root before moving to a tombstone.
- Backups must preserve user directory boundaries and file hashes.

### 5.6 FTS isolation

For SQLite (interim):

- Add `user_id UNINDEXED` to `document_search`.
- Index and delete by `(user_id, document_id)`.
- Search SQL must include both `document_search.user_id = :user_id` and `d.user_id = :user_id`.
- Snippet generation must happen after the owner filter; never generate a snippet for a row that might belong to someone else.
- Rebuild is per-user or admin-only; if global, it must reindex with the correct owner for every row.
- Startup repair must not expose global counts to normal users.

For PostgreSQL:

- Prefer a `document_search` table with `user_id`, `document_id`, and a `tsvector` column plus a GIN index.
- Build the vector from weighted fields (filename, title, category, tags, type, issuer, reference, extracted text).
- Always filter by `user_id`; optionally include `user_id` in the index for partition pruning, but do not rely on it for authorization.
- RLS on the search table adds defense in depth.

### 5.7 Ask isolation

- Require `user_id` in `get_relevant_documents`, `answer_question`, `prepare_assisted_request`, and `confirm_assisted_request`.
- Scoped document lookup: another user’s document ID behaves as not found.
- Related expansion uses owner-constrained relationships.
- Fallback query is `WHERE user_id = :user_id ORDER BY uploaded_at DESC LIMIT …`.
- Evidence list is built only from scoped documents; add an assertion/test that every evidence ID belongs to the requester.
- Per-user rate limits for Ask to prevent one tester exhausting the shared backend.
- Per-user AI mode; server policy controls whether Assisted Mode is offered at all.

### 5.8 Assisted-request isolation

- Store `user_id` with every prepared request.
- Confirm/cancel/revoke check `request.user_id == current_user.id`; otherwise return 404.
- `revoke-consent` deletes only the current user’s pending requests.
- Prefer a database table so requests survive restart and work with multiple workers. If kept in memory, document that the deployment must run exactly one worker and that a restart discards pending approvals.
- Never include another user’s excerpt in the payload hash or the confirmation UI.
- Audit “prepared,” “approved,” “rejected,” “expired,” and “revoked” per user without storing excerpt text.

### 5.9 Per-user settings and AI configuration

- `user_settings.ai_mode`: `private` or `assisted`; default `private`.
- Server-level policy: whether Assisted Mode is enabled at all, and whether an external provider is configured.
- Per-user storage mode: `backend` or `cloud` (and future `local`), default according to deployment policy.
- Do not let users change process-wide settings. The current `POST /ask/mode` mutation must become a database write to `user_settings`.
- Provider credentials remain server-side environment secrets. If BYOK is added later, encrypt per-user keys at rest and never return them through the API.

### 5.10 Administrative separation

- `require_admin` checks `users.role in ('owner', 'admin')` and `status = 'active'`.
- Admin routes live under a separate router/prefix with their own audit events.
- Admin can manage accounts and invitations; **admin cannot browse user documents or extracted text** in the MVP. If operational support requires it later, make it an explicit, audited, break-glass action with user notification.
- Deployment-wide rebuilds/revocations are admin operations, not user operations.
- The operator still has filesystem/database access; document that plainly. Isolation is between users, not between a user and the machine operator.

### 5.11 Cross-user isolation test matrix

Every row must be tested with two real users (A and B), not mocks.

| Operation | User A (owner) | User B (attacker) | Expected for B |
|---|---|---|---|
| List documents | Sees A’s rows | Sees only B’s rows | No A rows |
| Get document by ID | 200 | 404 | No existence leak |
| Download original | 200, correct bytes | 404 | No file |
| Delete document | 204 | 404, A’s row remains | No deletion |
| Update organization | 200 | 404, unchanged | No mutation |
| Classify / retry extraction | 200 | 404 | No mutation |
| Reclassify mixed IDs | 200 for own | 404, nothing changed | Atomic rejection |
| Search | A’s hits only | B’s hits only | No A snippet |
| Search rebuild | Per-user or admin-only | 403/404 | No global impact |
| Category counts | A’s counts | B’s counts | No A counts |
| Related list | A’s relations | B’s relations | No A relation |
| Recalculate relationships | A’s graph only | B’s graph only | No A graph |
| Rebuild relationships | Admin-only or per-user | 403/404 | No global impact |
| Get relationship by ID | 200 | 404 | No leak |
| Ask global | A’s evidence only | B’s evidence only | No A snippet |
| Ask document | A’s document | 404 | No A content |
| Assisted prepare | A’s excerpts | B’s excerpts | No A excerpts |
| Assisted confirm/cancel | A’s request | 404 | No A request |
| Revoke consent | A’s requests only | B unaffected | No global clear |
| Set AI mode | A’s setting | B’s setting unchanged | Per-user |
| Logout | A’s session | B unaffected | Per-session |
| Logout all | A’s sessions | B unaffected | Per-user |
| Admin invite/user routes | Admin only | 403 | No admin access |
| Disabled account | — | 401 on all routes | Sessions revoked |

Additional checks:

- For every table with an owner column, `SELECT count(*) WHERE user_id IS NULL` is zero.
- For every relationship, both endpoint owners equal the relationship owner.
- For every FTS row, the owner matches the document owner.
- For every assisted request, the owner matches the session that created it.
- File paths resolve under the correct user root.
- Database constraint tests attempt cross-user inserts and expect failure.

---

## 6. SQLite → PostgreSQL migration

### 6.1 Findings that drive the decision

1. **No migration framework.** `Base.metadata.create_all` plus `upgrade_legacy_document_table` (`app/main.py:36-37`, `app/db/migrations.py:6-97`) is the whole mechanism. There is no `alembic.ini`, no `versions/` directory, and no schema version table.
2. **SQLite-specific SQL is pervasive.** FTS5 virtual tables, `bm25()`, `snippet()`, `instr()`, `PRAGMA table_info`, `PRAGMA foreign_keys`, and `ALTER TABLE … RENAME COLUMN` are SQLite-specific.
3. **FTS5 is a separate virtual table with shadow tables.** It cannot be copied to PostgreSQL directly; it must be rebuilt as `tsvector`.
4. **JSON columns** use SQLAlchemy `JSON`, which maps to SQLite text and can map to PostgreSQL `JSON`/`JSONB`.
5. **Datetimes** are stored as SQLite `DATETIME`; PostgreSQL should use `TIMESTAMPTZ`. Existing naive values need an explicit UTC interpretation.
6. **Global uniqueness assumptions**: `documents.sha256` and `documents.storage_path` are globally unique (`app/models/document.py:20-21`). Multi-user requires per-owner uniqueness.
7. **Data volume is tiny today**: one 601-byte PDF, one FTS row, zero relationships, zero active sessions. This makes a careful migration cheap now and much cheaper than after testers join.
8. **SQLite write concurrency** is limited. For a handful of testers it is probably sufficient, but PostgreSQL removes the single-writer bottleneck and provides stronger constraints/RLS.

### 6.2 Options

| Option | Advantages | Disadvantages | Verdict |
|---|---|---|---|
| **A. Continue SQLite with strict user scoping** | Smallest change; existing FTS5 code works; no new hosting; easy local backup | No row-level security; every query must be scoped manually; single-writer; migration deferred; FTS isolation is application-only; risk grows as testers join | Acceptable as a temporary development posture, not for the tester launch |
| **B. Migrate to PostgreSQL before opening registration** | Strong constraints, composite FKs, RLS defense in depth, proper concurrency, mature backup tooling, schema versioning with Alembic | Requires a DB migration, FTS rewrite, hosted Postgres, more operational work; some SQLite-specific behavior changes | **Recommended** |
| **C. Introduce PostgreSQL and preserve SQLite as a legacy migration source** | Keeps the old database available for rollback/reference; can dual-read during cutover | Dual-database operational complexity; risk of divergence; overkill for one document and a small tester group | Use only as a temporary cutover technique inside Option B, not as the steady-state architecture |

### 6.3 Recommendation

**Adopt Option B: migrate to PostgreSQL before any tester receives an invitation.**

Rationale:

- The most important Phase 2 requirement is isolation. PostgreSQL provides composite foreign keys and optional row-level security that SQLite cannot match.
- The current dataset is tiny, so the migration can be rehearsed repeatedly at negligible cost.
- Testers should not be the first people to exercise a new isolation model on a database with weaker constraints.
- The project will need Alembic regardless; introducing it now is cheaper than after multiple ad-hoc SQLite upgrades.
- SQLite can still be used for development and automated tests during Phases 2.1–2.3, but **registration must remain closed to testers until the PostgreSQL cutover is verified**. This is the practical interpretation of “migrate before opening registration.”

Do **not** run production testers on SQLite “for now” and plan to migrate later; that postpones the highest-risk work until after real people’s data is in the system.

### 6.4 Target PostgreSQL schema

Use UUID primary keys (native `uuid`), `TIMESTAMPTZ`, `JSONB` for tags/reasons/evidence/metadata, and `TEXT` for extracted text. Key tables:

```sql
users (
  id uuid primary key,
  email_normalized varchar(254) not null unique,
  email_display varchar(254) not null,
  password_hash varchar(255) not null,
  role varchar(20) not null default 'user',
  status varchar(20) not null default 'active',
  email_verified_at timestamptz,
  failed_login_count integer not null default 0,
  locked_until timestamptz,
  last_login_at timestamptz,
  created_at timestamptz not null,
  updated_at timestamptz not null
);

auth_sessions (
  token_hash char(64) primary key,
  user_id uuid not null references users(id) on delete cascade,
  device_label varchar(120),
  created_at timestamptz not null,
  last_used_at timestamptz,
  expires_at timestamptz not null,
  revoked_at timestamptz
);

documents (
  id uuid primary key,
  user_id uuid not null references users(id) on delete restrict,
  ... existing columns ...,
  unique (user_id, id),
  unique (user_id, sha256)
);

document_relationships (
  id uuid primary key,
  user_id uuid not null,
  source_document_id uuid not null,
  related_document_id uuid not null,
  ...,
  foreign key (user_id, source_document_id) references documents(user_id, id) on delete cascade,
  foreign key (user_id, related_document_id) references documents(user_id, id) on delete cascade,
  unique (user_id, source_document_id, related_document_id, relationship_type),
  check (source_document_id < related_document_id)
);

document_search (
  document_id uuid primary key references documents(id) on delete cascade,
  user_id uuid not null,
  search_vector tsvector not null
);
create index document_search_vector_idx on document_search using gin(search_vector);
create index document_search_user_idx on document_search(user_id);

invitations (... token_hash unique, email_normalized, created_by, expires_at, used_at, revoked_at);
password_resets (... token_hash unique, user_id, expires_at, used_at, revoked_at);
user_settings (user_id uuid primary key references users(id), ai_mode, storage_mode, ...);
assisted_requests (id uuid primary key, user_id uuid not null, ..., expires_at, status);
audit_log (id bigserial primary key, actor_user_id uuid, action, target_type, target_id, created_at, metadata jsonb);
```

### 6.5 Full-text search migration

**Choice: PostgreSQL `tsvector` with the `simple` configuration**, because the current FTS5 configuration is `unicode61 remove_diacritics 2` with prefix matching and no stemming. `simple` preserves tokens without English stemming, which is closer to current behavior. Evaluate `english` later if stemming improves results; document the change because it alters search results.

Design:

- Add a `tsvector` column or a generated column combining weighted fields:
  `setweight(to_tsvector('simple', filename), 'A') || setweight(to_tsvector('simple', title), 'A') || … || setweight(to_tsvector('simple', extracted_text), 'D')`.
- Use a GIN index.
- Build queries with `websearch_to_tsquery` or a parameterized prefix query. Do not concatenate user input into SQL. The current code already tokenizes and quotes terms; preserve that safety approach and adapt it to `tsquery`.
- Replace `bm25()` with `ts_rank_cd` and explicit weights.
- Replace `snippet()` with `ts_headline` using the same owner-scoped row.
- Replace `instr()` exact-ranking boosts with `position()` or a computed rank expression, still parameterized.
- Always filter `user_id`.
- Rebuild per user or admin-only. Do not copy FTS shadow tables; regenerate from `documents`.
- Keep the `503` behavior when FTS is unavailable, but in PostgreSQL the more likely failure is a missing extension/config or a bad migration; return a clear, non-leaking error.

### 6.6 Migration procedure (design only; not executed)

**Phase A — Preparation**

1. Announce maintenance; stop writes. Do not run this while testers are active.
2. Back up:
   - `data/lore.db` (file copy),
   - the entire `data/documents/` directory,
   - a manifest of every file: relative path, size, SHA-256,
   - `.env`/deployment configuration (without printing secrets),
   - a `pg_dump` of any existing PostgreSQL target.
3. Run the full backend suite and record the 82-test baseline.
4. Create a migration ledger table or JSON file recording the source database hash, start time, row counts, and operator.
5. Verify the source database opens read-only and every document file exists.

**Phase B — Create the owner account**

1. Create the owner user with a verified email and a strong password using the admin CLI.
2. Record the owner UUID; it is the backfill value for all legacy documents.
3. Do not reuse a pairing token as a user credential.

**Phase C — Create the target schema**

1. Apply Alembic migrations to an empty PostgreSQL database.
2. Confirm constraints and indexes exist.
3. Do not insert data until the schema is verified.

**Phase D — Copy relational data**

1. Copy users/invitations only if they already exist; otherwise just the owner.
2. Copy documents with `user_id = owner_id`, preserving IDs, filenames, media types, sizes, SHA-256, extracted text, statuses, category, classification fields, title, date, type, issuer, reference, tags, and `uploaded_at`.
3. Copy relationships only if both endpoint documents exist and both will belong to the owner; otherwise abort and report.
4. Create `user_settings` for the owner.
5. Do **not** copy FTS shadow tables; rebuild the index in PostgreSQL.
6. Do **not** copy revoked/expired auth sessions. Delete them from the source only after verification, or leave them in the read-only source. Force a fresh login.

**Phase E — Copy original files**

1. Copy, do not move, each original to `users/<owner_id>/documents/<document_id><ext>`.
2. Verify SHA-256 after copy.
3. Keep the source files unchanged for the rollback window.
4. Do not re-encode PDFs or images.

**Phase F — Rebuild search and relationships**

1. Rebuild `document_search` from the migrated documents, owner-scoped.
2. Rebuild relationships with the new constraints; verify no cross-user pairs.
3. Compare counts and sample results with the SQLite baseline.

**Phase G — Cut over**

1. Point the backend at PostgreSQL via configuration; keep the SQLite file untouched.
2. Run migrations, start the app, and run read-only smoke checks.
3. Run the isolation test suite against PostgreSQL.
4. Only then enable registration and invite the first testers.

### 6.7 Verification checklist

| Check | Expected |
|---|---|
| Row counts | `documents`, `document_relationships`, `users`, `user_settings` match the source (except intentionally dropped sessions/FTS) |
| Per-user counts | Owner’s document count equals source; every other user has zero legacy documents |
| File hashes | Every `documents.sha256` equals the copied file’s SHA-256 |
| File paths | Every path resolves under the owner’s root; no absolute paths, `..`, or symlink escapes |
| Original filenames | Unchanged |
| Extracted text | Byte-identical character count and spot-checked content |
| Categories/tags | Unchanged per document |
| Relationships | All endpoints exist and share the owner; count matches or is explained |
| Search | Known queries return the same owner-scoped document IDs (ranking may differ) |
| Auth | No old session works; owner login works; revoked/expired tokens fail |
| Isolation | Full cross-user matrix passes |
| Downloads | Sample downloads byte-match the source |
| Logs | No tokens, passwords, codes, text, or snippets |
| Rollback | Old SQLite app starts against the untouched source after config revert |

### 6.8 Rollback design

**Triggers:** failed row-count/hash verification, cross-user leak in tests, migration script error, unacceptable search regression, or Postgres instability during the window.

**Steps:**

1. Stop the PostgreSQL-backed app.
2. Revert configuration to the SQLite database and original storage root.
3. Restore the SQLite file from the pre-migration copy if it was touched at all (it should not be).
4. Confirm original files were copied, not moved; if any were moved, restore from backup.
5. Start the old backend version and run the 82-test suite plus a smoke test.
6. Keep the PostgreSQL database and copied files for diagnosis; do not delete them until the rollback is declared complete.
7. Record the failure, the verification output, and the corrective action.

**Rollback-friendly choices:**

- Copy files instead of moving them.
- Keep stable document IDs.
- Do not delete the SQLite database for at least 30 days after a successful cutover.
- Keep the old application image/commit available.
- Use a configuration switch, not code edits, to choose the database.

### 6.9 Migration risks and unknowns

- **FTS behavior change:** ranking, snippets, diacritics, prefix matching, and tokenization will not be identical. Accept ranking differences; require document-set parity for known queries.
- **Timezone interpretation:** existing naive datetimes must be treated as UTC consistently. Verify one known `uploaded_at` value.
- **JSON semantics:** SQLite JSON text versus PostgreSQL `JSONB` ordering/normalization; compare parsed values, not raw text.
- **Constraint timing:** adding `NOT NULL user_id` to a table with rows requires a backfill. Do it in one transaction or a staged migration with a temporary default, then drop the default.
- **Alembic baseline:** autogenerate can miss FTS/composite constraints; write the baseline and constraints explicitly and review them.
- **Downtime:** with one document, downtime is seconds; with testers, schedule a window and announce it.
- **Hosting:** PostgreSQL must be reachable only from the backend; do not expose port 5432 publicly.
- **Unknown:** whether the chosen free host will provide stable capacity; verify before inviting testers.

---

## 7. Local and cloud storage architecture

### 7.1 Definitions and the privacy promise

Two modes are requested. They have very different implications:

| Mode | Original files | Extracted text / index | Ask processing | Current backend fit |
|---|---|---|---|---|
| **Backend-hosted (current)** | Server disk | Server | Server | Works today |
| **Private Cloud Mode** | Private object storage | Server | Server | Requires provider abstraction |
| **Private Local Mode (true)** | Android device only | Must also be device-only if content never leaves | Must be device-only or explicitly approved | **Does not exist**; requires a local data layer |

The critical distinction: “local storage” is not just where the original file sits. If the backend receives the file, extracts text, indexes it, and answers questions from it, the content has left the device. A privacy promise that says otherwise would be false.

### 7.2 Common storage-provider interface (design)

```python
class StorageProvider(Protocol):
    def put(self, *, user_id: str, document_id: str, extension: str,
            content: bytes, content_type: str) -> StoredObject: ...
    def open(self, *, user_id: str, storage_key: str) -> BinaryIO: ...
    def delete(self, *, user_id: str, storage_key: str) -> None: ...
    def exists(self, *, user_id: str, storage_key: str) -> bool: ...
    def stat(self, *, user_id: str, storage_key: str) -> StoredObjectInfo: ...
    def presign_download(self, *, user_id: str, storage_key: str,
                         ttl_seconds: int) -> str | None: ...
```

Rules:

- The provider returns a server-generated storage key. The client never supplies a key.
- The key always contains the owner: `users/<user_id>/documents/<document_id><ext>`.
- The provider never trusts a client path; the backend validates and canonicalizes.
- `put` should be atomic from the caller’s perspective: write a temporary object/file, verify size/hash, then promote.
- `delete` must be idempotent and owner-scoped.
- Presigned URLs, if supported, must be short-lived (e.g. 60–300 seconds), single-object, and never logged.
- The interface should support streaming so large PDFs are not fully buffered in memory twice.

Implementations:

- `LocalFilesystemStorageProvider` — the current disk layout, moved under per-user roots.
- `CloudObjectStorageProvider` — S3-compatible API (Cloudflare R2), private bucket, server-side encryption, no public access.
- Future `DeviceStorageProvider` — not a backend provider; it lives in Flutter and changes the whole processing boundary.

### 7.3 Private Cloud Mode

**Storage layout:** private bucket, keys `users/<user_id>/documents/<document_id><ext>`.

**Access:**

- The bucket has no public access and no public custom domain.
- Downloads either stream through the authenticated backend or use a very short-lived presigned GET created only after the backend authorizes the owner.
- Uploads either stream through the authenticated backend or use a short-lived presigned PUT with content-length/type constraints; the backend then verifies the object’s SHA-256 before committing metadata.
- Storage credentials stay in the backend environment/secret store. Never ship them to Flutter, never return them through the API, never log them.
- Server-side encryption is enabled (R2 encrypts at rest). TLS protects transit. This is not end-to-end encryption; the backend can read the content.
- Object lifecycle: delete the object when the document is deleted; use versioning only if the retention policy requires it; prevent orphaned objects with a reconciliation job.

**Implications for current processing:**

- Extraction, FTS, relationships, and Ask continue to run server-side, unchanged in principle.
- `storage_path` becomes a storage key, not a filesystem path; `get_document_file` becomes `storage.open`.
- The backend must support both streaming responses and `FileResponse`-style outputs.
- Upload validation currently reads the whole file into memory; with cloud storage, validate first, then put, and avoid keeping a second full copy.
- Backups must cover both PostgreSQL and the bucket (or rely on bucket durability plus an independent copy).

### 7.4 Private Local Mode (true device-only)

**What it would require:**

- A local database on Android (SQLite + FTS5 via `sqflite`/`drift`, or an encrypted store).
- On-device PDF text extraction (a Flutter/native plugin) and optionally OCR.
- On-device classification, relationship rules, and search indexing.
- On-device Ask: extractive locally, and/or an on-device LLM. The current app has neither and the current backend cannot run on the phone.
- Local file storage and deletion, plus backups/export under the user’s control.
- A clear boundary: when local mode is active, document bytes must not be sent to the backend at all. The backend can still handle account authentication and optional encrypted sync metadata, but not content.

**What the current code does instead:**

- Every upload goes to `POST /api/v1/documents`; the backend extracts and indexes.
- Every search and Ask call goes to the backend.
- Flutter has no local DB, extractor, index, or classifier (`mobile/pubspec.yaml` shows viewer/file picker/auth dependencies only).
- The viewer downloads originals from the backend.

**Honest conclusion:** true Local Mode is a separate product and engineering track, not a configuration flag. It would duplicate a meaningful part of the backend on the device. It should be explicitly deferred until the product owner decides whether “local” means “on my phone” or “on my own server.”

**Recommended interim interpretation:** offer **Backend-hosted** and **Private Cloud** modes to testers, and label the current self-hosted backend as “your own server” rather than “on-device.” Do not claim device-only privacy until the local data layer exists and is tested.

### 7.5 Switching storage modes without losing documents

Design a state machine per document:

```
backend ──copy──▶ cloud ──verify hash──▶ switch pointer ──grace period──▶ delete source
cloud   ──copy──▶ backend ──verify hash──▶ switch pointer ──grace period──▶ delete source
any     ──▶ local (future): download to device, verify hash, index locally,
                              switch pointer, delete remote after confirmation
```

Rules:

- Copy first; never move the only copy.
- Verify SHA-256 and size before switching.
- Switch the document’s `storage_mode`/`storage_key` in one transaction.
- Keep the source for a grace period (e.g. 7 days) so the user can recover from a failed switch.
- Show per-document and bulk progress; failures leave the document in its original mode.
- Never re-encode the original.
- A mode switch is a user action; it must not silently upload content in local mode. In local mode, “switch to cloud” is an explicit upload consent.
- Backups must know which mode each document is in.

### 7.6 Implications for extraction, FTS, and Ask

| Mode | Extraction | FTS | Ask |
|---|---|---|---|
| Backend-hosted | Server | Server FTS5/tsvector | Server |
| Private Cloud | Server, after authenticated upload | Server | Server |
| True Local | Device | Device | Device |
| Hybrid (original local, text server) | Server if text is sent | Server | Server; privacy claim must say text leaves the device |

The last row is the trap: keeping only the original file on the device while sending extracted text to the server does **not** satisfy “document content never leaves the device.” If the product wants that promise, extraction and indexing must be local.

### 7.7 Recommendation

1. **Phase 2.6a:** implement the provider interface and cloud provider; migrate the current backend-hosted storage to per-user paths. This is a real, testable improvement and fits the tester launch.
2. **Phase 2.6b:** run a time-boxed spike for true on-device local mode. Estimate the Flutter extraction/index/Ask work before committing. If the product requires device-only privacy, schedule it as its own phase with its own threat model.
3. **Do not** present a storage-mode switch in the UI before both modes exist and data migration is tested. A disabled “Local (coming soon)” option is more honest than a mode that silently uploads.

### 7.8 Storage risks

- Presigned URL leakage through logs, screenshots, or copied links.
- Bucket misconfiguration (public access, missing encryption, permissive CORS).
- Orphaned objects after failed metadata commits.
- Path traversal in the local provider.
- Disk exhaustion on the free VM.
- Backup exposure (unencrypted dumps).
- False privacy claims in local mode.
- Data loss during mode switching; copy-and-verify is mandatory.

---

## 8. Hosting and infrastructure evaluation (zero-budget MVP)

### 8.1 Recommended MVP topology

```
Internet
  │  HTTPS 443
  ▼
Caddy on Oracle Cloud Always Free A1 VM (2 OCPU / 12 GB documented as of this audit)
  │  reverse_proxy 127.0.0.1:8000
  ▼
uvicorn (FastAPI), non-root, systemd, one worker initially
  ├── PostgreSQL 16/17 on localhost:5432 (not exposed)
  ├── /var/lib/lore/documents (encrypted block volume; per-user dirs)
  ├── optional Cloudflare R2 private bucket (originals or backups)
  └── optional external AI provider (admin-configured; consent required)
        ▲
        │ outbound only
Admin ──┘  SSH key-only, admin CLI for owner/invites
Backups: encrypted pg_dump + document archive → R2 / second volume / offline
Monitoring: external uptime check + disk/memory alerts + journald logs
```

Why this shape:

- One VM keeps cost at zero and avoids managed-database free-tier pausing.
- Caddy provides automatic TLS with minimal configuration.
- PostgreSQL on the same host is acceptable for a handful of testers; keep it off the public network.
- R2 is optional at first; the 200 GB block volume is likely enough for a small tester group. R2 is valuable for offsite backups and egress-free downloads, but its free tier is only 10 GB.

### 8.2 Free-tier facts and caveats (verify at signup; providers change limits)

**Oracle Cloud Always Free (as documented at the time of this audit):**

- Ampere A1: first **1,500 OCPU-hours and 9,000 GB-hours per month**, equivalent to **2 OCPU / 12 GB** (older material says 4 OCPU / 24 GB; Oracle reduced this in 2026). One 2/12 instance or two 1/6 instances.
- AMD micro: up to **2 × VM.Standard.E2.1.Micro**, 1/8 OCPU, 1 GB RAM each.
- Block volume: **200 GB total** boot + block, with **5 volume backups**.
- Outbound data transfer: **10 TB/month**.
- Object/Archive storage: up to **20 GB total** (Always Free Only), **50,000 API requests/month**.
- **Home-region requirement** for free compute/block volumes.
- **Idle reclamation:** Oracle may reclaim instances if CPU, network, and memory are all below the 20th percentile over 7 days. This is a real risk for a low-traffic tester backend.
- No SLA for Always Free; capacity availability varies by region and shape.

**Cloudflare R2 free tier:**

- **10 GB-month** storage.
- **1 million Class A** operations/month.
- **10 million Class B** operations/month.
- **Egress free** (no egress charges).
- Beyond the free tier: storage ~$0.015/GB-month and Class A ~$4.50/million (verify current pricing).

**Managed PostgreSQL free tiers:**

- Neon: free plan around 1 GB storage and 100 CU-hours per project, with auto-suspend; good for prototyping, not guaranteed for a always-on tester service.
- Supabase: free plan around 500 MB database and 5 GB egress; pauses on inactivity.
- These are convenient but introduce another provider, data-residency questions, and pausing behavior. For a privacy-first single-tenant tester backend, self-hosted PostgreSQL on the Oracle VM is simpler to reason about.

**Genuinely free vs usage-limited:**

| Service | Genuinely free within limits? | Main limitation / risk |
|---|---|---|
| Oracle A1 2 OCPU/12 GB | Yes, within Always Free | Capacity, idle reclamation, region, no SLA |
| Oracle AMD micro | Yes | 1 GB RAM, weak CPU; not enough for Postgres + app comfortably |
| Oracle 200 GB block | Yes | Home region; 5 backups |
| Oracle 10 TB egress | Yes | Subject to fair use/account terms |
| Oracle 20 GB object storage | Yes | 50k requests/month; deletion warning if trial expires |
| Cloudflare R2 | Yes, ≤10 GB and ops limits | Ops overage and storage overage cost money |
| Let's Encrypt via Caddy | Yes | Rate limits; domain required |
| Domain name | **No** | ~$10–15/year |
| Email provider | Not used in MVP | Future cost |
| Managed Postgres free tier | Yes with limits | Pausing, storage caps, another vendor |
| Local LLM on free VM | Not reliable | CPU/RAM; model quality; not guaranteed |
| OCR on free VM | Possible but CPU-heavy | Tesseract latency; disable by default |

### 8.3 Cost summary for the MVP

| Item | Expected monthly cost |
|---|---|
| Oracle Always Free compute/storage/egress | $0 within limits |
| Domain name | ~$1/month amortized (annual purchase) |
| TLS (Let's Encrypt) | $0 |
| Cloudflare R2 (≤10 GB, within ops) | $0 |
| Email provider | $0 (manual invitations) |
| Monitoring (free tier) | $0 |
| **Total** | **~$1/month + domain**, assuming limits hold |

Hidden costs/risks: overage charges if R2 limits are exceeded; Oracle account termination or reclamation; time spent on operations; backup storage; a second region for disaster recovery (not free); email provider once verification is added.

### 8.4 Resource constraints

- **CPU:** 2 OCPU is enough for FastAPI + PostgreSQL + Caddy + PyMuPDF for a handful of users. PDF extraction is bursty; a 20 MB PDF can consume significant CPU and memory.
- **Memory:** 12 GB is comfortable for the app and Postgres. Do not run a local LLM (Ollama 7B) on this VM and expect good latency; keep Private Mode extractive by default.
- **Disk:** 200 GB shared with the OS, Postgres, WAL, backups, and originals. Monitor usage; set a per-user quota.
- **Single worker:** start with one uvicorn worker. In-memory assisted requests and rate-limit counters require it; after moving them to PostgreSQL, you can scale workers.
- **OCR:** disabled by default. If enabled, cap image pixels and concurrent jobs; Tesseract can saturate the CPU.
- **Uploads:** keep the 20 MiB limit; consider 10 MiB for testers. Enforce at the proxy and the app.
- **Backups:** a full document copy doubles disk usage; stage backups off-box (R2/offline) and prune.

### 8.5 Backup and recovery

- **PostgreSQL:** nightly `pg_dump -Fc` plus WAL archiving if feasible; encrypt before upload (`age`/GPG); retain 7 daily, 4 weekly, 3 monthly; test restore quarterly.
- **Documents:** nightly incremental archive of `users/` with a manifest of paths + SHA-256; encrypt; upload to R2 if within 10 GB, otherwise a second block volume or offline disk.
- **Configuration:** back up `.env`/systemd/Caddy config securely; never commit secrets.
- **Restore drill:** restore Postgres and a sample of files into a staging directory; verify hashes and run the isolation suite.
- **RPO/RTO for testers:** state them explicitly. A reasonable MVP target is RPO 24 hours, RTO 4 hours, but only if the restore drill passes.
- **Do not rely on Oracle volume backups alone**; keep an off-provider copy.

### 8.6 Monitoring

- External uptime check on `https://…/api/v1/health` every 5 minutes.
- Disk usage alert at 80%; memory alert; PostgreSQL connection count.
- `systemd` restart policy and `journald` log rotation.
- Log aggregation is optional; if used, ensure no document content, tokens, or emails are shipped.
- Error tracking (Sentry free tier) is optional and must be configured to scrub secrets and content.
- A simple admin status page is enough for a tester group; do not build a full observability stack.

### 8.7 Security hardening for the VM

- SSH key-only; disable password login; firewall only 22, 80, 443.
- Run the app as a non-root user; PostgreSQL local socket/loopback only.
- Caddy obtains and renews TLS; enable HSTS after confirming HTTPS.
- Keep the OS and Python dependencies patched; use a lockfile and a vulnerability scan.
- Do not expose `/docs` publicly in production if it reveals internals; gate it or disable it.
- Rate-limit at Caddy and in the app.
- Encrypt the block volume (OCI encrypts at rest by default; verify) and use full-disk encryption where possible.
- Separate admin access from the app; audit admin actions.
- Keep the pairing code path disabled in accounts mode.

### 8.8 Deployment configuration notes

- Release Android builds block cleartext HTTP (`mobile/android/app/src/debug/AndroidManifest.xml` only enables it); the production base URL must be `https://…` via `--dart-define=LORE_API_BASE_URL=…`.
- The default `http://10.0.2.2:8000` must not ship in a release profile.
- Caddy config example:

```caddyfile
lore.example.com {
    encode zstd gzip
    request_body {
        max_size 25MB
    }
    reverse_proxy 127.0.0.1:8000
}
```

- Keep uvicorn bound to `127.0.0.1`; only Caddy listens publicly.
- Set `LORE_DATABASE_URL` (new in Phase 2.4) and remove the SQLite-only assumptions.
- Set `LORE_AUTH_MODE=accounts`; disable pairing.
- Set `LORE_TRUSTED_PROXY`/forwarded-header handling carefully so rate limits see the real client IP through Caddy.

### 8.9 What is not guaranteed

- Free-tier limits can change (Oracle already halved the A1 allowance in 2026).
- Free compute can be reclaimed when idle; a low-traffic tester backend may qualify.
- Capacity may be unavailable in the chosen region.
- There is no SLA, no managed backup guarantee, and no support.
- R2 free operations can be exhausted by aggressive sync/retry loops.
- A domain and email provider are not free.
- Do not make this the only copy of any tester’s documents.

---

## 9. Flutter migration design

### 9.1 Current flow

```
App start
  → AuthGate.initialize()
  → secure storage has token? no → PairingScreen → pair → biometric unlock
                                  yes → LockScreen → biometric → validate /auth/session
  → AppShell (Home, Documents, Ask, Settings)
  → lock/logout → clear token from API client + in-memory state
```

Relevant code: `mobile/lib/screens/auth_gate.dart:62-71`, `mobile/lib/state/auth_controller.dart:63-140`, `mobile/lib/state/auth_controller.dart:191-237`, `mobile/lib/app.dart:43-58`.

### 9.2 Proposed auth state machine

```
initializing
   ├─ no stored account → welcome
   │     ├─ "I have an invitation" → register
   │     └─ "I already have an account" → login
   ├─ stored account, session valid → locked
   │     ├─ biometric success → unlocked
   │     └─ biometric unavailable → locked with honest explanation
   └─ stored account, 401 → login (clear token)

unlocked
   ├─ logout → welcome
   ├─ account disabled/401 → login
   └─ app background timeout → locked
```

States to add: `welcome`, `registering`, `loggingIn`, `accountRecovery`, `storageModeSelection`. Keep `locked` and `unlocked` as they are. Do not mount `AppShell` until `unlocked`.

### 9.3 Screens and flows (Archival Precision preserved)

| Screen | Purpose | Design notes |
|---|---|---|
| Welcome | Brand entry | “LORE” wordmark, short privacy statement, two actions: “Enter with invitation” and “Sign in”. No marketing chatbot. |
| Invitation registration | Code + email + password | Reuse `_SectionLabel`, `_SettingsCard`, `TextField` styling; show invite code as a secret; explain that the account is private. |
| Login | Email + password | Generic error text; “Use a recovery code” link (admin-assisted) rather than a fake email reset. |
| Biometric unlock | Existing `LockScreen` | Keep as-is; it is the second gate after account auth. |
| Account settings | Email, password change, sessions, deactivate request | Add a section to existing Settings; reuse `_InfoRow`/`_ActionRow`. |
| Recovery | Enter admin-issued reset code + new password | No fake “email sent” flow without an email provider. |
| Storage mode | Choose backend/cloud (local marked unavailable) | Explain what leaves the device; show current mode and migration progress. |
| Logout | Existing confirmation | Update copy: “Sign out of this account” rather than “forget this device” if the device can switch accounts. |

Preserve:

- The warm paper palette, serif display typography, thin rules, section labels, and archival card treatment (`mobile/lib/core/theme.dart`).
- The four-tab shell and document viewer.
- The distinction between Private and Assisted modes in Settings.
- Honest empty/offline/error states.

Avoid:

- A generic chat-app shell.
- Removing the archival document detail/viewer structure.
- Hiding privacy boundaries behind vague labels.

### 9.4 Controller and API changes

**`AuthController`**

- Replace pairing-first initialization with account-first initialization.
- Add `register(...)`, `login(...)`, `logoutAll()`, `changePassword(...)`, `resetPassword(...)`, `loadProfile()`.
- Keep `unlock()`/`lock()` biometric logic; the token is still installed only after device authentication.
- Keep `handleUnauthorized()`; on 401, clear the token, clear user-scoped state, and go to `login` (not `pairingRequired`).
- Store the account ID and server origin alongside the token so a token cannot be sent to a different backend.
- On logout/account switch, call `onSessionClosed` to clear documents, Ask, navigation, and AppState.

**`AuthStore`**

- Keep secure storage; add `accountId` and `serverOrigin` keys.
- Consider key names scoped by server: `lore.auth.<origin>.session_token`. If the base URL changes, never send the old token.
- For the MVP, one account per install; account switching clears all local state. Document this.

**`LoreApiClient`**

- Add unauthenticated `register`, `login`, `request`-free reset confirm, `getMe`.
- Keep bearer headers and the existing 401 hook.
- Add rate-limit (`429`) handling with `Retry-After` messaging.
- Do not send the token on register/login/pairing.
- Add `GET /auth/sessions` and session revocation if Account Settings shows devices.

**`AppState`**

- Load `aiMode` from `GET /auth/me` or a user settings endpoint, not a global process setting.
- Clear user settings on logout.
- Do not let one user’s mode change affect another.

**`DocumentsController` / `AskController`**

- Keep in-memory caches per session; `reset()`/`clearAllConversations()` must run on logout and account switch.
- Do not persist conversations to disk in the MVP without an explicit privacy decision.
- If local mode is ever added, these controllers need a second data source; do not pretend the backend is always present.

### 9.5 Flutter tests to add

- Welcome → register with a valid invite → biometric unlock → shell.
- Invalid/expired/used invite → generic error, no account created.
- Login success/failure; generic failure text; 429 handling.
- Stored token + biometric failure → remains locked; token not installed.
- Stored token + 401 → login, cached documents cleared.
- Logout → welcome; documents/Ask/AppState cleared.
- Account switch → no previous account data or token remains.
- Password change → other sessions invalidated, current session behavior as designed.
- Admin-assisted reset → new password works, old sessions rejected.
- Storage mode selection persists and is shown in Settings.
- Pairing remains available only in the explicit self-hosted mode (if retained).

### 9.6 Pairing in a multi-user world

Options:

| Option | Description | Recommendation |
|---|---|---|
| Remove pairing | Delete the pairing screen and endpoint | Cleanest for a cloud multi-user product, but breaks the current self-hosted workflow |
| Keep pairing as a hidden legacy mode | `LORE_AUTH_MODE=pairing` for self-hosted use; accounts mode hides it | **Recommended** |
| Show pairing alongside login | Confusing and creates a global backdoor | Do not do this |

In accounts mode, `POST /auth/pair` should be disabled. The Android biometric lock remains regardless.

### 9.7 Storage-mode UX without data loss

- Show the choice after registration, not before account creation.
- Explain in plain language:
  - “Your own server” — documents and text stay on the LORE backend you operate.
  - “Private cloud” — original files are stored in private object storage; the backend can read and index them.
  - “On this device (not available yet)” — do not offer until implemented.
- Show a per-document mode badge in document details.
- Switching shows copy progress, verifies hashes, and only then deletes the source after a grace period.
- If a switch fails, leave the document in its original mode and show the reason.
- Never silently change mode during an upload or login.

### 9.8 What not to change

- Do not redesign the app into a chatbot.
- Do not remove the original document viewer or replace originals with extracted text.
- Do not weaken `FLAG_SECURE` or the local biometric gate.
- Do not put backend storage credentials in Flutter.
- Do not add a public “forgot password” screen that claims to send email before an email provider exists.

---

## 10. Security threat model

### 10.1 Assets and trust boundaries

**Assets**

- Original documents and their content.
- Extracted text, snippets, titles, filenames, categories, tags, relationships.
- Account credentials, password hashes, session tokens, invitation/reset codes.
- AI provider credentials.
- Audit logs and backup archives.
- The integrity and availability of the service.

**Trust boundaries**

1. Android app ↔ network ↔ Caddy ↔ FastAPI.
2. FastAPI ↔ PostgreSQL.
3. FastAPI ↔ document storage (local disk or object storage).
4. FastAPI ↔ optional AI providers.
5. Admin/operator ↔ host and database.
6. User A ↔ user B (the boundary this phase must create).
7. Backup storage ↔ production.

### 10.2 Threat table

| # | Threat | Example | Impact | Mitigation | Residual risk |
|---|---|---|---|---|---|
| 1 | IDOR on documents | B guesses A’s UUID | Full document read/delete | Owner-scoped service queries; 404; composite constraints; tests | A bug in a new route can still leak; centralize |
| 2 | Search snippet leak | FTS returns A’s text in B’s results | Content disclosure | Owner predicate in FTS and join; per-user rebuild; tests | SQLite has no RLS; rely on application scoping |
| 3 | Relationship leak | B reads A’s related docs | Metadata/content disclosure | `user_id` + composite FKs; owner-scoped endpoints | Migration must validate legacy pairs |
| 4 | Ask evidence leak | B’s question retrieves A’s docs | Content disclosure to B and possibly external AI | Scoped retrieval/fallback; evidence assertions; per-user consent | Missed scope in a new provider path |
| 5 | Assisted request hijack | B confirms A’s request ID | A’s excerpts sent externally | `user_id` on requests; owner check; DB-backed state | In-memory state lost on restart |
| 6 | Global AI mode change | B switches everyone to Assisted | Privacy posture change | Per-user `user_settings.ai_mode` | Admin policy misconfiguration |
| 7 | Global revoke-all | B logs out every user | Availability | Per-user revoke; admin-only global | Admin abuse |
| 8 | Duplicate-hash oracle | B learns A uploaded a file | Existence/metadata leak | Per-user `(user_id, sha256)` unique; no cross-user 409 | Within-account duplicates still reveal |
| 9 | Invitation brute force | Attacker guesses codes | Account creation | 256-bit codes; hashed lookup; rate limit; generic errors | Log/DB compromise could expose hashes but not codes |
| 10 | Account enumeration | Login/register timing or messages | Privacy/abuse | Generic errors; dummy Argon2; per-IP/account limits | Coarse timing differences possible |
| 11 | Credential stuffing | Reused passwords | Account takeover | Rate limits; min length; future breach-list/MFA | Users reuse passwords |
| 12 | Stolen device | Thief opens app | Document access | Biometric gate; Keystore token; remote revoke; `FLAG_SECURE` | Compromised OS or known PIN |
| 13 | Token leakage | Token in logs/backup | Account takeover | Never log tokens; hash only; TLS; encrypted backups | Operator error |
| 14 | Public bucket / presigned URL | Cloud object publicly readable | Content disclosure | Private bucket; short TTL; no logs; access audit | URL sharing within TTL |
| 15 | Path traversal | Crafted storage path | Read/write outside user root | Server-generated keys; resolve + prefix check; tests | Symlink edge cases |
| 16 | Malicious document | Parser exploit / zip bomb | RCE/DoS | Upload validation; size/page/pixel limits; non-root; sandboxed worker; dependency updates | Parser 0-day |
| 17 | DoS via Ask/rebuild/upload | One user exhausts CPU/disk | Service outage | Per-user rate limits/quotas; admin-only global rebuild | Free-tier capacity |
| 18 | Backup exposure | Unencrypted dump in R2 | Mass disclosure | Client-side encryption; access control; retention | Key management |
| 19 | Operator access | Admin reads DB/files | Privacy violation | Document honestly; least privilege; audit; no admin UI for content | Operator is trusted by design |
| 20 | False local-mode claim | App says “local” but uploads text | Broken privacy promise | Do not ship local mode until on-device pipeline exists; explicit labels | Product pressure |
| 21 | Cross-account cache | Previous user’s docs remain after switch | Disclosure | Clear controllers/secure storage on logout; one account per install | Process kill/restore edge cases |
| 22 | Session fixation | Attacker supplies a token | Takeover | Server-generated random tokens; rotate on login; revoke on password change | — |
| 23 | Unauthorized admin | Normal user calls `/admin` | Account/data control | `require_admin`; tests; separate router | Role assignment error |
| 24 | Email existence via valid invite | 409 reveals account | Minor enumeration | Only after valid email-bound invite; audit | Invite holder learns existence |
| 25 | Log/audit content leak | Snippets or filenames in logs | Disclosure | Log IDs only; scrub; tests | Debug logs left on |

### 10.3 Residual risks to state plainly

- User isolation is only as strong as every query predicate and the database constraints. PostgreSQL RLS reduces, but does not eliminate, application bugs.
- The backend operator can read documents and extracted text. There is no end-to-end encryption. If the threat model includes the operator, LORE is not sufficient without client-side encryption, which conflicts with server-side search/Ask.
- Free-tier hosting has no SLA; availability and data durability are the operator’s responsibility.
- Android biometrics protect the local UI, not the network API. A stolen token is still a valid bearer credential until revoked/expired.
- `FLAG_SECURE` prevents screenshots/recent-apps preview but not a compromised OS or a camera.
- Email verification is deferred for testers; invitation-as-verification is a conscious risk acceptance.
- Search ranking/snippet behavior will change after PostgreSQL; content isolation must not depend on ranking.

### 10.4 Security requirements checklist for implementation

- [ ] Every protected route returns a typed current user.
- [ ] Every data query has an owner predicate.
- [ ] Composite FKs prevent cross-user relationships.
- [ ] Per-user unique constraints for hashes and storage keys.
- [ ] Cross-user requests return 404.
- [ ] Per-user FTS rows and rebuilds.
- [ ] Per-user Ask retrieval and assisted requests.
- [ ] Per-user AI mode and storage mode.
- [ ] Argon2id with reviewed parameters.
- [ ] Invitation/reset codes hashed, single-use, expiring.
- [ ] Generic auth errors and rate limits.
- [ ] Tokens/codes/passwords never logged.
- [ ] TLS mandatory in release; no cleartext.
- [ ] Private bucket/presigned URL rules.
- [ ] Encrypted backups with restore drill.
- [ ] Admin routes separated and audited.
- [ ] No false local/cloud privacy claims.

---

## 11. Ordered implementation roadmap

### 11.1 Ordering rationale

1. Identity primitives first, because everything else needs a user.
2. Ownership and authorization second, because it is the core privacy requirement.
3. Isolation tests third, as a gate before any tester sees the system.
4. PostgreSQL fourth, before registration opens, for stronger constraints and RLS.
5. Flutter account flows fifth, against a backend that already enforces isolation.
6. Storage providers sixth, because they depend on ownership and a stable data model.
7. Deployment and onboarding last, after the above gates pass.

Do not invite testers after Phase 2.2 and before Phase 2.4. The database migration should happen while the only user is the owner.

### 11.2 Phase 2.1 — Account and invitation backend

**Objective:** Create users, invitations, password hashing, owner bootstrap, and admin-assisted reset primitives **without opening registration or changing document access**.

**Files likely to change/new**

- `app/models/user.py`, `app/models/invitation.py`, `app/models/password_reset.py`, `app/models/audit.py`
- `app/services/passwords.py`, `app/services/accounts.py`, `app/services/invitations.py`
- `app/schemas/account.py`, `app/api/v1/accounts.py`, `app/api/v1/admin.py`
- `app/api/router.py`, `app/models/__init__.py`, `app/core/config.py`
- `app/cli/admin.py` or `app/admin.py` (owner/invite/reset CLI)
- Database schema creation path (Alembic baseline preferred; otherwise a reviewed migration)
- `tests/test_accounts.py`, `tests/test_invitations.py`, `tests/test_passwords.py`

**Dependencies:** Phase 1.3 checkpoint; Argon2id dependency approval (not installed during this audit).

**Risks:** Argon2 cost/DoS; invitation plaintext leakage; schema drift between SQLite and production; accidentally exposing a registration route before isolation is ready.

**Test requirements:** Argon2 hash/verify/rehash; invite hash/single-use/expiry/revocation/email binding; owner CLI idempotence; no plaintext codes in DB/logs; existing 82 tests remain green.

**Definition of done:** Owner and invitations can be created by CLI; all account routes are feature-flagged off or admin-only; no document route has changed; tests cover the primitives; no tester can register yet.

### 11.3 Phase 2.2 — User ownership and backend authorization

**Objective:** Attach every user-scoped object to a user and enforce ownership in services and queries.

**Files likely to change**

- `app/models/document.py`, `app/models/relationship.py`, `app/models/auth.py`
- New `app/models/user_settings.py`, `app/models/assisted_request.py`
- `app/services/documents.py`, `search.py`, `relationships.py`, `organization.py`, `ask.py`, `auth.py`
- `app/api/security.py`, `app/api/v1/documents.py`, `search.py`, `relationships.py`, `ask.py`, `categories.py`, `auth.py`
- `app/schemas/*` (add owner-safe fields; never expose internal paths)
- Migration/backfill script
- Tests across all existing suites (fixtures gain an owner)

**Dependencies:** Phase 2.1; a decision that the owner account will receive all legacy documents.

**Risks:** missed WHERE clauses; breaking 82 existing tests; FTS rebuild; relationship migration; auth dependency change; storage path rewrite; assisted-request global state.

**Test requirements:** the full cross-user matrix in §5.11 on SQLite; composite FK tests; per-user search/Ask; per-user AI mode; per-user assisted requests; original file integrity; legacy owner backfill.

**Definition of done:** No normal user route can access another user’s data; cross-user IDs return 404; all existing tests adapted and passing; no global mutation endpoints remain for normal users.

### 11.4 Phase 2.3 — Multi-user isolation test gate

**Objective:** Prove isolation with adversarial tests and fix findings before changing databases.

**Files likely to change**

- `tests/conftest.py` (two-user fixtures), `tests/test_isolation.py`, `tests/test_isolation_matrix.py`
- CI configuration
- Possibly small fixes found by tests

**Dependencies:** Phase 2.2.

**Risks:** tests that mirror implementation instead of attacking it; mocks hiding real query behavior; SQLite-only confidence.

**Test requirements:** two real users + real temp DB; every endpoint with A/B; direct SQL assertions; concurrency tests for invitation use and duplicate upload; log/token assertions; property-style loop over random IDs.

**Definition of done:** The matrix passes with zero exceptions; a reviewer can trace every route to an owner-scoped service call; the suite is part of CI and blocks merges.

### 11.5 Phase 2.4 — PostgreSQL migration

**Objective:** Move to PostgreSQL with Alembic, `tsvector` FTS, per-user constraints, and optional RLS; rehearse and execute the migration; keep rollback available.

**Files likely to change**

- `app/db/session.py` (database URL, Postgres engine, pool settings)
- `app/db/migrations.py` → `alembic/` baseline + versions
- `app/main.py` (startup migrations, FTS check)
- `app/services/search.py` (tsvector/tsquery/ts_headline/ts_rank)
- `app/core/config.py` (`database_url`, pool, TLS)
- `scripts/migrate_sqlite_to_postgres.py` (one-off)
- `tests/conftest.py` (Postgres fixture), CI service
- Documentation/runbook

**Dependencies:** Phase 2.3 green; hosting decision; a PostgreSQL instance.

**Risks:** FTS behavior differences; timezone/JSON conversion; downtime; extension/config availability; constraint migration; rollback complexity.

**Test requirements:** the full isolation suite on PostgreSQL; FTS document-set parity for known queries; migration rehearsal with the real 1-document DB; hash/count verification; rollback rehearsal; auth tests.

**Definition of done:** Production-like PostgreSQL passes isolation and migration checks; the real data is migrated and verified; rollback is documented and tested; registration can now be enabled.

### 11.6 Phase 2.5 — Flutter registration and account management

**Objective:** Add welcome, registration, login, account settings, recovery, and storage-mode selection while preserving the Archival Precision design and biometric gate.

**Files likely to change**

- `mobile/lib/state/auth_controller.dart`, `mobile/lib/core/auth_store.dart`
- `mobile/lib/data/api_client.dart`, `mobile/lib/data/models.dart`
- `mobile/lib/screens/auth_gate.dart`, `lock_screen.dart`, `settings_screen.dart`
- New: `welcome_screen.dart`, `register_screen.dart`, `login_screen.dart`, `account_screen.dart`, `recovery_screen.dart`, `storage_mode_screen.dart`
- `mobile/lib/app.dart`, `mobile/test/auth_controller_test.dart`, `widget_test.dart`, new tests

**Dependencies:** Phase 2.4 backend; product decisions on local mode and account switching.

**Risks:** token/account mixing; cached data after switch; UI scope creep; misleading privacy labels; pairing screens left visible.

**Test requirements:** all flows in §9.5; no private screen before auth; biometric token ordering; logout/switch clears state; 401 → login; storage mode persistence.

**Definition of done:** A new tester can register with an invite, log in, unlock with biometrics, use documents, sign out, and recover with an admin code; no pairing UI appears in accounts mode; tests pass.

### 11.7 Phase 2.6 — Storage architecture

**Objective:** Add a storage-provider interface and cloud object storage; decide and, if approved, spike true local mode.

**Files likely to change**

- New `app/storage/base.py`, `local.py`, `s3.py`
- `app/services/documents.py` (provider calls, streaming, keys)
- `app/core/config.py` (provider, bucket, endpoint, credentials)
- `app/api/v1/documents.py` (streaming/presigned download)
- Flutter storage-mode UI and API client
- Tests for both providers; migration/reconciliation script

**Dependencies:** Phase 2.2 ownership; Phase 2.4 database; product decision on local mode.

**Risks:** presigned URL leakage; orphaned objects; mode-switch data loss; false local claims; provider lock-in.

**Test requirements:** put/open/delete across providers; owner-scoped keys; hash verification; expired presigned URL; public-access denial; mode-switch copy/verify/switch/grace; no credentials in Flutter or logs.

**Definition of done:** Backend-hosted and cloud modes work with per-user keys; mode switching is verified; local mode is either implemented with a real on-device pipeline or explicitly marked unavailable.

### 11.8 Phase 2.7 — Tester deployment and onboarding

**Objective:** Deploy the verified system to the free-tier host, configure HTTPS/backups/monitoring, and invite the first small group.

**Files likely to change**

- Deployment files: systemd unit, Caddyfile, backup scripts, firewall/runbook, `.env.example`
- Documentation: tester onboarding, privacy notice, recovery procedure, incident contacts
- No application logic changes unless deployment testing finds bugs

**Dependencies:** Phases 2.4–2.6 complete; domain name; Oracle account; tested restore.

**Risks:** free-tier capacity/reclamation; backup failure; TLS misconfiguration; invite leakage; support burden.

**Test requirements:** production smoke test; HTTPS-only release; two real devices with two accounts; cross-user attempts fail; backup restore drill; monitoring alerts; invite/registration end to end.

**Definition of done:** The service is reachable over HTTPS, backed up, monitored, and tested with at least two independent accounts; the first tester is invited only after all gates pass.

### 11.9 Critical gates

| Gate | Must be true before |
|---|---|
| Phase 1.3 checkpoint | Starting Phase 2.1 with a clean baseline |
| Phase 2.3 isolation suite green | Any PostgreSQL migration or tester invite |
| Phase 2.4 migration verified + rollback tested | Opening registration |
| Phase 2.5 auth flows tested | Giving testers the app |
| Phase 2.7 backup restore passed | Promising data durability |
| Local mode implemented and tested | Claiming device-only privacy |

---

## 12. Testing strategy

### 12.1 Test pyramid

1. **Unit:** password hashing, email normalization, invitation lifecycle, token hashing, rate limits, ownership predicates, FTS query construction.
2. **Service/integration:** real SQLite temp DB for fast tests; real PostgreSQL for the migration/parity suite.
3. **API:** FastAPI ASGI client with real auth headers; no dependency overrides that bypass `require_current_user`.
4. **Widget:** Flutter auth gate, controllers, and screens with `MockClient`.
5. **End-to-end/manual:** two accounts on two devices against a production-like deployment.

### 12.2 Backend fixtures

Add to the existing test app factory (`tests/test_api.py:30` area):

- `owner` user + owner session.
- `user_a` and `user_b` with separate tokens.
- `auth_headers(user)` helper.
- A temp data directory per test; never the real `data/`.
- A document factory that uploads as a specific user.
- A second temp app for migration tests.

Every existing test that used a single implicit session must be updated to choose an owner. Do not add a global “default user” that hides missing scoping.

### 12.3 Isolation matrix

Implement the table in §5.11 as parameterized tests. For every endpoint:

- Owner request succeeds (or returns the documented status).
- Unauthenticated request returns 401.
- Cross-user request returns 404 (or 403 for admin-only routes).
- Disabled-user request returns 401.
- The response body contains no other user’s ID, filename, title, snippet, category count, or evidence.

### 12.4 Database-level tests

- Every owner column is `NOT NULL` after migration.
- Composite FK insertion of a cross-user relationship fails.
- `(user_id, sha256)` uniqueness allows the same bytes for two users.
- `(user_id, storage_path)` uniqueness holds.
- FTS rows always match the document owner.
- Assisted requests always have an owner.
- Deleting a document cascades only within the owner.
- Indexes exist on owner columns and session expiry.

### 12.5 PostgreSQL parity tests

Run the same isolation suite against PostgreSQL in CI (service container or ephemeral managed instance). Add:

- FTS document-set parity for a fixed query corpus (allow ranking differences).
- Timezone round-trip for `uploaded_at` and `calculated_at`.
- JSON/JSONB round-trip for tags/reasons/evidence.
- Constraint tests (composite FK, unique).
- RLS tests if enabled: a session with `app.user_id = B` cannot select A’s rows; an unset variable fails closed.

### 12.6 Migration tests

- Build a SQLite fixture with two users, documents, relationships, FTS rows, tags, and known hashes.
- Run the migration script against a fresh PostgreSQL database.
- Assert row counts, per-user counts, hashes, paths, and FTS rebuild.
- Attempt a cross-user relationship in the fixture; the migration must reject or report it, not silently import it.
- Re-run the migration; it must be idempotent or fail safely without duplicates.
- Roll back and verify the source SQLite app still works.

### 12.7 Flutter tests

Extend the existing 63-test suite:

- New auth controller tests for register/login/reset/change-password/logout-all.
- Token ordering: never installed before biometric success.
- 401 closes the session and clears cached documents/Ask/AppState.
- Account switch clears all state and secure storage.
- Welcome/register/login screens render and validate without leaking enumeration.
- Storage-mode selection and persistence.
- Pairing hidden in accounts mode.
- Existing viewer/document/Ask tests remain green.

### 12.8 Security and abuse tests

- Invitation single-use under concurrency (two parallel requests).
- Login rate limit and lockout; `Retry-After`.
- Generic error bodies for unknown email vs wrong password.
- Password hash never logged; invitation code never logged; token never logged.
- Cross-user assisted confirm/cancel/revoke.
- Cross-user FTS snippet absence.
- Path traversal on per-user storage keys.
- Presigned URL expiry and owner check (cloud mode).
- Upload validation: oversize, wrong MIME, malformed PDF/image, duplicate within/across users.
- Admin route rejection for normal users.
- Disabled account session revocation.

### 12.9 Manual/live tests

- Two Android devices (or emulators) with two accounts.
- Attempt every ID-guessing case from the matrix on the live HTTPS deployment.
- Verify `FLAG_SECURE` blocks screenshots and recent-apps preview.
- Verify release build rejects cleartext and uses the HTTPS base URL.
- Verify backup restore into a staging environment.
- Verify logs contain no secrets/content.
- Verify the operator recovery/reset procedure.

### 12.10 Honest coverage gaps

- No test can prove the absence of all cross-user leaks; the matrix plus centralization and database constraints are the mitigation.
- Timing-based enumeration tests are statistical and can be flaky; use coarse thresholds and code review.
- Local mode cannot be tested until it exists.
- Free-tier hosting behavior (reclamation, capacity) cannot be fully tested locally.
- Email deliverability cannot be tested because no provider is introduced.

---

## 13. Migration and rollback plan

### 13.1 Preconditions

- Phase 2.3 isolation suite green on SQLite.
- Phase 2.4 PostgreSQL schema and migration script reviewed.
- Fresh backup of `data/lore.db`, `data/documents/`, and deployment config.
- Manifest of every file with SHA-256.
- Owner account UUID chosen.
- Maintenance window announced.
- Rollback operator and checklist assigned.

### 13.2 Backup

1. Copy `data/lore.db` to a timestamped backup outside the project tree.
2. Copy `data/documents/` (or archive it) without modifying originals.
3. Generate `manifest.json`/CSV: path, size, SHA-256, document ID.
4. Dump any existing PostgreSQL target.
5. Record the current git commit and backend version.
6. Test that the backup opens/restores in a scratch directory.

### 13.3 Cutover steps

1. Stop the backend; confirm no writes.
2. Create the PostgreSQL database and apply Alembic migrations.
3. Create the owner account.
4. Copy relational data with `user_id = owner_id`; preserve IDs and metadata.
5. Copy original files to per-user paths; verify hashes.
6. Rebuild FTS and relationships; validate counts.
7. Point configuration at PostgreSQL; start the backend.
8. Run smoke tests, the isolation suite, and sample downloads.
9. Enable registration only after all checks pass.

### 13.4 Verification

Use the §6.7 checklist. Do not delete the SQLite source or the copied backup until the verification window closes (recommend 30 days).

### 13.5 Rollback

1. Stop the PostgreSQL-backed app.
2. Revert configuration to SQLite and the original storage root.
3. Restore the SQLite file only if it was modified (it should not be).
4. Restore original files from the copy/backup if needed.
5. Start the previous commit and run the backend suite + smoke test.
6. Keep the PostgreSQL database and copied files for diagnosis.
7. Record the incident and corrective actions.

Rollback is easiest because the plan copies rather than moves and keeps document IDs stable. If a future migration must move files, record the source/target mapping and keep a verified copy until the window closes.

### 13.6 Data preservation rules

- Never re-encode or rewrite an original.
- Never delete the only copy.
- Never change a document ID during migration.
- Never silently drop rows; report and stop on unexpected data.
- Preserve extracted text, classification fields, tags, categories, and dates.
- Preserve original filenames for download.
- Keep an audit trail of the migration itself.

### 13.7 Communication

- Tell testers the maintenance window and what to expect.
- Tell them sessions will be reset and they will log in again.
- Tell them how to report a cross-user or privacy issue.
- Publish a short privacy note describing backend/cloud/local boundaries honestly.

---

## 14. Unresolved decisions

| # | Decision | Options | Recommendation | Needed by |
|---|---|---|---|---|
| 1 | What does “Local Mode” mean? | On-device only vs user-hosted backend | Decide before Phase 2.6; do not claim device-only until implemented | Phase 2.6 |
| 2 | PostgreSQL before invites? | A/B/C | **B**: migrate before tester registration | Phase 2.4 |
| 3 | Email provider and verification | Manual vs provider | Manual/invitation-as-verification for MVP; provider before public | Phase 2.5/2.7 |
| 4 | Invitation email binding | Bound vs code-only | **Bound**; prevents sharing | Phase 2.1 |
| 5 | Account switching on one device | One account/install vs multi-account | One account per install for MVP; clear state on switch | Phase 2.5 |
| 6 | Admin visibility into documents | None vs break-glass | **None** in MVP; operator filesystem access acknowledged | Phase 2.1 |
| 7 | Session lifetime | 30d/7d vs shorter | 30-day absolute, 7-day idle; configurable | Phase 2.1 |
| 8 | Password recovery | Admin-assisted vs email self-service | Admin-assisted for MVP | Phase 2.1 |
| 9 | Assisted request storage | In-memory vs DB | **DB table**; supports restart/multi-worker | Phase 2.2/2.4 |
| 10 | PostgreSQL RLS | Yes vs no | Yes as defense in depth, not sole control | Phase 2.4 |
| 11 | FTS language config | `simple` vs `english` | `simple` to preserve behavior; evaluate later | Phase 2.4 |
| 12 | Tester object storage | Block volume vs R2 | Block volume first; R2 for backup/offsite | Phase 2.6/2.7 |
| 13 | Free-tier risk acceptance | Accept vs paid | Accept with off-provider backups and monitoring | Phase 2.7 |
| 14 | Account deletion/export | Now vs later | Later, with a written retention policy | Post-MVP |
| 15 | Worker count | One vs many | One until assisted requests/limits are DB-backed | Phase 2.4 |
| 16 | Roles and sharing | Owner/admin/user vs sharing | No per-document sharing in MVP | Phase 2.1 |
| 17 | Email normalization details | Library vs custom | Library (`email-validator`), lowercase, no provider-specific folding | Phase 2.1 |
| 18 | Backup retention | 7/4/3 vs longer | 7 daily/4 weekly/3 monthly, encrypted, restore-tested | Phase 2.7 |
| 19 | Local LLM on server | Yes vs no | No on free tier; extractive default; Assisted with consent | Phase 2.7 |
| 20 | Pairing endpoint in accounts mode | Remove vs hidden flag | Hidden `pairing` mode for self-hosted; disabled in accounts | Phase 2.5 |

---

## Recommended first implementation task

**Phase 2.1A — Account foundation without opening registration.**

Build the smallest safe slice of the account system on the current SQLite development database, with no public registration and no change to document access:

1. Add `users`, `invitations`, `password_resets`, `user_settings`, and `audit_log` models.
2. Add an Argon2id password service (hash, verify, needs-rehash).
3. Add an email normalization/validation helper.
4. Add an operator CLI to create the first owner and issue an invitation code, printing the plaintext code once and never logging it.
5. Keep `/auth/register` and `/auth/login` absent or feature-flagged off; do not open registration.
6. Do not add `user_id` to documents yet; that is Phase 2.2.
7. Add tests for Argon2, invite single-use/expiry/email binding, owner CLI idempotence, and secret-free logs.
8. Keep the existing 82 backend tests, 63 Flutter tests, and clean analysis green.

**Why this first:** It establishes identity primitives without changing the live document path, without a database migration, and without exposing a half-isolated API. Phase 2.2 can then attach ownership to documents and sessions in one deliberate change, and Phase 2.3 can prove isolation before any tester is invited.

**Before starting:** obtain permission to checkpoint Phase 1.3 in a commit (do not commit or push automatically), then create a feature branch for Phase 2.1.

---

## Appendix A — Primary source references

- `app/main.py` — app factory, startup, FTS initialization, middleware.
- `app/core/config.py` — all settings, including auth and Ask.
- `app/db/session.py` — SQLite engine and foreign-key pragma.
- `app/db/migrations.py` — legacy upgrade and FTS5 schema.
- `app/models/document.py`, `app/models/relationship.py`, `app/models/auth.py` — current schemas.
- `app/services/auth.py` — pairing, sessions, rate limiting, revocation.
- `app/services/documents.py` — upload, storage, extraction, delete.
- `app/services/search.py` — FTS indexing and query.
- `app/services/relationships.py` — relationship generation and rebuild.
- `app/services/organization.py` — categories and counts.
- `app/services/ask.py` — retrieval, providers, assisted requests.
- `app/api/security.py`, `app/api/router.py` — the single auth boundary.
- `app/api/v1/*.py` — route surfaces and ID-based access.
- `tests/test_api.py` — 54 test functions, 82 collected tests.
- `mobile/lib/state/auth_controller.dart`, `mobile/lib/screens/auth_gate.dart`, `mobile/lib/data/api_client.dart`, `mobile/lib/core/auth_store.dart` — Flutter auth.
- `mobile/lib/state/app_state.dart`, `documents_controller.dart`, `ask_controller.dart` — Flutter state.
- `mobile/android/app/src/main/AndroidManifest.xml`, `MainActivity.kt` — network and `FLAG_SECURE`.
- `README.md` — current single-user scope, pairing, recovery, and network exposure claims.
- `data/lore.db`, `data/documents/`, `data/pairing-code.txt` — real local state (not modified).

External hosting facts (verify at signup; limits change):

- Oracle Cloud Always Free resources: <https://docs.oracle.com/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm>
- Oracle Cloud Free Tier: <https://www.oracle.com/cloud/free/>
- Cloudflare R2 pricing: <https://developers.cloudflare.com/r2/pricing/>
- Neon pricing: <https://neon.com/pricing>
- Supabase pricing/limits: <https://supabase.com/pricing>

## Appendix B — Test inventory snapshot

**Backend:** 54 test functions, 82 collected cases. Coverage includes upload/list/download/delete, validation, OCR gating, legacy upgrades, FTS search/ranking/filters/rebuild, relationships, classification, organization, Ask/extractive/assisted/local-LLM, auth boundaries, pairing hashing/lockout/recovery, traversal, and original-file integrity.

**Flutter:** 63 tests across `api_client_test.dart`, `ask_controller_test.dart`, `auth_controller_test.dart`, `document_viewer_test.dart`, `models_test.dart`, and `widget_test.dart`. Coverage includes API paths/headers, pairing, session lifecycle, 401 handling, assisted consent, screens, offline state, lock/unlock, and viewer states.

**Gap:** none of these tests creates two independent users, because the application cannot represent one. Phase 2.3 adds that layer.
