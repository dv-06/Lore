# LORE

LORE is a privacy-first personal document app. It pairs a FastAPI backend with a Flutter Android client: documents are uploaded to the backend, extracted and indexed locally, organized deterministically, and searched or questioned locally by default. Assisted Mode sends only the excerpts you explicitly approve to the configured external provider, and the optional local LLM path uses `LORE_LOCAL_LLM_ENDPOINT`, which defaults to loopback but can be configured differently.

The backend provides local SQLite persistence, local document upload/extraction, deterministic classification and relationship rules, FTS5 search, and three Ask LORE answer paths:

- **Extractive** — selects a concise answer from indexed document text. This is not generated text.
- **Local LLM** — optional, Ollama-compatible inference that the backend sends to `LORE_LOCAL_LLM_ENDPOINT` (default `http://127.0.0.1:11434`); it never runs on the phone.
- **Assisted** — external inference prepared by the backend, paused for your explicit approval, then confirmed for one request at a time.

## Requirements

- Windows with Python 3.12+
- Flutter 3.41+ / Dart 3.11+ and the Android SDK for the mobile client

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

| Variable | Default | Purpose |
| --- | --- | --- |
| `LORE_APP_NAME` | `LORE` | API title |
| `LORE_DATA_DIR` | `data` | Local data and document storage directory |
| `LORE_DATABASE_PATH` | `data/lore.db` | SQLite database file |
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

The existing SQLite `documents` table is upgraded in place on startup; existing rows and source files are retained. Legacy rows without organization data are not silently reprocessed during migration and appear under `Uncategorized` until classified.

## Search and relationships

Text search uses the local SQLite FTS5 extension when available. The index includes extracted text and searchable metadata (filename, title, category, tags, type, issuer, and reference number); snippets and matching field names are returned instead of a full-text field. Exact filename, reference, and title matches are ranked before weighted FTS relevance. Query input is tokenized into safe Unicode word prefixes before it reaches FTS, so punctuation and FTS operators are never executed as query syntax. Requests are limited to 256 characters, 12 terms, 100 results, and offsets up to 100,000. An empty/punctuation-only query is rejected. If SQLite was built without FTS5, search returns `503` and document upload/metadata APIs remain available; install/use a Python distribution with SQLite FTS5 support to enable it. The local index is initialized and repaired at startup when its row count differs, and can be rebuilt explicitly.

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

The backend rejects confirmation when the question or excerpts changed, when the request expired, or when it was already consumed. `POST /api/v1/ask/cancel?request_id=...` cancels one prepared request and `POST /api/v1/ask/revoke-consent` cancels all of them. Prepared requests and Ask conversations are not written to SQLite; the mobile client also keeps conversations in memory only. External citations are not used as document evidence by the Android client; the app displays the approved excerpts instead. The external API key is read from the environment and is never returned by the API or embedded in the app. `GET /api/v1/ask/status` reports provider availability so the client can show the real state instead of guessing.

Assisted Mode requires a valid absolute `http(s)` `LORE_EXTERNAL_AI_ENDPOINT` and `LORE_EXTERNAL_AI_API_KEY`. `GET /api/v1/ask/status` reports the external provider as unavailable with a reason when that configuration is missing or invalid, and `POST /api/v1/ask/mode` refuses to enable Assisted Mode with HTTP 503 while leaving the previous mode unchanged. Private Mode (the default) never uses the Assisted external provider; it answers with the extractive provider or, when selected, the configured local LLM endpoint. Private Mode inference is only as local as `LORE_LOCAL_LLM_ENDPOINT`: it defaults to loopback but accepts another address, and a loopback-only restriction is not yet implemented.

## Authentication and app lock

LORE uses two independent boundaries:

1. **Android app lock** decides whether private content may be shown on the phone. The app starts locked and unlocks through Android biometrics with the device PIN/pattern/password as fallback. A configurable auto-lock covers immediate, 1 minute, 5 minutes, and 15 minutes after backgrounding; Settings also offers a manual **Lock now** action. Locking removes the token from the API client and clears in-memory documents, searches, status, and conversations. Android `FLAG_SECURE` blocks screenshots and the recent-apps preview.
2. **Backend bearer authentication** protects every document, upload, download, search, relationship, Ask, AI-mode, and Assisted endpoint. Unpaired or revoked clients receive `401` regardless of the local UI state.

