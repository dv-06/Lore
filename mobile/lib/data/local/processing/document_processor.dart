import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../document_file_store.dart';
import '../document_repository.dart';
import '../local_models.dart';
import 'document_classifier.dart';
import 'extraction_types.dart';
import 'image_ocr_extractor.dart';
import 'metadata_extractor.dart';
import 'ocr_engine.dart';
import 'pdf_text_extractor.dart';
import 'scanned_pdf_processor.dart';
import 'text_file_extractor.dart';

class DocumentNotFoundException implements Exception {
  const DocumentNotFoundException(this.documentId);

  final String documentId;

  @override
  String toString() => 'Document $documentId was not found.';
}

class ProcessingInProgressException implements Exception {
  const ProcessingInProgressException(this.documentId);

  final String documentId;

  @override
  String toString() => 'Document $documentId is already being processed.';
}

class ProcessingOutcome {
  const ProcessingOutcome({
    required this.documentId,
    required this.processingStatus,
    required this.extractionStatus,
    this.extractionMethod,
    this.pageCount,
    this.error,
    this.cancelled = false,
    this.textLength = 0,
  });

  final String documentId;
  final ProcessingStatus processingStatus;
  final ExtractionStatus extractionStatus;
  final String? extractionMethod;
  final int? pageCount;
  final String? error;
  final bool cancelled;
  final int textLength;
}

class DocumentProcessor {
  DocumentProcessor({
    required this.documents,
    required this.fileStore,
    required this.textExtractor,
    required this.pdfExtractor,
    required this.imageOcrExtractor,
    required this.scannedPdfProcessor,
    required this.metadataExtractor,
    this.classifier = const DocumentClassifier(),
    DateTime Function()? clock,
    this.staleAfter = const Duration(minutes: 15),
    this.maxPending = 25,
  }) : _clock = clock ?? DateTime.now;

  final DocumentRepository documents;
  final DocumentFileStore fileStore;
  final TextFileExtractor textExtractor;
  final PdfTextExtractor pdfExtractor;
  final ImageOcrExtractor imageOcrExtractor;
  final ScannedPdfProcessor scannedPdfProcessor;
  final MetadataExtractor metadataExtractor;
  final DocumentClassifier classifier;
  final DateTime Function() _clock;
  final Duration staleAfter;
  final int maxPending;

  Future<ProcessingOutcome> process(
    String documentId, {
    CancellationSignal? cancellation,
  }) async {
    final signal = cancellation ?? CancellationSignal();
    final document = await documents.findById(documentId);
    if (document == null || document.isDeleted) {
      throw DocumentNotFoundException(documentId);
    }

    final claimed = await documents.tryClaimForProcessing(
      documentId: documentId,
      staleAfter: staleAfter,
      now: _clock(),
    );
    if (!claimed) {
      throw ProcessingInProgressException(documentId);
    }

    try {
      return await _processClaimed(document, signal);
    } on ProcessingCancelledException {
      final update = _preservingUpdate(
        document,
        processingStatus: ProcessingStatus.pending,
        extractionStatus: document.extractionStatus,
        processingError: 'Processing was cancelled.',
        metadata: null,
      );
      await documents.applyProcessingUpdate(
        documentId: documentId,
        update: update,
      );
      return ProcessingOutcome(
        documentId: documentId,
        processingStatus: ProcessingStatus.pending,
        extractionStatus: document.extractionStatus,
        extractionMethod: document.extractionMethod,
        pageCount: document.pageCount,
        error: 'Processing was cancelled.',
        cancelled: true,
        textLength: document.extractedText.length,
      );
    } catch (error) {
      final update = _preservingUpdate(
        document,
        processingStatus: ProcessingStatus.failed,
        extractionStatus: ExtractionStatus.failed,
        extractionError: 'Processing failed unexpectedly: $error',
        processingError: 'Processing failed unexpectedly: $error',
        metadata: null,
      );
      await documents.applyProcessingUpdate(
        documentId: documentId,
        update: update,
      );
      return ProcessingOutcome(
        documentId: documentId,
        processingStatus: ProcessingStatus.failed,
        extractionStatus: ExtractionStatus.failed,
        extractionMethod: document.extractionMethod,
        pageCount: document.pageCount,
        error: update.processingError,
        textLength: document.extractedText.length,
      );
    }
  }

  Future<List<String>> pendingDocumentIds({int? limit}) async {
    final pending = await documents.listPending(limit: limit ?? maxPending);
    return pending.map((document) => document.id).toList(growable: false);
  }

  Future<int> recoverInterrupted() {
    return documents.resetStaleProcessing(
      staleAfter: staleAfter,
      now: _clock(),
      message: 'Processing was interrupted and is ready to retry.',
    );
  }

