import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Privacy/provider status indicator — shows current AI mode and
/// connection status. Matches Stitch privacy badge design.
class PrivacyStatusIndicator extends StatelessWidget {
  final String mode;
  final String provider;
  final bool isAvailable;

  const PrivacyStatusIndicator({
    super.key,
    required this.mode,
    required this.provider,
    required this.isAvailable,
  });

  @override
  Widget build(BuildContext context) {
    final isPrivate = mode == 'private';
    final statusColor = isAvailable
        ? (isPrivate ? LoreColors.privacyGreen : LoreColors.primary)
        : LoreColors.secondary;
    final statusLabel = isPrivate
        ? 'Private'
        : (isAvailable ? 'Assisted' : 'Assisted · Unavailable');
    final providerLabel = _formatProvider(provider);
    final showProvider = isPrivate || isAvailable;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.08),
        borderRadius: LoreRadius.borderMd,
        border: Border.all(color: statusColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Status pip
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: isAvailable ? statusColor : LoreColors.secondary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              showProvider ? '$statusLabel · $providerLabel' : statusLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: LoreTypography.labelSm.copyWith(color: statusColor),
            ),
          ),
        ],
      ),
    );
  }

  String _formatProvider(String provider) {
    switch (provider) {
      case 'extractive':
        return 'Extractive';
      case 'local-llm':
        return 'Local LLM';
      case 'external':
        return 'External AI';
      default:
        return provider;
    }
  }
}

/// Lore search field matching Stitch design: recessed container with
/// search icon and submit button.
class LoreSearchField extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback? onSubmit;
  final ValueChanged<String>? onChanged;
  final String hint;
  final bool showSubmitButton;

  const LoreSearchField({
    super.key,
    required this.controller,
    this.onSubmit,
    this.onChanged,
    this.hint = 'Search your documents...',
    this.showSubmitButton = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: LoreColors.surfaceContainerLowest,
        borderRadius: LoreRadius.borderXl,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 1),
          ),
        ],
        border: Border.all(
          color: LoreColors.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.search, size: 21, color: LoreColors.secondary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              onSubmitted: (_) => onSubmit?.call(),
              style: LoreTypography.bodyMd.copyWith(
                color: LoreColors.onSurface,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: LoreTypography.bodyMd.copyWith(
                  color: LoreColors.secondary,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                isDense: true,
              ),
            ),
          ),
          if (showSubmitButton)
            GestureDetector(
              onTap: onSubmit,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: LoreColors.primary,
                  borderRadius: LoreRadius.borderLg,
                ),
                child: const Icon(
                  Icons.arrow_forward,
                  size: 18,
                  color: LoreColors.onPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Loading, error, empty, and offline state widgets.
class LoreLoadingState extends StatelessWidget {
  final String? message;

  const LoreLoadingState({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: LoreColors.primary,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 16),
              Text(
                message!,
                style: LoreTypography.bodySm.copyWith(
                  color: LoreColors.secondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class LoreErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const LoreErrorState({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: LoreColors.errorContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.error_outline,
                size: 24,
                color: LoreColors.error,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: LoreTypography.bodyMd.copyWith(
                color: LoreColors.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: onRetry,
                child: Text(
                  'Try again',
                  style: LoreTypography.bodyMd.copyWith(
                    color: LoreColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class LoreEmptyState extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget? action;

  const LoreEmptyState({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.folder_open_outlined,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: LoreColors.surfaceContainer,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Icon(icon, size: 28, color: LoreColors.secondary),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: LoreTypography.headlineSm.copyWith(
                color: LoreColors.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                style: LoreTypography.bodyMd.copyWith(
                  color: LoreColors.secondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

class LoreOfflineState extends StatelessWidget {
  final VoidCallback? onRetry;

  const LoreOfflineState({super.key, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return LoreErrorState(
      message:
          'Unable to connect to LORE backend.\nCheck your network and backend status.',
      onRetry: onRetry,
    );
  }
}
