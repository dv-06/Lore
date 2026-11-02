import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lore_mobile/app.dart';
import 'package:lore_mobile/core/api_config.dart';
import 'package:lore_mobile/core/auth_store.dart';
import 'package:lore_mobile/core/device_authenticator.dart';
import 'package:lore_mobile/data/api_client.dart';

const ApiConfig _config = ApiConfig(baseUrl: 'http://127.0.0.1:8000');

class _MemoryAuthStore implements AuthStore {
  _MemoryAuthStore({this.token = 'test-token', this.autoLockSeconds});

  String? token;
  int? autoLockSeconds;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> writeToken(String token) async => this.token = token;

  @override
  Future<void> clearToken() async => token = null;

  @override
  Future<int?> readAutoLockSeconds() async => autoLockSeconds;

  @override
  Future<void> writeAutoLockSeconds(int seconds) async =>
      autoLockSeconds = seconds;
}

class _FakeAuthenticator implements DeviceAuthenticator {
  _FakeAuthenticator({this.supported = true, this.succeeds = true});

  bool supported;
  bool succeeds;
  int attempts = 0;

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<String> capabilityLabel() async =>
      supported ? 'Fingerprint' : 'Device authentication unavailable';

  @override
  Future<DeviceAuthOutcome> authenticate({required String reason}) async {
    attempts++;
    if (succeeds) return const DeviceAuthOutcome.authenticated();
    return const DeviceAuthOutcome.failed('Authentication failed.');
  }
}

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
  String title = 'Warranty policy',
  String category = 'Finance',
  String documentType = 'Warranty',
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
    'category': category,
    'classification_confidence': 0.82,
    'classification_reasons': ['filename contains warranty'],
    'classification_method': 'keywords',
    'document_title': title,
    'document_date': '2026-01-01',
    'document_type': documentType,
    'issuer': 'Acme',
    'reference_number': 'W-123',
    'tags': ['appliance'],
  };
}

http.Client _backendClient({
  String mode = 'private',
  bool externalConfigured = false,
  bool requireAuth = false,
}) {
  return MockClient((request) async {
    final path = request.url.path;
    final method = request.method;

    const publicPaths = {
      '/api/v1/auth/status',
      '/api/v1/auth/pair',
      '/api/v1/system/status',
    };
    if (requireAuth &&
        !publicPaths.contains(path) &&
        request.headers['authorization'] != 'Bearer test-token') {
      return _json({'detail': 'Authentication required.'}, 401);
    }

    if (path == '/api/v1/auth/session') {
      if (request.headers['authorization'] == null) {
        return _json({'detail': 'Authentication required.'}, 401);
      }
      return _json({
        'authenticated': true,
        'created_at': '2026-11-01T10:00:00Z',
        'expires_at': '2026-12-01T10:00:00Z',
      });
    }
    if (path == '/api/v1/auth/status') {
      return _json({
        'paired': true,
        'pairing_required': false,
        'active_sessions': 1,
        'pairing_expires_at': null,
      });
    }
    if (path == '/api/v1/auth/pair') {
      return _json({
        'token': 'paired-token',
        'created_at': '2026-11-01T10:00:00Z',
        'expires_at': '2026-12-01T10:00:00Z',
      });
    }
    if (path == '/api/v1/auth/logout') {
      return _json({'revoked': true});
    }
    if (path == '/api/v1/auth/revoke-all') {
      return _json({'revoked': 1, 'pairing_required': true});
    }
    if (path == '/api/v1/system/status') {
      return _json({'status': 'ok', 'database': 'ok'});
    }
    if (path == '/api/v1/ask/status') {
      return _json({
        'providers': {
          'extractive': {'available': true, 'reason': null},
          'local-llm': {
            'available': false,
            'reason': 'Local model is not configured.',
          },
          'external': {
            'available': false,
            'reason': 'No external provider is configured.',
          },
        },
        'selected_provider': mode == 'assisted' && externalConfigured
            ? 'external'
            : 'extractive',
        'available': mode == 'assisted' ? externalConfigured : true,
        'mode': mode,
        'local_model_ready': false,
        'external_provider_configured': externalConfigured,
      });
    }
    if (path == '/api/v1/categories') {
      return _json({
        'items': [
          {'category': 'Finance', 'document_count': 1},
          {'category': 'Appliances', 'document_count': 1},
        ],
      });
    }
    if (path == '/api/v1/documents' && method == 'GET') {
      return _json({
        'items': [
          _documentJson(),
          _documentJson(
            id: 'doc-2',
            filename: 'fridge.pdf',
            title: 'Fridge manual',
            category: 'Appliances',
            documentType: 'Manual',
          ),
        ],
        'limit': 100,
        'offset': 0,
      });
    }
    if (path == '/api/v1/search') {
      return _json({
        'query': request.url.queryParameters['q'] ?? '',
        'items': [
          {
            'document_id': 'doc-1',
            'filename': 'warranty.pdf',
            'title': 'Warranty policy',
            'category': 'Finance',
            'snippet': 'The warranty ends on 1 March 2027.',
            'matching_fields': ['extracted_text'],
            'score': 1.0,
            'document_type': 'Warranty',
          },
        ],
        'limit': 50,
        'offset': 0,
      });
    }
    if (path == '/api/v1/documents/doc-1/related') {
      return _json({'document_id': 'doc-1', 'items': <Object>[]});
    }
    if (path == '/api/v1/documents/doc-1') {
      return _json(_documentJson());
    }
    if (path == '/api/v1/ask') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return _json({
        'question': body['question'],
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
      });
    }
    return _json({'detail': 'Unexpected request: $path'}, 404);
  });
}