  Future<ProcessingOutcome> _processClaimed(
    LocalDocument document,
    CancellationSignal cancellation,
  ) async {
    final file = await fileStore.resolve(document.storedFilename);
    if (file == null || !await file.exists()) {
      final update = _preservingUpdate(
        document,
        processingStatus: ProcessingStatus.failed,
        extractionStatus: ExtractionStatus.failed,
        extractionError: 'The stored original file is missing.',
        processingError: 'The stored original file is missing.',
        metadata: null,
      );
      await documents.applyProcessingUpdate(
        documentId: document.id,
        update: update,
      );
      return _outcomeFrom(document, update, cancelled: false);
    }

    final metadata = await metadataExtractor.read(file);
    final mediaType = _mediaType(document);

    _ExtractionResult result;
    try {
      result = await _extract(
        document: document,
        file: file,
        mediaType: mediaType,
        cancellation: cancellation,
      );
    } on OcrUnavailableException catch (error) {
      final update = _preservingUpdate(
        document,
        processingStatus: ProcessingStatus.partiallyCompleted,
        extractionStatus: ExtractionStatus.unsupported,
        extractionError: error.message,
        processingError: error.message,
        metadata: metadata,
      );
      await documents.applyProcessingUpdate(
        documentId: document.id,
        update: update,
      );
      return _outcomeFrom(document, update, cancelled: false);
    } on OcrProcessingException catch (error) {
      final update = _preservingUpdate(
        document,
        processingStatus: ProcessingStatus.failed,
        extractionStatus: ExtractionStatus.failed,
        extractionError: error.message,
        processingError: error.message,
        metadata: metadata,
      );
      await documents.applyProcessingUpdate(
        documentId: document.id,
        update: update,
      );
      return _outcomeFrom(document, update, cancelled: false);
    } on DocumentExtractionException catch (error) {
      final unsupported =
          error.isCapabilityFailure ||
          error.kind == ExtractionFailureKind.unsupportedFormat;
      final update = _preservingUpdate(
        document,
        processingStatus: unsupported
            ? ProcessingStatus.partiallyCompleted
            : ProcessingStatus.failed,
        extractionStatus: unsupported
            ? ExtractionStatus.unsupported
            : ExtractionStatus.failed,
        extractionError: error.message,
        processingError: error.message,
        metadata: metadata,
      );
      await documents.applyProcessingUpdate(
        documentId: document.id,
        update: update,
      );
      return _outcomeFrom(document, update, cancelled: false);
    } on ProcessingCancelledException {
      rethrow;
    } on FileSystemException catch (error) {
      final message = error.message.isEmpty
          ? 'The stored original could not be read.'
          : 'The stored original could not be read: ${error.message}';
      final update = _preservingUpdate(
        document,
        processingStatus: ProcessingStatus.failed,
        extractionStatus: ExtractionStatus.failed,
        extractionError: message,
        processingError: message,
        metadata: metadata,
      );
      await documents.applyProcessingUpdate(
        documentId: document.id,
        update: update,
      );
      return _outcomeFrom(document, update, cancelled: false);
    }

    final preservePrevious =
        !result.outcome.hasText && document.extractedText.trim().isNotEmpty;
    final text = preservePrevious
        ? document.extractedText
        : result.outcome.text;
    final classification = preservePrevious
        ? null
        : classifier.classify(
            filename: document.originalFilename,
            extractedText: text,
            existingTags: _existingTags(document),
          );
    final update = ProcessingUpdate(
      extractedText: text,
      extractionStatus: result.extractionStatus,
      processingStatus: result.processingStatus,
      processingCompletedAt: _clock().toUtc(),
      extractionMethod: preservePrevious
          ? (document.extractionMethod ?? result.outcome.method)
          : result.outcome.method,
      extractionError: null,
      processingError: result.outcome.warning,
      pageCount: result.outcome.pageCount ?? document.pageCount,
      sourceModifiedAt: metadata.modifiedAt ?? document.sourceModifiedAt,
      documentTitle: classification != null
          ? classification.documentTitle
          : document.documentTitle,
      category: classification != null
          ? classification.category
          : document.category,
      tagsJson: classification == null
          ? document.tagsJson
          : jsonEncode(classification.tags),
      tagsText: classification == null
          ? document.tagsText
          : classification.tags.join(' '),
      documentType: classification != null
          ? classification.documentType
          : document.documentType,
      issuer: classification != null
          ? classification.issuer
          : document.issuer,
      referenceNumber: classification != null
          ? classification.referenceNumber
          : document.referenceNumber,
      documentDate: classification != null
          ? (classification.documentDate == null
                ? null
                : dateOnlyIso8601(classification.documentDate!))
          : document.documentDate,
      classificationReasonsJson: classification == null
          ? document.classificationReasonsJson
          : jsonEncode(classification.reasons),
      classificationConfidence: classification != null
          ? classification.confidence
          : document.classificationConfidence,
      classificationVersion: classification != null
          ? classification.method
          : document.classificationVersion,
    );

    await documents.applyProcessingUpdate(
      documentId: document.id,
      update: update,
    );
    return _outcomeFrom(document, update, cancelled: false);
  }

