import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import 'extraction_types.dart';
import 'ocr_engine.dart';
import 'pdf_text_extractor.dart';

class ScannedPdfProcessor {
  ScannedPdfProcessor({
    required this.ocr,
    required this.runtime,
    required this.processingDirectory,
    this.maxPages = 50,
    this.renderScale = 2.0,
    this.maxRenderedPixels = 8000000,
    this.maxCharacters = 1000000,
  });

  final OcrEngine ocr;
  final PdfRuntime runtime;
  final Directory processingDirectory;
  final int maxPages;
  final double renderScale;
  final int maxRenderedPixels;
  final int maxCharacters;

  Future<ExtractionOutcome> extract(
    File file, {
    required String documentId,
    CancellationSignal? cancellation,
  }) async {
    if (!ocr.isAvailable) {
      throw const OcrUnavailableException(
        'Offline OCR is unavailable, so this scanned PDF was not processed.',
      );
    }

    cancellation?.throwIfCancelled();
    await runtime.ensureInitialized();
    PdfDocument? document;
    try {
      document = await PdfDocument.openFile(file.path);
      final pageCount = document.pages.length;
      if (pageCount == 0) {
        return const ExtractionOutcome(
          text: '',
          method: 'pdf_ocr',
          partial: true,
          warning: 'The PDF has no pages.',
        );
      }

      final pagesToProcess = math.min(pageCount, maxPages);
      final buffer = StringBuffer();
      final warnings = <String>[];
      final safeId = documentId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      await processingDirectory.create(recursive: true);

      for (var index = 0; index < pagesToProcess; index++) {
        cancellation?.throwIfCancelled();
        final page = document.pages[index];
        File? temp;
        PdfImage? rendered;
        try {
          rendered = await _renderPage(page);
          if (rendered == null) {
            warnings.add('Page ${page.pageNumber} could not be rendered.');
            continue;
          }
          final pngBytes = _encodePng(rendered);
          temp = File(
            p.join(
              processingDirectory.path,
              'scan_${safeId}_${page.pageNumber}_'
              '${DateTime.now().microsecondsSinceEpoch}.png',
            ),
          );
          await temp.writeAsBytes(pngBytes, flush: true);
          cancellation?.throwIfCancelled();
          final pageText = normalizeOcrText(
            await ocr.recognizeFile(temp.path),
          );
          if (pageText.isNotEmpty) {
            final separator = buffer.isEmpty ? '' : '\n\f\n';
            final remaining =
                maxCharacters - buffer.length - separator.length;
            if (remaining <= 0) {
              warnings.add(
                'Recognized text was truncated to $maxCharacters characters.',
              );
              break;
            }
            buffer.write(separator);
            if (pageText.length > remaining) {
              buffer.write(pageText.substring(0, remaining));
              warnings.add(
                'Recognized text was truncated to $maxCharacters characters.',
              );
              break;
            }
            buffer.write(pageText);
          }
        } on OcrUnavailableException {
          rethrow;
        } on ProcessingCancelledException {
          rethrow;
        } catch (_) {
          warnings.add('Page ${page.pageNumber} could not be OCR processed.');
        } finally {
          rendered?.dispose();
          if (temp != null) {
            try {
              await temp.delete();
            } catch (_) {
              // Best-effort cleanup of the temporary page render.
            }
          }
        }
      }

      cancellation?.throwIfCancelled();
      final text = buffer.toString();
      if (text.trim().isEmpty) {
        if (warnings.isNotEmpty) {
          throw OcrProcessingException(warnings.first);
        }
        return ExtractionOutcome(
          text: '',
          method: 'pdf_ocr',
          pageCount: pageCount,
          partial: true,
          warning: 'OCR did not recognize text in this PDF.',
        );
      }

      if (pagesToProcess < pageCount) {
        warnings.add(
          'OCR processed the first $pagesToProcess of $pageCount pages.',
        );
      }
      return ExtractionOutcome(
        text: text,
        method: 'pdf_ocr',
        pageCount: pageCount,
        partial: pagesToProcess < pageCount || warnings.isNotEmpty,
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
    } on OcrUnavailableException {
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

  Future<PdfImage?> _renderPage(PdfPage page) async {
    var width = page.width * renderScale;
    var height = page.height * renderScale;
    final pixels = width * height;
    if (pixels > maxRenderedPixels) {
      final factor = math.sqrt(maxRenderedPixels / pixels);
      width *= factor;
      height *= factor;
    }
    final safeWidth = math.max(1.0, width);
    final safeHeight = math.max(1.0, height);
    return page.render(fullWidth: safeWidth, fullHeight: safeHeight);
  }

  Uint8List _encodePng(PdfImage image) {
    final decoded = img.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: image.pixels.buffer,
      bytesOffset: image.pixels.offsetInBytes,
      numChannels: 4,
      order: img.ChannelOrder.bgra,
    );
    return img.encodePng(decoded);
  }
}
