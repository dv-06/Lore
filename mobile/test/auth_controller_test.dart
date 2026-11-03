import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lore_mobile/core/api_config.dart';
import 'package:lore_mobile/core/auth_store.dart';
import 'package:lore_mobile/core/device_authenticator.dart';
import 'package:lore_mobile/data/api_client.dart';
import 'package:lore_mobile/state/auth_controller.dart';

const ApiConfig _config = ApiConfig(baseUrl: 'http://127.0.0.1:8000');

class _MemoryAuthStore implements AuthStore {
  _MemoryAuthStore({this.token});

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
  _FakeAuthenticator({this.succeeds = true});

  bool supported = true;
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

Map<String, dynamic> _sessionJson() => {
  'authenticated': true,
  'created_at': '2026-11-01T10:00:00Z',
  'expires_at': '2026-12-01T10:00:00Z',
};

class _Backend {
  _Backend({
    this.sessionStatus = 200,
    this.logoutStatus = 200,
    this.logoutThrows = false,
  });

  int sessionStatus;
  int logoutStatus;
  bool logoutThrows;
  final List<http.Request> requests = [];

  http.Client get client => MockClient((request) async {
    requests.add(request);
    final path = request.url.path;
    if (path == '/api/v1/auth/pair') {
      return _json({
        'token': 'paired-token',
        'created_at': '2026-11-01T10:00:00Z',
        'expires_at': '2026-12-01T10:00:00Z',
      });
    }
    if (path == '/api/v1/auth/session') {
      if (sessionStatus == 200) return _json(_sessionJson());
      return _json({'detail': 'Authentication required.'}, sessionStatus);
    }
    if (path == '/api/v1/auth/logout') {
      if (logoutThrows) throw const SocketException('backend offline');
      if (logoutStatus == 200) return _json({'revoked': true});
      return _json({'detail': 'Authentication required.'}, logoutStatus);
    }
    if (path == '/api/v1/documents') {
      return _json({'detail': 'Authentication required.'}, 401);
    }
    return _json({'detail': 'Unexpected request: $path'}, 404);
  });