  Future<_ExtractionResult> _extract({
    required LocalDocument document,
    required File file,
    required String mediaType,
    required CancellationSignal cancellation,
  }) async {
    if (mediaType == 'text/plain') {
      final outcome = await textExtractor.extract(
        file,
        cancellation: cancellation,
      );
      return _resultFor(outcome);
    }

    if (mediaType == 'application/pdf') {
      final pdf = await pdfExtractor.extract(
        file,
        cancellation: cancellation,
      );
      if (pdf.hasText) {
        return _resultFor(pdf);
      }
      if (!scannedPdfProcessor.ocr.isAvailable) {
        throw const OcrUnavailableException(
          'This PDF has no selectable text and offline OCR is unavailable.',
        );
      }
      final ocr = await scannedPdfProcessor.extract(
        file,
        documentId: document.id,
        cancellation: cancellation,
      );
      return _resultFor(ocr);
    }

    if (mediaType.startsWith('image/')) {
      final outcome = await imageOcrExtractor.extract(
        file,
        cancellation: cancellation,
      );
      return _resultFor(outcome);
    }

    throw const DocumentExtractionException(
      'This document type is not supported by local processing.',
      kind: ExtractionFailureKind.unsupportedFormat,
    );
  }

  _ExtractionResult _resultFor(ExtractionOutcome outcome) {
    return _ExtractionResult(
      outcome: outcome,
      processingStatus: outcome.partial
          ? ProcessingStatus.partiallyCompleted
          : ProcessingStatus.completed,
      extractionStatus: ExtractionStatus.ready,
    );
  }

  ProcessingUpdate _preservingUpdate(
    LocalDocument document, {
    required ProcessingStatus processingStatus,
    required ExtractionStatus extractionStatus,
    required SourceFileMetadata? metadata,
    String? extractionError,
    String? processingError,
  }) {
    return ProcessingUpdate(
      extractedText: document.extractedText,
      extractionStatus: extractionStatus,
      processingStatus: processingStatus,
      processingCompletedAt: _clock().toUtc(),
      extractionMethod: document.extractionMethod,
      extractionError: extractionError,
      processingError: processingError,
      pageCount: document.pageCount,
      sourceModifiedAt: metadata?.modifiedAt ?? document.sourceModifiedAt,
      documentTitle: document.documentTitle,
      category: document.category,
      tagsJson: document.tagsJson,
      tagsText: document.tagsText,
      documentType: document.documentType,
      issuer: document.issuer,
      referenceNumber: document.referenceNumber,
      documentDate: document.documentDate,
      classificationReasonsJson: document.classificationReasonsJson,
      classificationConfidence: document.classificationConfidence,
      classificationVersion: document.classificationVersion,
    );
  }

  ProcessingOutcome _outcomeFrom(
    LocalDocument document,
    ProcessingUpdate update, {
    required bool cancelled,
  }) {
    return ProcessingOutcome(
      documentId: document.id,
      processingStatus: update.processingStatus,
      extractionStatus: update.extractionStatus,
      extractionMethod: update.extractionMethod,
      pageCount: update.pageCount,
      error: update.processingError,
      cancelled: cancelled,
      textLength: update.extractedText.length,
    );
  }

  String _mediaType(LocalDocument document) {
    final extension = p.extension(document.originalFilename).toLowerCase();
    const imageExtensions = <String>{
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.bmp',
      '.tif',
      '.tiff',
      '.webp',
    };
    if (extension == '.pdf') {
      return 'application/pdf';
    }
    if (extension == '.txt') {
      return 'text/plain';
    }
    if (imageExtensions.contains(extension)) {
      return switch (extension) {
        '.png' => 'image/png',
        '.jpg' || '.jpeg' => 'image/jpeg',
        '.gif' => 'image/gif',
        '.bmp' => 'image/bmp',
        '.tif' || '.tiff' => 'image/tiff',
        '.webp' => 'image/webp',
        _ => 'image/unknown',
      };
    }
    return document.mediaType.split(';').first.trim().toLowerCase();
  }

  List<String> _existingTags(LocalDocument document) {
    try {
      final decoded = jsonDecode(document.tagsJson);
      if (decoded is List) {
        return decoded.whereType<String>().toList(growable: false);
      }
    } catch (_) {
      // A malformed tag cache must not prevent reprocessing.
    }
    return const <String>[];
  }
}

class _ExtractionResult {
  const _ExtractionResult({
    required this.outcome,
    required this.processingStatus,
    required this.extractionStatus,
  });

  final ExtractionOutcome outcome;
  final ProcessingStatus processingStatus;
  final ExtractionStatus extractionStatus;
}
