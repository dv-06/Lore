import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lore_mobile/data/local/processing/extraction_types.dart';
import 'package:lore_mobile/data/local/processing/pdf_text_extractor.dart';

import 'support/processing_fakes.dart';

const _fixtures = 'test/local/fixtures/documents';

File _fixture(String name) => File('$_fixtures/$name');

void main() {
  late PdfTextExtractor extractor;

  setUpAll(() async {
    extractor = PdfTextExtractor(runtime: hostPdfRuntime());
  });

  test('extracts selectable text page by page', () async {
    final outcome = await extractor.extract(_fixture('selectable_text.pdf'));

    expect(outcome.method, 'pdf_text');
    expect(outcome.pageCount, 2);
    expect(outcome.partial, isFalse);
    expect(outcome.text, contains('Annual insurance premium receipt'));
    expect(outcome.text, contains('POL-2024-0042'));
    expect(outcome.text, contains('Second page: coverage details'));
    expect(outcome.text, contains('\n\f\n'));
  });

  test('reports a blank PDF as partially processed', () async {
    final outcome = await extractor.extract(_fixture('empty.pdf'));

    expect(outcome.text, isEmpty);
    expect(outcome.pageCount, 1);
    expect(outcome.partial, isTrue);
    expect(outcome.warning, contains('No selectable text'));
  });

  test('reports an image-only PDF as having no selectable text', () async {
    final outcome = await extractor.extract(
      _fixture('scanned_single_page.pdf'),
    );

    expect(outcome.hasText, isFalse);
    expect(outcome.pageCount, 1);
    expect(outcome.partial, isTrue);
    expect(outcome.warning, contains('No selectable text'));
  });

  test('rejects a malformed PDF', () async {
    await expectLater(
      extractor.extract(_fixture('malformed.pdf')),
      throwsA(
        isA<DocumentExtractionException>().having(
          (error) => error.kind,
          'kind',
          ExtractionFailureKind.malformedDocument,
        ),
      ),
    );
  });

  test('rejects a password-protected PDF', () async {
    await expectLater(
      extractor.extract(_fixture('encrypted.pdf')),
      throwsA(
        isA<DocumentExtractionException>().having(
          (error) => error.message,
          'message',
          contains('password-protected'),
        ),
      ),
    );
  });

  test('honours cancellation before opening the file', () async {
    final signal = CancellationSignal()..cancel();

    await expectLater(
      extractor.extract(
        _fixture('selectable_text.pdf'),
        cancellation: signal,
      ),
      throwsA(isA<ProcessingCancelledException>()),
    );
  });

  test('truncates at the character limit and flags partial', () async {
    final limited = PdfTextExtractor(
      runtime: hostPdfRuntime(),
      maxCharacters: 20,
    );
    final outcome = await limited.extract(_fixture('selectable_text.pdf'));

    expect(outcome.text.length, lessThanOrEqualTo(20));
    expect(outcome.partial, isTrue);
    expect(outcome.warning, contains('truncated'));
  });
}
