# LORE

LORE is a privacy-first personal document app. It pairs a FastAPI backend with a Flutter Android client: documents are uploaded to the backend, extracted and indexed locally, organized deterministically, and searched or questioned locally by default. Assisted Mode sends only the excerpts you explicitly approve to the configured external provider, and the optional local LLM path uses `LORE_LOCAL_LLM_ENDPOINT`, which defaults to loopback but can be configured differently.

The backend provides local SQLite or PostgreSQL persistence, local document upload/extraction, deterministic classification and relationship rules, portable full-text search, and three Ask LORE answer paths:

- **Extractive** — selects a concise answer from indexed document text. This is not generated text.
- **Local LLM** — optional, Ollama-compatible inference that the backend sends to `LORE_LOCAL_LLM_ENDPOINT` (default `http://127.0.0.1:11434`); it never runs on the phone.
- **Assisted** — external inference prepared by the backend, paused for your explicit approval, then confirmed for one request at a time.

## Requirements

- Windows with Python 3.12+
- Flutter 3.41+ / Dart 3.11+ and the Android SDK for the mobile client
- Optional PostgreSQL 14+ for the multi-user database target; SQLite remains the default

## Setup

Run these commands from the project directory in PowerShell:

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -e ".[dev]"
Copy-Item .env.example .env
```

The `.env` file is optional. Settings are read from environment variables prefixed with `LORE_`; values in the process environment take precedence over `.env`.

Create or update the database schema explicitly before starting the backend:

```powershell
python -m app.migrate upgrade
```

This command is safe to re-run. On a brand-new installation it creates the current schema. On an existing pre-Alembic SQLite database it adopts the existing tables and rows in place, records a baseline revision, and does not rewrite document files. Downgrade and current-revision inspection are also available:

```powershell
python -m app.migrate current
python -m app.migrate downgrade 0002_pairing_attempts
```

Application startup never alters the schema. If the database is not at the expected revision, the backend refuses to start and tells you to run the upgrade command. This applies to both SQLite and PostgreSQL.

### PostgreSQL

SQLite stays the development default. To target PostgreSQL, set `LORE_DATABASE_URL` before running migrations and starting the backend:

```powershell
$env:LORE_DATABASE_URL = "postgresql://lore:replace-me@127.0.0.1:5432/lore"
python -m app.migrate upgrade
python -m app.migrate current
```

The URL may also use the `postgres://` form; the backend normalizes it to the psycopg 3 driver. Credentials are never stored in source. `LORE_DATABASE_URL` overrides `LORE_DATABASE_PATH`, and leaving it empty keeps SQLite. Create the database and role with your hosting provider's console or your own PostgreSQL server first; LORE does not provision a server or create the database itself.

PostgreSQL connections use `pool_pre_ping`, a bounded pool, periodic recycling, a connect timeout, and a UTC session timezone. Tune the pool for the host's connection limit:

| Variable | Default | Purpose |
| --- | --- | --- |
| `LORE_DATABASE_POOL_SIZE` | `5` | Persistent PostgreSQL connections per process |
| `LORE_DATABASE_MAX_OVERFLOW` | `10` | Temporary connections above the pool size |
| `LORE_DATABASE_POOL_RECYCLE_SECONDS` | `1800` | Recycle connections older than this |
| `LORE_DATABASE_CONNECT_TIMEOUT_SECONDS` | `10` | Connection attempt timeout |

Timestamps are stored with timezone information and read back in UTC. UUIDs use the existing `VARCHAR(36)` representation in both databases, so document and session IDs are unchanged by a transfer.

