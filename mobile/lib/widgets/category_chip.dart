import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Category chip matching Stitch design: compact rounded badge with
/// optional count and active state.
class CategoryChip extends StatelessWidget {
  final String label;
  final int? count;
  final bool isSelected;
  final VoidCallback? onTap;

  const CategoryChip({
    super.key,
    required this.label,
    this.count,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? LoreColors.onSurface
              : LoreColors.surfaceContainer,
          borderRadius: LoreRadius.borderSm,
          border: Border.all(
            color: isSelected
                ? LoreColors.onSurface
                : LoreColors.structuralLine,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: LoreTypography.labelMd.copyWith(
                color: isSelected
                    ? LoreColors.surfaceContainerLowest
                    : LoreColors.onSurface,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 4),
              Text(
                count.toString(),
                style: LoreTypography.labelSm.copyWith(
                  color: isSelected
                      ? LoreColors.surfaceContainerLowest.withValues(alpha: 0.7)
                      : LoreColors.secondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
