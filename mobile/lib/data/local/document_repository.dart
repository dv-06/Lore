import 'package:drift/drift.dart';

import 'local_database.dart';
import 'local_models.dart';

abstract interface class DocumentRepository {
  Future<void> insert(LocalDocument document);

  Future<LocalDocument?> findById(String id);

  Future<LocalDocument?> findBySha256(String sha256);

  Future<List<LocalDocument>> listActive({int limit = 100, int offset = 0});

  Future<List<LocalDocument>> listPending({int limit = 100});

  Future<void> updateExtraction({
    required String documentId,
    required String extractedText,
    required ExtractionStatus status,
    String? error,
    int? pageCount,
    DateTime? updatedAt,
  });

  /// Atomically moves a document into `processing`.
  ///
  /// A document already processing is only reclaimed when its start time is
  /// older than [staleAfter], which recovers crashes without allowing
  /// simultaneous duplicate processing.
  Future<bool> tryClaimForProcessing({
    required String documentId,
    Duration staleAfter = const Duration(minutes: 15),
    DateTime? now,
  });

  Future<void> applyProcessingUpdate({
    required String documentId,
    required ProcessingUpdate update,
    DateTime? updatedAt,
  });

  /// Resets stale `processing` rows so a crash cannot strand a document.
  Future<int> resetStaleProcessing({
    Duration staleAfter = const Duration(minutes: 15),
    DateTime? now,
    String? message,
  });

  Future<void> softDelete(String documentId, {DateTime? deletedAt});

  Future<void> hardDelete(String documentId);

  Future<int> countActive();

  Future<Set<String>> listStoredFilenames({bool includeDeleted = true});
}

class DriftDocumentRepository implements DocumentRepository {
  DriftDocumentRepository(this._database);

  final LoreDatabase _database;

  @override
  Future<void> insert(LocalDocument document) {
    return _database.into(_database.documents).insert(_toCompanion(document));
  }

