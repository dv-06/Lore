import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/document_style.dart';
import '../core/formatting.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../state/ask_controller.dart';
import '../widgets/ask_thread.dart';
import '../widgets/chat_widgets.dart';
import '../widgets/shared_widgets.dart';
import 'document_detail_screen.dart';

class DocumentAskScreen extends StatefulWidget {
  const DocumentAskScreen({super.key, required this.document});

  final DocumentResponse document;

  @override
  State<DocumentAskScreen> createState() => _DocumentAskScreenState();
}

class _DocumentAskScreenState extends State<DocumentAskScreen> {
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  AskController? _ask;
  AppState? _appState;
  bool _includeRelated = false;
  int _lastRenderedItems = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ask != null) return;
    _appState = context.read<AppState>();
    _ask = AskController(client: _appState!.client, appState: _appState!);
  }

  @override
  void dispose() {
    _ask?.dispose();
    _composer.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _askQuestion(String question) {
    final ask = _ask;
    final trimmed = question.trim();
    if (ask == null || trimmed.isEmpty) return;
    _composer.clear();
    FocusScope.of(context).unfocus();
    unawaited(
      ask.ask(
        trimmed,
        documentId: widget.document.id,
        includeRelated: _includeRelated,
      ),
    );
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
    if (evidence.documentId == widget.document.id) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DocumentDetailScreen(documentId: evidence.documentId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ask = _ask!;
    final appState = _appState!;
    return ListenableBuilder(
      listenable: ask,
      builder: (context, _) {
        if (ask.hasConversation) _scrollToLatest(ask);
        return Scaffold(
          appBar: AppBar(
            leading: const BackButton(),
            title: Text(
              ask.hasConversation
                  ? (ask.currentConversation?.title ??
                        widget.document.displayName)
                  : 'Ask about this document',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          body: Column(
            children: [
              Expanded(
                child: ask.hasConversation
                    ? AskThread(
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
                      )
                    : _buildLanding(ask, appState),
              ),
              if (ask.hasConversation)
                _RelatedToggle(
                  value: _includeRelated,
                  onChanged: (value) => setState(() => _includeRelated = value),
                ),
              AskInputBar(
                controller: _composer,
                onSubmit: () => _askQuestion(_composer.text),
                isLoading: ask.isLoading,
                isEnabled: !ask.isAwaitingApproval,
                hintText: ask.isAwaitingApproval
                    ? 'Review the request above before asking again'
                    : 'Ask about this document...',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLanding(AskController ask, AppState appState) {
    final document = widget.document;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: LoreColors.surfaceContainerLowest,
            borderRadius: LoreRadius.borderLg,
            border: Border.all(color: LoreColors.structuralLine),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: LoreColors.surfaceContainerLow,
                  borderRadius: LoreRadius.borderLg,
                ),
                child: Icon(
                  iconForDocument(document),
                  size: 20,
                  color: LoreColors.secondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LoreTypography.bodyMd.copyWith(
                        fontWeight: FontWeight.w600,
                        color: LoreColors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${document.categoryLabel} · ${formatDate(document.uploadedAt)}',
                      style: LoreTypography.bodySm.copyWith(
                        color: LoreColors.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        PrivacyStatusIndicator(
          mode: appState.aiMode,
          provider: appState.selectedProvider,
          isAvailable: appState.askStatus?.available ?? false,
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: LoreColors.surfaceContainerLow,
            borderRadius: LoreRadius.borderLg,
            border: Border.all(color: LoreColors.structuralLine),
          ),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _includeRelated,
            onChanged: (value) => setState(() => _includeRelated = value),
            activeThumbColor: LoreColors.primary,
            title: Text(
              'Include related documents',
              style: LoreTypography.bodySm.copyWith(
                color: LoreColors.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: Text(
              'Also search files that LORE has connected to this one.',
              style: LoreTypography.bodySm.copyWith(
                color: LoreColors.secondary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'SUGGESTED',
          style: LoreTypography.labelSm.copyWith(
            color: LoreColors.secondary,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        for (final suggestion in const [
          'What is this document about?',
          'What are the key dates in this document?',
          'Who issued this document?',
        ])
          _Suggestion(text: suggestion, onTap: () => _askQuestion(suggestion)),
        const SizedBox(height: 18),
        _DocumentPrivacyNote(appState: appState),
      ],
    );
  }
}

class _RelatedToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _RelatedToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      color: LoreColors.surfaceContainerLow,
      child: Row(
        children: [
          const Icon(Icons.hub_outlined, size: 15, color: LoreColors.secondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Include related documents in follow-ups',
              style: LoreTypography.labelMd.copyWith(
                color: LoreColors.secondary,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: LoreColors.primary,
          ),
        ],
      ),
    );
  }
}

class _Suggestion extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _Suggestion({required this.text, required this.onTap});

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

class _DocumentPrivacyNote extends StatelessWidget {
  final AppState appState;

  const _DocumentPrivacyNote({required this.appState});

  @override
  Widget build(BuildContext context) {
    final message = appState.isAssistedMode
        ? 'Assisted Mode. This question pauses for your approval before any '
              'excerpt is sent to the configured external provider.'
        : 'Private Mode. Answers are extracted from this document and its '
              'connections on the LORE backend. No external AI requests are made.';
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
