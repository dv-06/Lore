import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:lore_mobile/data/local/local_models.dart';
import 'package:lore_mobile/data/local/local_storage.dart';
import 'package:lore_mobile/data/local/local_storage_paths.dart';
import 'package:lore_mobile/data/local/processing/ocr_engine.dart';
import 'package:path/path.dart' as p;

import 'probe_assets.dart';

class ProbeCheck {
  const ProbeCheck(this.label, this.passed, this.detail);

  final String label;
  final bool passed;
  final String detail;

  @override
  String toString() => '$label ${passed ? 'PASS' : 'FAIL'} $detail';
}

class ProbeReport {
  const ProbeReport(this.checks, this.rssBytes, this.maxRssBytes);

  final List<ProbeCheck> checks;
  final int rssBytes;
  final int maxRssBytes;

  bool get passed => checks.every((check) => check.passed);

  int get failureCount => checks.where((check) => !check.passed).length;

  String get summary =>
      'LORE_PROBE_DONE ${passed ? 'PASS' : 'FAIL'} '
      'checks=${checks.length} failures=$failureCount '
      'rssBytes=$rssBytes maxRssBytes=$maxRssBytes';
}

/// Runs the whole local pipeline with the real on-device OCR engine and
/// PDFium. No server URL or API client is constructed.
Future<ProbeReport> runLocalProcessingProbe({
  void Function(String line)? log,
}) async {
  final checks = <ProbeCheck>[];
  final requests = <String>[];
  final previousOverrides = HttpOverrides.current;
  HttpOverrides.global = _RecordingHttpOverrides(requests);

  final root = await Directory.systemTemp.createTemp('lore_phase32_probe');
  final storage = await LocalStorage.open(
    paths: LocalStoragePaths(rootDirectory: p.join(root.path, 'lore_local')),
  );
  try {
    final engine = storage.ocrEngine;
    _record(
      checks,
      log,
      'ocr_engine',
      engine is MlKitOcrEngine && engine.isAvailable,
      'engine=${engine.runtimeType} available=${engine.isAvailable}',
    );

    final txt = await _import(
      storage,
      'offer.txt',
      'text/plain',
      plainUtf8Base64,
    );
    final txtOutcome = await storage.processDocument(txt.document.id);
    _record(
      checks,
      log,
      'txt',
      txtOutcome.processingStatus == ProcessingStatus.completed &&
          txtOutcome.extractionMethod == 'plain_text',
      'status=${txtOutcome.processingStatus} '
          'method=${txtOutcome.extractionMethod} '
          'textLength=${txtOutcome.textLength}',
    );

    final pdf = await _import(
      storage,
      'insurance.pdf',
      'application/pdf',
      selectablePdfBase64,
    );
    final pdfOutcome = await storage.processDocument(pdf.document.id);
    _record(
      checks,
      log,
      'pdf_text',
      pdfOutcome.processingStatus == ProcessingStatus.completed &&
          pdfOutcome.extractionMethod == 'pdf_text' &&
          pdfOutcome.pageCount == 2,
      'status=${pdfOutcome.processingStatus} '
          'method=${pdfOutcome.extractionMethod} '
          'pages=${pdfOutcome.pageCount} textLength=${pdfOutcome.textLength}',
    );
    _record(
      checks,
      log,
      'pdf_search',
      (await storage.search.search('premium')).isNotEmpty,
      'fts hit for premium',
    );
    _record(
      checks,
      log,
      'pdf_original_unchanged',
      await _unchanged(pdf, selectablePdfBase64),
      'stored bytes match the imported bytes',
    );

    final scanned = await _import(
      storage,
      'scanned_bill.pdf',
      'application/pdf',
      scannedPdfBase64,
    );
    final scannedOutcome = await storage.processDocument(scanned.document.id);
    final scannedRecord = await storage.documents.findById(scanned.document.id);
    _record(
      checks,
      log,
      'pdf_ocr',
      scannedOutcome.processingStatus == ProcessingStatus.completed &&
          scannedOutcome.extractionMethod == 'pdf_ocr' &&
          (scannedRecord?.extractedText.toUpperCase().contains('POWER') ??
              false),
      'status=${scannedOutcome.processingStatus} '
          'method=${scannedOutcome.extractionMethod} '
          'textLength=${scannedOutcome.textLength} '
          'text=${_preview(scannedRecord?.extractedText)}',
    );
    _record(
      checks,
      log,
      'scanned_original_unchanged',
      await _unchanged(scanned, scannedPdfBase64),
      'stored bytes match the imported bytes',
    );

    final image = await _import(
      storage,
      'receipt.png',
      'image/png',
      receiptPngBase64,
    );
    final imageOutcome = await storage.processDocument(image.document.id);
    final imageRecord = await storage.documents.findById(image.document.id);
    _record(
      checks,
      log,
      'image_ocr',
      imageOutcome.processingStatus == ProcessingStatus.completed &&
          imageOutcome.extractionMethod == 'image_ocr' &&
          (imageRecord?.extractedText.toUpperCase().contains('POWER') ?? false),
      'status=${imageOutcome.processingStatus} '
          'method=${imageOutcome.extractionMethod} '
          'textLength=${imageOutcome.textLength} '
          'text=${_preview(imageRecord?.extractedText)}',
    );

    final rotated = await _import(
      storage,
      'rotated.png',
      'image/png',
      rotatedPngBase64,
    );
    final rotatedOutcome = await storage.processDocument(rotated.document.id);
    final rotatedRecord = await storage.documents.findById(rotated.document.id);
    _record(
      checks,
      log,
      'rotated_ocr',
      rotatedOutcome.processingStatus == ProcessingStatus.completed &&
          (rotatedRecord?.extractedText.toUpperCase().contains('POWER') ??
              false),
      'status=${rotatedOutcome.processingStatus} '
          'method=${rotatedOutcome.extractionMethod} '
          'text=${_preview(rotatedRecord?.extractedText)}',
    );

    final encrypted = await _import(
      storage,
      'locked.pdf',
      'application/pdf',
      encryptedPdfBase64,
    );
    final encryptedOutcome = await storage.processDocument(encrypted.document.id);
    _record(
      checks,
      log,
      'encrypted_pdf',
      encryptedOutcome.processingStatus == ProcessingStatus.failed &&
          (encryptedOutcome.error ?? '').contains('password-protected'),
      'status=${encryptedOutcome.processingStatus} '
          'error=${encryptedOutcome.error}',
    );

    final malformed = await _import(
      storage,
      'broken.pdf',
      'application/pdf',
      malformedPdfBase64,
    );
    final malformedOutcome = await storage.processDocument(malformed.document.id);
    _record(
      checks,
      log,
      'malformed_pdf',
      malformedOutcome.processingStatus == ProcessingStatus.failed,
      'status=${malformedOutcome.processingStatus} '
          'error=${malformedOutcome.error}',
    );

    final diagnostics = await storage.diagnostics();
    _record(
      checks,
      log,
      'diagnostics',
      diagnostics.schemaVersion == 2 &&
          diagnostics.fts5Usable &&
          diagnostics.documentCount == 7,
      'schema=${diagnostics.schemaVersion} '
          'fts5=${diagnostics.fts5Usable} '
          'documents=${diagnostics.documentCount} '
          'indexed=${diagnostics.indexedDocumentCount}',
    );

    _record(
      checks,
      log,
      'no_dart_http',
      requests.isEmpty,
      requests.isEmpty ? 'no Dart HTTP requests' : requests.join(', '),
    );

    return ProbeReport(checks, ProcessInfo.currentRss, ProcessInfo.maxRss);
  } finally {
    await storage.close();
    HttpOverrides.global = previousOverrides;
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  }
}

