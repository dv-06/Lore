import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lore_mobile/core/api_config.dart';
import 'package:lore_mobile/data/api_client.dart';

const ApiConfig _config = ApiConfig(baseUrl: 'http://127.0.0.1:8000');

http.Response _json(Object body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

Map<String, dynamic> _documentJson({
  String id = 'doc-1',
  String filename = 'warranty.pdf',
}) {
  return {
    'id': id,
    'original_filename': filename,
    'media_type': 'application/pdf',
    'size_bytes': 2048,
    'sha256': 'a' * 64,
    'extraction_status': 'extracted',
    'processing_status': 'completed',
    'processing_error': null,
    'uploaded_at': '2026-10-20T10:00:00Z',
    'category': 'Finance',
    'classification_confidence': 0.82,
    'classification_reasons': ['filename contains invoice'],
    'classification_method': 'keywords',
    'document_title': 'Warranty policy',
    'document_date': '2026-01-01',
    'document_type': 'Warranty',
    'issuer': 'Acme',
    'reference_number': 'W-123',
    'tags': ['appliance'],
  };
}

Map<String, dynamic> _askJson() {
  return {
    'question': 'When does the warranty expire?',
    'answer': 'The warranty ends on 1 March 2027.',
    'provider': 'extractive',
    'sufficient_evidence': true,
    'evidence': [
      {
        'document_id': 'doc-1',
        'filename': 'warranty.pdf',
        'title': 'Warranty policy',
        'location': 'Page 1',
        'snippet': 'The warranty ends on 1 March 2027.',
        'score': 0.91,
        'reason': 'Direct match for warranty period.',
      },
    ],
    'warnings': <String>[],
  };
}

void main() {
  test('listDocuments sends pagination and category filters', () async {
    late Uri captured;
    final client = LoreApiClient(
      config: _config,
      httpClient: MockClient((request) async {
        captured = request.url;
        return _json({
          'items': [_documentJson()],
          'limit': 5,
          'offset': 10,
        });
      }),
    );

    final response = await client.listDocuments(
      limit: 5,
      offset: 10,
      category: 'Finance',
    );

    expect(response.items.single.originalFilename, 'warranty.pdf');
    expect(captured.path, '/api/v1/documents');
    expect(captured.queryParameters['limit'], '5');
    expect(captured.queryParameters['offset'], '10');
    expect(captured.queryParameters['category'], 'Finance');
  });

  test('askQuestion posts to the backend /ask endpoint', () async {
    late http.Request captured;
    final client = LoreApiClient(
      config: _config,
      httpClient: MockClient((request) async {
        captured = request;
        return _json(_askJson());
      }),
    );

    final response = await client.askQuestion('When does the warranty expire?');

    expect(response.provider, 'extractive');
    expect(response.evidence.single.location, 'Page 1');
    expect(captured.method, 'POST');
    expect(captured.url.path, '/api/v1/ask');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['question'], 'When does the warranty expire?');
    expect(body['max_sources'], 5);
  });

  test(
    'getRelatedDocuments uses the document-scoped related endpoint',
    () async {
      late Uri captured;
      final client = LoreApiClient(
        config: _config,
        httpClient: MockClient((request) async {
          captured = request.url;
          return _json({
            'document_id': 'doc-1',
            'items': [
              {
                'id': 'rel-1',
                'relationship_type': 'same_category',
                'score': 0.7,
                'explanation': 'Both are appliance documents.',
                'evidence': ['category: Appliances'],
                'calculated_at': '2026-10-20T10:00:00Z',
                'related_document': {
                  'id': 'doc-2',
                  'filename': 'fridge.pdf',
                  'title': 'Fridge manual',
                  'category': 'Appliances',
                  'document_type': 'Manual',
                },
              },
            ],
          });
        }),
      );

      final response = await client.getRelatedDocuments('doc-1');

      expect(
        response.items.single.relatedDocument.displayName,
        'Fridge manual',
      );
      expect(captured.path, '/api/v1/documents/doc-1/related');
      expect(captured.queryParameters['limit'], '20');
    },
  );

  test('uploadDocument sends multipart content to /documents', () async {
    late http.Request captured;
    final client = LoreApiClient(
      config: _config,
      httpClient: MockClient((request) async {
        captured = request;
        return _json(_documentJson(), 201);
      }),
    );

    final document = await client.uploadDocument(
      filename: 'warranty.pdf',
      bytes: [1, 2, 3],
    );

    expect(document.id, 'doc-1');
    expect(captured.method, 'POST');
    expect(captured.url.path, '/api/v1/documents');
    expect(captured.headers['content-type'], contains('multipart/form-data'));
  });

  test('backend error details become typed ApiExceptions', () async {
    final client = LoreApiClient(
      config: _config,
      httpClient: MockClient(
        (request) async => _json({'detail': 'Document not found'}, 404),
      ),
    );

    await expectLater(
      client.getDocument('missing'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 404)
            .having((error) => error.isNotFound, 'isNotFound', true)
            .having((error) => error.message, 'message', 'Document not found'),
      ),
    );
  });

  test('socket failures become offline ApiExceptions', () async {
    final client = LoreApiClient(
      config: _config,
      httpClient: MockClient(
        (request) async => throw const SocketException('offline'),
      ),
    );

    await expectLater(
      client.getSystemStatus(),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 0)
            .having((error) => error.isOffline, 'isOffline', true),
      ),
    );
  });

  test(
    'session tokens are sent as bearer headers on private requests',
    () async {
      final headers = <String, String?>{};
      final client = LoreApiClient(
        config: _config,
        httpClient: MockClient((request) async {
          headers[request.method] = request.headers['authorization'];
          return _json({
            'items': [_documentJson()],
            'limit': 50,
            'offset': 0,
          });
        }),
      )..setSessionToken('secret-token');

      await client.listDocuments();

      expect(headers['GET'], 'Bearer secret-token');
    },
  );

  test('upload and download include the bearer token', () async {
    final headers = <String, String?>{};
    final client = LoreApiClient(
      config: _config,
      httpClient: MockClient((request) async {
        headers[request.url.path] = request.headers['authorization'];
        if (request.url.path.endsWith('/download')) {
          return http.Response.bytes(
            [1, 2, 3, 4],
            200,
            headers: {'content-type': 'application/pdf'},
          );
        }
        return _json(_documentJson(), 201);
      }),
    )..setSessionToken('secret-token');

    await client.uploadDocument(filename: 'warranty.pdf', bytes: [1, 2, 3]);
    final download = await client.downloadDocument('doc-1');

    expect(headers['/api/v1/documents'], 'Bearer secret-token');
    expect(headers['/api/v1/documents/doc-1/download'], 'Bearer secret-token');
    expect(download.bytes, [1, 2, 3, 4]);
    expect(download.mediaType, 'application/pdf');
  });

  test('pairing never sends an existing bearer token', () async {
    String? authorization;
    final client = LoreApiClient(
      config: _config,
      httpClient: MockClient((request) async {
        authorization = request.headers['authorization'];
        return _json({
          'token': 'paired-token',
          'created_at': '2026-11-01T10:00:00Z',
          'expires_at': '2026-12-01T10:00:00Z',
        });
      }),
    )..setSessionToken('stale-token');

    final result = await client.pairWithCode('CODE');

    expect(result.token, 'paired-token');
    expect(authorization, isNull);
  });

  test('a 401 on a private request reports an invalid session', () async {
    var invalidated = 0;
    final client =
        LoreApiClient(
            config: _config,
            httpClient: MockClient(
              (request) async =>
                  _json({'detail': 'Authentication required.'}, 401),
            ),
          )
          ..setSessionToken('expired-token')
          ..onUnauthorized = () => invalidated++;

    await expectLater(
      client.listDocuments(),
      throwsA(
        isA<ApiException>().having((error) => error.statusCode, 'status', 401),
      ),
    );
    expect(invalidated, 1);
  });

  test('session validation handles its own 401 without looping', () async {
    var invalidated = 0;
    final client =
        LoreApiClient(
            config: _config,
            httpClient: MockClient(
              (request) async =>
                  _json({'detail': 'Authentication required.'}, 401),
            ),
          )
          ..setSessionToken('expired-token')
          ..onUnauthorized = () => invalidated++;

    await expectLater(client.getAuthSession(), throwsA(isA<ApiException>()));
    expect(invalidated, 0);
  });

  test('logout and revoke-all call the protected auth endpoints', () async {
    final paths = <String>[];
    final client = LoreApiClient(
      config: _config,
      httpClient: MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.path.endsWith('/revoke-all')) {
          return _json({'revoked': 2, 'pairing_required': true});
        }
        return _json({'revoked': true});
      }),
    )..setSessionToken('secret-token');

    await client.logout();
    final revoked = await client.revokeAllSessions();

    expect(paths, ['/api/v1/auth/logout', '/api/v1/auth/revoke-all']);
    expect(revoked, 2);
  });
}