| Variable | Default | Purpose |
| --- | --- | --- |
| `LORE_APP_NAME` | `LORE` | API title |
| `LORE_DATA_DIR` | `data` | Local data and document storage directory |
| `LORE_DATABASE_PATH` | `data/lore.db` | SQLite database file |
| `LORE_DATABASE_URL` | unset | Optional PostgreSQL URL (`postgresql://...` or `postgres://...`); overrides the SQLite path |
| `LORE_LOG_LEVEL` | `INFO` | Structured application log level |
| `LORE_MAX_UPLOAD_SIZE_BYTES` | `20971520` | Maximum file size (20 MiB) |
| `LORE_MAX_EXTRACTED_TEXT_CHARS` | `1000000` | Maximum extracted text stored per document |
| `LORE_ENABLE_OCR` | `false` | Explicitly enable local OCR for images |
| `LORE_AI_MODE` | `private` | `private` or `assisted`; the client cannot switch silently |
| `LORE_ASK_PROVIDER` | `extractive` | `extractive`, `local-llm`, or `assisted` |
| `LORE_MAX_ASK_QUESTION_LENGTH` | `1000` | Maximum question length |
| `LORE_MAX_ASK_SOURCES` | `5` | Maximum evidence documents per answer |
| `LORE_LOCAL_LLM_MODEL_NAME` | unset | Model name available in the local runtime |
| `LORE_LOCAL_LLM_MODEL_PATH` | unset | Alternative local model file path |
| `LORE_LOCAL_LLM_ENDPOINT` | `http://127.0.0.1:11434` | Ollama-compatible endpoint used by the local LLM provider |
| `LORE_LOCAL_LLM_TIMEOUT_SECONDS` | `30` | Local inference timeout |
| `LORE_LOCAL_LLM_MAX_OUTPUT_TOKENS` | `256` | Local generation limit |
| `LORE_LOCAL_LLM_MAX_CONCURRENCY` | `1` | Concurrent local generations |
| `LORE_EXTERNAL_AI_PROVIDER` | unset | Label for the assisted provider |
| `LORE_EXTERNAL_AI_ENDPOINT` | unset | Required before Assisted Mode can be enabled; must be an absolute `http://` or `https://` URL |
| `LORE_EXTERNAL_AI_API_KEY` | unset | Required bearer token for Assisted Mode; keep it in `.env`, never in source |
| `LORE_ASSISTED_CONFIRMATION_TTL_SECONDS` | `300` | Expiry for prepared assisted requests |
| `LORE_AUTH_SESSION_TTL_HOURS` | `720` | Backend bearer-session lifetime (30 days) |
| `LORE_AUTH_PAIRING_CODE_TTL_MINUTES` | `30` | Lifetime of the one-time local pairing code |
| `LORE_AUTH_PAIRING_MAX_FAILURES` | `5` | Failed pairing attempts allowed before a temporary lockout |
| `LORE_AUTH_PAIRING_LOCKOUT_SECONDS` | `300` | First pairing lockout; later lockouts double |
| `LORE_AUTH_PAIRING_MAX_LOCKOUT_SECONDS` | `900` | Upper bound for a pairing lockout |
| `LORE_AUTH_PASSWORD_MIN_LENGTH` | `12` | Minimum account password length |
| `LORE_AUTH_PASSWORD_MAX_LENGTH` | `128` | Maximum account password length |
| `LORE_AUTH_PASSWORD_MEMORY_KIB` | `65536` | Argon2id memory cost (64 MiB) |
| `LORE_AUTH_PASSWORD_TIME_COST` | `3` | Argon2id iteration count |
| `LORE_AUTH_PASSWORD_PARALLELISM` | `4` | Argon2id lanes |
| `LORE_INVITATION_TTL_DAYS` | `7` | Default invitation lifetime |

