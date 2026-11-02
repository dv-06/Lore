import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lore_mobile/core/api_config.dart';
import 'package:lore_mobile/data/api_client.dart';
import 'package:lore_mobile/data/models.dart';
import 'package:lore_mobile/screens/document_viewer_screen.dart';
import 'package:provider/provider.dart';

const ApiConfig _config = ApiConfig(baseUrl: 'http://127.0.0.1:8000');

DocumentResponse _document({
  String id = 'doc-1',
  String filename = 'warranty.pdf',
  String? mediaType = 'application/pdf',
}) {
  return DocumentResponse(
    id: id,
    originalFilename: filename,
    mediaType: mediaType,
    sizeBytes: 2048,
    extractionStatus: 'extracted',
    processingStatus: 'completed',
    uploadedAt: DateTime.utc(2026, 1, 1),
    documentTitle: 'Extracted title',
  );
}

Future<void> _pumpViewer(
  WidgetTester tester, {
  required DocumentResponse document,
  required http.Client backend,
  PdfDocumentViewBuilder? pdfViewBuilder,
}) async {
  final client = LoreApiClient(config: _config, httpClient: backend)
    ..setSessionToken('viewer-token');

  await tester.pumpWidget(
    Provider<LoreApiClient>.value(
      value: client,
      child: MaterialApp(
        home: DocumentViewerScreen(
          document: document,
          pdfViewBuilder: pdfViewBuilder,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('PDF originals render through the PDF viewer', (tester) async {
    late http.Request captured;
    final backend = MockClient((request) async {
      captured = request;
      return http.Response.bytes(
        [37, 80, 68, 70],
        200,
        headers: {'content-type': 'application/pdf'},
      );
    });

    await _pumpViewer(
      tester,
      document: _document(),
      backend: backend,
      pdfViewBuilder: (context, bytes, controller, onPageChanged) {
        return Text('PDF viewer bytes: ${bytes.length}');
      },
    );

    expect(find.text('PDF viewer bytes: 4'), findsOneWidget);
    expect(captured.url.path, '/api/v1/documents/doc-1/download');
    expect(captured.headers['authorization'], 'Bearer viewer-token');
  });

  testWidgets('image originals are zoomable', (tester) async {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE'
      'hQGAhKmMIQAAAABJRU5ErkJggg==',
    );
    final backend = MockClient(
      (request) async =>
          http.Response.bytes(png, 200, headers: {'content-type': 'image/png'}),
    );

    await _pumpViewer(
      tester,
      document: _document(filename: 'receipt.png', mediaType: 'image/png'),
      backend: backend,
    );

    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('plain text originals are shown read-only', (tester) async {
    final backend = MockClient(
      (request) async => http.Response.bytes(
        utf8.encode('Original note contents'),
        200,
        headers: {'content-type': 'text/plain; charset=utf-8'},
      ),
    );

    await _pumpViewer(
      tester,
      document: _document(filename: 'note.txt', mediaType: 'text/plain'),
      backend: backend,
    );

    expect(find.byType(SelectableText), findsOneWidget);
    final text = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(text.data, 'Original note contents');
    expect(find.text('ORIGINAL TEXT · READ-ONLY'), findsOneWidget);
  });

  testWidgets('unsupported originals are not replaced by extracted text', (
    tester,
  ) async {
    final backend = MockClient(
      (request) async => http.Response.bytes(
        [1, 2, 3],
        200,
        headers: {'content-type': 'application/zip'},
      ),
    );

    await _pumpViewer(
      tester,
      document: _document(
        filename: 'archive.zip',
        mediaType: 'application/zip',
      ),
      backend: backend,
    );

    expect(
      find.text('This format cannot be displayed in the app'),
      findsOneWidget,
    );
  });

  testWidgets('a missing original is reported honestly', (tester) async {
    final backend = MockClient(
      (request) async => http.Response(
        jsonEncode({'detail': 'Document or stored file not found.'}),
        404,
        headers: {'content-type': 'application/json'},
      ),
    );

    await _pumpViewer(
      tester,
      document: _document(),
      backend: backend,
      pdfViewBuilder: (context, bytes, controller, onPageChanged) {
        return const Text('PDF viewer should not build');
      },
    );

    expect(find.text('PDF viewer should not build'), findsNothing);
    expect(
      find.textContaining('The original file is missing from backend storage'),
      findsOneWidget,
    );
  });
}
