/// Domain values for the local-first storage layer.
///
/// These types deliberately do not depend on Drift, the HTTP client, or the
/// server DTOs so the persistence implementation can be replaced later.
enum ExtractionStatus { pending, processing, ready, failed, unsupported }

enum ProcessingStatus {
  pending,
  processing,
  completed,
  partiallyCompleted,
  failed,
}

extension ProcessingStatusStorage on ProcessingStatus {
  String get dbValue => switch (this) {
    ProcessingStatus.pending => 'pending',
    ProcessingStatus.processing => 'processing',
    ProcessingStatus.completed => 'completed',
    ProcessingStatus.partiallyCompleted => 'partially_completed',
    ProcessingStatus.failed => 'failed',
  };

  static ProcessingStatus fromDb(String value) => switch (value) {
    'pending' => ProcessingStatus.pending,
    'processing' => ProcessingStatus.processing,
    'completed' => ProcessingStatus.completed,
    'partially_completed' => ProcessingStatus.partiallyCompleted,
    'failed' => ProcessingStatus.failed,
    _ => throw FormatException('Unknown processing status: $value'),
  };
}

class LocalDocument {
  const LocalDocument({
    required this.id,
    required this.originalFilename,
    required this.storedFilename,
    required this.mediaType,
    required this.sizeBytes,
    required this.sha256,
    required this.createdAt,
    required this.updatedAt,
    this.extractedText = '',
    this.extractionStatus = ExtractionStatus.pending,
    this.extractionError,
    this.extractionMethod,
    this.processingStatus = ProcessingStatus.pending,
    this.processingError,
    this.processingStartedAt,
    this.processingCompletedAt,
    this.processingAttempts = 0,
    this.pageCount,
    this.sourceModifiedAt,
    this.documentTitle,
    this.category,
    this.tagsJson = '[]',
    this.tagsText = '',
    this.documentType,
    this.issuer,
    this.referenceNumber,
    this.documentDate,
    this.classificationReasonsJson = '[]',
    this.classificationConfidence,
    this.classificationVersion,
    this.isDeleted = false,
    this.deletedAt,
  });

  final String id;
  final String originalFilename;
  final String storedFilename;
  final String mediaType;
  final int sizeBytes;
  final String sha256;
  final String extractedText;
  final ExtractionStatus extractionStatus;
  final String? extractionError;
  final String? extractionMethod;
  final ProcessingStatus processingStatus;
  final String? processingError;
  final DateTime? processingStartedAt;
  final DateTime? processingCompletedAt;
  final int processingAttempts;
  final int? pageCount;
  final DateTime? sourceModifiedAt;
  final String? documentTitle;
  final String? category;
  final String tagsJson;
  final String tagsText;
  final String? documentType;
  final String? issuer;
  final String? referenceNumber;
  final String? documentDate;
  final String classificationReasonsJson;
  final double? classificationConfidence;
  final String? classificationVersion;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

/// Complete processing result written in a single transaction.
///
/// Failures deliberately carry the previous text and classification so a
/// failed reprocessing attempt cannot erase a usable result.
class ProcessingUpdate {
  const ProcessingUpdate({
    required this.extractedText,
    required this.extractionStatus,
    required this.processingStatus,
    required this.processingCompletedAt,
    this.extractionMethod,
    this.extractionError,
    this.processingError,
    this.pageCount,
    this.sourceModifiedAt,
    this.documentTitle,
    this.category,
    this.tagsJson = '[]',
    this.tagsText = '',
    this.documentType,
    this.issuer,
    this.referenceNumber,
    this.documentDate,
    this.classificationReasonsJson = '[]',
    this.classificationConfidence,
    this.classificationVersion,
  });

  final String extractedText;
  final ExtractionStatus extractionStatus;
  final ProcessingStatus processingStatus;
  final DateTime processingCompletedAt;
  final String? extractionMethod;
  final String? extractionError;
  final String? processingError;
  final int? pageCount;
  final DateTime? sourceModifiedAt;
  final String? documentTitle;
  final String? category;
  final String tagsJson;
  final String tagsText;
  final String? documentType;
  final String? issuer;
  final String? referenceNumber;
  final String? documentDate;
  final String classificationReasonsJson;
  final double? classificationConfidence;
  final String? classificationVersion;
}

class LocalSearchResult {
  const LocalSearchResult({
    required this.documentId,
    required this.filename,
    required this.rank,
    this.title,
    this.category,
    this.snippet,
  });

