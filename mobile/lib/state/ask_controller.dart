import 'package:flutter/foundation.dart';

import '../core/error_text.dart';
import '../data/api_client.dart';
import '../data/models.dart';
import 'app_state.dart';

enum AskRole { user, assistant }

class AskMessage {
  final AskRole role;
  final String text;
  final AskResponse? response;
  final DateTime createdAt;

  const AskMessage({
    required this.role,
    required this.text,
    this.response,
    required this.createdAt,
  });
}

class AskConversation {
  AskConversation({required this.id, required this.title});

  final String id;
  String title;
  final List<AskMessage> messages = [];

  bool get hasMessages => messages.isNotEmpty;
}

/// Session-only Ask LORE state.
///
/// Conversations stay in memory and are never written to phone storage. Only
/// short evidence excerpts returned by the backend are held for display.
class AskController extends ChangeNotifier {
  AskController({required this.client, required this.appState});

  final LoreApiClient client;
  final AppState appState;

  final List<AskConversation> _conversations = [];
  AskConversation? _current;
  bool _loading = false;
  String? _error;
  String _statusMessage = '';
  AssistedPrepareResponse? _pendingAssisted;
  int _sequence = 0;

  List<AskConversation> get conversations => List.unmodifiable(_conversations);
  AskConversation? get currentConversation => _current;
  bool get hasConversation => _current?.hasMessages ?? false;
  List<AskMessage> get messages =>
      _current == null ? const [] : List.unmodifiable(_current!.messages);
  AskConversation? get latestConversation =>
      _conversations.isEmpty ? null : _conversations.first;

  int get latestConversationEvidenceCount {
    final conversation = latestConversation;
    if (conversation == null) return 0;
    for (var index = conversation.messages.length - 1; index >= 0; index--) {
      final response = conversation.messages[index].response;
      if (response != null) return response.evidence.length;
    }
    return 0;
  }

  bool get isLoading => _loading;
  String? get error => _error;
  String get statusMessage => _statusMessage;
  AssistedPrepareResponse? get pendingAssisted => _pendingAssisted;
  bool get isAwaitingApproval => _pendingAssisted != null;

  void startNewConversation() {
    _current = null;
    _pendingAssisted = null;
    _error = null;
    _statusMessage = '';
    notifyListeners();
  }

  void openConversation(AskConversation conversation) {
    _current = conversation;
    _pendingAssisted = null;
    _error = null;
    _statusMessage = '';
    notifyListeners();
  }

  void returnToLanding() {
    _current = null;
    _pendingAssisted = null;
    _error = null;
    _statusMessage = '';
    notifyListeners();
  }

  void clearAllConversations() {
    _conversations.clear();
    _current = null;
    _pendingAssisted = null;
    _error = null;
    _statusMessage = '';
    notifyListeners();
  }

  void clearPendingAfterRevocation() {
    if (_pendingAssisted == null) return;
    _pendingAssisted = null;
    _statusMessage = '';
    _appendAssistantText(
      'Prepared assisted requests were revoked. Nothing was sent to an '
      'external provider.',
    );
    notifyListeners();
  }