void _record(
  List<ProbeCheck> checks,
  void Function(String line)? log,
  String label,
  bool passed,
  String detail,
) {
  final check = ProbeCheck(label, passed, detail);
  checks.add(check);
  log?.call('LORE_PROBE $check');
}

Future<ImportResult> _import(
  LocalStorage storage,
  String filename,
  String mediaType,
  String base64,
) async {
  final directory = await Directory.systemTemp.createTemp('lore_probe_src');
  final source = File(p.join(directory.path, filename));
  await source.writeAsBytes(base64Decode(base64), flush: true);
  try {
    return await storage.imports.importFile(
      source: source,
      originalFilename: filename,
      mediaType: mediaType,
    );
  } finally {
    await directory.delete(recursive: true);
  }
}

Future<bool> _unchanged(ImportResult imported, String base64) async {
  final stored = await File(imported.file.path).readAsBytes();
  return listEquals(stored, base64Decode(base64));
}

String _preview(String? text) {
  if (text == null) {
    return '<null>';
  }
  final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return compact.length <= 120 ? compact : '${compact.substring(0, 120)}...';
}

class _RecordingHttpOverrides extends HttpOverrides {
  _RecordingHttpOverrides(this.requests);

  final List<String> requests;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return _RecordingHttpClient(requests);
  }
}

class _RecordingHttpClient implements HttpClient {
  _RecordingHttpClient(this.requests);

  final List<String> requests;

  Never _block(String method, Object? url) {
    requests.add('$method $url');
    throw StateError('Network access is forbidden during local processing.');
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _block('GET', url);

  @override
  Future<HttpClientRequest> postUrl(Uri url) async => _block('POST', url);

  @override
  Future<HttpClientRequest> putUrl(Uri url) async => _block('PUT', url);

  @override
  Future<HttpClientRequest> deleteUrl(Uri url) async => _block('DELETE', url);

  @override
  Future<HttpClientRequest> patchUrl(Uri url) async => _block('PATCH', url);

  @override
  Future<HttpClientRequest> headUrl(Uri url) async => _block('HEAD', url);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _block(method, url);

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('HttpClient.${invocation.memberName} is blocked.');
}