Future<void> _pumpApp(
  WidgetTester tester, {
  http.Client? backend,
  AuthStore? authStore,
  DeviceAuthenticator? authenticator,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final client = LoreApiClient(
    config: _config,
    httpClient: backend ?? _backendClient(),
  );
  await tester.pumpWidget(
    LoreApp(
      client: client,
      authStore: authStore ?? _MemoryAuthStore(),
      deviceAuthenticator: authenticator ?? _FakeAuthenticator(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('home renders documents from the LORE backend', (tester) async {
    await _pumpApp(tester);

    expect(find.text('Your documents, understood.'), findsOneWidget);
    expect(find.text('2 files'), findsOneWidget);
    expect(find.text('Warranty policy'), findsWidgets);
    expect(find.text('Fridge manual'), findsWidgets);
    expect(find.text('Private'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('documents tab searches the backend', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byIcon(Icons.folder_outlined));
    await tester.pumpAndSettle();

    expect(
      find.text('Find files or explore their connections.'),
      findsOneWidget,
    );
    expect(find.text('2 documents'), findsOneWidget);

    final searchField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'Search your documents',
    );
    expect(searchField, findsOneWidget);

    await tester.enterText(searchField, 'warranty');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('1 result'), findsOneWidget);
    expect(find.text('The warranty ends on 1 March 2027.'), findsOneWidget);
  });

  testWidgets('asking from the Ask tab shows a labeled extractive answer', (
    tester,
  ) async {
    await _pumpApp(tester);

    await tester.tap(find.byIcon(Icons.chat_bubble_outline));
    await tester.pumpAndSettle();

    expect(find.text('Answers from your documents.'), findsOneWidget);
    expect(
      find.text('What should I know about my Finance documents?'),
      findsOneWidget,
    );

    await tester.tap(
      find.text('What should I know about my Finance documents?'),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('The warranty ends on 1 March 2027.'),
      findsWidgets,
    );
    expect(
      find.text(
        'Extractive answer · selected from your documents, not generated',
      ),
      findsOneWidget,
    );
    expect(find.text('View evidence'), findsOneWidget);
    expect(find.text('Ask a follow-up...'), findsOneWidget);
  });

  testWidgets('settings states the real mode and provider availability', (
    tester,
  ) async {
    await _pumpApp(tester);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Your app, your data.'), findsOneWidget);
    expect(find.text('Private →'), findsOneWidget);
    expect(
      find.text(
        'Private Mode is active. No request is sent to an external AI provider.',
      ),
      findsOneWidget,
    );
    expect(find.text('Not installed'), findsOneWidget);

    await tester.tap(find.text('AI processing'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('never switches modes silently'),
      findsOneWidget,
    );
    expect(
      find.text('Unavailable. No external provider is configured.'),
      findsOneWidget,
    );
  });

  testWidgets('assisted mode without a provider is shown as unavailable', (
    tester,
  ) async {
    await _pumpApp(tester, backend: _backendClient(mode: 'assisted'));

    expect(find.text('Assisted'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Assisted →'), findsOneWidget);
    expect(
      find.textContaining('Assisted Mode is selected on the backend'),
      findsOneWidget,
    );
    expect(find.text('Not configured'), findsOneWidget);

    await tester.tap(find.text('AI processing'));
    await tester.pumpAndSettle();

    expect(find.text('Unavailable'), findsOneWidget);
    expect(
      find.textContaining('Unavailable. No external provider is configured.'),
      findsOneWidget,
    );
  });

  testWidgets('assisted mode without a provider blocks the ask workflow', (
    tester,
  ) async {
    await _pumpApp(tester, backend: _backendClient(mode: 'assisted'));

    await tester.tap(find.byIcon(Icons.chat_bubble_outline));
    await tester.pumpAndSettle();

    await tester.tap(
      find.text('What should I know about my Finance documents?'),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
        'Assisted Mode is unavailable because the external AI provider',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('The warranty ends on 1 March 2027.'),
      findsNothing,
    );
  });

  testWidgets('an unreachable backend shows an honest offline state', (
    tester,
  ) async {
    final offlineClient = MockClient(
      (request) async => throw const SocketException('offline'),
    );

    await _pumpApp(tester, backend: offlineClient);

    expect(find.text('Retry'), findsOneWidget);
    expect(
      find.textContaining('Unable to reach the LORE backend'),
      findsWidgets,
    );
    expect(find.text('Documents are unavailable'), findsOneWidget);
  });

  testWidgets('app starts locked and never shows private documents', (
    tester,
  ) async {
    await _pumpApp(tester, authenticator: _FakeAuthenticator(succeeds: false));

    expect(find.text('Your archive is locked'), findsOneWidget);
    expect(find.text('Your documents, understood.'), findsNothing);
    expect(find.text('Warranty policy'), findsNothing);
    expect(find.text('Fridge manual'), findsNothing);
  });

  testWidgets('a failed authentication can be retried successfully', (
    tester,
  ) async {
    final authenticator = _FakeAuthenticator(succeeds: false);
    await _pumpApp(tester, authenticator: authenticator);

    expect(find.text('Your archive is locked'), findsOneWidget);
    expect(authenticator.attempts, 1);

    authenticator.succeeds = true;
    await tester.tap(find.text('Unlock LORE'));
    await tester.pumpAndSettle();

    expect(find.text('Your documents, understood.'), findsOneWidget);
    expect(authenticator.attempts, 2);
  });

  testWidgets('manual lock and unlock restores the authenticated session', (
    tester,
  ) async {
    await _pumpApp(tester, backend: _backendClient(requireAuth: true));

    expect(find.text('Your documents, understood.'), findsOneWidget);
    expect(find.text('Warranty policy'), findsWidgets);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    final settingsScroll = find.byKey(const ValueKey('settings-scroll'));
    for (var i = 0; i < 8 && find.text('Lock now').evaluate().isEmpty; i++) {
      await tester.drag(settingsScroll, const Offset(0, -400));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.text('Lock now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lock now'));
    await tester.pumpAndSettle();

    expect(find.text('Your archive is locked'), findsOneWidget);
    expect(find.text('Warranty policy'), findsNothing);

    await tester.tap(find.text('Unlock LORE'));
    await tester.pumpAndSettle();

    expect(find.text('Your documents, understood.'), findsOneWidget);
    expect(find.text('Warranty policy'), findsWidgets);
    expect(find.text('Authentication required.'), findsNothing);
  });

  testWidgets('a new device pairs before showing any documents', (
    tester,
  ) async {
    final store = _MemoryAuthStore(token: null);
    await _pumpApp(tester, authStore: store);

    expect(find.text('Pair this device'), findsOneWidget);
    expect(find.text('Warranty policy'), findsNothing);

    await tester.enterText(find.byType(TextField), 'TEST-CODE');
    await tester.tap(find.text('Pair and continue'));
    await tester.pumpAndSettle();

    expect(store.token, 'paired-token');
    expect(find.text('Your documents, understood.'), findsOneWidget);
  });

  testWidgets('devices without a screen lock report the limitation', (
    tester,
  ) async {
    await _pumpApp(tester, authenticator: _FakeAuthenticator(supported: false));

    expect(find.text('Your documents, understood.'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    final settingsScroll = find.byKey(const ValueKey('settings-scroll'));
    for (
      var i = 0;
      i < 8 && find.text('Device authentication').evaluate().isEmpty;
      i++
    ) {
      await tester.drag(settingsScroll, const Offset(0, -400));
      await tester.pumpAndSettle();
    }

    expect(find.text('Device authentication'), findsOneWidget);
    expect(find.text('Unavailable'), findsOneWidget);
  });

  testWidgets('backgrounding immediately relocks when configured', (
    tester,
  ) async {
    final store = _MemoryAuthStore(autoLockSeconds: 0);
    await _pumpApp(tester, authStore: store);

    expect(find.text('Your documents, understood.'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('Your archive is locked'), findsOneWidget);
    expect(find.text('Warranty policy'), findsNothing);
  });
}
