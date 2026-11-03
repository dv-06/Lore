import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lore_mobile/data/local/local_models.dart';
import 'package:lore_mobile/data/local/local_storage.dart';
import 'package:lore_mobile/data/local/local_storage_paths.dart';
import 'package:lore_mobile/data/local/processing/document_processor.dart';
import 'package:lore_mobile/data/local/processing/extraction_types.dart';
import 'package:lore_mobile/data/local/processing/image_ocr_extractor.dart';
import 'package:lore_mobile/data/local/processing/metadata_extractor.dart';
import 'package:lore_mobile/data/local/processing/ocr_engine.dart';
import 'package:lore_mobile/data/local/processing/pdf_text_extractor.dart';
import 'package:lore_mobile/data/local/processing/scanned_pdf_processor.dart';
import 'package:lore_mobile/data/local/processing/text_file_extractor.dart';

import 'support/processing_fakes.dart';

const _fixtures = 'test/local/fixtures/documents';

void main() {
  late Directory tempDir;
  late LocalStoragePaths paths;
  late FakeOcrEngine ocr;
  late LocalStorage storage;
  var nextId = 0;

  Future<LocalStorage> openStorage({
    bool autoProcessImports = false,
    OcrEngine? engine,
    PdfRuntime? runtime,
  }) {
    return LocalStorage.open(
      paths: paths,
      idGenerator: () => 'doc-${++nextId}',
      ocrEngine: engine ?? ocr,
      pdfRuntime: runtime ?? inertPdfRuntime(),
      autoProcessImports: autoProcessImports,
    );
  }

  Future<ImportResult> importFixture(
    String fixture, {
    required String filename,
    required String mediaType,
  }) {
    return storage.imports.importFile(
      source: File('$_fixtures/$fixture'),
      originalFilename: filename,
      mediaType: mediaType,
    );
  }

  Future<LocalDocument> waitForStatus(
    String documentId,
    ProcessingStatus status,
  ) async {
    for (var attempt = 0; attempt < 200; attempt++) {
      final document = await storage.documents.findById(documentId);
      if (document?.processingStatus == status) {
        return document!;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('Document $documentId never reached $status.');
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lore_processor');
    paths = LocalStoragePaths(rootDirectory: '${tempDir.path}/lore_local');
    ocr = FakeOcrEngine(recognizer: (_) async => 'Recognized receipt text');
    nextId = 0;
    storage = await openStorage();
  });

  tearDown(() async {
    await storage.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('text documents', () {
    test('extracts, classifies and completes', () async {
      final imported = await importFixture(
        'plain_utf8.txt',
        filename: 'employment_offer.txt',
        mediaType: 'text/plain',
      );

      final outcome = await storage.processDocument(imported.document.id);
      final document = await storage.documents.findById(imported.document.id);

      expect(outcome.processingStatus, ProcessingStatus.completed);
      expect(outcome.extractionStatus, ExtractionStatus.ready);
      expect(outcome.extractionMethod, 'plain_text');
      expect(outcome.textLength, greaterThan(0));
      expect(document!.extractedText, contains('Employment offer letter'));
      expect(document.extractionStatus, ExtractionStatus.ready);
      expect(document.processingStatus, ProcessingStatus.completed);
      expect(document.processingAttempts, 1);
      expect(document.processingCompletedAt, isNotNull);
      expect(document.category, 'Work');
      expect(document.classificationVersion, 'rules-v1');
      expect(document.sourceModifiedAt, isNotNull);
      expect(
        (await storage.search.search('employment')).single.documentId,
        imported.document.id,
      );
    });

    test('preserves extracted text when reprocessing fails', () async {
      final imported = await importFixture(
        'plain_utf8.txt',
        filename: 'offer.txt',
        mediaType: 'text/plain',
      );
      await storage.processDocument(imported.document.id);
      final before = await storage.documents.findById(imported.document.id);

      await File(imported.file.path).writeAsBytes(<int>[0xff, 0xfe, 0x00]);

      final outcome = await storage.processDocument(imported.document.id);
      final after = await storage.documents.findById(imported.document.id);

      expect(outcome.processingStatus, ProcessingStatus.failed);
      expect(outcome.error, isNotNull);
      expect(after!.extractedText, before!.extractedText);
      expect(after.category, before.category);
      expect(after.documentTitle, before.documentTitle);
      expect(after.processingStatus, ProcessingStatus.failed);
      expect(after.extractionStatus, ExtractionStatus.failed);
      expect(after.processingAttempts, 2);
    });

    test('retries after a missing original is restored', () async {
      final imported = await importFixture(
        'plain_utf8.txt',
        filename: 'offer.txt',
        mediaType: 'text/plain',
      );
      final stored = File(imported.file.path);
      final originalBytes = await stored.readAsBytes();
      await stored.delete();

      final failed = await storage.processDocument(imported.document.id);
      expect(failed.processingStatus, ProcessingStatus.failed);
      expect(failed.error, contains('missing'));

      await stored.writeAsBytes(originalBytes);
      final retried = await storage.processDocument(imported.document.id);
      final document = await storage.documents.findById(imported.document.id);

      expect(retried.processingStatus, ProcessingStatus.completed);
      expect(document!.extractionStatus, ExtractionStatus.ready);
      expect(document.processingAttempts, 2);
    });

    test('marks unsupported formats without failing the record', () async {
      final imported = await importFixture(
        'unknown.xyz',
        filename: 'mystery.xyz',
        mediaType: 'application/octet-stream',
      );

      final outcome = await storage.processDocument(imported.document.id);

      expect(outcome.processingStatus, ProcessingStatus.partiallyCompleted);
      expect(outcome.extractionStatus, ExtractionStatus.unsupported);
      expect(outcome.error, contains('not supported'));
    });
  });

  group('pdf documents', () {
    setUp(() async {
      await storage.close();
      storage = await openStorage(runtime: hostPdfRuntime());
    });

    test('extracts selectable PDF text and metadata', () async {
      final imported = await importFixture(
        'selectable_text.pdf',
        filename: 'insurance_receipt.pdf',
        mediaType: 'application/pdf',
      );

      final outcome = await storage.processDocument(imported.document.id);
      final document = await storage.documents.findById(imported.document.id);

      expect(outcome.processingStatus, ProcessingStatus.completed);
      expect(outcome.extractionStatus, ExtractionStatus.ready);
      expect(outcome.extractionMethod, 'pdf_text');
      expect(outcome.pageCount, 2);
      expect(document!.extractedText, contains('POL-2024-0042'));
      expect(document.category, 'Insurance');
      expect(document.pageCount, 2);
      expect(document.sourceModifiedAt, isNotNull);
    });

    test('falls back to OCR for a scanned PDF', () async {
      final imported = await importFixture(
        'scanned_single_page.pdf',
        filename: 'scanned.pdf',
        mediaType: 'application/pdf',
      );

      final outcome = await storage.processDocument(imported.document.id);
      final document = await storage.documents.findById(imported.document.id);

      expect(outcome.processingStatus, ProcessingStatus.completed);
      expect(outcome.extractionMethod, 'pdf_ocr');
      expect(document!.extractedText, contains('Recognized receipt text'));
      expect(ocr.recognizedPaths, isNotEmpty);
    });

    test('fails cleanly for an encrypted PDF', () async {
      final imported = await importFixture(
        'encrypted.pdf',
        filename: 'locked.pdf',
        mediaType: 'application/pdf',
      );

      final outcome = await storage.processDocument(imported.document.id);
      final document = await storage.documents.findById(imported.document.id);

      expect(outcome.processingStatus, ProcessingStatus.failed);
      expect(outcome.error, contains('password-protected'));
      expect(document!.processingStatus, ProcessingStatus.failed);
      expect(document.extractionStatus, ExtractionStatus.failed);
      expect(document.processingStartedAt, isNotNull);
    });
  });

  group('images', () {
    test('OCRs an image document', () async {
      final imported = await importFixture(
        'ocr_receipt.png',
        filename: 'receipt.png',
        mediaType: 'image/png',
      );

      final outcome = await storage.processDocument(imported.document.id);
      final document = await storage.documents.findById(imported.document.id);

      expect(outcome.processingStatus, ProcessingStatus.completed);
      expect(outcome.extractionMethod, 'image_ocr');
      expect(document!.extractedText, contains('Recognized receipt text'));
    });

    test('keeps the record usable when OCR is unavailable', () async {
      await storage.close();
      storage = await openStorage(engine: const DisabledOcrEngine());

      final imported = await importFixture(
        'ocr_receipt.png',
        filename: 'receipt.png',
        mediaType: 'image/png',
      );

      final outcome = await storage.processDocument(imported.document.id);
      final document = await storage.documents.findById(imported.document.id);

      expect(outcome.processingStatus, ProcessingStatus.partiallyCompleted);
      expect(outcome.extractionStatus, ExtractionStatus.unsupported);
      expect(document!.processingStatus, ProcessingStatus.partiallyCompleted);
      expect(document.extractionStatus, ExtractionStatus.unsupported);
    });
  });

  group('claiming and recovery', () {
    test('prevents two workers from claiming one document', () async {
      final imported = await importFixture(
        'plain_utf8.txt',
        filename: 'offer.txt',
        mediaType: 'text/plain',
      );

      final first = await storage.documents.tryClaimForProcessing(
        documentId: imported.document.id,
      );
      final second = await storage.documents.tryClaimForProcessing(
        documentId: imported.document.id,
      );

      expect(first, isTrue);
      expect(second, isFalse);
    });

    test('reclaims a stale claim but not a live one', () async {
      final imported = await importFixture(
        'plain_utf8.txt',
        filename: 'offer.txt',
        mediaType: 'text/plain',
      );
      await storage.documents.tryClaimForProcessing(
        documentId: imported.document.id,
      );

      final live = await storage.documents.tryClaimForProcessing(
        documentId: imported.document.id,
        staleAfter: const Duration(minutes: 15),
      );
      final stale = await storage.documents.tryClaimForProcessing(
        documentId: imported.document.id,
        staleAfter: Duration.zero,
      );

      expect(live, isFalse);
      expect(stale, isTrue);
    });

    test('recovers an interrupted document without losing text', () async {
      final imported = await importFixture(
        'plain_utf8.txt',
        filename: 'offer.txt',
        mediaType: 'text/plain',
      );
      await storage.processDocument(imported.document.id);
      await storage.documents.applyProcessingUpdate(
        documentId: imported.document.id,
        update: ProcessingUpdate(
          extractedText: 'Preserved text',
          extractionStatus: ExtractionStatus.ready,
          processingStatus: ProcessingStatus.processing,
          processingCompletedAt: DateTime.now().toUtc(),
        ),
      );
      await storage.database.customStatement(
        'UPDATE documents SET processing_started_at = ? WHERE id = ?',
        ['2000-01-01T00:00:00.000Z', imported.document.id],
      );

      final recovered = await storage.recoverInterrupted();
      final document = await storage.documents.findById(imported.document.id);

      expect(recovered, 1);
      expect(document!.processingStatus, ProcessingStatus.pending);
      expect(document.extractedText, 'Preserved text');
      expect(document.processingError, contains('interrupted'));
    });

    test('open recovers work interrupted by a previous process', () async {
      final imported = await importFixture(
        'plain_utf8.txt',
        filename: 'offer.txt',
        mediaType: 'text/plain',
      );
      await storage.database.customStatement(
        "UPDATE documents SET processing_status = 'processing', "
        'processing_started_at = ? WHERE id = ?',
        ['2000-01-01T00:00:00.000Z', imported.document.id],
      );
      await storage.close();

      storage = await openStorage();
      final document = await storage.documents.findById(imported.document.id);

      expect(document!.processingStatus, ProcessingStatus.pending);
      expect(document.processingError, contains('interrupted'));
    });
  });

  group('cancellation', () {
    test('cancels an active run and preserves earlier text', () async {
      final imported = await importFixture(
        'plain_utf8.txt',
        filename: 'offer.txt',
        mediaType: 'text/plain',
      );
      await storage.processDocument(imported.document.id);

      final gate = Completer<void>();
      final extractor = ControllableTextExtractor(gate: gate);
      final processor = _customProcessor(storage, extractor);
      final signal = CancellationSignal();

      final pending = processor.process(
        imported.document.id,
        cancellation: signal,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      signal.cancel();
      gate.complete();

      final outcome = await pending;
      final document = await storage.documents.findById(imported.document.id);

      expect(outcome.cancelled, isTrue);
      expect(outcome.processingStatus, ProcessingStatus.pending);
      expect(document!.processingStatus, ProcessingStatus.pending);
      expect(document.extractedText, contains('Employment offer letter'));
      expect(document.processingAttempts, 2);
    });
  });

  group('queue', () {
    test('auto-processes imports when enabled', () async {
      await storage.close();
      storage = await openStorage(autoProcessImports: true);

      final imported = await importFixture(
        'plain_utf8.txt',
        filename: 'offer.txt',
        mediaType: 'text/plain',
      );
      final document = await waitForStatus(
        imported.document.id,
        ProcessingStatus.completed,
      );

      expect(document.extractionStatus, ExtractionStatus.ready);
      expect(document.extractedText, contains('Employment offer letter'));
    });

    test('coalesces duplicate requests for one document', () async {
      final imported = await importFixture(
        'plain_utf8.txt',
        filename: 'offer.txt',
        mediaType: 'text/plain',
      );

      final first = storage.processingQueue.enqueue(imported.document.id);
      final second = storage.processingQueue.enqueue(imported.document.id);

      expect(identical(first, second), isTrue);
      await Future.wait([first, second]);
      expect(
        (await storage.documents.findById(imported.document.id))!
            .processingAttempts,
        1,
      );
    });

    test('drains pending documents in order', () async {
      final first = await importFixture(
        'plain_utf8.txt',
        filename: 'one.txt',
        mediaType: 'text/plain',
      );
      final second = await importFixture(
        'plain_bom.txt',
        filename: 'two.txt',
        mediaType: 'text/plain',
      );

      final outcomes = await storage.processPending();

      expect(outcomes, hasLength(2));
      expect(
        outcomes.every(
          (outcome) => outcome.processingStatus == ProcessingStatus.completed,
        ),
        isTrue,
      );
      expect(
        (await storage.documents.findById(first.document.id))!.processingStatus,
        ProcessingStatus.completed,
      );
      expect(
        (await storage.documents.findById(second.document.id))!.processingStatus,
        ProcessingStatus.completed,
      );
    });
  });
}

DocumentProcessor _customProcessor(
  LocalStorage storage,
  TextFileExtractor textExtractor,
) {
  final directory = Directory(storage.paths.processingDirectory);
  return DocumentProcessor(
    documents: storage.documents,
    fileStore: storage.fileStore,
    textExtractor: textExtractor,
    pdfExtractor: PdfTextExtractor(runtime: inertPdfRuntime()),
    imageOcrExtractor: ImageOcrExtractor(
      ocr: const DisabledOcrEngine(),
      processingDirectory: directory,
    ),
    scannedPdfProcessor: ScannedPdfProcessor(
      ocr: const DisabledOcrEngine(),
      runtime: inertPdfRuntime(),
      processingDirectory: directory,
    ),
    metadataExtractor: const MetadataExtractor(),
  );
}
