import 'dart:async';
import 'dart:io';

import 'document_file_store.dart';
import 'document_import_coordinator.dart';
import 'document_repository.dart';
import 'local_database.dart';
import 'local_models.dart';
import 'local_search_repository.dart';
import 'local_storage_paths.dart';
import 'processing/document_processor.dart';
import 'processing/image_ocr_extractor.dart';
import 'processing/metadata_extractor.dart';
import 'processing/ocr_engine.dart';
import 'processing/pdf_text_extractor.dart';
import 'processing/processing_queue.dart';
import 'processing/scanned_pdf_processor.dart';
import 'processing/text_file_extractor.dart';
import 'relationship_repository.dart';

/// Composition root for the local-first storage layer.
///
/// This is intentionally not wired into the app shell yet. It exposes the
/// storage contracts without changing any existing server-backed behavior.
class LocalStorage {
  LocalStorage._({
    required this.paths,
    required this.database,
    required this.documents,
    required this.fileStore,
    required this.imports,
    required this.search,
    required this.relationships,
    required this.processing,
    required this.processingQueue,
    required this.ocrEngine,
  });

  final LocalStoragePaths paths;
  final LoreDatabase database;
  final DocumentRepository documents;
  final DocumentFileStore fileStore;
  final DocumentImportCoordinator imports;
  final LocalSearchRepository search;
  final RelationshipRepository relationships;
  final DocumentProcessor processing;
  final ProcessingQueue processingQueue;
  final OcrEngine ocrEngine;

  static Future<LocalStorage> open({
    LocalStoragePaths? paths,
    String Function()? idGenerator,
    DateTime Function()? clock,
    int maxImportBytes = 20 * 1024 * 1024,
    OcrEngine? ocrEngine,
    PdfRuntime? pdfRuntime,
    bool autoProcessImports = false,
  }) async {
    final resolvedPaths = paths ?? await LocalStoragePaths.forApplication();
    await resolvedPaths.ensureDirectories();

    final database = LoreDatabase.openFile(File(resolvedPaths.databaseFile));
    try {
      // Force the lazily-opened connection so schema creation errors surface
      // at startup instead of on the first user action.
      await database.customSelect('SELECT 1').getSingle();
    } catch (_) {
      await database.close();
      rethrow;
    }

    final documents = DriftDocumentRepository(database);
    final fileStore = IoDocumentFileStore(paths: resolvedPaths);
    final search = DriftLocalSearchRepository(database);

    final engine = ocrEngine ?? MlKitOcrEngine();
    final runtime = pdfRuntime ?? PdfRuntime();
    final processingDirectory = Directory(resolvedPaths.processingDirectory);

    final processor = DocumentProcessor(
      documents: documents,
      fileStore: fileStore,
      textExtractor: const TextFileExtractor(maxCharacters: 1000000),
      pdfExtractor: PdfTextExtractor(runtime: runtime, maxCharacters: 1000000),
      imageOcrExtractor: ImageOcrExtractor(
        ocr: engine,
        processingDirectory: processingDirectory,
        maxCharacters: 1000000,
      ),
      scannedPdfProcessor: ScannedPdfProcessor(
        ocr: engine,
        runtime: runtime,
        processingDirectory: processingDirectory,
        maxCharacters: 1000000,
      ),
      metadataExtractor: const MetadataExtractor(),
      clock: clock,
    );
    final queue = ProcessingQueue(processor: processor);

    // A document left in "processing" by a killed process must become
    // retryable, but only after the stale window has elapsed so a live worker
    // is never pre-empted.
    await processor.recoverInterrupted();

    return LocalStorage._(
      paths: resolvedPaths,
      database: database,
      documents: documents,
      fileStore: fileStore,
      imports: DocumentImportCoordinator(
        documents: documents,
        fileStore: fileStore,
        idGenerator: idGenerator,
        clock: clock,
        maxBytes: maxImportBytes,
        onImported: autoProcessImports
            ? (document) {
                unawaited(queue.enqueue(document.id));
              }
            : null,
      ),
      search: search,
      relationships: DriftRelationshipRepository(database),
      processing: processor,
      processingQueue: queue,
      ocrEngine: engine,
    );
  }

  /// Processes one already-imported document through the local pipeline.
  Future<ProcessingOutcome> processDocument(String documentId) {
    return processingQueue.enqueue(documentId);
  }

  /// Drains the oldest pending documents through the serialized queue.
  Future<List<ProcessingOutcome>> processPending({int? limit}) {
    return processingQueue.enqueuePending(limit: limit);
  }

  /// Re-queues documents whose processing was interrupted by a crash.
  Future<int> recoverInterrupted() => processing.recoverInterrupted();

  Future<LocalStorageDiagnostics> diagnostics() async {
    final version = await database
        .customSelect('SELECT sqlite_version() AS version')
        .getSingle();
    final fts5 = await database
        .customSelect(
          "SELECT sqlite_compileoption_used('ENABLE_FTS5') AS enabled",
        )
        .getSingle();
    final ftsTable = await database
        .customSelect(
          "SELECT name FROM sqlite_master "
          "WHERE type = 'table' AND name = 'document_search'",
        )
        .getSingleOrNull();

    return LocalStorageDiagnostics(
      databasePath: paths.databaseFile,
      schemaVersion: database.schemaVersion,
      sqliteVersion: version.read<String>('version'),
      fts5Compiled: fts5.read<int>('enabled') != 0,
      fts5TablePresent: ftsTable != null,
      documentCount: await documents.countActive(),
      indexedDocumentCount: await search.indexedDocumentCount(),
    );
  }

  Future<void> close() async {
    await processingQueue.cancelAll();
    await ocrEngine.close();
    await database.close();
  }
}
