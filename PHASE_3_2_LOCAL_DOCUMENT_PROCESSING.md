# Phase 3.2 — Offline Local Document Processing

Status: implementation complete for PDF text, TXT, image OCR, scanned-PDF OCR,
metadata extraction, local `rules-v1` classification, and persistent processing
status/retry handling.

All extraction and classification runs inside the Android app process on the
device. No processing path constructs an HTTP request, and no document or
extracted text leaves the device during processing.

This document states explicitly which claims were verified and where. Emulator
validation is **not** physical ARM-device validation.

---

## 1. Architecture

### Composition root

`LocalStorage` ([mobile/lib/data/local/local_storage.dart](file:///D:/Dishanth-Project/Lore/mobile/lib/data/local/local_storage.dart))
is still the only entry point into the local layer and is still **not wired
into the app shell**. It now constructs:

```
LocalStorage.open()
 ├── LocalStoragePaths.forApplication()       app-private root
 ├── LoreDatabase.openFile()                  SQLite schema v2 (Drift)
 ├── DriftDocumentRepository
 ├── IoDocumentFileStore
 ├── DriftLocalSearchRepository               FTS5 (Phase 3.1)
 ├── MlKitOcrEngine            (or injected OcrEngine)
 ├── PdfRuntime                (or injected PdfRuntime)
 ├── DocumentProcessor
 │    ├── TextFileExtractor
 │    ├── PdfTextExtractor
 │    ├── ImageOcrExtractor
 │    ├── ScannedPdfProcessor
 │    ├── MetadataExtractor
 │    └── DocumentClassifier   (Dart port of rules-v1)
 ├── ProcessingQueue
 ├── DocumentImportCoordinator (optional onImported hook)
 └── processor.recoverInterrupted()           open-time crash recovery
```

`LocalStorage.open` also forces the lazy SQLite connection (`SELECT 1`) so a
schema failure surfaces at startup rather than on the first user action.
`close()` cancels the queue, closes the ML Kit recognizer, then closes the
database.

New public API on `LocalStorage`:

| Method | Purpose |
| --- | --- |
| `processDocument(id)` | Enqueue one document; resolves with its outcome |
| `processPending({limit})` | Enqueue the oldest pending documents |
| `recoverInterrupted()` | Re-queue rows stranded in `processing` |
| `diagnostics()` | Unchanged Phase 3.1 diagnostics |

Auto-processing is opt-in: `autoProcessImports` defaults to `false`, so the
Phase 3.1 import behavior (insert only) is preserved unless a caller asks for
the new queue hook. This kept `local_storage_test`'s Phase 3.1 expectations
valid and avoided changing UI behavior.

### Processing modules

| File | Responsibility |
| --- | --- |
| `processing/extraction_types.dart` | Cancellation signal, failure kinds, `ExtractionOutcome` |
| `processing/text_file_extractor.dart` | UTF-8 TXT decoding and limits |
| `processing/pdf_text_extractor.dart` | pdfrx text-layer extraction, page count, PDF failure mapping |
| `processing/ocr_engine.dart` | `OcrEngine` interface, ML Kit Latin implementation, text normalization |
| `processing/image_ocr_extractor.dart` | Image OCR with rotation fallback |
| `processing/scanned_pdf_processor.dart` | Render pages with pdfrx, OCR each render, clean temp files |
| `processing/metadata_extractor.dart` | Filesystem modification time |
| `processing/document_classifier.dart` | Deterministic 11-category `rules-v1` port |
| `processing/document_processor.dart` | Claim, dispatch, classify, persist, recover |
| `processing/processing_queue.dart` | Serialized in-process queue with coalescing |

### Deliberate non-goals

No background-work framework (WorkManager/isolate pool) was introduced. The
queue is in-memory and serialized to bound peak memory (OCR renders and PDF
bitmaps are the expensive allocations). Persistence lives in the database, so
process death is recoverable without a scheduler.

---

## 2. Dependencies and compatibility

### New runtime dependencies (`mobile/pubspec.yaml`)

| Package | Resolved | Why |
| --- | --- | --- |
| `google_mlkit_text_recognition` | 0.16.0 | On-device Latin OCR, bundled model |
| `image` | 4.12.0 | Re-encode pdfrx BGRA page renders to PNG; rotate images for retry |

### New dev dependencies

| Package | Resolved | Why |
| --- | --- | --- |
| `integration_test` | Flutter SDK | Release-mode on-device probe |
| `sqlite3` | 3.5.2 | Build a genuine schema-v1 database in the migration test |

Everything else (`drift` 2.34.4, `pdfrx` 2.4.7, `pdfrx_engine` 0.4.5,
`path_provider` 2.1.6, `crypto`, `uuid`, `path`) was already present.

### Android dependency chain (verified from the Gradle graph)

```
google_mlkit_text_recognition:0.16.0
 ├── com.google.mlkit:text-recognition:16.0.1
 └── com.google.mlkit:text-recognition-bundled-common:17.0.0
```

The `text-recognition` artifact (not `text-recognition-play-services`) is the
bundled variant. Inference does not require Google Play Services and does not
download a model.

### Release/R8

`google_mlkit_text_recognition` references script-specific recognizers that are
not packaged (the app requests `TextRecognitionScript.latin`). R8 initially
failed on the missing Chinese, Devanagari, Japanese, and Korean classes. Added
`mobile/android/app/proguard-rules.pro` with four `-dontwarn` rules and wired
`proguardFiles(...)` into the release build type. This suppresses unreachable
references only; no behavior is removed.

- Verified: `flutter build apk --release` succeeds (103.6 MB APK).
- Verified: release APK contains
  `assets/mlkit-google-ocr-models/**` and
  `lib/{arm64-v8a,armeabi-v7a,x86_64}/libmlkit_google_ocr_pipeline.so`.
- Not verified: R8 behavior on a physical ARM device (no device available).

The release build still uses the debug signing config, which is unchanged from
the pre-existing project configuration. This is suitable for internal testing
only.

### Platform compatibility

- Android `minSdk` 24, `targetSdk`/`compileSdk` from Flutter (36).
- `MlKitOcrEngine.isAvailable` is true only on Android/iOS; on other platforms
  a `DisabledOcrEngine` is injected in tests, so the pipeline degrades instead
  of crashing.
- Host (Windows) tests can exercise PDF extraction because pdfrx ships a host
  PDFium build; OCR itself is faked in host tests.

---

## 3. PDF text extraction approach

`PdfTextExtractor` uses pdfrx/PDFium (`PdfDocument.openFile`):

1. Ensure `PdfRuntime.ensureInitialized()` ran once (`pdfrxFlutterInitialize`
   in the app; a no-op or `pdfrxInitialize` in tests).
2. Open the file, iterate `document.pages`, call `page.loadText()`.
3. Join pages with `"\n\f\n"` (form feed) so page boundaries survive.
4. Record `pageCount` from the document.
5. Stop and mark the result partial when accumulated text reaches
   `maxCharacters` (1,000,000).
6. A single unreadable page is recorded as a warning; other pages are kept.
7. Empty text with no page failures returns a partial outcome with
   "No selectable text was found in this PDF." rather than an error, which
   signals the processor to try scanned-PDF OCR.

Failure mapping:

| Condition | Exception | Processor result |
| --- | --- | --- |
| Password/encryption (`PdfPasswordException`) | `malformedDocument` | `failed` / `failed`, text preserved |
| PDFium parse error (`PdfException`) | `malformedDocument` | `failed` / `failed`, text preserved |
| Cancelled between pages | `ProcessingCancelledException` | `pending`, text preserved |
| Every page unreadable | `malformedDocument` | `failed` / `failed` |

Verified (host tests, real PDFium): selectable text, blank PDF, image-only PDF,
malformed PDF, encrypted PDF, cancellation, character-limit truncation.
Verified (release emulator probe): a 2-page selectable PDF produced 206 chars,
`method=pdf_text`, and an FTS hit for "premium".

No PDF document-information dictionary (Title/Author/Subject/CreationDate) is
read; see §6.

---

## 4. TXT extraction approach

`TextFileExtractor`:

1. Reject files over `maxBytes` (20 MB) as `unsupportedFormat`.
2. Reject files containing a NUL byte as `malformedDocument` (binary data).
3. Strict `utf8.decode`; a `FormatException` becomes a failure with
   "Text documents must use UTF-8 encoding."
4. Strip a single leading U+FEFF BOM.
5. Empty/whitespace-only text succeeds but is flagged partial with
   "The text file is empty or contains only whitespace."
6. Truncate at `maxCharacters` (1,000,000) and flag partial.
7. Method string: `plain_text`.

Verified (host tests): UTF-8 extraction, BOM, CRLF, empty, whitespace-only,
invalid UTF-8, NUL bytes, size limit, character truncation, cancellation.
Verified (release emulator probe): 85-character TXT completed with
`method=plain_text`.

---

## 5. OCR, scanned PDFs, and offline guarantees

### Engine

`MlKitOcrEngine` wraps `TextRecognizer(script: TextRecognitionScript.latin)`,
created lazily, closed when `LocalStorage.close()` runs. Results are normalized
(CRLF → LF, trailing spaces removed, trimmed).

### Images

`ImageOcrExtractor`:

1. Fail with `OcrUnavailableException` when the platform has no OCR engine.
2. Run recognition on the original file.
3. If the alphanumeric score is below 8, decode with `image`, try 90°/180°/270°
   rotations (skipped above 40,000,000 pixels), OCR each, and keep the highest
   score.
4. Delete every temporary rotation render in `finally`.
5. Empty text is partial, not a hard failure; truncate at 1,000,000 chars.
6. Method string: `image_ocr`.

### Scanned PDFs

Triggered only when PDF text extraction produced no text. `ScannedPdfProcessor`:

1. Open the PDF with pdfrx.
2. Render up to `maxPages` (50) at `renderScale` 2.0, capped at 8,000,000
   rendered pixels per page.
3. Convert the BGRA `PdfImage` to PNG with `image`, write to the app-private
   `processing/` directory, OCR, then delete the temp file in `finally`.
4. Join page text with `"\n\f\n"`; truncate at 1,000,000 chars with a warning.
5. Fail (not partial) when rendering succeeded but nothing was recognized and
   warnings exist; return partial "no text" when the OCR simply found nothing.
6. Re-throw `OcrUnavailableException` and cancellation; other per-page errors
   become warnings.
7. Method string: `pdf_ocr`.

### Offline guarantee

Claim: OCR inference uses models that ship inside the APK.

Verified by APK inspection of the built release artifact:

```
assets/mlkit-google-ocr-models/gocr/... (Latn_ctc models, tflite_langid)
assets/mlkit-google-ocr-models/taser/... (detector/segmenter models)
lib/arm64-v8a/libmlkit_google_ocr_pipeline.so
lib/armeabi-v7a/libmlkit_google_ocr_pipeline.so
lib/x86_64/libmlkit_google_ocr_pipeline.so
```

Verified by runtime probe with networking disabled (see §11): OCR succeeded
for an image and for a rendered scanned PDF while Wi-Fi and mobile data were
off and the host was unreachable. No Dart HTTP request was observed.

**Important limitation:** this proves no model download and no Dart-level
network access. It does **not** prove that the ML Kit native SDK emits no
telemetry through its own channel. ML Kit is a Google SDK and may collect
usage/diagnostics subject to Google's policies; that behavior was not audited
or disabled in this phase. Dart's `HttpOverrides` cannot observe native
traffic. If zero third-party telemetry is a requirement, this must be
addressed (for example by an SDK audit, a network-security policy, or replacing
the OCR engine).

---

## 6. Metadata extraction

Stored per document after processing:

| Field | Source | Notes |
| --- | --- | --- |
| `page_count` | pdfrx page list | PDFs only |
| `source_modified_at` | `File.stat().modified` | The one reliable filesystem timestamp |
| `document_title` | classifier | Derived from filename/first line, **not** PDF metadata |
| `document_type` | classifier | e.g. invoice, receipt, letter |
| `document_date` | classifier | First valid date in extracted text, stored `YYYY-MM-DD` |
| `issuer` | classifier | Issuer/organization line heuristic |
| `reference_number` | classifier | Reference/account/invoice number heuristic |
| `category`, `tags`, `confidence`, `reasons`, `version` | classifier | §7 |
| `extraction_method` | extractor | `plain_text` / `pdf_text` / `image_ocr` / `pdf_ocr` |
| `extraction_error`, `processing_error` | pipeline | Human-readable, shown to caller |

Deliberately **not** extracted:

- PDF Info dictionary (Title, Author, Subject, CreationDate). pdfrx exposes no
  public metadata API for these fields; only page text and rendering are used.
  This is an API limitation, not a decision to ignore metadata.
- EXIF from images. Not read.
- Filesystem "creation" time. During implementation `FileStat.changed` was
  briefly stored as `source_created_at`. On Android that value is the inode
  change time, not a creation time, so the column and its writes were removed
  before shipping and the migration test asserts the column does not exist.
  No released database ever contained it.

Verified (host tests): page counts, selectable-PDF metadata path, scanned-PDF
status. Verified (release probe): page counts `pages=2` for the selectable PDF.

---

## 7. Classifier parity

The Dart classifier is a direct port of the unchanged Python
`app/services/organization.py` `rules-v1` implementation. The Python code was
not modified.

- 11 categories in fixed order: Finance, Education, Health, Identity, Home,
  Appliances, Insurance, Travel, Work, Legal, Uncategorized.
- Case-insensitive, Unicode-aware whole-term matching with
  `(?<![\p{L}\p{N}_])term(?![\p{L}\p{N}_])`.
- Score = min(6, matched terms); category = first category in list order with
  the maximum score (stable tie-break).
- Confidence = min(0.95, 0.55 + 0.1 × score); Uncategorized = 0.
- Reasons: up to three "Matched 'term'" entries, plus the tie-break reason when
  more than one category scored.
- Existing tags are preserved, category and document type are inserted at most
  once, capped at 20 tags.
- Method string: `rules-v1`.

Parity harness:

- `mobile/tool/generate_classifier_fixtures.py` imports the real Python
  `classify_document` and emits 24 fixtures covering all 11 categories, ties,
  date formats, invalid/valid dates, issuer/reference, existing tags, case
  insensitivity, empty text, and filename fallback.
- `mobile/test/local/document_classifier_test.dart` compares category,
  confidence (1e-12), reasons, method, title, type, date, issuer, reference,
  and tags for every fixture.

Verified: all 24 fixtures match. The Python implementation was not changed.

---

## 8. Database migration

Schema version 1 → 2. Version 1 is the Phase 3.1 schema.

New columns on `documents`:

| Column | Type | Constraint |
| --- | --- | --- |
| `extraction_method` | TEXT | nullable |
| `processing_status` | TEXT NOT NULL DEFAULT `'pending'` | CHECK in (`pending`, `processing`, `completed`, `partially_completed`, `failed`) |
| `processing_error` | TEXT | nullable |
| `processing_started_at` | TEXT | nullable |
| `processing_completed_at` | TEXT | nullable |
| `processing_attempts` | INTEGER NOT NULL DEFAULT 0 | CHECK `>= 0` |
| `source_modified_at` | TEXT | nullable |
| `classification_confidence` | REAL | CHECK NULL or 0.0–1.0 |

Existing columns (`extracted_text`, `extraction_status`, `page_count`,
`document_title`, `category`, tags, `document_type`, `issuer`,
`reference_number`, `document_date`, reasons, `classification_version`,
`is_deleted`, timestamps) are unchanged.

`onUpgrade` uses `migrator.addColumn` for each of the eight columns. SQLite
supports column-level CHECK constraints in `ADD COLUMN`; the new columns have
defaults, so existing rows satisfy them. Table-level constraints and FTS
triggers are untouched. `beforeOpen` then synchronizes metadata rows:

- `schema_meta.local_schema_version = '2'`
- `schema_meta.classifier_version = 'rules-v1'`
- `app_settings.local_storage_phase = '3.2'`
- `app_settings.processing_pipeline_version = '1'`

Fresh creation (`onCreate`) additionally seeds the Phase 3.2 metadata values.

Verified (host test `upgrading a version 1 database adds processing columns`):
a real SQLite file is created from a verbatim v1 DDL dump, `PRAGMA user_version`
is set to 1, a document with extracted text is inserted, then
`LoreDatabase.openFile` is opened. Assertions confirm:

- `schemaVersion == 2` and all eight new columns exist;
- `source_created_at` does **not** exist;
- the existing document's text, `ready` extraction status, `pending`
  processing status, and `0` attempts survive;
- its FTS row still matches a query;
- metadata/settings report 3.2 and pipeline 1.

The v1→v2 migration does not copy server data, does not touch the FastAPI
database, and does not migrate originals. Binary originals remain in the file
store, not in SQLite.

---

## 9. Processing state machine

Two independent fields:

- `extraction_status`: `pending` → `processing` → `ready` | `failed` |
  `unsupported`
- `processing_status`: `pending` → `processing` → `completed` |
  `partially_completed` | `failed`

`processing` is the claim marker. Everything else is terminal until re-queued.

| Event | processing_status | extraction_status | Stored text |
| --- | --- | --- | --- |
| Import | `pending` | `pending` | empty |
| Claim (atomic UPDATE) | `processing`, attempts +1, started_at set | unchanged | unchanged |
| Success | `completed` | `ready` | new text |
| Partial success (truncation, empty OCR, unreadable page) | `partially_completed` | `ready` | new text + warning in `processing_error` |
| Unsupported type or unavailable OCR capability | `partially_completed` | `unsupported` | previous text preserved |
| Malformed/encrypted/encoding/filesystem failure | `failed` | `failed` | previous text preserved |
| Cancellation | `pending` | previous | previous text preserved |
| Stale recovery | `pending` | unchanged | unchanged |
| Missing original | `failed` | `failed` | previous text preserved |

Important semantics:

- Losing a claim race is an error (`ProcessingInProgressException`) and does not
  modify the row; the losing caller cannot overwrite the winner.
- Failure never clears an earlier usable result. `_preservingUpdate` copies
  extracted text, classification, tags, title, type, issuer, reference, date,
  and page count from the prior row.
- A successful re-run that yields no text also keeps the prior text (and skips
  reclassification) instead of replacing it with an empty string.
- `unsupported` is a capability statement, not a document failure, so it maps to
  `partially_completed` rather than `failed`.
- Classification only runs when new text exists; a failure does not attempt to
  re-derive or erase metadata.

---

## 10. Retry and recovery

### Atomic claim

`DriftDocumentRepository.tryClaimForProcessing` performs one raw UPDATE:

```sql
UPDATE documents
SET processing_status = 'processing',
    processing_started_at = ?,
    processing_attempts = processing_attempts + 1,
    processing_error = NULL,
    updated_at = ?
WHERE id = ?
  AND is_deleted = 0
  AND (processing_status <> 'processing'
       OR processing_started_at IS NULL
       OR processing_started_at <= ?)
```

Only one caller can observe `changed == 1`. Stale claims older than
`staleAfter` (15 minutes) can be reclaimed; live claims cannot.

### Crash recovery

Two layers:

1. `LocalStorage.open()` always calls `processor.recoverInterrupted()`, which
   resets rows that are still `processing` and started before the stale window
   to `pending` with "Processing was interrupted and is ready to retry."
2. `LocalStorage.recoverInterrupted()` can be called again at runtime.

A crash cannot leave a document permanently `processing`: the row either
becomes retryable after 15 minutes or is reset at the next open. The trade-off
is that a genuinely long OCR job (over 15 minutes) could be pre-empted by
another claim; the default is intentionally conservative and configurable on
`DocumentProcessor`.

### Retry

There is no automatic exponential backoff and no attempt cap. Retry is an
explicit `processDocument` / `processPending` call (or automatic for imports
when a caller enables `autoProcessImports`). `processing_attempts` records how
many claims occurred, including failed and cancelled attempts, so a future UI
can surface repeated failures.

### Cancellation

`CancellationSignal` is checked before/after each expensive step and between
pages. Cancelling an active run marks the row `pending` and preserves prior
text. Cancelling a queued (not started) run completes the caller with
`pending` and never touches the row. `cancelAll()` cancels queued and active
work and waits for the drain loop to exit before `close()` returns.

### Queue behavior

- One document at a time, FIFO.
- Duplicate enqueues for the same ID share one future.
- `enqueuePending` reads the oldest pending rows (`maxPending = 25`) and awaits
  all of them; execution is still serialized.
- Exceptions are converted into `failed` outcomes for the caller; the processor
  itself persists the real status.

Verified (host tests): double claim, stale vs live claim, interrupted-row
recovery with text retention, open-time recovery, active cancellation, queued
cancellation, duplicate coalescing, ordering, and auto-processing.

---

## 11. Tests and Android verification

Test environment: Windows 10 x64 host, Flutter 3.41.4 stable, Dart 3.11.1.

### Host test suite

`flutter test` → **149 tests passed, 0 failed**.

Phase 3.2-specific tests (86 of the 149):

| File | Tests |
| --- | --- |
| `test/local/document_classifier_test.dart` | 3 |
| `test/local/text_file_extractor_test.dart` | 10 |
| `test/local/pdf_text_extractor_test.dart` | 7 |
| `test/local/image_ocr_extractor_test.dart` | 8 |
| `test/local/scanned_pdf_processor_test.dart` | 6 |
| `test/local/document_processor_test.dart` | 17 |
| `test/local/local_database_test.dart` | 17 (incl. v1→v2 migration) |
| `test/local/document_file_store_test.dart` | 16 (Phase 3.1) |
| `test/local/local_storage_test.dart` | 2 (Phase 3.1) |

The remaining 63 tests are the pre-existing widget/auth suites, which continue
to pass.

Static analysis: `flutter analyze` → **No issues found**.

PDF tests use real PDFium on the host. OCR is faked with `FakeOcrEngine` for
host tests; the real ML Kit engine is only exercised on Android.

### Android release validation

Device: `sdk_gphone64_x86_64`, Android 16 (API 36), x86_64 **emulator**.
**No physical ARM device was connected. Physical ARM validation has not been
performed.**

Release build:

```
flutter build apk --release
→ build/app/outputs/flutter-apk/app-release.apk (103.6 MB)
```

Release-mode on-device probe: because `flutter drive` does not support
`--release` (and the profile driver failed to connect), a release entrypoint
(`integration_test/release_probe_main.dart`) was built as a release APK with the
same `LocalStorage` code. It imported seven fixtures, processed them, and wrote
results to logcat. Wi-Fi and mobile data were disabled; the host was
unreachable. All 13 checks passed:

```
ocr_engine            PASS engine=MlKitOcrEngine available=true
txt                   PASS status=completed method=plain_text textLength=85
pdf_text              PASS status=completed method=pdf_text pages=2 textLength=206
pdf_search            PASS fts hit for premium
pdf_original_unchanged PASS stored bytes match the imported bytes
pdf_ocr               PASS status=completed method=pdf_ocr textLength=97
scanned_original_unchanged PASS stored bytes match the imported bytes
image_ocr             PASS status=completed method=image_ocr
rotated_ocr           PASS status=completed rotation recognized
encrypted_pdf         PASS status=failed error=password-protected
malformed_pdf         PASS status=failed error=FPDF_ERR_FORMAT: 3
diagnostics           PASS schema=2 fts5=true documents=7 indexed=7
no_dart_http          PASS no Dart HTTP requests
LORE_PROBE_DONE PASS checks=13 failures=0
```

The probe also measured roughly 282–305 MB of process RSS on the x86_64
emulator across runs. This is not a performance certification; no ARM figures
exist.

After the probe, the **normal** release APK (no probe entrypoint) was rebuilt
and reinstalled. The process starts, `MainActivity` is resumed, and there is no
crash in logcat.

Visual UI verification of the normal app on this emulator was **not possible**:
the app window returned an all-black frame, and the same is true for the
pre-Phase-3.2 baseline debug APK built on 2026-11-02. Because that baseline
contains none of this phase's code, the black frame is attributed to the
emulator/GPU environment, not to Phase 3.2. This still means end-to-end UI
behavior was not visually confirmed in this phase.

Verified on emulator only:

- ML Kit bundled OCR availability and recognition.
- PDF text extraction and scanned-PDF rendering/OCR.
- Classification metadata written into SQLite.
- FTS indexing of new text.
- Original file bytes unchanged.
- No Dart HTTP requests during processing.

Not verified anywhere:

- Physical ARM device performance, memory, or OCR quality.
- UI integration (none exists yet; `LocalStorage` is not wired into screens).
- Behavior under Android background restrictions (the queue is foreground-only).

---

## 12. Privacy and networking

- All file paths are under `getApplicationSupportDirectory()/lore_local`
  (app-private internal storage). No shared-storage or SAF permission is used.
- Originals are copied into the store; the source file is never modified.
  The probe re-hashed both imported originals and confirmed they were unchanged.
- Processing constructs no `HttpClient`, `http` request, or socket.
- The probe installed `HttpOverrides` with a recording client that fails on any
  request; zero requests were recorded and processing still completed,
  including OCR.
- OCR models are packaged in the APK.
- The FastAPI backend, server database, and server-side documents are untouched
  by this phase. Processing never calls the backend.
- Extracted text is stored in SQLite (plaintext, app-private). FTS5 indexes it
  for Phase 3.1 search. No SQLCipher was added (out of scope).
- Telemetry caveat for the native ML Kit SDK is stated in §5 and §13.

Protected-state verification at completion:

- Git branch `main`, HEAD `4a16e9516685cee03cdbc659fb246e1c6b0847d8` (unchanged).
- Server DB SHA-256 `3223c49416484cd0226ba414dd5fe449eedbb2f2ec5e0ef9de1abef10d75b25e`
  (unchanged).
- Protected PDF SHA-256 `4269be1ca668bde90badb1c177e34038e7489f64b174e4221024fb7d667b7d82`
  (unchanged, 601 bytes).
- No commit, reset, checkout, stash, clean, or push was performed.
- Pre-existing modified and untracked files were preserved. The only tracked
  file newly modified by this phase is
  `mobile/android/app/build.gradle.kts` (proguard wiring); `pubspec.yaml` and
  `pubspec.lock` already carried Phase 3.1 changes and gained the new
  dependencies in place. All backend changes predate Phase 3.2 (latest backend
  mtime 2026-11-03 20:19, before this phase began).

---

## 13. Known limitations

1. **No physical ARM testing.** All Android validation is x86_64 emulator.
   ARM library packaging is verified by APK inspection, not execution.
2. **No UI integration.** `LocalStorage` is not referenced by the app shell;
   there is no import trigger, progress indicator, retry button, or status
   display wired to screens.
3. **ML Kit telemetry not audited.** Models are bundled and no download occurs,
   but native SDK telemetry was not observed or disabled.
4. **Latin script only.** `TextRecognitionScript.latin`; other scripts would
   require additional bundled recognizers and APK size.
5. **No PDF document metadata.** pdfrx does not expose Title/Author/Subject/
   CreationDate; only text, page count, and rendering are available.
6. **No EXIF or authored dates.** `source_modified_at` is filesystem
   modification time, not an authored date. Creation time was removed as
   unreliable on Android.
7. **TXT must be UTF-8.** Legacy encodings fail explicitly; no charset
   detection.
8. **Mixed PDFs use the text layer only.** If any page has selectable text, the
   document is not OCR'd; image-only pages inside an otherwise selectable PDF
   are not recognized. This avoids double work but can miss content.
9. **OCR heuristics are basic.** Rotation retry triggers only when the initial
   alphanumeric score is below 8; there is no deskew, denoise, contrast
   enhancement, or language detection beyond the fixed Latin model.
10. **Limits:** 20 MB import, 1,000,000 characters per document, 50 OCR pages
    per scanned PDF, 8,000,000 rendered pixels per PDF page, 40,000,000 pixels
    for image rotation.
11. **Stale-window trade-off:** a legitimate run over 15 minutes can be
    reclaimed by another claim.
12. **Foreground-only queue.** Android may kill the process; recovery happens at
    next open, not in the background.
13. **No attempt cap/backoff.** Repeated manual retries are unbounded, though
    counted.
14. **Debug signing on release.** Pre-existing project configuration; not
    suitable for distribution.
15. **Search behavior is Phase 3.1/3.3.** Extraction writes to FTS, but no
    search UI or ranking changes were made here.

---

## 14. Recommended Phase 3.3 scope

1. **Wire `LocalStorage` into the app**: initialize at startup, import from the
   existing file picker, expose processing progress and per-document status.
2. **Local search UI** backed by the existing FTS5 index: query, ranking,
   highlights, and empty/error states, all offline.
3. **Reprocessing and retry controls**: manual "reprocess", surfaced failure
   reasons, attempt counts, and a batch "process pending" action.
4. **Startup batch processing**: call `processPending()` when the app opens,
   with a visible queue indicator.
5. **Physical ARM validation**: install the release APK on at least one arm64
   device, measure OCR time/memory on a realistic scan, and confirm bundled
   models load without network.
6. **Telemetry decision**: explicitly accept, document, or reduce ML Kit's
   native telemetry before making a zero-network privacy claim in user-facing
   copy.
7. **OCR quality work**: test a corpus of real receipts/scans, tune the rotation
   heuristic, and evaluate whether mixed-PDF page-level OCR is worth the cost.
8. **Encoding support**: optional BOM/charset detection for common legacy text
   files.
9. **Search after processing**: ensure newly processed text is searchable in the
   same session and after restart, including rebuild behavior.
10. **Instrumentation**: persist timing and failure-kind counters locally for
    diagnostics (still on-device).

Do not begin any of the above until Phase 3.3 is explicitly requested.
