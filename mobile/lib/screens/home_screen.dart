import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/document_style.dart';
import '../core/formatting.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../state/app_navigation.dart';
import '../state/app_state.dart';
import '../state/ask_controller.dart';
import '../state/documents_controller.dart';
import '../widgets/app_header.dart';
import '../widgets/document_card.dart';
import '../widgets/shared_widgets.dart';
import 'document_viewer_screen.dart';
import 'import_documents_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _askFromHome() {
    final question = _searchController.text.trim();
    if (question.isEmpty) {
      context.read<AppNavigation>().openDocuments();
      return;
    }
    _searchController.clear();
    FocusScope.of(context).unfocus();
    unawaited(context.read<AskController>().ask(question));
    context.read<AppNavigation>().openAsk();
  }

  void _openDocument(DocumentResponse document) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DocumentViewerScreen(document: document),
      ),
    );
  }

  Future<void> _openImport() {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ImportDocumentsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final documents = context.watch<DocumentsController>();
    final ask = context.watch<AskController>();

    return Scaffold(
      appBar: LoreAppHeader(
        privacyLabel: appState.privacyLabel,
        onProfileTap: () => context.read<AppNavigation>().openSettings(),
      ),
      body: RefreshIndicator(
        color: LoreColors.primary,
        onRefresh: () async {
          await Future.wait([appState.initialize(), documents.refresh()]);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text(
              'Your documents, understood.',
              style: LoreTypography.headlineLgMobile.copyWith(
                color: LoreColors.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Find what you need. Understand how it connects.',
              style: LoreTypography.bodyMd.copyWith(
                color: LoreColors.secondary,
              ),
            ),
            const SizedBox(height: 20),
            LoreSearchField(
              controller: _searchController,
              hint: 'Ask anything about your files...',
              onSubmit: _askFromHome,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _QuickTile(
                    icon: Icons.folder_open_outlined,
                    label: 'Browse documents',
                    detail: documents.hasLoaded
                        ? '${documents.totalDocumentCount} file${documents.totalDocumentCount == 1 ? '' : 's'}'
                        : 'Your archive',
                    onTap: () => context.read<AppNavigation>().openDocuments(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _QuickTile(
                    icon: Icons.hub_outlined,
                    label: 'Explore connections',
                    detail: 'Across categories',
                    onTap: () => context.read<AppNavigation>().openDocuments(
                      view: DocumentsView.connections,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            _SectionHeading(
              title: 'Recent documents',
              actionLabel: documents.totalDocumentCount > 0 ? 'View all' : null,
              onAction: () => context.read<AppNavigation>().openDocuments(),
            ),
            const SizedBox(height: 6),
            ..._buildRecentDocuments(documents),
            if (ask.latestConversation != null) ...[
              const SizedBox(height: 26),
              const _SectionHeading(title: 'Recent conversation'),
              const SizedBox(height: 6),
              _ConversationCard(
                conversation: ask.latestConversation!,
                evidenceCount: ask.latestConversationEvidenceCount,
                onTap: () {
                  context.read<AskController>().openConversation(
                    ask.latestConversation!,
                  );
                  context.read<AppNavigation>().openAsk();
                },
              ),
            ],
            const SizedBox(height: 26),
            _PrivacyNote(appState: appState),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildRecentDocuments(DocumentsController documents) {
    if (documents.isLoading && documents.documents.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: LoreLoadingState(message: 'Loading your documents...'),
        ),
      ];
    }
    if (documents.error != null && documents.documents.isEmpty) {
      return [
        _InlineNotice(
          icon: Icons.cloud_off_outlined,
          title: 'Documents are unavailable',
          message: documents.error!,
          actionLabel: 'Try again',
          onAction: () => documents.load(),
        ),
      ];
    }
    if (documents.hasLoaded && documents.documents.isEmpty) {
      return [
        _InlineNotice(
          icon: Icons.folder_open_outlined,
          title: 'No documents yet',
          message:
              'Import a PDF, text file, or image. Extraction happens on your '
              'LORE backend.',
          actionLabel: 'Import documents',
          onAction: _openImport,
        ),
      ];
    }
    if (documents.documents.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: LoreLoadingState(),
        ),
      ];
    }

    final recent = documents.recentDocuments;
    return [
      Container(
        decoration: BoxDecoration(
          color: LoreColors.surfaceContainerLowest,
          borderRadius: LoreRadius.borderLg,
          border: Border.all(color: LoreColors.structuralLine),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Column(
          children: [
            for (var index = 0; index < recent.length; index++) ...[
              DocumentCard(
                title: recent[index].displayName,
                subtitle:
                    '${recent[index].categoryLabel} · ${formatDate(recent[index].uploadedAt)}',
                icon: iconForDocument(recent[index]),
                onTap: () => _openDocument(recent[index]),
              ),
              if (index < recent.length - 1)
                const Divider(
                  height: 1,
                  indent: 44,
                  color: LoreColors.surfaceContainerHigh,
                ),
            ],
          ],
        ),
      ),
    ];
  }
}

class _QuickTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback onTap;

  const _QuickTile({
    required this.icon,
    required this.label,
    required this.detail,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: LoreRadius.borderLg,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: LoreColors.surfaceContainerLowest,
          borderRadius: LoreRadius.borderLg,
          border: Border.all(color: LoreColors.structuralLine),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: LoreColors.surfaceContainer,
                borderRadius: LoreRadius.borderLg,
              ),
              child: Icon(icon, size: 18, color: LoreColors.primary),
            ),
            const SizedBox(height: 14),
            Text(
              label,
              style: LoreTypography.bodyMd.copyWith(
                fontWeight: FontWeight.w600,
                color: LoreColors.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              detail,
              style: LoreTypography.labelMd.copyWith(
                color: LoreColors.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _SectionHeading({required this.title, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: LoreTypography.headlineSm.copyWith(
              color: LoreColors.onSurface,
            ),
          ),
        ),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              minimumSize: const Size(0, 32),
            ),
            child: Text(
              '$actionLabel →',
              style: LoreTypography.labelMd.copyWith(color: LoreColors.primary),
            ),
          ),
      ],
    );
  }
}

class _InlineNotice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _InlineNotice({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

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
              Icon(icon, size: 20, color: LoreColors.secondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
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
            message,
            style: LoreTypography.bodySm.copyWith(
              color: LoreColors.secondary,
              height: 1.5,
            ),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

class _ConversationCard extends StatelessWidget {
  final AskConversation conversation;
  final int evidenceCount;
  final VoidCallback onTap;

  const _ConversationCard({
    required this.conversation,
    required this.evidenceCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final messageCount = conversation.messages.length;
    final detail = evidenceCount > 0
        ? 'This session · cited $evidenceCount document${evidenceCount == 1 ? '' : 's'}'
        : 'This session · $messageCount message${messageCount == 1 ? '' : 's'}';

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
                    style: LoreTypography.bodyMd.copyWith(
                      fontWeight: FontWeight.w600,
                      color: LoreColors.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    detail,
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

class _PrivacyNote extends StatelessWidget {
  final AppState appState;

  const _PrivacyNote({required this.appState});

  @override
  Widget build(BuildContext context) {
    final String message;
    if (appState.isAssistedMode) {
      message =
          'Assisted Mode is on. LORE pauses every request until you approve '
          'the excerpts that would leave the backend.';
    } else if (appState.selectedProvider == 'local-llm' &&
        appState.localModelReady) {
      message =
          'Private Mode. A local model on the LORE backend host answers from '
          'your documents. This phone does not run an LLM.';
    } else {
      message =
          'Private Mode. Answers are extracted from documents indexed by your '
          'LORE backend. No external AI requests are made.';
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
