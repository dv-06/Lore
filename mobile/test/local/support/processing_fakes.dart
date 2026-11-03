import 'dart:async';
import 'dart:io';

import 'package:lore_mobile/data/local/processing/ocr_engine.dart';
import 'package:lore_mobile/data/local/processing/pdf_text_extractor.dart';
import 'package:lore_mobile/data/local/processing/text_file_extractor.dart';
import 'package:lore_mobile/data/local/processing/extraction_types.dart';
import 'package:pdfrx/pdfrx.dart';

/// OCR stand-in that records what it was asked to read.
class FakeOcrEngine implements OcrEngine {
  FakeOcrEngine({this.available = true, this.recognizer});

  final bool available;
  Future<String> Function(String path)? recognizer;
  final List<String> recognizedPaths = <String>[];
  bool closed = false;

  @override
  bool get isAvailable => available;

  @override
  Future<String> recognizeFile(String path) async {
    if (!available) {
      throw const OcrUnavailableException('OCR is unavailable in this test.');
    }
    recognizedPaths.add(path);
    final handler = recognizer;
    return handler == null ? '' : handler(path);
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

/// Runtime that skips native PDFium setup for tests that never open a PDF.
PdfRuntime inertPdfRuntime() => PdfRuntime(initializer: () async {});

/// Runtime that initializes PDFium for tests that read real fixtures.
PdfRuntime hostPdfRuntime() {
  return PdfRuntime(
    initializer: () => pdfrxInitialize(
      tmpPath: Directory.systemTemp
          .createTempSync('lore_pdfrx_')
          .path,
    ),
  );
}

/// Text extractor that can be paused or made to fail deterministically.
class ControllableTextExtractor extends TextFileExtractor {
  ControllableTextExtractor({
    super.maxCharacters,
    this.gate,
    this.failure,
  });

  Completer<void>? gate;
  Object? failure;

  @override
  Future<ExtractionOutcome> extract(
    File file, {
    CancellationSignal? cancellation,
  }) async {
    final pending = gate;
    if (pending != null) {
      await pending.future;
    }
    final error = failure;
    if (error != null) {
      throw error;
    }
    return super.extract(file, cancellation: cancellation);
  }
}
