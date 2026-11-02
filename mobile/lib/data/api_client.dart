import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/api_config.dart';
import 'models.dart';

/// Typed API client for the LORE FastAPI backend.
///
/// All document content stays between the app and the LORE backend. This
/// client never contacts an external AI provider directly; Assisted Mode is
/// always mediated by the backend's explicit prepare/confirm workflow.
class LoreApiClient {
  final ApiConfig config;
  final http.Client _httpClient;
  String? _sessionToken;

  /// Invoked when the backend rejects a request because the session is no
  /// longer valid. The auth controller clears local credentials in response.
  void Function()? onUnauthorized;

  LoreApiClient({this.config = const ApiConfig(), http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  bool get hasSessionToken => _sessionToken != null;

  void setSessionToken(String? token) {
    _sessionToken = token;
  }

  void dispose() {
    _httpClient.close();
  }

  // ─── Authentication ────────────────────────────────────────

  Future<AuthStatusResponse> getAuthStatus() async {
    final response = await _get('/auth/status', authenticated: false);
    return AuthStatusResponse.fromJson(response);
  }

  Future<AuthPairResponse> pairWithCode(String code) async {
    final response = await _post(
      '/auth/pair',
      body: {'code': code},
      authenticated: false,
    );
    return AuthPairResponse.fromJson(response);
  }

  Future<AuthSessionResponse> getAuthSession() async {
    final response = await _get('/auth/session', notifyUnauthorized: false);
    return AuthSessionResponse.fromJson(response);
  }

  Future<void> logout() async {
    await _post('/auth/logout', notifyUnauthorized: false);
  }

  Future<int> revokeAllSessions() async {
    final response = await _post('/auth/revoke-all', notifyUnauthorized: false);
    return (response['revoked'] as num?)?.toInt() ?? 0;
  }

  // ─── Documents ─────────────────────────────────────────────

  Future<DocumentListResponse> listDocuments({
    int limit = 50,
    int offset = 0,
    String? category,
  }) async {
    final response = await _get(
      '/documents',
      queryParameters: {
        'limit': limit.toString(),
        'offset': offset.toString(),
        'category': ?category,
      },
    );
    return DocumentListResponse.fromJson(response);
  }

  Future<DocumentResponse> getDocument(String id) async {
    final response = await _get('/documents/${Uri.encodeComponent(id)}');
    return DocumentResponse.fromJson(response);
  }

  Future<DocumentResponse> uploadDocument({
    required String filename,
    required List<int> bytes,
  }) {
    return _guard(() async {
      final request = http.MultipartRequest('POST', config.uri('/documents'));
      request.headers.addAll(_headers());
      request.files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      );
      final streamedResponse = await _httpClient
          .send(request)
          .timeout(const Duration(minutes: 2));
      final response = await http.Response.fromStream(streamedResponse);
      _checkResponse(response);
      return DocumentResponse.fromJson(_decodeMap(response.body));
    });
  }

  Future<void> deleteDocument(String id) {
    return _guard(() async {
      final uri = config.uri('/documents/${Uri.encodeComponent(id)}');
      final response = await _httpClient
          .delete(uri, headers: _headers())
          .timeout(config.timeout);
      if (response.statusCode == 204) return;
      _checkResponse(response);
    });
  }

  Future<DocumentResponse> retryExtraction(String id) async {
    final response = await _post(
      '/documents/${Uri.encodeComponent(id)}/retry-extraction',
    );
    return DocumentResponse.fromJson(response);
  }

  Future<DocumentResponse> classifyDocument(String id) async {
    final response = await _post(
      '/documents/${Uri.encodeComponent(id)}/classify',
    );
    return DocumentResponse.fromJson(response);
  }

  Future<DocumentResponse> updateOrganization(
    String id, {
    String? category,
    List<String>? tags,
  }) async {
    final response = await _patch(
      '/documents/${Uri.encodeComponent(id)}/organization',
      body: {'category': ?category, 'tags': ?tags},
    );
    return DocumentResponse.fromJson(response);
  }

  // ─── Categories ────────────────────────────────────────────

  Future<CategoriesResponse> listCategories() async {
    final response = await _get('/categories');
    return CategoriesResponse.fromJson(response);
  }

  // ─── Search ────────────────────────────────────────────────

  Future<SearchResponse> search(
    String query, {
    int limit = 20,
    int offset = 0,
    String? category,
    String? documentType,
  }) async {
    final response = await _get(
      '/search',
      queryParameters: {
        'q': query,
        'limit': limit.toString(),
        'offset': offset.toString(),
        'category': ?category,
        'document_type': ?documentType,
      },
    );
    return SearchResponse.fromJson(response);
  }

  Future<SearchRebuildResponse> rebuildSearchIndex() async {
    final response = await _post('/search/rebuild');
    return SearchRebuildResponse.fromJson(response);
  }

  // ─── Ask LORE ──────────────────────────────────────────────

  Future<AskResponse> askQuestion(String question, {int maxSources = 5}) async {
    final response = await _post(
      '/ask',
      body: {'question': question, 'max_sources': maxSources},
      timeout: const Duration(seconds: 90),
    );
    return AskResponse.fromJson(response);
  }

  Future<AskResponse> askDocumentQuestion(
    String documentId,
    String question, {
    int maxSources = 5,
    bool includeRelated = false,
  }) async {
    final response = await _post(
      '/documents/${Uri.encodeComponent(documentId)}/ask',
      body: {
        'question': question,
        'max_sources': maxSources,
        'include_related': includeRelated,
      },
      timeout: const Duration(seconds: 90),
    );
    return AskResponse.fromJson(response);
  }

  Future<AskStatusResponse> getAskStatus() async {
    final response = await _get('/ask/status');
    return AskStatusResponse.fromJson(response);
  }

  Future<AskModeResponse> setAiMode(String mode) async {
    final response = await _post('/ask/mode', body: {'mode': mode});
    return AskModeResponse.fromJson(response);
  }

  Future<AssistedPrepareResponse> prepareAssistedRequest({
    required String question,
    int maxSources = 5,
    String? documentId,
    bool includeRelated = false,
  }) async {
    final response = await _post(
      '/ask/prepare',
      body: {
        'question': question,
        'max_sources': maxSources,
        'document_id': ?documentId,
        'include_related': includeRelated,
      },
      timeout: const Duration(seconds: 60),
    );
    return AssistedPrepareResponse.fromJson(response);
  }

  Future<AssistedConfirmationResult> confirmAssistedRequest({
    required String requestId,
    required bool approved,
    String? question,
    List<AskEvidence> excerpts = const [],
  }) async {
    final response = await _post(
      '/ask/confirm',
      body: {
        'request_id': requestId,
        'approved': approved,
        'question': ?question,
        'excerpts': excerpts.map((item) => item.toJson()).toList(),
      },
      timeout: const Duration(seconds: 120),
    );
    return AssistedConfirmationResult.fromJson(response);
  }

  Future<void> cancelAssistedRequest(String requestId) async {
    await _post('/ask/cancel', queryParameters: {'request_id': requestId});
  }

  Future<int> revokeAssistedConsent() async {
    final response = await _post('/ask/revoke-consent');
    return (response['count'] as num?)?.toInt() ?? 0;
  }

  // ─── Relationships ─────────────────────────────────────────

  Future<RelatedDocumentsResponse> getRelatedDocuments(
    String documentId, {
    int limit = 20,
  }) async {
    final response = await _get(
      '/documents/${Uri.encodeComponent(documentId)}/related',
      queryParameters: {'limit': limit.toString()},
    );
    return RelatedDocumentsResponse.fromJson(response);
  }

  Future<RelatedDocumentsResponse> recalculateRelatedDocuments(
    String documentId,
  ) async {
    final response = await _post(
      '/documents/${Uri.encodeComponent(documentId)}/related/recalculate',
      timeout: const Duration(seconds: 90),
    );
    return RelatedDocumentsResponse.fromJson(response);
  }

  Future<RelationshipRebuildResponse> rebuildRelationships() async {
    final response = await _post(
      '/relationships/rebuild',
      timeout: const Duration(seconds: 90),
    );
    return RelationshipRebuildResponse.fromJson(response);
  }

  // ─── System ────────────────────────────────────────────────

  Future<SystemStatusResponse> getSystemStatus() async {
    final response = await _get('/system/status');
    return SystemStatusResponse.fromJson(response);
  }

  Future<Map<String, dynamic>> getRootInfo() async {
    return _guard(() async {
      final response = await _httpClient
          .get(config.rootUri('/'))
          .timeout(config.timeout);
      _checkResponse(response);
      return _decodeMap(response.body);
    });
  }

  /// Downloads the unchanged original file through the authenticated API.
  ///
  /// Extracted text is never substituted for the stored original.
  Future<DownloadedDocument> downloadDocument(String id) {
    return _guard(() async {
      final response = await _httpClient
          .get(
            config.uri('/documents/${Uri.encodeComponent(id)}/download'),
            headers: _headers(),
          )
          .timeout(const Duration(seconds: 60));
      _checkResponse(response);
      return DownloadedDocument(
        bytes: response.bodyBytes,
        mediaType: response.headers['content-type'],
      );
    });
  }

  // ─── HTTP helpers ──────────────────────────────────────────

  Map<String, String> _headers({bool json = false}) {
    return {
      if (_sessionToken != null) 'Authorization': 'Bearer $_sessionToken',
      if (json) 'Content-Type': 'application/json',
    };
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String>? queryParameters,
    bool authenticated = true,
    bool notifyUnauthorized = true,
  }) {
    return _guard(() async {
      final response = await _httpClient
          .get(
            config.uri(path, queryParameters),
            headers: authenticated ? _headers() : const {},
          )
          .timeout(config.timeout);
      _checkResponse(response, notifyUnauthorized: notifyUnauthorized);
      return _decodeMap(response.body);
    });
  }

