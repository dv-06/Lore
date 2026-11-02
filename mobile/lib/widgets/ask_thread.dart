import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/models.dart';
import '../state/ask_controller.dart';
import 'chat_widgets.dart';
import 'source_citation.dart';

class AskThread extends StatelessWidget {
  final List<AskMessage> messages;
  final bool isLoading;
  final String statusMessage;
  final String? error;
  final AssistedPrepareResponse? pendingAssisted;
  final ValueChanged<AskEvidence>? onOpenEvidence;
  final VoidCallback? onApproveAssisted;
  final VoidCallback? onRejectAssisted;
  final VoidCallback? onDismissError;
  final ScrollController? scrollController;

  const AskThread({
    super.key,
    required this.messages,
    this.isLoading = false,
    this.statusMessage = '',
    this.error,
    this.pendingAssisted,
    this.onOpenEvidence,
    this.onApproveAssisted,
    this.onRejectAssisted,
    this.onDismissError,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        for (final message in messages)
          if (message.role == AskRole.user)
            ChatMessageBubble(text: message.text, isUser: true)
          else
            _AssistantMessage(message: message, onOpenEvidence: onOpenEvidence),
        if (pendingAssisted != null)
          _AssistedApprovalCard(
            prepared: pendingAssisted!,
            isLoading: isLoading,
            onApprove: onApproveAssisted,
            onReject: onRejectAssisted,
          ),
        if (isLoading) _ThinkingRow(message: statusMessage),
        if (error != null)
          _ErrorNote(message: error!, onDismiss: onDismissError),
      ],
    );
  }
}

class _AssistantMessage extends StatelessWidget {
  final AskMessage message;
  final ValueChanged<AskEvidence>? onOpenEvidence;

  const _AssistantMessage({required this.message, this.onOpenEvidence});

