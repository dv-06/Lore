import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'extraction_types.dart';
import 'ocr_engine.dart';

class ImageOcrExtractor {
  ImageOcrExtractor({
    required this.ocr,
    required this.processingDirectory,
    this.maxCharacters = 1000000,
    this.maxPixels = 40000000,
  });

  final OcrEngine ocr;
  final Directory processingDirectory;
  final int maxCharacters;
  final int maxPixels;

  Future<ExtractionOutcome> extract(
    File file, {
    CancellationSignal? cancellation,
  }) async {
    if (!ocr.isAvailable) {
      throw const OcrUnavailableException(
        'Offline OCR is unavailable, so this image was not processed.',
      );
    }

    cancellation?.throwIfCancelled();
    var text = normalizeOcrText(await ocr.recognizeFile(file.path));
    cancellation?.throwIfCancelled();

    if (_alphanumericScore(text) < 8) {
      final rotated = await _tryRotations(
        file,
        currentText: text,
        cancellation: cancellation,
      );
      if (rotated != null) {
        text = rotated;
      }
    }

    String? warning;
    var partial = false;
    if (text.isEmpty) {
      warning = 'No text was recognized in this image.';
      partial = true;
    }
    if (text.length > maxCharacters) {
      text = text.substring(0, maxCharacters);
      warning = 'Recognized text was truncated to $maxCharacters characters.';
      partial = true;
    }

    return ExtractionOutcome(
      text: text,
      method: 'image_ocr',
      partial: partial,
      warning: warning,
    );
  }

  Future<String?> _tryRotations(
    File file, {
    required String currentText,
    CancellationSignal? cancellation,
  }) async {
    img.Image? decoded;
    try {
      decoded = img.decodeImage(await file.readAsBytes());
    } catch (_) {
      return null;
    }
    if (decoded == null || decoded.width * decoded.height > maxPixels) {
      return null;
    }

    var best = currentText;
    var bestScore = _alphanumericScore(best);
    await processingDirectory.create(recursive: true);
    for (final angle in const <int>[90, 180, 270]) {
      cancellation?.throwIfCancelled();
      final rotated = img.copyRotate(decoded, angle: angle);
      final temp = File(
        p.join(
          processingDirectory.path,
          'ocr_${DateTime.now().microsecondsSinceEpoch}_$angle.png',
        ),
      );
      try {
        await temp.writeAsBytes(img.encodePng(rotated), flush: true);
        final candidate = normalizeOcrText(await ocr.recognizeFile(temp.path));
        final score = _alphanumericScore(candidate);
        if (score > bestScore) {
          best = candidate;
          bestScore = score;
        }
      } catch (_) {
        // A single rotation failing must not discard a usable result.
      } finally {
        try {
          await temp.delete();
        } catch (_) {
          // Best-effort cleanup of the temporary render.
        }
      }
    }
    return best == currentText ? null : best;
  }

  int _alphanumericScore(String text) {
    return RegExp(r'[A-Za-z0-9]').allMatches(text).length;
  }
}