Data remains on the machine by default. The default database and document directory are excluded from version control; if you configure custom paths inside the repository, exclude those paths too. Do not point either setting at a shared or public location unless that is intentional. In Private Mode (the default), document bytes and extracted text are not sent to the Assisted external provider. Assisted Mode sends only the excerpts you explicitly approve, and only to the configured external endpoint. The metadata API does not return extracted text. All private endpoints require a paired bearer session; see [Authentication and app lock](#authentication-and-app-lock). Bind the development server to loopback or a trusted LAN and do not expose it to the internet without TLS.

Uploads are limited to PDF, UTF-8 TXT, PNG, JPEG, GIF, BMP, TIFF, and WebP; extension, declared MIME type, and file contents are checked. A 20 MiB default per-file limit is also enforced on the multipart request body. Stored filenames are generated from internal UUIDs, and client paths are discarded. SHA-256 duplicate uploads return `409 Conflict` with the existing document ID. Supported PDFs and text files are extracted locally during upload; image extraction is marked `not_requested` unless OCR is enabled. Document deletion removes its database row and stored file; if filesystem cleanup fails after metadata deletion, the API returns an explicit error.

## Document organization

New uploads are classified locally using a versioned, deterministic keyword ruleset. Categories are Finance, Education, Health, Identity, Home, Appliances, Insurance, Travel, Work, Legal, and Uncategorized. Rules inspect the original filename and locally extracted text; ambiguous or empty text yields `Uncategorized`. The returned confidence is a heuristic score, **not a statistically calibrated probability**. Classification does not interpret or execute document instructions, use a semantic search index, or contact a network service. Re-running classification is deterministic and does not modify the original file or extracted text.

Metadata extraction is conservative. It may identify a short title, a supported document type, an explicit issuer label (`Issued by:`, `Issuer:`, `From:`, `Prepared by:`, or `Provided by:`), labeled invoice/policy/reference/claim/account/order numbers, and unambiguous dates. Accepted dates include ISO `YYYY-MM-DD`, explicit month-name dates, and numeric dates only where one component is greater than 12. Ambiguous numeric dates (such as `03/04/2025`) and invalid calendar dates are left unset. `uploaded_at` is always the upload time; `document_date` is a distinct date extracted from text. Extracted text remains local and is not included in metadata API responses.

Examples (PowerShell):

```powershell
# Classify or reclassify one document
Invoke-RestMethod -Method Post http://127.0.0.1:8000/api/v1/documents/{id}/classify

# List Finance documents with pagination
Invoke-RestMethod "http://127.0.0.1:8000/api/v1/documents?category=Finance&limit=20&offset=0"

# List categories and current document counts
Invoke-RestMethod http://127.0.0.1:8000/api/v1/categories

# Manually set category and tags
Invoke-RestMethod -Method Patch `
  -Uri http://127.0.0.1:8000/api/v1/documents/{id}/organization `
  -ContentType "application/json" `
  -Body '{"category":"Home","tags":["rental","renewal"]}'

# Reclassify up to 100 selected documents in one request
Invoke-RestMethod -Method Post `
  -Uri http://127.0.0.1:8000/api/v1/documents/reclassify `
  -ContentType "application/json" `
  -Body '{"document_ids":["id-1","id-2"]}'
```

Document metadata includes `category`, `classification_confidence`, `classification_reasons`, `classification_method`, `document_title`, `document_type`, `document_date`, `issuer`, `reference_number`, and `tags`, alongside upload metadata. Classification method is `rules-v1`; a manually selected category uses `manual` and has no heuristic confidence. The categories endpoint includes zero-count categories; documents not yet classified are included under `Uncategorized`.

### Optional image OCR

Install the Python extra and separately install the Tesseract OCR executable on the same machine:

```powershell
python -m pip install -e ".[dev,ocr]"
$env:LORE_ENABLE_OCR = "true"
```

Tesseract must be available on `PATH`. OCR runs locally only. If the Python extra or Tesseract executable is missing, image uploads are still stored, with extraction marked failed and a clear dependency message; retry returns `503 Service Unavailable` until the dependency is available.

The existing `documents` table is adopted by the Alembic baseline revision on either database; existing rows and source files are retained. Legacy rows without organization data are not silently reprocessed during migration and appear under `Uncategorized` until classified.

## Search and relationships

Text search is provided by the active database dialect and keeps the same HTTP contract on both:

- **SQLite** uses the local FTS5 extension with the `unicode61` tokenizer.
- **PostgreSQL** uses a regular `document_search` table with a weighted `tsvector` and a GIN index. Extracted text is weighted lowest; filename, title, and reference number are weighted highest. Snippets come from `ts_headline` and results are ranked with `ts_rank_cd` plus the same exact filename/reference/title preference used on SQLite.

The index includes extracted text and searchable metadata (filename, title, category, tags, type, issuer, and reference number); snippets and matching field names are returned instead of a full-text field. Exact filename, reference, and title matches are ranked before weighted relevance. Query input is tokenized into safe Unicode word prefixes before it reaches the provider, so punctuation and query operators are never executed as syntax. Requests are limited to 256 characters, 12 terms, 100 results, and offsets up to 100,000. An empty/punctuation-only query is rejected. If the search index is missing or cannot be used, search returns `503` and document upload/metadata APIs remain available; the message names the affected database. The index is initialized and repaired at startup when its row count differs, and can be rebuilt explicitly.

Search behavior is close but not byte-identical between the two providers. PostgreSQL's `simple` dictionary is used deliberately so that technical references, filenames, and non-English text are not stemmed away. Hyphenated values such as `INV-923456` are indexed as separate word tokens on both providers, so prefix queries still match them. Snippet highlighting and relevance scores can differ slightly, and results should not be compared numerically across databases. Empty or malformed input is handled identically.

Examples:

```powershell
# Search with a category and document-type filter
Invoke-RestMethod "http://127.0.0.1:8000/api/v1/search?q=invoice%20INV-12345&category=Finance&document_type=invoice&limit=10"

# Rebuild the local full-text index
Invoke-RestMethod -Method Post http://127.0.0.1:8000/api/v1/search/rebuild

# Recalculate one document's related-document suggestions
Invoke-RestMethod -Method Post `
  -Uri http://127.0.0.1:8000/api/v1/documents/{id}/related/recalculate

# Rebuild suggestions across a bounded local document set
Invoke-RestMethod -Method Post http://127.0.0.1:8000/api/v1/relationships/rebuild

# Retrieve a document's suggestions and their evidence
Invoke-RestMethod http://127.0.0.1:8000/api/v1/documents/{id}/related
```

Relationship suggestions are deterministic local rules. Matching labeled reference numbers or explicit product/model/serial/brand labels are strong evidence; issuer matches are considered only with complementary document types. Category or issuer alone never creates a suggestion. Scores are heuristic rankings, not calibrated probabilities, and each result is explicitly described as a suggestion with its evidence. Pairs use sorted document IDs and a stable relationship ID to prevent A-to-B/B-to-A duplicates. Classification, extraction, or manual organization changes invalidate existing suggestions for that document; recalculate or rebuild to refresh them.

The full-text rebuild is limited by `LORE_SEARCH_REBUILD_MAX_DOCUMENTS` (default 10,000; max 50,000) and 100 million extracted-text characters per request. Relationship operations are limited by `LORE_RELATIONSHIP_MAX_DOCUMENTS` (default 1,000; max 5,000), 100 million text characters, and a 20,000 candidate-pair cap. Tune the configured maximums only for machines with adequate local storage and memory. These operations make no network calls.

## Ask LORE and privacy

`POST /api/v1/ask` answers a question from documents indexed by the backend. The response states which provider produced it (`extractive`, `local-llm`, or `assisted`), whether evidence was sufficient, and the retrieved excerpts used as evidence. Extractive answers are selected from document text and are not generated. The local LLM path sends prompts and retrieved excerpts to `LORE_LOCAL_LLM_ENDPOINT` (default `http://127.0.0.1:11434`) and requires an Ollama-compatible runtime and model reachable there; it does not run on the Android device.

Assisted Mode is a two-step consent workflow:

1. `POST /api/v1/ask/prepare` retrieves candidate excerpts and stores a prepared request in backend memory with a payload hash and a TTL (`LORE_ASSISTED_CONFIRMATION_TTL_SECONDS`, default 300 seconds). **Nothing is sent to the external provider at this point.** The response lists the exact excerpts that would leave the backend.
2. `POST /api/v1/ask/confirm` accepts only the prepared request ID, question, and unmodified excerpts. The backend verifies the payload hash and TTL, sends only those excerpts to the configured external endpoint, and discards the request.

The backend rejects confirmation when the question or excerpts changed, when the request expired, or when it was already consumed. `POST /api/v1/ask/cancel?request_id=...` cancels one prepared request and `POST /api/v1/ask/revoke-consent` cancels all of them. Prepared requests and Ask conversations are not written to the database; the mobile client also keeps conversations in memory only. External citations are not used as document evidence by the Android client; the app displays the approved excerpts instead. The external API key is read from the environment and is never returned by the API or embedded in the app. `GET /api/v1/ask/status` reports provider availability so the client can show the real state instead of guessing.

Assisted Mode requires a valid absolute `http(s)` `LORE_EXTERNAL_AI_ENDPOINT` and `LORE_EXTERNAL_AI_API_KEY`. `GET /api/v1/ask/status` reports the external provider as unavailable with a reason when that configuration is missing or invalid, and `POST /api/v1/ask/mode` refuses to enable Assisted Mode with HTTP 503 while leaving the previous mode unchanged. Private Mode (the default) never uses the Assisted external provider; it answers with the extractive provider or, when selected, the configured local LLM endpoint. Private Mode inference is only as local as `LORE_LOCAL_LLM_ENDPOINT`: it defaults to loopback but accepts another address, and a loopback-only restriction is not yet implemented.

## Authentication and app lock

LORE uses two independent boundaries:

1. **Android app lock** decides whether private content may be shown on the phone. The app starts locked and unlocks through Android biometrics with the device PIN/pattern/password as fallback. A configurable auto-lock covers immediate, 1 minute, 5 minutes, and 15 minutes after backgrounding; Settings also offers a manual **Lock now** action. Locking removes the token from the API client and clears in-memory documents, searches, status, and conversations. Android `FLAG_SECURE` blocks screenshots and the recent-apps preview.
2. **Backend bearer authentication** protects every document, upload, download, search, relationship, Ask, AI-mode, and Assisted endpoint. Unpaired or revoked clients receive `401` regardless of the local UI state.

Pairing is local and one-time. On first start, or whenever there are no active sessions, the backend creates `data/pairing-code.txt` containing a short-lived code (default 30 minutes). Enter that code in the Android app. Successful pairing returns a 256-bit random session token, stores only its SHA-256 hash in the database, and deletes the pairing file. Pairing is refused with `409` while another active session exists. The code and tokens are never written to application logs.

Failed pairing attempts are rate limited. After `LORE_AUTH_PAIRING_MAX_FAILURES` failures (default 5), the endpoint returns `429` with a `Retry-After` header and stays locked for `LORE_AUTH_PAIRING_LOCKOUT_SECONDS` (default 300). Further failure cycles double that delay up to `LORE_AUTH_PAIRING_MAX_LOCKOUT_SECONDS` (default 900). The counter and lockout are stored in the `pairing_attempts` row, so restarting the backend does not reset them. A successful pairing deletes the row, and a lockout is always temporary; it never blocks the owner permanently. Missing or expired pairing codes also count as failed attempts.

The mobile client stores the session token in Android Keystore-backed encrypted storage (`flutter_secure_storage`), never in plain preferences. Tokens are sent only as `Authorization: Bearer` headers. The stored token is not installed into the API client until Android device authentication succeeds; after unlocking, the app validates it with `GET /api/v1/auth/session`, and an explicit `401` clears secure storage and returns to pairing. A network failure during that check does not block local unlock, but the first request the backend rejects with `401` closes the session, clears local credentials, and returns to pairing, so a stale token cannot silently restore access. `POST /api/v1/auth/logout` revokes the current session; `POST /api/v1/auth/revoke-all` revokes every session and returns the backend to pairing-required state. If logout cannot reach the backend, the app removes the local token but tells you that server-side revocation could not be confirmed, so the session may remain valid on the server until it expires. Expired, revoked, malformed, and missing tokens are rejected. There are no hardcoded credentials.

### Recovery when the device session is lost

LORE has no public recovery endpoint and never returns a token or pairing code through the API. Recovery is an explicit operator action on the machine that hosts the backend:

1. Stop the LORE backend.
2. From the backend project directory, run `python -m app.recovery`.
3. The command revokes active sessions, clears any pairing lockout, and ensures a valid `data/pairing-code.txt` exists (writing a fresh code if needed), then prints its path. It does not delete documents, metadata, or stored original files.
4. Start the backend again and pair the device with that code.

The same recovery is needed after clearing app data on the phone, because the backend still considers the old session active and refuses new pairing while it is. If you still hold a valid session, you can instead use `POST /api/v1/auth/revoke-all` from the app.

### Single-user scope and storage limits

LORE is still a single-user local backend in this phase. Pairing is available only while no active session exists, and there is no multi-user registration, per-user isolation, email/password login route, or role separation exposed to clients yet. The account and invitation tables prepared in Phase 2.1A are reachable only through the local operator CLI. Document originals are stored as files under `LORE_DATA_DIR/documents` and metadata in the configured database; neither is encrypted at rest by LORE, and there is no end-to-end encryption. Use full-disk encryption and OS file permissions if that matters for your threat model.

The trust boundary is deliberate: local biometrics cannot protect a network API, and backend authentication cannot prove who is holding the phone. LORE requires both for normal use. If a device has no screen lock configured, the app reports that local confirmation is unavailable and Android cannot raise a prompt; backend authentication still applies, and the app still removes the token from the API client when it locks. Android `FLAG_SECURE` blocks screenshots and the recent-apps preview, but it does not stop a compromised operating system or a person who knows the device PIN.

## Accounts and invitations (Phase 2.1A)

LORE now has the database and service foundation for invitation-only accounts, but **no public registration or email/password login endpoint exists yet**. The Flutter client still uses local pairing and the biometric app lock; neither changed in this phase.

Create the single owner account from the machine that hosts the backend. Passwords are read with `getpass`, are never accepted on the command line, and only the Argon2id hash is stored:

```powershell
python -m app.admin init-owner
```

A second owner cannot be created; the database also enforces this with a partial unique index. Create a single-use invitation bound to an email address:

```powershell
python -m app.admin invite --email tester@example.com
python -m app.admin invite --email tester@example.com --expires-days 7
```

The invitation secret is printed once and only its SHA-256 digest is stored. Invitations expire, can be revoked, are bound to the invited email, and are consumed atomically at most once. Email normalization is conservative and ASCII-only: input is NFKC-normalized, trimmed, lowercased, and validated before storage, so the same address always maps to the same account.

Accounts use Argon2id (`argon2-cffi`) with 64 MiB memory, 3 iterations, 4 lanes, a 16-byte library-generated salt, and a 32-byte hash. The full encoded hash is stored. The defaults measured about 60 ms per verification on the development host; benchmark on your target host and adjust `LORE_AUTH_PASSWORD_*` if needed.

Sessions now record `auth_method`. Existing pairing sessions remain `pairing` and have no user; a future email/password session will be `password` with a mandatory user. A database check constraint enforces that pairing sessions never carry a user and password sessions always do. Legacy pairing tokens are never silently upgraded or reinterpreted as a multi-user credential.

The existing documents table has a nullable `owner_user_id` column prepared for the owner account, but this phase deliberately does **not** assign ownership or filter documents by user. No live document rows or original files were modified.

## PostgreSQL preparation and data transfer (Phase 2.1B)

This phase makes the backend run on PostgreSQL as well as SQLite, provides a portable search abstraction, and adds a verified transfer tool. It does **not** enable registration, email/password login, invitation redemption, multi-user authorization, or document ownership. Existing documents stay unowned (`owner_user_id = NULL`).

### Local development

SQLite remains the default:

```powershell
python -m app.migrate upgrade
python -m uvicorn app.main:app --reload
```

To develop against a local PostgreSQL server instead:

```powershell
$env:LORE_DATABASE_URL = "postgresql://lore:replace-me@127.0.0.1:5432/lore_dev"
python -m app.migrate upgrade
python -m uvicorn app.main:app --reload
```

Use a disposable database for development and tests. The backend never creates a database, role, or extension for you. PostgreSQL 14 or newer is recommended; the tests were run against PostgreSQL 18.

### Transfer a live SQLite installation

Stop the backend before transferring. The tool never opens the live SQLite file writable: it takes a consistent snapshot through SQLite's backup API, migrates only that snapshot, and verifies the source file hash before and after.

1. Create an empty PostgreSQL database and run migrations against it.
2. Copy or mount the original document directory on the target host. The tool requires a separate target data directory and refuses to write into the source directory.
3. Run the transfer from the backend project directory:

```powershell
$env:LORE_DATABASE_URL = "postgresql://lore:replace-me@db-host:5432/lore"

python -m app.transfer `
  --source-sqlite data/lore.db `
  --source-data-dir data `
  --target-url $env:LORE_DATABASE_URL `
  --target-data-dir D:\lore-data `
  --report transfer-report.json
```

The command:

- Refuses a non-PostgreSQL target, a non-empty target, an un-migrated target, or source/target paths that overlap.
- Preserves document IDs, filenames, MIME types, sizes, SHA-256 values, categories, classification data, titles, dates, types, issuers, reference numbers, tags, extracted text, storage paths, upload timestamps, relationships, accounts, invitations, and active sessions.
- Forces every transferred document to remain unowned; it never invents an owner.
- Copies original files without deleting or moving the source, verifies source file size and SHA-256 against the database, then verifies the copied target file.
- Rebuilds the PostgreSQL search index.
- Compares source and target row counts, identifier sets, and every field, and writes a JSON report with `source_unchanged: true`.
- Aborts on the first mismatch. Recreate an empty target database before retrying after a partial failure.

To verify after transfer, start the backend with `LORE_DATABASE_URL` pointing at PostgreSQL and the same `LORE_DATA_DIR` as `--target-data-dir`. Confirm that an existing paired device still authenticates, documents open and download, search returns the same documents, and relationship suggestions are present. The report also records the source snapshot hash, target revision, per-table counts, file totals, and ownership counts.

### Backup and restore

Back up the database and the document directory together; either alone is incomplete.

- **SQLite:** stop the backend, copy both the database file and any `-wal`/`-shm` files, then copy `LORE_DATA_DIR/documents`. Do not copy a running database with ordinary file copy.
- **PostgreSQL:** use your provider's snapshot/backup feature or `pg_dump` while writes are stopped, and copy `LORE_DATA_DIR/documents` separately. Restore the database before restoring the files, then run `python -m app.migrate current` to confirm the revision.
- Test a restore into a separate database and directory before relying on it. LORE does not encrypt originals or database contents at rest; use encrypted volumes and provider encryption if that matters for your threat model.

### Deployment readiness

Before pointing a client at a hosted backend:

- Create a dedicated database and least-privilege role. Store the URL only in the host's environment, never in the repository.
- Use TLS for the database connection when the provider requires it (`?sslmode=require` or the provider's documented parameter) and keep the API behind HTTPS as described below.
- Run `python -m app.migrate upgrade` as an explicit deploy step. Startup refuses an outdated schema and never migrates automatically.
- Size `LORE_DATABASE_POOL_SIZE` + `LORE_DATABASE_MAX_OVERFLOW` below the provider's connection limit, especially with serverless poolers.
- Persist `LORE_DATA_DIR/documents` on a durable volume. A database alone is not a complete backup because the originals are files.
- Configure provider backups and retention, monitor disk usage, and rehearse restoration.

Free-tier hosting choices change frequently. Treat this comparison as a starting point, not a guarantee of permanence or zero cost:

| Option | Practical notes | Main caveat |
| --- | --- | --- |
| Neon | Managed PostgreSQL with a connection pooler and branching | Free plans may scale to zero; cold starts and limits vary |
| Supabase | Managed PostgreSQL plus a pooler and dashboard | Free projects may pause after inactivity; storage policies and limits change |
| Railway / Render | Small managed databases alongside an app service | Trial credits, sleep behavior, and free tiers are time-limited or plan-dependent |
| Fly.io | Small PostgreSQL machines with volume storage | Billing allowances change; volumes and backups are your responsibility |
| Self-hosted VPS | Full control over PostgreSQL and file storage | You own patching, backups, TLS, and capacity |

Verify current quotas, region behavior, backup retention, pooler support, and whether the free tier can be paused or deleted before trusting any provider with your only copy. None of these options make LORE multi-user; per-user authorization is a later phase.

## Network exposure and HTTPS

The backend defaults to loopback (`127.0.0.1:8000`), and the Android emulator reaches it through `10.0.2.2:8000`. This is the recommended development setup, and it does not expose the API to other machines.

Three modes are supported, and they have different risk levels:

1. **Emulator on the same computer (recommended for development).** Keep the default loopback bind and the app's default `http://10.0.2.2:8000` base URL. No LAN exposure.
2. **Trusted LAN (development only).** Start the backend with `--host 0.0.0.0`, allow the port through the local firewall, and pass your computer's LAN address to the app with `--dart-define=LORE_API_BASE_URL=http://<lan-ip>:8000`. Plain HTTP on a LAN can be observed by other devices on that network; use this only on a network you trust, and never on public Wi-Fi.
3. **Public or untrusted access (requires TLS).** Put an HTTPS reverse proxy in front of the backend and use its URL for `LORE_API_BASE_URL`. LORE does not terminate TLS itself. Release Android builds block cleartext HTTP, so HTTPS is required outside debug builds. HTTPS is not active unless you configure and verify a proxy; the default setup is plain HTTP on loopback.

Example Caddy reverse proxy (automatic TLS for a real hostname):

```caddyfile
lore.example.com {
    reverse_proxy 127.0.0.1:8000
}
```

Example Nginx reverse proxy with a certificate you manage:

```nginx
server {
    listen 443 ssl;
    server_name lore.example.com;
    ssl_certificate     /path/to/fullchain.pem;
    ssl_certificate_key /path/to/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto https;
    }
}
```

After configuring a proxy, verify that pairing and document requests actually work over `https://`, and restrict the backend port so it is reachable only from the proxy. Do not send bearer tokens over public unencrypted HTTP.

## Run

```powershell
python -m app.migrate upgrade
python -m uvicorn app.main:app --reload
```

The service listens on `http://127.0.0.1:8000` by default. The migration command must be run explicitly after installing or updating the backend; startup refuses to proceed against a database that is not at the current revision and never alters the schema itself. On first start, the pairing code is written to `data/pairing-code.txt`. Interactive API documentation is available at `/docs`. Leave the default loopback bind unless you deliberately need emulator or LAN access; startup does not expose the API to the LAN on its own.

## API

Public endpoints:

- `GET /` — API name, version, and basic service status
- `GET /api/v1/system/status` — service and database connectivity status
- `GET /api/v1/auth/status` — paired state and pairing-code expiry
- `POST /api/v1/auth/pair` — exchange the one-time local pairing code for a bearer token

All endpoints below require `Authorization: Bearer <session-token>` and return `401` otherwise:

- `GET /api/v1/auth/session` — validate the current session
- `POST /api/v1/auth/logout` — revoke the current session
- `POST /api/v1/auth/revoke-all` — revoke every session and require pairing again
- `POST /api/v1/documents` — upload a multipart form field named `file`
- `GET /api/v1/documents?limit=50&offset=0` — list metadata
- `GET /api/v1/documents/{id}` — retrieve metadata
- `GET /api/v1/documents/{id}/download` — download original file
- `DELETE /api/v1/documents/{id}` — delete metadata and local file
- `POST /api/v1/documents/{id}/retry-extraction` — retry local text extraction
- `POST /api/v1/documents/{id}/classify` — classify and extract document metadata
- `GET /api/v1/categories` — list categories and document counts
- `GET /api/v1/documents?category=Finance&limit=20&offset=0` — filter and paginate
- `PATCH /api/v1/documents/{id}/organization` — manually update category/tags
- `POST /api/v1/documents/reclassify` — reclassify 1–100 selected document IDs
- `GET /api/v1/search?q=...&limit=20&offset=0` — local full-text search
- `POST /api/v1/search/rebuild` — rebuild the bounded FTS5 index
- `GET /api/v1/documents/{id}/related` — related-document suggestions and evidence
- `POST /api/v1/documents/{id}/related/recalculate` — refresh one document's suggestions
- `POST /api/v1/relationships/rebuild` — rebuild bounded relationship suggestions
- `GET /api/v1/relationships/{relationship_id}` — retrieve relationship details
- `POST /api/v1/ask` — answer a question with evidence from indexed documents
- `POST /api/v1/documents/{id}/ask` — answer scoped to one document and optional related documents
- `GET /api/v1/ask/status` — mode, selected provider, and provider availability
- `POST /api/v1/ask/mode` — switch between `private` and `assisted`
- `POST /api/v1/ask/prepare` — prepare assisted excerpts without sending them
- `POST /api/v1/ask/confirm` — approve and send one prepared request
- `POST /api/v1/ask/cancel?request_id=...` — cancel one prepared request
- `POST /api/v1/ask/revoke-consent` — cancel all prepared requests

## Android client

The Flutter app lives in `mobile/`. It uses the backend for every document operation and never contacts an AI provider directly. Home, Documents/Search/Connections, Ask LORE, document details and original viewer, import, app lock/pairing, and Settings are implemented against the endpoints above.

On launch the app pairs (first run) or asks for device authentication. The stored token is read only after the app is locked, and it is installed into the API client only after device authentication succeeds. Home and Documents open the original document: PDFs use an integrated scroll/zoom viewer with page controls, images are zoomable, and UTF-8 text is shown read-only. Missing, corrupted, unsupported, offline, and loading states are explicit; extracted text is never substituted for a PDF or image.

```powershell
cd mobile
flutter pub get
flutter run --dart-define=LORE_API_BASE_URL=http://10.0.2.2:8000
```

- **Emulator (default, safe).** `10.0.2.2` is the Android emulator's alias for the host machine and matches the default `http://10.0.2.2:8000` base URL. The backend can keep its loopback bind.
- **Trusted LAN (development only).** For a physical device on the same network, pass your computer's LAN address, start the backend with `python -m uvicorn app.main:app --host 0.0.0.0 --port 8000`, and allow it through the local firewall. Bearer tokens on plain HTTP can be observed by other devices on that network; do not use this on public Wi-Fi or expose the backend to the internet.
- **Public HTTPS.** Release builds block cleartext HTTP, so point `LORE_API_BASE_URL` at an `https://` reverse proxy as described in [Network exposure and HTTPS](#network-exposure-and-https). LORE does not ship TLS termination itself.
- The manifest requests `INTERNET`, `USE_BIOMETRIC`, and `USE_FINGERPRINT`. `MainActivity` extends `FlutterFragmentActivity` and sets `FLAG_SECURE`. Cleartext HTTP is enabled only in the debug manifest; release builds keep cleartext blocked.
- Pair the app using `data/pairing-code.txt` on the backend. The file is deleted after pairing and regenerated after logout, revocation, expiry of all sessions, or `python -m app.recovery`.
- Ask conversations are held in memory for the session only. The viewer holds a downloaded original in memory for display and does not persist it on the phone; the app does not download or run a model.

## Test

Backend:

```powershell
python -m pytest
python -m compileall -q app tests
python -m pip check
```

Mobile:

```powershell
cd mobile
dart format .
flutter analyze
flutter test
```

The backend tests use temporary SQLite databases and do not access or modify your normal local data. They cover PDF/TXT/image validation and extraction, classification across all categories, metadata/date extraction, offline behavior, organization filtering and updates, bounded reclassification, legacy SQLite upgrades, portable search/ranking/filters/index repair, relationship evidence and limits, Ask evidence and provider selection, assisted prepare/confirm/cancel safeguards, type/size rejection, duplicate detection, download, retry, and deletion.

PostgreSQL integration tests are opt-in and create disposable databases. Point `LORE_TEST_POSTGRES_URL` at an administrative connection:

```powershell
$env:LORE_TEST_POSTGRES_URL = "postgresql://postgres:replace-me@127.0.0.1:5432/postgres"
python -m pytest -q
```

The PostgreSQL tests cover fresh migrations, the `tsvector`/GIN schema, search ranking and snippets, category filters, malformed queries, extraction failure, relationship rebuild/deletion, migration downgrade/upgrade, the verified SQLite transfer, and legacy pre-Alembic snapshot adoption. They never touch the live SQLite database or its document directory.

They also cover the authentication boundary: every private endpoint rejects missing, malformed, Basic-auth, expired, logged-out, and revoked tokens; pairing hashes tokens and removes the one-time code; expired codes rotate; pairing failures are rate limited with a persisted, restart-resistant, progressive lockout that is capped and cleared on success; pairing codes and tokens never appear in logs; downloads return the unchanged original; storage path traversal is rejected; and documents created before authentication was enabled remain accessible after pairing. Recovery tests cover active, expired, and already-revoked sessions, confirm that documents and stored files survive, and confirm that operator recovery clears a pairing lockout.

Account tests cover email normalization, duplicate rejection, Argon2id hashing and malformed-hash handling, password bounds, owner creation and single-owner enforcement, invitation hashing, expiry, revocation, email binding, atomic single-use redemption, safe duplicate-email handling, owner CLI initialization and invitation creation, session-to-user association, disabled-account rejection, per-account revocation, legacy pairing survival, migration upgrade/downgrade round trips, idempotent adoption of a pre-Alembic SQLite database with unchanged document bytes, startup refusal against an unmigrated database, and the absence of public registration/login routes.

The mobile tests use `MockClient` and never contact a real backend. They cover API paths, bearer headers, pairing, session validation and 401 handling, error mapping, response parsing, private-mode extraction, the assisted approval/rejection workflow, honest empty-evidence handling, Home/Documents/Ask/Settings rendering, search, offline state, locked start, failed and successful authentication, pairing before content, background relock, and PDF/image/text/unsupported/missing original viewer states. Session-lifecycle tests confirm that a stored token is not installed before device authentication, a revoked token cannot be revived, logout clears local credentials and distinguishes an unconfirmed server-side revocation, and locking keeps the token out of memory while preserving the stored credential for the next unlock.
