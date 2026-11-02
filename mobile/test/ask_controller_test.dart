import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lore_mobile/core/api_config.dart';
import 'package:lore_mobile/data/api_client.dart';
import 'package:lore_mobile/state/app_state.dart';
import 'package:lore_mobile/state/ask_controller.dart';

const ApiConfig _config = ApiConfig(baseUrl: 'http://127.0.0.1:8000');

http.Response _json(Object body, [int statusCode = 200]) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

Map<String, dynamic> _evidenceJson() {
  return {
    'document_id': 'doc-1',
    'filename': 'warranty.pdf',
    'title': 'Warranty policy',
    'location': 'Page 1',
    'snippet': 'The warranty ends on 1 March 2027.',
    'score': 0.91,
    'reason': 'Direct match for warranty period.',
  };
}

Map<String, dynamic> _answerJson(String question) {
  return {
    'question': question,
    'answer': 'The warranty ends on 1 March 2027.',
    'provider': 'extractive',
    'sufficient_evidence': true,
    'evidence': [_evidenceJson()],
    'warnings': <String>[],
  };
}

class _FakeBackend {
  _FakeBackend({
    this.mode = 'private',
    this.externalConfigured = false,
    this.documentAskNotFound = false,
  });

  String mode;
  bool externalConfigured;
  bool documentAskNotFound;

  final List<String> calls = [];
  Map<String, dynamic>? confirmBody;
  String? cancelledRequestId;
  int prepareCount = 0;

  Map<String, dynamic> _statusJson() {
    return {
      'providers': {
        'extractive': {'available': true, 'reason': null},
        'local-llm': {
          'available': false,
          'reason': 'Local model is not configured.',
        },
        'external': {
          'available': externalConfigured,
          'reason': externalConfigured
              ? null
              : 'No external provider is configured.',
        },
      },
      'selected_provider': mode == 'assisted' && externalConfigured
          ? 'external'
          : 'extractive',
      'available': mode == 'assisted' ? externalConfigured : true,
      'mode': mode,
      'local_model_ready': false,
      'external_provider_configured': externalConfigured,
    };
  }

  http.Client get httpClient {
    return MockClient((request) async {
      final path = request.url.path;
      calls.add('${request.method} $path');

      if (path == '/api/v1/ask/status') {
        return _json(_statusJson());
      }
      if (path == '/api/v1/ask/mode') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final requested = body['mode'] as String;
        if (requested == 'assisted' && !externalConfigured) {
          return _json({
            'detail':
                'The external AI provider configuration is incomplete. Set '
                'LORE_EXTERNAL_AI_API_KEY to enable Assisted Mode.',
          }, 503);
        }
        mode = requested;
        return _json({
          'mode': mode,
          'selected_provider': mode == 'assisted' ? 'external' : 'extractive',
          'available': true,
        });
      }
      if (path == '/api/v1/ask/prepare') {
        prepareCount++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return _json({
          'request_id': 'req-1',
          'provider': 'external',
          'question': body['question'],
          'proposed_excerpts': [_evidenceJson()],
          'payload_hash': 'hash-1',
          'expires_at': '2026-10-27T12:00:00Z',
          'status': 'prepared',
        });
      }
      if (path == '/api/v1/ask/confirm') {
        confirmBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _json({
          'approved': true,
          'request_id': confirmBody!['request_id'],
          'provider': 'external',
          'answer': 'External answer after approval.',
          'status': 'confirmed',
        });
      }
      if (path == '/api/v1/ask/cancel') {
        cancelledRequestId = request.url.queryParameters['request_id'];
        return _json({'request_id': cancelledRequestId, 'cancelled': true});
      }
      if (path == '/api/v1/ask') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return _json(_answerJson(body['question'] as String));
      }
      if (path == '/api/v1/documents/doc-9/ask') {
        if (documentAskNotFound) {
          return _json({'detail': 'No evidence found for this document.'}, 404);
        }
        return _json(_answerJson('Document question'));
      }
      return _json({'detail': 'Unexpected request: $path'}, 500);
    });
  }
}

