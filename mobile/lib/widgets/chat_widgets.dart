import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Chat message bubble used in Ask LORE conversations.
/// Matches Stitch design: user messages aligned right with primary tint,
/// LORE responses aligned left with paper-white surface.
class ChatMessageBubble extends StatelessWidget {
  final String text;
  final bool isUser;
  final String? timestamp;

  const ChatMessageBubble({
    super.key,
    required this.text,
    required this.isUser,
    this.timestamp,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: LoreSpacing.md),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: LoreColors.primaryFixed,
                borderRadius: LoreRadius.borderMd,
              ),
              child: Center(
                child: Text(
                  'L',
                  style: LoreTypography.labelLg.copyWith(
                    color: LoreColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? LoreColors.primary
                    : LoreColors.surfaceContainerLowest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: Radius.circular(isUser ? 14 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 14),
                ),
                border: isUser
                    ? null
                    : Border.all(
                        color: LoreColors.outlineVariant.withValues(alpha: 0.3),
                      ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    style: LoreTypography.bodyMd.copyWith(
                      color: isUser
                          ? LoreColors.onPrimary
                          : LoreColors.onSurface,
                      height: 1.5,
                    ),
                  ),
                  if (timestamp != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      timestamp!,
                      style: LoreTypography.labelSm.copyWith(
                        color: isUser
                            ? LoreColors.onPrimary.withValues(alpha: 0.6)
                            : LoreColors.secondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ask input bar — matches Stitch design: rounded input with
/// attachment and submit actions.
class AskInputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSubmit;
  final VoidCallback? onAttach;
  final bool isLoading;
  final bool isEnabled;
  final String hintText;

  const AskInputBar({
    super.key,
    required this.controller,
    required this.onSubmit,
    this.onAttach,
    this.isLoading = false,
    this.isEnabled = true,
    this.hintText = 'Ask anything about your files...',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LoreSpacing.marginMobile,
        vertical: LoreSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: LoreColors.surface.withValues(alpha: 0.95),
        border: const Border(
          top: BorderSide(
            color: LoreColors.surfaceContainerHighest,
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: LoreColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          padding: const EdgeInsets.all(6),
          child: Row(
            children: [
              if (onAttach != null)
                IconButton(
                  onPressed: onAttach,
                  icon: const Icon(
                    Icons.attach_file_rounded,
                    size: 20,
                    color: LoreColors.secondary,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  padding: EdgeInsets.zero,
                ),
              const SizedBox(width: 4),
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: isEnabled,
                  style: LoreTypography.bodyMd.copyWith(
                    color: LoreColors.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText: hintText,
                    hintStyle: LoreTypography.bodyMd.copyWith(
                      color: LoreColors.secondary,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                    isDense: true,
                  ),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSubmit(),
                  minLines: 1,
                  maxLines: 4,
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: isLoading || !isEnabled ? null : onSubmit,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isLoading || !isEnabled
                        ? LoreColors.secondary
                        : LoreColors.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: LoreColors.onPrimary,
                          ),
                        )
                      : const Icon(
                          Icons.arrow_upward,
                          size: 19,
                          color: LoreColors.onPrimary,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