  @override
  Future<LocalDocument?> findById(String id) async {
    final row = await (_database.select(
      _database.documents,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  @override
  Future<LocalDocument?> findBySha256(String sha256) async {
    final row = await (_database.select(
      _database.documents,
    )..where((table) => table.sha256.equals(sha256))).getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  @override
  Future<List<LocalDocument>> listActive({
    int limit = 100,
    int offset = 0,
  }) async {
    final rows =
        await (_database.select(_database.documents)
              ..where((table) => table.isDeleted.equals(false))
              ..orderBy([(table) => OrderingTerm.desc(table.createdAt)])
              ..limit(limit, offset: offset))
            .get();
    return rows.map(_toDomain).toList(growable: false);
  }

  @override
  Future<List<LocalDocument>> listPending({int limit = 100}) async {
    final rows =
        await (_database.select(_database.documents)
              ..where(
                (table) =>
                    table.isDeleted.equals(false) &
                    table.processingStatus.equals(
                      ProcessingStatus.pending.dbValue,
                    ),
              )
              ..orderBy([(table) => OrderingTerm.asc(table.createdAt)])
              ..limit(limit))
            .get();
    return rows.map(_toDomain).toList(growable: false);
  }

  @override
  Future<void> updateExtraction({
    required String documentId,
    required String extractedText,
    required ExtractionStatus status,
    String? error,
    int? pageCount,
    DateTime? updatedAt,
  }) async {
    final timestamp = (updatedAt ?? DateTime.now()).toUtc().toIso8601String();
    final changed =
        await (_database.update(
          _database.documents,
        )..where((table) => table.id.equals(documentId))).write(
          DocumentsCompanion(
            extractedText: Value(extractedText),
            extractionStatus: Value(status.name),
            extractionError: Value(error),
            pageCount: Value(pageCount),
            updatedAt: Value(timestamp),
          ),
        );
    if (changed == 0) {
      throw LocalStorageException('Document $documentId was not found.');
    }
  }

  @override
  Future<bool> tryClaimForProcessing({
    required String documentId,
    Duration staleAfter = const Duration(minutes: 15),
    DateTime? now,
  }) async {
    final timestamp = (now ?? DateTime.now()).toUtc();
    final staleBefore = timestamp.subtract(staleAfter).toIso8601String();
    final changed = await _database.customUpdate(
      '''
      UPDATE documents
      SET processing_status = ?,
          processing_started_at = ?,
          processing_attempts = processing_attempts + 1,
          processing_error = NULL,
          updated_at = ?
      WHERE id = ?
        AND is_deleted = 0
        AND (
          processing_status <> ?
          OR processing_started_at IS NULL
          OR processing_started_at <= ?
        )
      ''',
      variables: [
        Variable<String>(ProcessingStatus.processing.dbValue),
        Variable<String>(timestamp.toIso8601String()),
        Variable<String>(timestamp.toIso8601String()),
        Variable<String>(documentId),
        Variable<String>(ProcessingStatus.processing.dbValue),
        Variable<String>(staleBefore),
      ],
    );
    return changed == 1;
  }

  @override
  Future<void> applyProcessingUpdate({
    required String documentId,
    required ProcessingUpdate update,
    DateTime? updatedAt,
  }) async {
    final timestamp = (updatedAt ?? DateTime.now()).toUtc();
    final completedAt = update.processingCompletedAt.toUtc();
    final changed =
        await (_database.update(
          _database.documents,
        )..where((table) => table.id.equals(documentId))).write(
          DocumentsCompanion(
            extractedText: Value(update.extractedText),
            extractionStatus: Value(update.extractionStatus.name),
            extractionError: Value(update.extractionError),
            extractionMethod: Value(update.extractionMethod),
            processingStatus: Value(update.processingStatus.dbValue),
            processingError: Value(update.processingError),
            processingCompletedAt: Value(completedAt.toIso8601String()),
            pageCount: Value(update.pageCount),
            sourceModifiedAt: Value(
              update.sourceModifiedAt?.toUtc().toIso8601String(),
            ),
            documentTitle: Value(update.documentTitle),
            category: Value(update.category),
            tagsJson: Value(update.tagsJson),
            tagsText: Value(update.tagsText),
            documentType: Value(update.documentType),
            issuer: Value(update.issuer),
            referenceNumber: Value(update.referenceNumber),
            documentDate: Value(update.documentDate),
            classificationReasonsJson: Value(update.classificationReasonsJson),
            classificationConfidence: Value(update.classificationConfidence),
            classificationVersion: Value(update.classificationVersion),
            updatedAt: Value(timestamp.toIso8601String()),
          ),
        );
    if (changed == 0) {
      throw LocalStorageException('Document $documentId was not found.');
    }
  }

  @override
  Future<int> resetStaleProcessing({
    Duration staleAfter = const Duration(minutes: 15),
    DateTime? now,
    String? message,
  }) async {
    final timestamp = (now ?? DateTime.now()).toUtc();
    final staleBefore = timestamp.subtract(staleAfter).toIso8601String();
    return _database.customUpdate(
      '''
      UPDATE documents
      SET processing_status = ?,
          processing_error = ?,
          updated_at = ?
      WHERE processing_status = ?
        AND is_deleted = 0
        AND (processing_started_at IS NULL OR processing_started_at <= ?)
      ''',
      variables: [
        Variable<String>(ProcessingStatus.pending.dbValue),
        Variable<String>(message),
        Variable<String>(timestamp.toIso8601String()),
        Variable<String>(ProcessingStatus.processing.dbValue),
        Variable<String>(staleBefore),
      ],
    );
  }

  @override
  Future<void> softDelete(String documentId, {DateTime? deletedAt}) async {
    final timestamp = (deletedAt ?? DateTime.now()).toUtc();
    final changed =
        await (_database.update(
          _database.documents,
        )..where((table) => table.id.equals(documentId))).write(
          DocumentsCompanion(
            isDeleted: const Value(true),
            deletedAt: Value(timestamp.toIso8601String()),
            updatedAt: Value(timestamp.toIso8601String()),
          ),
        );
    if (changed == 0) {
      throw LocalStorageException('Document $documentId was not found.');
    }
  }

  @override
  Future<void> hardDelete(String documentId) async {
    await (_database.delete(
      _database.documents,
    )..where((table) => table.id.equals(documentId))).go();
  }

  @override
  Future<int> countActive() async {
    final count = _database.documents.id.count();
    final row =
        await (_database.selectOnly(_database.documents)
              ..addColumns([count])
              ..where(_database.documents.isDeleted.equals(false)))
            .getSingle();
    return row.read(count) ?? 0;
  }

  @override
  Future<Set<String>> listStoredFilenames({bool includeDeleted = true}) async {
    final query = _database.selectOnly(_database.documents)
      ..addColumns([_database.documents.storedFilename]);
    if (!includeDeleted) {
      query.where(_database.documents.isDeleted.equals(false));
    }
    final rows = await query.get();
    return rows
        .map((row) => row.read(_database.documents.storedFilename))
        .whereType<String>()
        .toSet();
  }

  DocumentsCompanion _toCompanion(LocalDocument document) {
    return DocumentsCompanion.insert(
      id: document.id,
      originalFilename: document.originalFilename,
      storedFilename: document.storedFilename,
      mediaType: document.mediaType,
      sizeBytes: document.sizeBytes,
      sha256: document.sha256,
      extractedText: Value(document.extractedText),
      extractionStatus: Value(document.extractionStatus.name),
      extractionError: Value(document.extractionError),
      extractionMethod: Value(document.extractionMethod),
      processingStatus: Value(document.processingStatus.dbValue),
      processingError: Value(document.processingError),
      processingStartedAt: Value(
        document.processingStartedAt?.toUtc().toIso8601String(),
      ),
      processingCompletedAt: Value(
        document.processingCompletedAt?.toUtc().toIso8601String(),
      ),
      processingAttempts: Value(document.processingAttempts),
      pageCount: Value(document.pageCount),
      sourceModifiedAt: Value(
        document.sourceModifiedAt?.toUtc().toIso8601String(),
      ),
      documentTitle: Value(document.documentTitle),
      category: Value(document.category),
      tagsJson: Value(document.tagsJson),
      tagsText: Value(document.tagsText),
      documentType: Value(document.documentType),
      issuer: Value(document.issuer),
      referenceNumber: Value(document.referenceNumber),
      documentDate: Value(document.documentDate),
      classificationReasonsJson: Value(document.classificationReasonsJson),
      classificationConfidence: Value(document.classificationConfidence),
      classificationVersion: Value(document.classificationVersion),
      isDeleted: Value(document.isDeleted),
      createdAt: document.createdAt.toUtc().toIso8601String(),
      updatedAt: document.updatedAt.toUtc().toIso8601String(),
      deletedAt: Value(document.deletedAt?.toUtc().toIso8601String()),
    );
  }

  LocalDocument _toDomain(Document row) {
    return LocalDocument(
      id: row.id,
      originalFilename: row.originalFilename,
      storedFilename: row.storedFilename,
      mediaType: row.mediaType,
      sizeBytes: row.sizeBytes,
      sha256: row.sha256,
      extractedText: row.extractedText,
      extractionStatus: ExtractionStatus.values.byName(row.extractionStatus),
      extractionError: row.extractionError,
      extractionMethod: row.extractionMethod,
      processingStatus: ProcessingStatusStorage.fromDb(row.processingStatus),
      processingError: row.processingError,
      processingStartedAt: row.processingStartedAt == null
          ? null
          : DateTime.parse(row.processingStartedAt!).toUtc(),
      processingCompletedAt: row.processingCompletedAt == null
          ? null
          : DateTime.parse(row.processingCompletedAt!).toUtc(),
      processingAttempts: row.processingAttempts,
      pageCount: row.pageCount,
      sourceModifiedAt: row.sourceModifiedAt == null
          ? null
          : DateTime.parse(row.sourceModifiedAt!).toUtc(),
      documentTitle: row.documentTitle,
      category: row.category,
      tagsJson: row.tagsJson,
      tagsText: row.tagsText,
      documentType: row.documentType,
      issuer: row.issuer,
      referenceNumber: row.referenceNumber,
      documentDate: row.documentDate,
      classificationReasonsJson: row.classificationReasonsJson,
      classificationConfidence: row.classificationConfidence,
      classificationVersion: row.classificationVersion,
      isDeleted: row.isDeleted,
      createdAt: DateTime.parse(row.createdAt).toUtc(),
      updatedAt: DateTime.parse(row.updatedAt).toUtc(),
      deletedAt: row.deletedAt == null
          ? null
          : DateTime.parse(row.deletedAt!).toUtc(),
    );
  }
}