({_FakeBackend backend, AskController ask, AppState appState}) _create(
  _FakeBackend backend,
) {
  final client = LoreApiClient(config: _config, httpClient: backend.httpClient);
  final appState = AppState(client: client);
  final ask = AskController(client: client, appState: appState);
  addTearDown(() {
    ask.dispose();
    appState.dispose();
  });
  return (backend: backend, ask: ask, appState: appState);
}

void main() {
  test('private mode gets an extractive answer from the backend', () async {
    final context = _create(_FakeBackend());
    final ask = context.ask;

    await ask.ask('When does the warranty expire?');

    expect(context.backend.calls, contains('POST /api/v1/ask'));
    expect(
      context.backend.calls.where((call) => call.contains('/ask/prepare')),
      isEmpty,
    );
    expect(ask.error, isNull);
    expect(ask.messages, hasLength(2));
    expect(ask.messages.first.role, AskRole.user);
    expect(ask.messages.last.response?.provider, 'extractive');
    expect(ask.messages.last.response?.evidence.single.location, 'Page 1');
    expect(ask.latestConversationEvidenceCount, 1);
    expect(ask.currentConversation?.title, 'When does the warranty expire?');
  });

  test(
    'private mode never prepares an external request when configured',
    () async {
      final context = _create(_FakeBackend(externalConfigured: true));

      await context.ask.ask('What does the policy cover?');

      expect(context.backend.prepareCount, 0);
      expect(context.backend.calls, contains('POST /api/v1/ask'));
      expect(context.ask.messages.last.response?.provider, 'extractive');
    },
  );

  test('assisted mode waits for approval before confirming', () async {
    final context = _create(
      _FakeBackend(mode: 'assisted', externalConfigured: true),
    );
    final ask = context.ask;

    await context.appState.refreshAskStatus();
    expect(context.appState.isAssistedMode, isTrue);

    await ask.ask('What does the policy cover?');

    expect(context.backend.prepareCount, 1);
    expect(ask.isAwaitingApproval, isTrue);
    expect(ask.pendingAssisted?.requestId, 'req-1');
    expect(ask.pendingAssisted?.proposedExcerpts, hasLength(1));
    expect(ask.messages, hasLength(1));
    expect(ask.messages.single.role, AskRole.user);
    expect(
      context.backend.calls.where((call) => call.contains('/ask/confirm')),
      isEmpty,
    );
    expect(context.backend.calls, isNot(contains('POST /api/v1/ask')));
  });

  test(
    'approving sends only the prepared excerpts and marks the answer',
    () async {
      final context = _create(
        _FakeBackend(mode: 'assisted', externalConfigured: true),
      );
      final ask = context.ask;
      await context.appState.refreshAskStatus();
      await ask.ask('What does the policy cover?');

      await ask.approveAssisted();

      expect(ask.isAwaitingApproval, isFalse);
      expect(context.backend.confirmBody?['request_id'], 'req-1');
      final excerpts =
          context.backend.confirmBody?['excerpts'] as List<dynamic>;
      expect(excerpts, hasLength(1));
      expect(
        (excerpts.single as Map<String, dynamic>)['snippet'],
        'The warranty ends on 1 March 2027.',
      );

      expect(ask.messages, hasLength(2));
      final response = ask.messages.last.response;
      expect(response?.provider, 'external');
      expect(response?.answer, 'External answer after approval.');
      expect(response?.evidence, hasLength(1));
      expect(response?.warnings.single, contains('Assisted Mode'));
    },
  );

  test('rejecting cancels the prepared request without confirming', () async {
    final context = _create(
      _FakeBackend(mode: 'assisted', externalConfigured: true),
    );
    final ask = context.ask;
    await context.appState.refreshAskStatus();
    await ask.ask('What does the policy cover?');

    await ask.rejectAssisted();

    expect(context.backend.cancelledRequestId, 'req-1');
    expect(context.backend.confirmBody, isNull);
    expect(
      context.backend.calls.where((call) => call.contains('/ask/confirm')),
      isEmpty,
    );
    expect(ask.isAwaitingApproval, isFalse);
    expect(ask.messages.last.text, contains('No excerpts were sent'));
    expect(ask.messages.last.response, isNull);
  });

  test('a second question is ignored while approval is pending', () async {
    final context = _create(
      _FakeBackend(mode: 'assisted', externalConfigured: true),
    );
    final ask = context.ask;
    await context.appState.refreshAskStatus();

    await ask.ask('First question');
    await ask.ask('Second question');

    expect(context.backend.prepareCount, 1);
    expect(ask.messages, hasLength(1));
    expect(ask.messages.single.text, 'First question');
  });

  test('blank questions do not create a conversation', () async {
    final context = _create(_FakeBackend());

    await context.ask.ask('   ');

    expect(context.ask.conversations, isEmpty);
    expect(context.backend.calls, isEmpty);
  });

  test('missing evidence produces an honest message, not a citation', () async {
    final context = _create(_FakeBackend(documentAskNotFound: true));
    final ask = context.ask;

    await ask.ask('What is covered?', documentId: 'doc-9');

    expect(ask.error, isNull);
    expect(ask.messages, hasLength(2));
    expect(ask.messages.last.response, isNull);
    expect(ask.messages.last.text, contains('No citation was invented'));
  });

  test('clearing conversations removes all session history', () async {
    final context = _create(_FakeBackend());
    final ask = context.ask;
    await ask.ask('When does the warranty expire?');
    expect(ask.conversations, hasLength(1));

    ask.clearAllConversations();

    expect(ask.conversations, isEmpty);
    expect(ask.currentConversation, isNull);
    expect(ask.latestConversation, isNull);
    expect(ask.messages, isEmpty);
  });

  test(
    'assisted mode without a valid provider blocks before any request',
    () async {
      final context = _create(_FakeBackend(mode: 'assisted'));
      await context.appState.refreshAskStatus();

      expect(context.appState.isAssistedMode, isTrue);
      expect(context.appState.assistedAvailable, isFalse);
      expect(context.appState.privacyLabel, 'Assisted');

      await context.ask.ask('What does the policy cover?');

      expect(context.backend.prepareCount, 0);
      expect(context.backend.calls, isNot(contains('POST /api/v1/ask')));
      expect(context.ask.messages, hasLength(1));
      expect(context.ask.messages.single.role, AskRole.user);
      expect(context.ask.error, contains('not fully configured'));
    },
  );

  test(
    'assisted mode can be enabled only when the backend reports a valid provider',
    () async {
      final unavailable = _create(_FakeBackend());
      await unavailable.appState.refreshAskStatus();

      expect(await unavailable.appState.setAiMode('assisted'), isFalse);
      expect(unavailable.appState.aiMode, 'private');
      expect(
        unavailable.appState.modeError,
        contains('complete external AI provider configuration'),
      );
      expect(
        unavailable.backend.calls,
        isNot(contains('POST /api/v1/ask/mode')),
      );

      final available = _create(_FakeBackend(externalConfigured: true));
      await available.appState.refreshAskStatus();

      expect(available.appState.assistedAvailable, isTrue);
      expect(await available.appState.setAiMode('assisted'), isTrue);
      expect(available.appState.aiMode, 'assisted');
      expect(available.appState.privacyLabel, 'Assisted');
      expect(available.backend.calls, contains('POST /api/v1/ask/mode'));

      expect(await available.appState.setAiMode('private'), isTrue);
      expect(available.appState.aiMode, 'private');
      expect(available.appState.privacyLabel, 'Private');
    },
  );

  test('a stale availability state cannot enable assisted mode', () async {
    final backend = _FakeBackend(externalConfigured: true);
    final context = _create(backend);
    await context.appState.refreshAskStatus();
    expect(context.appState.assistedAvailable, isTrue);

    backend.externalConfigured = false;
    final switched = await context.appState.setAiMode('assisted');

    expect(switched, isFalse);
    expect(context.appState.aiMode, 'private');
    expect(context.appState.modeError, contains('LORE_EXTERNAL_AI_API_KEY'));
    expect(context.appState.assistedAvailable, isFalse);
  });
}