  final String documentId;
  final String filename;
  final String? title;
  final String? category;
  final String? snippet;
  final double rank;
}

class LocalRelationship {
  const LocalRelationship({
    required this.id,
    required this.sourceDocumentId,
    required this.relatedDocumentId,
    required this.relationshipType,
    required this.score,
    required this.explanation,
    required this.calculatedAt,
    this.evidenceJson = '[]',
  });

  final String id;
  final String sourceDocumentId;
  final String relatedDocumentId;
  final String relationshipType;
  final double score;
  final String explanation;
  final String evidenceJson;
  final DateTime calculatedAt;
}

class StagedDocumentFile {
  const StagedDocumentFile({
    required this.documentId,
    required this.originalFilename,
    required this.storedFilename,
    required this.mediaType,
    required this.tempPath,
    required this.sizeBytes,
    required this.sha256,
  });

  final String documentId;
  final String originalFilename;
  final String storedFilename;
  final String mediaType;
  final String tempPath;
  final int sizeBytes;
  final String sha256;
}

class PublishedDocumentFile {
  const PublishedDocumentFile({
    required this.storedFilename,
    required this.path,
    required this.sizeBytes,
    required this.sha256,
  });

  final String storedFilename;
  final String path;
  final int sizeBytes;
  final String sha256;
}

class ImportResult {
  const ImportResult({required this.document, required this.file});

  final LocalDocument document;
  final PublishedDocumentFile file;
}

class ReconciliationReport {
  const ReconciliationReport({
    required this.movedOrphans,
    required this.movedIncomplete,
    required this.pendingIncomplete,
    required this.missingReferencedFiles,
    required this.errors,
  });

  final List<String> movedOrphans;
  final List<String> movedIncomplete;
  final List<String> pendingIncomplete;
  final List<String> missingReferencedFiles;
  final List<String> errors;

  bool get hasChanges => movedOrphans.isNotEmpty || movedIncomplete.isNotEmpty;
}

class LocalStorageDiagnostics {
  const LocalStorageDiagnostics({
    required this.databasePath,
    required this.schemaVersion,
    required this.sqliteVersion,
    required this.fts5Compiled,
    required this.fts5TablePresent,
    required this.documentCount,
    required this.indexedDocumentCount,
  });

  final String databasePath;
  final int schemaVersion;
  final String sqliteVersion;
  final bool fts5Compiled;
  final bool fts5TablePresent;
  final int documentCount;
  final int indexedDocumentCount;

  bool get fts5Usable => fts5Compiled && fts5TablePresent;
}

class LocalStorageException implements Exception {
  const LocalStorageException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class UnsafeStoragePathException extends LocalStorageException {
  const UnsafeStoragePathException(super.message);
}

class StorageCollisionException extends LocalStorageException {
  const StorageCollisionException(super.message);
}

class StagedFileMissingException extends LocalStorageException {
  const StagedFileMissingException(super.message);
}

class ImportFileTooLargeException extends LocalStorageException {
  const ImportFileTooLargeException(this.maxBytes)
    : super(
        'The selected file exceeds the local import limit of $maxBytes bytes.',
      );

  final int maxBytes;
}

class DuplicateDocumentException implements Exception {
  const DuplicateDocumentException({
    required this.existing,
    required this.sha256,
  });

  final LocalDocument existing;
  final String sha256;

  @override
  String toString() =>
      'A document with the same content already exists (${existing.id}).';
}

class ImportPersistenceException implements Exception {
  const ImportPersistenceException({
    required this.message,
    required this.retainedFilePath,
    this.cause,
    this.stackTrace,
  });

  final String message;
  final String retainedFilePath;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => '$message Retained file: $retainedFilePath';
}