Pairing is local and one-time. On first start, or whenever there are no active sessions, the backend creates `data/pairing-code.txt` containing a short-lived code (default 30 minutes). Enter that code in the Android app. Successful pairing returns a 256-bit random session token, stores only its SHA-256 hash in SQLite, and deletes the pairing file. Pairing is refused with `409` while another active session exists. The code and tokens are never written to application logs.

The mobile client stores the session token in Android Keystore-backed encrypted storage (`flutter_secure_storage`), never in plain preferences. Tokens are sent only as `Authorization: Bearer` headers. `POST /api/v1/auth/logout` revokes the current session; `POST /api/v1/auth/revoke-all` revokes every session and returns the backend to pairing-required state. Expired, revoked, malformed, and missing tokens are rejected. There are no hardcoded credentials.

The trust boundary is deliberate: local biometrics cannot protect a network API, and backend authentication cannot prove who is holding the phone. LORE requires both for normal use. If a device has no screen lock configured, the app reports that local confirmation is unavailable and Android cannot raise a prompt; backend authentication still applies. If the stored token is lost while the backend still has an active session (for example after clearing app data), pairing stays disabled until an operator removes that session or calls `revoke-all`. TLS is not built in: use a reverse proxy or trusted local setup, because bearer tokens sent over plain HTTP on a LAN can be observed.

## Run

```powershell
python -m uvicorn app.main:app --reload
```

The service listens on `http://127.0.0.1:8000` by default. On first start, the pairing code is written to `data/pairing-code.txt`. Interactive API documentation is available at `/docs`.

## API

Public endpoints:

- `GET /` — API name, version, and basic service status
- `GET /api/v1/system/status` — service and SQLite connectivity status
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

On launch the app pairs (first run) or asks for device authentication. The token is read from encrypted storage only after the app is already locked, and it is removed from the API client whenever the app locks. Home and Documents open the original document: PDFs use an integrated scroll/zoom viewer with page controls, images are zoomable, and UTF-8 text is shown read-only. Missing, corrupted, unsupported, offline, and loading states are explicit; extracted text is never substituted for a PDF or image.

```powershell
cd mobile
flutter pub get
flutter run --dart-define=LORE_API_BASE_URL=http://10.0.2.2:8000
```

- `10.0.2.2` is the Android emulator's alias for the host machine; it is the default base URL.
- For a physical device on the same trusted network, pass your computer's LAN address, start the backend with `python -m uvicorn app.main:app --host 0.0.0.0 --port 8000`, and allow it through the local firewall. Do not expose the backend to the internet; bearer tokens are not encrypted by the development server.
- The manifest requests `INTERNET`, `USE_BIOMETRIC`, and `USE_FINGERPRINT`. `MainActivity` extends `FlutterFragmentActivity` and sets `FLAG_SECURE`. Cleartext HTTP is enabled only in the debug manifest; release builds keep cleartext blocked, so use HTTPS or a local debug build for development.
- Pair the app using `data/pairing-code.txt` on the backend. The file is deleted after pairing and regenerated after logout, revocation, or expiry of all sessions.
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

The backend tests use temporary SQLite databases and do not access or modify your normal local data. They cover PDF/TXT/image validation and extraction, classification across all categories, metadata/date extraction, offline behavior, organization filtering and updates, bounded reclassification, legacy SQLite upgrades, FTS search/ranking/filters/index repair, relationship evidence and limits, Ask evidence and provider selection, assisted prepare/confirm/cancel safeguards, type/size rejection, duplicate detection, download, retry, and deletion.

They also cover the authentication boundary: every private endpoint rejects missing, malformed, Basic-auth, expired, logged-out, and revoked tokens; pairing hashes tokens and removes the one-time code; expired codes rotate; downloads return the unchanged original; storage path traversal is rejected; and documents created before authentication was enabled remain accessible after pairing.

The mobile tests use `MockClient` and never contact a real backend. They cover API paths, bearer headers, pairing, session validation and 401 handling, error mapping, response parsing, private-mode extraction, the assisted approval/rejection workflow, honest empty-evidence handling, Home/Documents/Ask/Settings rendering, search, offline state, locked start, failed and successful authentication, pairing before content, background relock, and PDF/image/text/unsupported/missing original viewer states.