  Future<Map<String, dynamic>> _post(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParameters,
    Duration? timeout,
    bool authenticated = true,
    bool notifyUnauthorized = true,
  }) {
    return _guard(() async {
      final headers = authenticated
          ? _headers(json: true)
          : const {'Content-Type': 'application/json'};
      final response = await _httpClient
          .post(
            config.uri(path, queryParameters),
            headers: headers,
            body: body == null ? null : jsonEncode(body),
          )
          .timeout(timeout ?? config.timeout);
      _checkResponse(response, notifyUnauthorized: notifyUnauthorized);
      return _decodeMap(response.body);
    });
  }

  Future<Map<String, dynamic>> _patch(
    String path, {
    Map<String, dynamic>? body,
  }) {
    return _guard(() async {
      final response = await _httpClient
          .patch(
            config.uri(path),
            headers: _headers(json: true),
            body: body == null ? null : jsonEncode(body),
          )
          .timeout(config.timeout);
      _checkResponse(response);
      return _decodeMap(response.body);
    });
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException(
        statusCode: 0,
        message:
            'The LORE backend did not respond in time. Check the server and '
            'your network connection.',
      );
    } on SocketException {
      throw const ApiException(
        statusCode: 0,
        message:
            'Unable to reach the LORE backend. On an emulator use 10.0.2.2; '
            'on a device use your computer\'s LAN address.',
      );
    } on http.ClientException {
      throw const ApiException(
        statusCode: 0,
        message:
            'Unable to reach the LORE backend. Check that the server is running '
            'and reachable from this device.',
      );
    }
  }

  Map<String, dynamic> _decodeMap(String body) {
    if (body.trim().isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Fall through to the explicit error below.
    }
    throw const ApiException(
      statusCode: -1,
      message: 'The LORE backend returned an unexpected response.',
    );
  }

  void _checkResponse(
    http.Response response, {
    bool notifyUnauthorized = true,
  }) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;

    if (response.statusCode == 401 &&
        notifyUnauthorized &&
        _sessionToken != null) {
      onUnauthorized?.call();
    }

    String message = 'Request failed with status ${response.statusCode}.';
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'];
        if (detail is String && detail.trim().isNotEmpty) {
          message = detail;
        } else if (detail is Map) {
          message = detail['message']?.toString() ?? message;
        } else if (detail is List && detail.isNotEmpty) {
          message = detail
              .map((item) {
                if (item is Map && item['msg'] != null) {
                  return item['msg'].toString();
                }
                return item.toString();
              })
              .join(' ');
        } else if (decoded['message'] is String) {
          message = decoded['message'] as String;
        }
      }
    } on FormatException {
      // Keep the status-based message.
    }
    throw ApiException(statusCode: response.statusCode, message: message);
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;

  const ApiException({required this.statusCode, required this.message});

  bool get isNotFound => statusCode == 404;
  bool get isConflict => statusCode == 409;
  bool get isUnavailable => statusCode == 503;
  bool get isTimeout => statusCode == 408;
  bool get isOffline => statusCode == 0;

  @override
  String toString() => 'ApiException($statusCode): $message';
}
