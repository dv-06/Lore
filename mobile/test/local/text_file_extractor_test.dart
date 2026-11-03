import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lore_mobile/data/local/processing/extraction_types.dart';
import 'package:lore_mobile/data/local/processing/text_file_extractor.dart';

const _fixtures = 'test/local/fixtures/documents';

File _fixture(String name) => File('$_fixtures/$name');

void main() {
  const extractor = TextFileExtractor();

  group('UTF-8 text', () {
    test('extracts the decoded contents', () async {
      final outcome = await extractor.extract(_fixture('plain_utf8.txt'));

      expect(outcome.method, 'plain_text');
      expect(outcome.partial, isFalse);
      expect(outcome.text, contains('Employment offer letter'));
      expect(outcome.text, contains('Salary: 42000'));
      expect(outcome.warning, isNull);
    });

    test('strips a single UTF-8 byte order mark', () async {
      final outcome = await extractor.extract(_fixture('plain_bom.txt'));

      expect(outcome.text.startsWith('\uFEFF'), isFalse);
      expect(outcome.text, startsWith('Bank statement'));
    });

    test('normalizes CRLF line endings through decoding', () async {
      final outcome = await extractor.extract(_fixture('plain_utf8.txt'));

      expect(outcome.text, contains('Employment offer letter\r\nEmployer'));
    });
  });

  group('degenerate text', () {
    test('flags an empty file as partial', () async {
      final outcome = await extractor.extract(_fixture('empty.txt'));

      expect(outcome.text, isEmpty);
      expect(outcome.partial, isTrue);
      expect(outcome.warning, contains('empty'));
    });

    test('flags a whitespace-only file as partial', () async {
      final outcome = await extractor.extract(_fixture('whitespace.txt'));

      expect(outcome.text.trim(), isEmpty);
      expect(outcome.partial, isTrue);
      expect(outcome.warning, contains('whitespace'));
    });

    test('rejects invalid UTF-8', () async {
      await expectLater(
        extractor.extract(_fixture('invalid_utf8.txt')),
        throwsA(
          isA<DocumentExtractionException>().having(
            (error) => error.kind,
            'kind',
            ExtractionFailureKind.encoding,
          ),
        ),
      );
    });

    test('rejects binary data containing NUL bytes', () async {
      await expectLater(
        extractor.extract(_fixture('binary.txt')),
        throwsA(
          isA<DocumentExtractionException>().having(
            (error) => error.kind,
            'kind',
            ExtractionFailureKind.malformedDocument,
          ),
        ),
      );
    });

    test('rejects files above the byte limit', () async {
      const limited = TextFileExtractor(maxBytes: 8);
      await expectLater(
        limited.extract(_fixture('plain_utf8.txt')),
        throwsA(
          isA<DocumentExtractionException>().having(
            (error) => error.kind,
            'kind',
            ExtractionFailureKind.unsupportedFormat,
          ),
        ),
      );
    });
  });

  group('limits and cancellation', () {
    test('truncates at the character limit and flags partial', () async {
      final directory = await Directory.systemTemp.createTemp('lore_txt');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/long.txt');
      await file.writeAsString('abcdefghij' * 4);

      const limited = TextFileExtractor(maxCharacters: 18);
      final outcome = await limited.extract(file);

      expect(outcome.text, 'abcdefghijabcdefgh');
      expect(outcome.text.length, 18);
      expect(outcome.partial, isTrue);
      expect(outcome.warning, contains('truncated'));
    });

    test('honours cancellation before reading', () async {
      final signal = CancellationSignal()..cancel();

      await expectLater(
        extractor.extract(_fixture('plain_utf8.txt'), cancellation: signal),
        throwsA(isA<ProcessingCancelledException>()),
      );
    });
  });
}
