import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lore_mobile/data/local/processing/extraction_types.dart';
import 'package:lore_mobile/data/local/processing/image_ocr_extractor.dart';
import 'package:lore_mobile/data/local/processing/ocr_engine.dart';

import 'support/processing_fakes.dart';

const _fixtures = 'test/local/fixtures/documents';

File _fixture(String name) => File('$_fixtures/$name');

void main() {
  late Directory processingDirectory;

  setUp(() async {
    processingDirectory = await Directory.systemTemp.createTemp('lore_ocr');
  });

  tearDown(() async {
    if (await processingDirectory.exists()) {
      await processingDirectory.delete(recursive: true);
    }
  });

  ImageOcrExtractor extractorFor(FakeOcrEngine engine) {
    return ImageOcrExtractor(
      ocr: engine,
      processingDirectory: processingDirectory,
    );
  }

  test('returns recognized text without rotating when it scores', () async {
    final engine = FakeOcrEngine(
      recognizer: (_) async => 'Receipt total 42.00 paid',
    );

    final outcome = await extractorFor(
      engine,
    ).extract(_fixture('ocr_receipt.png'));

    expect(outcome.method, 'image_ocr');
    expect(outcome.text, 'Receipt total 42.00 paid');
    expect(outcome.partial, isFalse);
    expect(engine.recognizedPaths, hasLength(1));
  });

  test('tries rotations when the first result is unusable', () async {
    final engine = FakeOcrEngine(
      recognizer: (path) async {
        if (path.contains('_90.')) {
          return 'Rotated receipt total 99.95';
        }
        return '|';
      },
    );

    final outcome = await extractorFor(
      engine,
    ).extract(_fixture('ocr_rotated.png'));

    expect(outcome.text, 'Rotated receipt total 99.95');
    expect(engine.recognizedPaths, hasLength(4));
    expect(
      engine.recognizedPaths.where((path) => path.contains('_90.')),
      hasLength(1),
    );
  });

  test('flags an empty recognition result as partial', () async {
    final engine = FakeOcrEngine(recognizer: (_) async => '  \n ');

    final outcome = await extractorFor(
      engine,
    ).extract(_fixture('ocr_poor_quality.png'));

    expect(outcome.text, isEmpty);
    expect(outcome.partial, isTrue);
    expect(outcome.warning, contains('No text'));
  });

  test('removes temporary rotation renders', () async {
    final engine = FakeOcrEngine(recognizer: (_) async => '');

    await extractorFor(engine).extract(_fixture('ocr_rotated.png'));

    expect(await processingDirectory.list().toList(), isEmpty);
  });

  test('surfaces an unavailable OCR engine', () async {
    final engine = FakeOcrEngine(available: false);

    await expectLater(
      extractorFor(engine).extract(_fixture('ocr_receipt.png')),
      throwsA(isA<OcrUnavailableException>()),
    );
    expect(engine.recognizedPaths, isEmpty);
  });

  test('surfaces OCR processing failures', () async {
    final engine = FakeOcrEngine(
      recognizer: (_) async => throw const OcrProcessingException('boom'),
    );

    await expectLater(
      extractorFor(engine).extract(_fixture('ocr_receipt.png')),
      throwsA(isA<OcrProcessingException>()),
    );
  });

  test('honours cancellation before recognition', () async {
    final engine = FakeOcrEngine(recognizer: (_) async => 'text');
    final signal = CancellationSignal()..cancel();

    await expectLater(
      extractorFor(
        engine,
      ).extract(_fixture('ocr_receipt.png'), cancellation: signal),
      throwsA(isA<ProcessingCancelledException>()),
    );
    expect(engine.recognizedPaths, isEmpty);
  });

  test('truncates at the character limit', () async {
    final engine = FakeOcrEngine(recognizer: (_) async => 'A' * 50);
    final extractor = ImageOcrExtractor(
      ocr: engine,
      processingDirectory: processingDirectory,
      maxCharacters: 10,
    );

    final outcome = await extractor.extract(_fixture('ocr_receipt.png'));

    expect(outcome.text, 'A' * 10);
    expect(outcome.partial, isTrue);
    expect(outcome.warning, contains('truncated'));
  });
}
