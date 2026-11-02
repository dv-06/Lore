import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../data/models.dart';
import '../state/app_navigation.dart';
import '../state/app_state.dart';
import '../state/ask_controller.dart';
import '../state/documents_controller.dart';
import '../widgets/ask_thread.dart';
import '../widgets/chat_widgets.dart';
import '../widgets/shared_widgets.dart';
import 'document_detail_screen.dart';

class AskScreen extends StatefulWidget {
  const AskScreen({super.key});

  @override
  State<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends State<AskScreen> {
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  int _lastRenderedItems = 0;

  @override
  void dispose() {
    _composer.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _ask(String question) {
    final trimmed = question.trim();
    if (trimmed.isEmpty) return;
    _composer.clear();
    FocusScope.of(context).unfocus();
    unawaited(context.read<AskController>().ask(trimmed));
  }

  void _scrollToLatest(AskController ask) {
    final itemCount =
        ask.messages.length +
        (ask.isLoading ? 1 : 0) +
        (ask.isAwaitingApproval ? 1 : 0);
    if (itemCount == _lastRenderedItems) return;
    _lastRenderedItems = itemCount;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _openEvidence(AskEvidence evidence) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DocumentDetailScreen(documentId: evidence.documentId),
      ),
    );
  }

  Future<void> _showHistory(AskController ask) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final maxHeight = MediaQuery.of(sheetContext).size.height * 0.6;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Session conversations',
                        style: LoreTypography.headlineSm.copyWith(
                          color: LoreColors.onSurface,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          ask.startNewConversation();
                          _lastRenderedItems = 0;
                        },
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('New'),
                      ),
                    ],
                  ),
                  Text(
                    'These conversations are held in memory for this session '
                    'only and are never saved by the app.',
                    style: LoreTypography.bodySm.copyWith(
                      color: LoreColors.secondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (ask.conversations.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        'No conversations yet.',
                        style: LoreTypography.bodyMd.copyWith(
                          color: LoreColors.secondary,
                        ),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: ask.conversations.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final conversation = ask.conversations[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.chat_bubble_outline,
                              size: 20,
                              color: LoreColors.secondary,
                            ),
                            title: Text(
                              conversation.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: LoreTypography.bodyMd.copyWith(
                                color: LoreColors.onSurface,
                              ),
                            ),
                            subtitle: Text(
                              '${conversation.messages.length} message${conversation.messages.length == 1 ? '' : 's'}',
                              style: LoreTypography.labelSm.copyWith(
                                color: LoreColors.secondary,
                              ),
                            ),
                            onTap: () {
                              Navigator.of(sheetContext).pop();
                              ask.openConversation(conversation);
                              _lastRenderedItems = 0;
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _newConversation(AskController ask) {
    ask.startNewConversation();
    _lastRenderedItems = 0;
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final documents = context.watch<DocumentsController>();
    final ask = context.watch<AskController>();

    if (!ask.hasConversation) {
      return _buildLanding(context, appState, documents, ask);
    }

    _scrollToLatest(ask);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () {
            ask.returnToLanding();
            _lastRenderedItems = 0;
          },
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to Ask LORE',
        ),
        title: Text(
          ask.currentConversation?.title ?? 'Ask LORE',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (ask.conversations.length > 1)
            IconButton(
              onPressed: () => _showHistory(ask),
              icon: const Icon(Icons.history),
              tooltip: 'Session conversations',
            ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'new') _newConversation(ask);
              if (value == 'history') _showHistory(ask);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'new', child: Text('New conversation')),
              PopupMenuItem(value: 'history', child: Text('Session history')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: AskThread(
              messages: ask.messages,
              isLoading: ask.isLoading,
              statusMessage: ask.statusMessage,
              error: ask.error,
              pendingAssisted: ask.pendingAssisted,
              onOpenEvidence: _openEvidence,
              onApproveAssisted: ask.approveAssisted,
              onRejectAssisted: ask.rejectAssisted,
              onDismissError: ask.clearError,
              scrollController: _scrollController,
            ),
          ),
          AskInputBar(
            controller: _composer,
            onSubmit: () => _ask(_composer.text),
            isLoading: ask.isLoading,
            isEnabled: !ask.isAwaitingApproval,
            hintText: ask.isAwaitingApproval
                ? 'Review the request above before asking again'
                : 'Ask a follow-up...',
          ),
        ],
      ),
    );
  }

  Widget _buildLanding(
    BuildContext context,
    AppState appState,
    DocumentsController documents,
    AskController ask,
  ) {
    final suggestions = _suggestedQuestions(documents);
    final latest = ask.latestConversation;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ask LORE',
                        style: LoreTypography.headlineLgMobile.copyWith(
                          color: LoreColors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Answers from your documents.',
                        style: LoreTypography.bodyMd.copyWith(
                          color: LoreColors.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (ask.conversations.isNotEmpty)
                  IconButton(
                    onPressed: () => _showHistory(ask),
                    icon: const Icon(Icons.history),
                    tooltip: 'Session conversations',
                  ),
              ],
            ),
            const SizedBox(height: 16),
            PrivacyStatusIndicator(
              mode: appState.aiMode,
              provider: appState.selectedProvider,
              isAvailable: appState.askStatus?.available ?? false,
            ),
            if (appState.askStatusError != null) ...[
              const SizedBox(height: 10),
              Text(
                'Provider status is unavailable: ${appState.askStatusError}',
                style: LoreTypography.bodySm.copyWith(color: LoreColors.error),
              ),
            ],
            const SizedBox(height: 18),
            _LandingComposer(
              controller: _composer,
              onSend: () => _ask(_composer.text),
            ),
            const SizedBox(height: 24),
            if (documents.hasLoaded && documents.documents.isEmpty)
              _AskEmptyDocuments(
                onBrowse: () => context.read<AppNavigation>().openDocuments(),
              )
            else if (suggestions.isNotEmpty) ...[
              Row(
                children: [
                  Text(
                    'SUGGESTED',
                    style: LoreTypography.labelSm.copyWith(
                      color: LoreColors.secondary,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Tap to ask',
                    style: LoreTypography.labelSm.copyWith(
                      color: LoreColors.secondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (final suggestion in suggestions)
                _SuggestionCard(
                  text: suggestion,
                  onTap: () => _ask(suggestion),
                ),
            ],
            if (latest != null) ...[
              const SizedBox(height: 22),
              Text(
                'LAST CONVERSATION',
                style: LoreTypography.labelSm.copyWith(
                  color: LoreColors.secondary,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              _LastConversationCard(
                conversation: latest,
                onTap: () {
                  ask.openConversation(latest);
                  _lastRenderedItems = 0;
                },
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => _showHistory(ask),
                  child: const Text('View all conversations'),
                ),
              ),
            ],
            const SizedBox(height: 20),
            _AskPrivacyNote(appState: appState),
          ],
        ),
      ),
    );
  }

  List<String> _suggestedQuestions(DocumentsController documents) {
    if (!documents.hasLoaded || documents.documents.isEmpty) {
      return const [];
    }
    final suggestions = <String>[];
    final seen = <String>{};

    void add(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return;
      if (seen.add(trimmed.toLowerCase())) suggestions.add(trimmed);
    }

    final categories = documents.categories
        .where(
          (item) => item.documentCount > 0 && item.category != 'Uncategorized',
        )
        .take(2);
    for (final category in categories) {
      add('What should I know about my ${category.category} documents?');
    }
    for (final document in documents.documents) {
      if (suggestions.length >= 3) break;
      var name = document.displayName;
      if (name.length > 46) name = '${name.substring(0, 43)}...';
      add('What are the key details in $name?');
    }
    return suggestions.take(3).toList(growable: false);
  }
}

class _LandingComposer extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;

  const _LandingComposer({required this.controller, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: LoreColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: LoreColors.structuralLine),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.description_outlined,
            size: 20,
            color: LoreColors.secondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              style: LoreTypography.bodyMd.copyWith(
                color: LoreColors.onSurface,
              ),
              decoration: InputDecoration(
                hintText: 'Ask anything about your files...',
                hintStyle: LoreTypography.bodyMd.copyWith(
                  color: LoreColors.secondary,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                isDense: true,
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              minLines: 1,
              maxLines: 4,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onSend,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: LoreColors.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.arrow_upward,
                size: 19,
                color: LoreColors.onPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _SuggestionCard({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: LoreRadius.borderLg,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: LoreColors.surfaceContainerLowest,
            borderRadius: LoreRadius.borderLg,
            border: Border.all(color: LoreColors.structuralLine),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.auto_awesome_outlined,
                size: 16,
                color: LoreColors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: LoreTypography.bodySm.copyWith(
                    color: LoreColors.onSurface,
                    height: 1.45,
                  ),
                ),
              ),
              const Icon(
                Icons.arrow_outward,
                size: 15,
                color: LoreColors.secondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LastConversationCard extends StatelessWidget {
  final AskConversation conversation;
  final VoidCallback onTap;

  const _LastConversationCard({
    required this.conversation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: LoreRadius.borderLg,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: LoreColors.surfaceContainerLowest,
          borderRadius: LoreRadius.borderLg,
          border: Border.all(color: LoreColors.structuralLine),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: LoreColors.primaryFixed.withValues(alpha: 0.6),
                borderRadius: LoreRadius.borderLg,
              ),
              child: const Icon(
                Icons.chat_bubble_outline,
                size: 18,
                color: LoreColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conversation.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LoreTypography.bodyMd.copyWith(
                      fontWeight: FontWeight.w600,
                      color: LoreColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'This session · ${conversation.messages.length} message${conversation.messages.length == 1 ? '' : 's'}',
                    style: LoreTypography.labelMd.copyWith(
                      color: LoreColors.secondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: LoreColors.secondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _AskEmptyDocuments extends StatelessWidget {
  final VoidCallback onBrowse;

  const _AskEmptyDocuments({required this.onBrowse});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: LoreColors.surfaceContainerLow,
        borderRadius: LoreRadius.borderLg,
        border: Border.all(color: LoreColors.structuralLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.folder_open_outlined,
                size: 20,
                color: LoreColors.secondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'No documents to ask about yet',
                  style: LoreTypography.bodyMd.copyWith(
                    fontWeight: FontWeight.w600,
                    color: LoreColors.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Import documents on the Documents tab. LORE can only answer from '
            'files that your backend has indexed.',
            style: LoreTypography.bodySm.copyWith(
              color: LoreColors.secondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onBrowse,
            child: const Text('Browse documents'),
          ),
        ],
      ),
    );
  }
}

class _AskPrivacyNote extends StatelessWidget {
  final AppState appState;

  const _AskPrivacyNote({required this.appState});

  @override
  Widget build(BuildContext context) {
    final String message;
    if (appState.isAssistedMode) {
      message =
          'Assisted Mode. Every question pauses for your approval before any '
          'excerpt is sent to the configured external provider.';
    } else if (appState.selectedProvider == 'local-llm' &&
        appState.localModelReady) {
      message =
          'Answers come from a local model running on the LORE backend host. '
          'This phone does not run an LLM.';
    } else {
      message =
          'Answers are grounded in documents indexed by your LORE backend. '
          'Private Mode makes no external AI requests.';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: LoreColors.surfaceContainerLow,
        borderRadius: LoreRadius.borderLg,
        border: Border.all(color: LoreColors.structuralLine),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            appState.isAssistedMode
                ? Icons.open_in_new_outlined
                : Icons.lock_outline,
            size: 18,
            color: appState.isAssistedMode
                ? LoreColors.primary
                : LoreColors.privacyGreen,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: LoreTypography.bodySm.copyWith(
                color: LoreColors.secondary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
