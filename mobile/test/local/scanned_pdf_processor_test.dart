import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lore_mobile/data/local/processing/extraction_types.dart';
import 'package:lore_mobile/data/local/processing/ocr_engine.dart';
import 'package:lore_mobile/data/local/processing/pdf_text_extractor.dart';
import 'package:lore_mobile/data/local/processing/scanned_pdf_processor.dart';

import 'support/processing_fakes.dart';

const _fixtures = 'test/local/fixtures/documents';

File _fixture(String name) => File('$_fixtures/$name');

void main() {
  late Directory processingDirectory;
  late PdfRuntime runtime;

  setUpAll(() {
    runtime = hostPdfRuntime();
  });

  setUp(() async {
    processingDirectory = await Directory.systemTemp.createTemp('lore_scan');
  });

  tearDown(() async {
    if (await processingDirectory.exists()) {
      await processingDirectory.delete(recursive: true);
    }
  });

  ScannedPdfProcessor processorFor(
    FakeOcrEngine engine, {
    int maxPages = 50,
  }) {
    return ScannedPdfProcessor(
      ocr: engine,
      runtime: runtime,
      processingDirectory: processingDirectory,
      maxPages: maxPages,
    );
  }

  test('OCRs every page and separates page text', () async {
    var count = 0;
    final engine = FakeOcrEngine(
      recognizer: (_) async => 'Scanned page content ${++count}',
    );

    final outcome = await processorFor(
      engine,
    ).extract(_fixture('scanned_multi_page.pdf'), documentId: 'doc-1');

    expect(outcome.method, 'pdf_ocr');
    expect(outcome.pageCount, 2);
    expect(outcome.partial, isFalse);
    expect(outcome.text, contains('Scanned page content 1'));
    expect(outcome.text, contains('Scanned page content 2'));
    expect(outcome.text, contains('\n\f\n'));
    expect(engine.recognizedPaths, hasLength(2));
    expect(await processingDirectory.list().toList(), isEmpty);
  });

  test('caps the number of OCR pages', () async {
    final engine = FakeOcrEngine(recognizer: (_) async => 'Page text 12345');

    final outcome = await processorFor(
      engine,
      maxPages: 1,
    ).extract(_fixture('scanned_multi_page.pdf'), documentId: 'doc-1');

    expect(engine.recognizedPaths, hasLength(1));
    expect(outcome.partial, isTrue);
    expect(outcome.warning, contains('first 1 of 2 pages'));
  });

  test('reports a scan with no recognized text as partial', () async {
    final engine = FakeOcrEngine(recognizer: (_) async => '');

    final outcome = await processorFor(
      engine,
    ).extract(_fixture('scanned_single_page.pdf'), documentId: 'doc-1');

    expect(outcome.text, isEmpty);
    expect(outcome.partial, isTrue);
    expect(outcome.warning, contains('did not recognize'));
  });

  test('fails when OCR is unavailable', () async {
    final engine = FakeOcrEngine(available: false);

    await expectLater(
      processorFor(
        engine,
      ).extract(_fixture('scanned_single_page.pdf'), documentId: 'doc-1'),
      throwsA(isA<OcrUnavailableException>()),
    );
  });

  test('rejects an encrypted PDF before rendering', () async {
    final engine = FakeOcrEngine(recognizer: (_) async => 'text');

    await expectLater(
      processorFor(
        engine,
      ).extract(_fixture('encrypted.pdf'), documentId: 'doc-1'),
      throwsA(
        isA<DocumentExtractionException>().having(
          (error) => error.message,
          'message',
          contains('password-protected'),
        ),
      ),
    );
    expect(engine.recognizedPaths, isEmpty);
  });

  test('honours cancellation before rendering', () async {
    final engine = FakeOcrEngine(recognizer: (_) async => 'text');
    final signal = CancellationSignal()..cancel();

    await expectLater(
      processorFor(engine).extract(
        _fixture('scanned_single_page.pdf'),
        documentId: 'doc-1',
        cancellation: signal,
      ),
      throwsA(isA<ProcessingCancelledException>()),
    );
  });
}
