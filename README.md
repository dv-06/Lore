# LORE backend

LORE is a privacy-first, API-first backend for a future personal document app. This MVP provides FastAPI endpoints, local SQLite persistence, local document upload/extraction, and deterministic document organization. It does not include AI functionality.

## Requirements

- Windows with Python 3.12

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

Data remains on the machine by default. The default database and document directory are excluded from version control; if you configure custom paths inside the repository, exclude those paths too. Do not point either setting at a shared or public location unless that is intentional. Document bytes and extracted text are never sent to an external service. The metadata API does not return extracted text. Bind the development server to loopback and do not expose this unauthenticated MVP to an untrusted network.

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

## Run

```powershell
python -m uvicorn app.main:app --reload
```

The service listens on `http://127.0.0.1:8000` by default. Interactive API documentation is available at `/docs`.

## API

- `GET /` — API name, version, and basic service status
- `GET /api/v1/system/status` — service and SQLite connectivity status
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

## Test

```powershell
python -m pytest
```

The tests use temporary SQLite databases and do not access or modify your normal local data. They cover PDF/TXT/image validation and extraction, classification across all categories, metadata/date extraction, offline behavior, organization filtering and updates, bounded reclassification, legacy SQLite upgrades, FTS search/ranking/filters/index repair, relationship evidence and limits, type/size rejection, duplicate detection, download, retry, and deletion.