  @override
  Widget build(BuildContext context) {
    final response = message.response;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ChatMessageBubble(text: message.text, isUser: false),
        if (response != null) ...[
          Padding(
            padding: const EdgeInsets.only(left: 36, bottom: 8),
            child: _ProviderNote(response: response),
          ),
          if (response.warnings.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 36, bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final warning in response.warnings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.info_outline,
                            size: 13,
                            color: LoreColors.secondary,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              warning,
                              style: LoreTypography.bodySm.copyWith(
                                color: LoreColors.secondary,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          if (response.evidence.isNotEmpty)
            _SourcesBlock(
              evidence: response.evidence,
              onOpenEvidence: onOpenEvidence,
            ),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class _ProviderNote extends StatelessWidget {
  final AskResponse response;

  const _ProviderNote({required this.response});

  @override
  Widget build(BuildContext context) {
    final String label;
    final IconData icon;
    final Color color;
    switch (response.provider) {
      case 'extractive':
        label =
            'Extractive answer · selected from your documents, not generated';
        icon = Icons.format_quote;
        color = LoreColors.privacyGreen;
      case 'local-llm':
        label =
            'Local LLM · generated on the LORE backend host, not on this phone';
        icon = Icons.memory;
        color = LoreColors.tertiary;
      case 'assisted':
      case 'external':
        label = 'Assisted answer · generated externally after your approval';
        icon = Icons.open_in_new_outlined;
        color = LoreColors.primary;
      default:
        label = 'Provider: ${response.provider}';
        icon = Icons.info_outline;
        color = LoreColors.secondary;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            label,
            style: LoreTypography.labelSm.copyWith(color: color, height: 1.45),
          ),
        ),
      ],
    );
  }
}

class _SourcesBlock extends StatefulWidget {
  final List<AskEvidence> evidence;
  final ValueChanged<AskEvidence>? onOpenEvidence;

  const _SourcesBlock({required this.evidence, this.onOpenEvidence});

  @override
  State<_SourcesBlock> createState() => _SourcesBlockState();
}

class _SourcesBlockState extends State<_SourcesBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'SOURCES',
                style: LoreTypography.labelSm.copyWith(
                  color: LoreColors.secondary,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: LoreColors.surfaceContainerHigh,
                  borderRadius: LoreRadius.borderSm,
                ),
                child: Text(
                  '${widget.evidence.length}',
                  style: LoreTypography.labelSm.copyWith(
                    color: LoreColors.secondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final item in widget.evidence)
            _SourceRow(
              evidence: item,
              onTap: widget.onOpenEvidence == null
                  ? null
                  : () => widget.onOpenEvidence!(item),
            ),
          TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              minimumSize: const Size(0, 30),
            ),
            child: Text(
              _expanded ? 'Hide evidence' : 'View evidence',
              style: LoreTypography.labelMd.copyWith(color: LoreColors.primary),
            ),
          ),
          if (_expanded)
            for (final item in widget.evidence)
              EvidenceExpansionPanel(
                filename: item.displayName,
                snippet: item.snippet,
                location: item.location,
                reason: item.reason,
                score: item.score,
              ),
        ],
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  final AskEvidence evidence;
  final VoidCallback? onTap;

  const _SourceRow({required this.evidence, this.onTap});

  @override
  Widget build(BuildContext context) {
    final subtitle = evidence.location ?? evidence.reason;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: LoreRadius.borderMd,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: LoreColors.surfaceContainerLowest,
            borderRadius: LoreRadius.borderMd,
            border: Border.all(color: LoreColors.structuralLine),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.description_outlined,
                size: 16,
                color: LoreColors.secondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      evidence.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LoreTypography.bodySm.copyWith(
                        color: LoreColors.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LoreTypography.labelSm.copyWith(
                        color: LoreColors.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 16,
                color: LoreColors.secondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssistedApprovalCard extends StatelessWidget {
  final AssistedPrepareResponse prepared;
  final bool isLoading;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const _AssistedApprovalCard({
    required this.prepared,
    required this.isLoading,
    this.onApprove,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 36, bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: LoreColors.primaryFixed.withValues(alpha: 0.35),
        borderRadius: LoreRadius.borderLg,
        border: Border.all(color: LoreColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.shield_outlined,
                size: 18,
                color: LoreColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Review before sending',
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
            'Assisted Mode is on. Nothing has left LORE yet. Approve only if you '
            'want these excerpts sent to ${prepared.provider}. This request '
            'expires shortly.',
            style: LoreTypography.bodySm.copyWith(
              color: LoreColors.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          if (prepared.proposedExcerpts.isEmpty)
            Text(
              'No document excerpts were proposed for this question.',
              style: LoreTypography.bodySm.copyWith(
                color: LoreColors.secondary,
              ),
            )
          else
            for (
              var index = 0;
              index < prepared.proposedExcerpts.length;
              index++
            )
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: LoreColors.surfaceContainerLowest.withValues(
                    alpha: 0.8,
                  ),
                  borderRadius: LoreRadius.borderMd,
                  border: Border.all(color: LoreColors.structuralLine),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${index + 1}. ${prepared.proposedExcerpts[index].displayName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LoreTypography.bodySm.copyWith(
                        fontWeight: FontWeight.w600,
                        color: LoreColors.onSurface,
                      ),
                    ),
                    if (prepared.proposedExcerpts[index].location != null)
                      Text(
                        prepared.proposedExcerpts[index].location!,
                        style: LoreTypography.labelSm.copyWith(
                          color: LoreColors.secondary,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      prepared.proposedExcerpts[index].snippet,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: LoreTypography.bodySm.copyWith(
                        color: LoreColors.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: isLoading ? null : onReject,
                child: const Text('Keep private'),
              ),
              const SizedBox(width: 6),
              FilledButton(
                onPressed: isLoading ? null : onApprove,
                child: const Text('Approve & send'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ThinkingRow extends StatelessWidget {
  final String message;

  const _ThinkingRow({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 36, top: 4, bottom: 12),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.8,
              color: LoreColors.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message.isEmpty ? 'Searching your documents...' : message,
              style: LoreTypography.bodySm.copyWith(
                color: LoreColors.secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorNote extends StatelessWidget {
  final String message;
  final VoidCallback? onDismiss;

  const _ErrorNote({required this.message, this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 36, bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: LoreColors.errorContainer.withValues(alpha: 0.6),
        borderRadius: LoreRadius.borderMd,
        border: Border.all(color: LoreColors.error.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 18, color: LoreColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: LoreTypography.bodySm.copyWith(
                color: LoreColors.onErrorContainer,
                height: 1.45,
              ),
            ),
          ),
          if (onDismiss != null)
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close, size: 16),
              color: LoreColors.onErrorContainer,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }
}