  Future<void> ask(
    String question, {
    String? documentId,
    bool includeRelated = false,
  }) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty || _loading || _pendingAssisted != null) return;
    if (appState.aiMode == 'assisted' && !appState.assistedAvailable) {
      _error =
          'Assisted Mode is unavailable because the external AI provider is '
          'not fully configured. Switch to Private Mode in Settings to keep '
          'asking questions; nothing was sent externally.';
      _ensureConversation(trimmed);
      _current!.messages.add(
        AskMessage(
          role: AskRole.user,
          text: trimmed,
          createdAt: DateTime.now(),
        ),
      );
      notifyListeners();
      return;
    }

    _error = null;
    _pendingAssisted = null;
    _ensureConversation(trimmed);
    _current!.messages.add(
      AskMessage(role: AskRole.user, text: trimmed, createdAt: DateTime.now()),
    );
    _loading = true;
    _statusMessage = documentId == null
        ? 'Searching your documents and local evidence…'
        : 'Searching this document and its connections…';
    notifyListeners();

    try {
      if (appState.aiMode == 'assisted') {
        _pendingAssisted = await client.prepareAssistedRequest(
          question: trimmed,
          documentId: documentId,
          includeRelated: includeRelated,
        );
        _statusMessage =
            'Awaiting your explicit approval before any excerpt leaves LORE.';
        return;
      }

      final response = documentId == null
          ? await client.askQuestion(trimmed)
          : await client.askDocumentQuestion(
              documentId,
              trimmed,
              includeRelated: includeRelated,
            );
      _appendAssistantResponse(response);
    } on ApiException catch (error) {
      if (documentId != null && error.isNotFound) {
        _appendAssistantText(
          'The available text in this document does not establish a reliable '
          'answer. No citation was invented.',
        );
      } else {
        _error = error.message;
      }
    } catch (error) {
      _error = describeError(error);
    } finally {
      _loading = false;
      if (_pendingAssisted == null) {
        _statusMessage = '';
      }
      notifyListeners();
    }
  }

  Future<void> approveAssisted() async {
    final prepared = _pendingAssisted;
    if (prepared == null || _loading) return;

    _loading = true;
    _statusMessage =
        'Sending only the approved excerpts to the configured provider…';
    notifyListeners();
    try {
      final result = await client.confirmAssistedRequest(
        requestId: prepared.requestId,
        approved: true,
        question: prepared.question,
        excerpts: prepared.proposedExcerpts,
      );
      _pendingAssisted = null;
      if (result.approved) {
        _appendAssistantResponse(
          AskResponse(
            question: prepared.question,
            answer:
                result.answer ??
                'The external provider did not return a usable answer.',
            provider: result.provider ?? 'assisted',
            sufficientEvidence: result.answer != null,
            evidence: prepared.proposedExcerpts,
            warnings: const [
              'Assisted Mode: this answer was produced externally only after '
                  'you approved the excerpts shown for this request.',
            ],
          ),
        );
      } else {
        _appendAssistantText(
          'The request was not approved. Nothing was sent to an external provider.',
        );
      }
    } catch (error) {
      _error = describeError(error);
    } finally {
      _loading = false;
      _statusMessage = '';
      notifyListeners();
    }
  }

  Future<void> rejectAssisted() async {
    final prepared = _pendingAssisted;
    _pendingAssisted = null;
    if (prepared != null) {
      try {
        await client.cancelAssistedRequest(prepared.requestId);
      } catch (_) {
        // The server expires unprepared requests; local cancellation stands.
      }
    }
    _statusMessage = '';
    _appendAssistantText(
      'No excerpts were sent. Your question stayed with the LORE backend.',
    );
    notifyListeners();
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  void _ensureConversation(String question) {
    if (_current != null) return;
    final conversation = AskConversation(
      id: 'session-${++_sequence}',
      title: _titleFor(question),
    );
    _conversations.insert(0, conversation);
    _current = conversation;
  }

  void _appendAssistantResponse(AskResponse response) {
    _current?.messages.add(
      AskMessage(
        role: AskRole.assistant,
        text: response.answer,
        response: response,
        createdAt: DateTime.now(),
      ),
    );
  }

  void _appendAssistantText(String text) {
    _current?.messages.add(
      AskMessage(
        role: AskRole.assistant,
        text: text,
        createdAt: DateTime.now(),
      ),
    );
  }

  String _titleFor(String question) {
    final words = question
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty);
    var title = words.take(8).join(' ');
    if (title.length > 64) {
      title = '${title.substring(0, 61).trimRight()}...';
    }
    return title.isEmpty ? 'Untitled conversation' : title;
  }
}
