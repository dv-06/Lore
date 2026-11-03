import 'dart:io';

import 'package:uuid/uuid.dart';

import 'document_file_store.dart';
import 'document_repository.dart';
import 'local_models.dart';

class DocumentImportCoordinator {
  DocumentImportCoordinator({
    required this.documents,
    required this.fileStore,
    String Function()? idGenerator,
    DateTime Function()? clock,
    this.onImported,
    this.maxBytes = 20 * 1024 * 1024,
  }) : _idGenerator = idGenerator ?? (() => Uuid().v4()),
       _clock = clock ?? DateTime.now;

  final DocumentRepository documents;
  final DocumentFileStore fileStore;
  final void Function(LocalDocument document)? onImported;
  final String Function() _idGenerator;
  final DateTime Function() _clock;
  final int maxBytes;

  Future<ImportResult> importFile({
    required File source,
    required String originalFilename,
    required String mediaType,
  }) async {
    if (mediaType.trim().isEmpty) {
      throw const LocalStorageException('A document media type is required.');
    }

    final documentId = _idGenerator();
    final staged = await fileStore.stageFile(
      source: source,
      documentId: documentId,
      originalFilename: originalFilename,
      mediaType: mediaType,
      maxBytes: maxBytes,
    );

    final LocalDocument? existing;
    try {
      existing = await documents.findBySha256(staged.sha256);
    } catch (error, stackTrace) {
      throw ImportPersistenceException(
        message:
            'The file was staged but duplicate detection failed. '
            'The staged file was retained for reconciliation.',
        retainedFilePath: staged.tempPath,
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (existing != null) {
      await fileStore.discardStaging(staged);
      throw DuplicateDocumentException(
        existing: existing,
        sha256: staged.sha256,
      );
    }

    final published = await fileStore.publish(staged);
    final now = _clock().toUtc();
    final document = LocalDocument(
      id: documentId,
      originalFilename: staged.originalFilename,
      storedFilename: published.storedFilename,
      mediaType: mediaType,
      sizeBytes: published.sizeBytes,
      sha256: published.sha256,
      createdAt: now,
      updatedAt: now,
    );

    try {
      await documents.insert(document);
    } catch (error, stackTrace) {
      throw ImportPersistenceException(
        message:
            'The original file was stored but its metadata could not be '
            'saved. The file was retained for reconciliation.',
        retainedFilePath: published.path,
        cause: error,
        stackTrace: stackTrace,
      );
    }

    final imported = document;
    try {
      onImported?.call(imported);
    } catch (_) {
      // Import must succeed even when optional local processing cannot start.
    }

    return ImportResult(document: document, file: published);
  }

  Future<ReconciliationReport> reconcile({
    Duration incompleteGrace = const Duration(hours: 24),
    DateTime? now,
  }) async {
    final referenced = await documents.listStoredFilenames(
      includeDeleted: true,
    );
    return fileStore.reconcile(
      referencedStoredFilenames: referenced,
      incompleteGrace: incompleteGrace,
      now: now,
    );
  }
}
