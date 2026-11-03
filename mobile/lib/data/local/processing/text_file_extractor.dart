import 'dart:convert';
import 'dart:io';

import 'extraction_types.dart';

class TextFileExtractor {
  const TextFileExtractor({
    this.maxCharacters = 1000000,
    this.maxBytes = 20 * 1024 * 1024,
  });

  final int maxCharacters;
  final int maxBytes;

  Future<ExtractionOutcome> extract(
    File file, {
    CancellationSignal? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    final length = await file.length();
    if (length > maxBytes) {
      throw const DocumentExtractionException(
        'The text file exceeds the local processing size limit.',
        kind: ExtractionFailureKind.unsupportedFormat,
      );
    }

    final bytes = await file.readAsBytes();
    cancellation?.throwIfCancelled();
    if (bytes.contains(0)) {
      throw const DocumentExtractionException(
        'The text file contains binary data.',
        kind: ExtractionFailureKind.malformedDocument,
      );
    }

    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      throw const DocumentExtractionException(
        'Text documents must use UTF-8 encoding.',
        kind: ExtractionFailureKind.encoding,
      );
    }

    if (text.startsWith('\uFEFF')) {
      text = text.substring(1);
    }

    String? warning;
    var partial = false;
    if (text.trim().isEmpty) {
      warning = 'The text file is empty or contains only whitespace.';
      partial = true;
    }
    if (text.length > maxCharacters) {
      text = text.substring(0, maxCharacters);
      warning =
          'Extracted text was truncated to $maxCharacters characters.';
      partial = true;
    }

    return ExtractionOutcome(
      text: text,
      method: 'plain_text',
      partial: partial,
      warning: warning,
    );
  }
}
