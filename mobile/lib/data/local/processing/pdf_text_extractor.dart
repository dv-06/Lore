import 'dart:io';

import 'package:pdfrx/pdfrx.dart';

import 'extraction_types.dart';

class PdfRuntime {
  PdfRuntime({Future<void> Function()? initializer})
    : _initializer = initializer ?? pdfrxFlutterInitialize;

  final Future<void> Function() _initializer;
  bool _initialized = false;

  Future<void> ensureInitialized() async {
    if (_initialized) {
      return;
    }
    await _initializer();
    _initialized = true;
  }
}

class PdfTextExtractor {
  const PdfTextExtractor({
    required this.runtime,
    this.maxCharacters = 1000000,
  });

  final PdfRuntime runtime;
  final int maxCharacters;

  Future<ExtractionOutcome> extract(
    File file, {
    CancellationSignal? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    await runtime.ensureInitialized();

    PdfDocument? document;
    try {
      document = await PdfDocument.openFile(file.path);
      final pageCount = document.pages.length;
      final buffer = StringBuffer();
      var truncated = false;
      final failures = <String>[];

      for (final page in document.pages) {
        cancellation?.throwIfCancelled();
        try {
          final raw = await page.loadText();
          final pageText = raw?.fullText ?? '';
          if (pageText.isEmpty) {
            continue;
          }
          final separator = buffer.isEmpty ? '' : '\n\f\n';
          final remaining =
              maxCharacters - buffer.length - separator.length;
          if (remaining <= 0) {
            truncated = true;
            break;
          }
          buffer.write(separator);
          if (pageText.length > remaining) {
            buffer.write(pageText.substring(0, remaining));
            truncated = true;
            break;
          }
          buffer.write(pageText);
        } catch (_) {
          failures.add('Page ${page.pageNumber} could not be read.');
        }
      }

      cancellation?.throwIfCancelled();
      final text = buffer.toString();
      if (text.trim().isEmpty) {
        if (failures.isNotEmpty) {
          throw DocumentExtractionException(
            failures.first,
            kind: ExtractionFailureKind.malformedDocument,
          );
        }
        return ExtractionOutcome(
          text: '',
          method: 'pdf_text',
          pageCount: pageCount,
          partial: true,
          warning: pageCount == 0
              ? 'The PDF has no pages.'
              : 'No selectable text was found in this PDF.',
        );
      }

      final warnings = <String>[
        if (truncated)
          'Extracted text was truncated to $maxCharacters characters.',
        ...failures,
      ];
      return ExtractionOutcome(
        text: text,
        method: 'pdf_text',
        pageCount: pageCount,
        partial: truncated || failures.isNotEmpty,
        warning: warnings.isEmpty ? null : warnings.join(' '),
      );
    } on PdfPasswordException {
      throw const DocumentExtractionException(
        'The PDF is password-protected or encrypted.',
        kind: ExtractionFailureKind.malformedDocument,
      );
    } on PdfException catch (error) {
      throw DocumentExtractionException(
        'The PDF could not be read: ${error.message}',
        kind: ExtractionFailureKind.malformedDocument,
      );
    } on DocumentExtractionException {
      rethrow;
    } on ProcessingCancelledException {
      rethrow;
    } catch (error) {
      throw DocumentExtractionException(
        'The PDF could not be read: $error',
        kind: ExtractionFailureKind.malformedDocument,
      );
    } finally {
      if (document != null) {
        try {
          await document.dispose();
        } catch (_) {
          // The original file is untouched even if disposal fails.
        }
      }
    }
  }
}
