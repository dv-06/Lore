import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Document card matching Stitch design: white surface, hairline border,
/// file icon, title, category, date, and chevron.
class DocumentCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? category;
  final String? documentType;
  final IconData icon;
  final VoidCallback? onTap;

  const DocumentCard({
    super.key,
    required this.title,
    this.subtitle,
    this.category,
    this.documentType,
    this.icon = Icons.description_outlined,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: LoreRadius.borderLg,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: LoreColors.surfaceContainer,
                borderRadius: LoreRadius.borderLg,
              ),
              child: Icon(icon, size: 18, color: LoreColors.secondary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: LoreTypography.bodyMd.copyWith(
                      fontWeight: FontWeight.w500,
                      color: LoreColors.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: LoreTypography.bodySm.copyWith(
                        color: LoreColors.secondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
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

/// Full document list item with border dividers, matching Stitch doc listing.
class DocumentListItem extends StatelessWidget {
  final String title;
  final String? category;
  final String? date;
  final String? documentType;
  final String? sizeLabel;
  final VoidCallback? onTap;

  const DocumentListItem({
    super.key,
    required this.title,
    this.category,
    this.date,
    this.documentType,
    this.sizeLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: LoreColors.surfaceContainerHighest,
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: LoreColors.surfaceContainerLow,
                borderRadius: LoreRadius.borderLg,
              ),
              child: const Icon(
                Icons.description_outlined,
                size: 18,
                color: LoreColors.secondary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: LoreTypography.bodyMd.copyWith(
                      fontWeight: FontWeight.w500,
                      color: LoreColors.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (category != null)
                        Text(
                          category!,
                          style: LoreTypography.bodySm.copyWith(
                            color: LoreColors.secondary,
                          ),
                        ),
                      if (category != null && date != null)
                        Text(
                          ' · ',
                          style: LoreTypography.bodySm.copyWith(
                            color: LoreColors.secondary,
                          ),
                        ),
                      if (date != null)
                        Text(
                          date!,
                          style: LoreTypography.bodySm.copyWith(
                            color: LoreColors.secondary,
                          ),
                        ),
                      if (sizeLabel != null) ...[
                        Text(
                          ' · ',
                          style: LoreTypography.bodySm.copyWith(
                            color: LoreColors.secondary,
                          ),
                        ),
                        Text(
                          sizeLabel!,
                          style: LoreTypography.labelMd.copyWith(
                            color: LoreColors.secondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (documentType != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: LoreColors.surfaceContainer,
                  borderRadius: LoreRadius.borderSm,
                  border: Border.all(color: LoreColors.structuralLine),
                ),
                child: Text(
                  documentType!.toUpperCase(),
                  style: LoreTypography.labelSm.copyWith(
                    color: LoreColors.secondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
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
