import 'package:flutter/material.dart';
import '../core/theme.dart';

/// LORE App Header — matches Stitch design header with LORE branding,
/// privacy shield indicator, and user avatar.
class LoreAppHeader extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final bool showPrivacyBadge;
  final String privacyLabel;
  final VoidCallback? onProfileTap;
  final List<Widget>? actions;

  const LoreAppHeader({
    super.key,
    this.title,
    this.showPrivacyBadge = true,
    this.privacyLabel = 'Private',
    this.onProfileTap,
    this.actions,
  });

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: LoreColors.surface.withValues(alpha: 0.85),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleSpacing: LoreSpacing.marginMobile,
      title: Row(
        children: [
          Text(
            title ?? 'LORE',
            style: LoreTypography.headlineSm.copyWith(
              color: LoreColors.onSurface,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          if (showPrivacyBadge) ...[
            const SizedBox(width: LoreSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: LoreColors.privacyGreen.withValues(alpha: 0.1),
                borderRadius: LoreRadius.borderSm,
                border: Border.all(
                  color: LoreColors.privacyGreen.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.shield_outlined,
                    size: 14,
                    color: LoreColors.privacyGreen,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    privacyLabel,
                    style: LoreTypography.labelSm.copyWith(
                      color: LoreColors.privacyGreen,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        ...?actions,
        Padding(
          padding: const EdgeInsets.only(right: LoreSpacing.marginMobile),
          child: GestureDetector(
            onTap: onProfileTap,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: LoreColors.primary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.person,
                size: 18,
                color: LoreColors.onPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