  List<String?> get sessionAuthHeaders => [
    for (final request in requests)
      if (request.url.path == '/api/v1/auth/session')
        request.headers['authorization'],
  ];
}

AuthController _controller(
  _Backend backend,
  _MemoryAuthStore store,
  _FakeAuthenticator authenticator,
) {
  return AuthController(
    client: LoreApiClient(config: _config, httpClient: backend.client),
    store: store,
    authenticator: authenticator,
  );
}

void main() {
  test(
    'initialize does not install or use the token before device auth',
    () async {
      final store = _MemoryAuthStore(token: 'stored-token');
      final authenticator = _FakeAuthenticator(succeeds: false);
      final backend = _Backend();
      final controller = _controller(backend, store, authenticator);

      await controller.initialize();

      expect(controller.state, AuthState.locked);
      expect(controller.client.hasSessionToken, isFalse);
      expect(backend.requests, isEmpty);
      expect(authenticator.attempts, 1);

      authenticator.succeeds = true;
      await controller.unlock();

      expect(controller.state, AuthState.unlocked);
      expect(controller.client.hasSessionToken, isTrue);
      expect(backend.sessionAuthHeaders, ['Bearer stored-token']);
    },
  );

  test('initialize without a stored token requires pairing', () async {
    final store = _MemoryAuthStore();
    final backend = _Backend();
    final controller = _controller(
      backend,
      store,
      _FakeAuthenticator(succeeds: false),
    );

    await controller.initialize();

    expect(controller.state, AuthState.pairingRequired);
    expect(controller.client.hasSessionToken, isFalse);
    expect(backend.requests, isEmpty);
  });

  test('a revoked stored token is cleared and cannot be revived', () async {
    final store = _MemoryAuthStore(token: 'revoked-token');
    final backend = _Backend(sessionStatus: 401);
    final controller = _controller(backend, store, _FakeAuthenticator());

    await controller.initialize();

    expect(controller.state, AuthState.pairingRequired);
    expect(store.token, isNull);
    expect(controller.client.hasSessionToken, isFalse);
    expect(controller.error, contains('no longer valid'));
    final requestsAfterRevocation = backend.requests.length;

    await controller.unlock();
    expect(controller.state, AuthState.pairingRequired);
    expect(backend.requests.length, requestsAfterRevocation);

    await controller.initialize();
    expect(controller.state, AuthState.pairingRequired);
    expect(controller.client.hasSessionToken, isFalse);
    expect(backend.requests.length, requestsAfterRevocation);
  });

  test('a rejected active request closes the session permanently', () async {
    final store = _MemoryAuthStore(token: 'stored-token');
    final backend = _Backend();
    final controller = _controller(backend, store, _FakeAuthenticator());
    var sessionClosed = 0;
    controller.onSessionClosed = () => sessionClosed++;

    await controller.initialize();
    expect(controller.state, AuthState.unlocked);

    await expectLater(
      controller.client.listDocuments(),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.state, AuthState.pairingRequired);
    expect(store.token, isNull);
    expect(controller.client.hasSessionToken, isFalse);
    expect(controller.error, contains('rejected'));
    expect(sessionClosed, 1);

    await controller.unlock();
    expect(controller.state, AuthState.pairingRequired);
    expect(controller.client.hasSessionToken, isFalse);
  });

  test(
    'pairing keeps the new token out of the client until device auth',
    () async {
      final store = _MemoryAuthStore();
      final authenticator = _FakeAuthenticator(succeeds: false);
      final backend = _Backend();
      final controller = _controller(backend, store, authenticator);

      await controller.initialize();
      expect(controller.state, AuthState.pairingRequired);

      final paired = await controller.pair('PAIR-CODE');

      expect(paired, isTrue);
      expect(store.token, 'paired-token');
      expect(controller.state, AuthState.locked);
      expect(controller.client.hasSessionToken, isFalse);
      expect(backend.requests.map((request) => request.url.path), [
        '/api/v1/auth/pair',
      ]);

      authenticator.succeeds = true;
      await controller.unlock();

      expect(controller.state, AuthState.unlocked);
      expect(controller.client.hasSessionToken, isTrue);
      expect(backend.sessionAuthHeaders, ['Bearer paired-token']);
    },
  );

  test(
    'locking removes the in-memory token but keeps the stored credential',
    () async {
      final store = _MemoryAuthStore(token: 'stored-token');
      final backend = _Backend();
      final controller = _controller(backend, store, _FakeAuthenticator());
      await controller.initialize();
      expect(controller.state, AuthState.unlocked);

      controller.lock();

      expect(controller.state, AuthState.locked);
      expect(controller.client.hasSessionToken, isFalse);
      expect(store.token, 'stored-token');

      await controller.unlock();

      expect(controller.state, AuthState.unlocked);
      expect(controller.client.hasSessionToken, isTrue);
    },
  );

  test(
    'logout clears local credentials when the backend revokes the session',
    () async {
      final store = _MemoryAuthStore(token: 'stored-token');
      final backend = _Backend();
      final controller = _controller(backend, store, _FakeAuthenticator());
      await controller.initialize();

      await controller.logout();

      expect(controller.state, AuthState.pairingRequired);
      expect(controller.client.hasSessionToken, isFalse);
      expect(store.token, isNull);
      expect(controller.error, isNull);
      final logoutRequest = backend.requests.last;
      expect(logoutRequest.url.path, '/api/v1/auth/logout');
      expect(logoutRequest.headers['authorization'], 'Bearer stored-token');
    },
  );

  test(
    'logout without connectivity distinguishes local removal from revocation',
    () async {
      final store = _MemoryAuthStore(token: 'stored-token');
      final backend = _Backend(logoutThrows: true);
      final controller = _controller(backend, store, _FakeAuthenticator());
      await controller.initialize();

      await controller.logout();

      expect(controller.state, AuthState.pairingRequired);
      expect(controller.client.hasSessionToken, isFalse);
      expect(store.token, isNull);
      expect(controller.error, isNotNull);
      expect(controller.error, contains('could not confirm'));
      expect(controller.error, contains('recovery'));
    },
  );

  test('logout treats a 401 as already revoked and clears locally', () async {
    final store = _MemoryAuthStore(token: 'stored-token');
    final backend = _Backend(logoutStatus: 401);
    final controller = _controller(backend, store, _FakeAuthenticator());
    await controller.initialize();

    await controller.logout();

    expect(controller.state, AuthState.pairingRequired);
    expect(store.token, isNull);
    expect(controller.error, isNull);
  });
}
