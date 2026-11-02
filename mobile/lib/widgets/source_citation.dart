import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Source citation card from Ask LORE — displays document filename,
/// snippet, location, and score. Matches Stitch evidence card layout.
class SourceCitationCard extends StatelessWidget {
  final String filename;
  final String? title;
  final String snippet;
  final String? location;
  final double? score;
  final String? reason;
  final VoidCallback? onTap;

  const SourceCitationCard({
    super.key,
    required this.filename,
    this.title,
    required this.snippet,
    this.location,
    this.score,
    this.reason,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: LoreSpacing.sm),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: LoreColors.surfaceContainerLowest,
          borderRadius: LoreRadius.borderLg,
          border: Border.all(
            color: LoreColors.outlineVariant.withValues(alpha: 0.3),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: file icon + filename + score
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: LoreColors.surfaceContainer,
                    borderRadius: LoreRadius.borderMd,
                  ),
                  child: const Icon(
                    Icons.description_outlined,
                    size: 15,
                    color: LoreColors.secondary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title ?? filename,
                        style: LoreTypography.bodyMd.copyWith(
                          fontWeight: FontWeight.w500,
                          color: LoreColors.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (location != null)
                        Text(
                          location!,
                          style: LoreTypography.labelMd.copyWith(
                            color: LoreColors.secondary,
                          ),
                        ),
                    ],
                  ),
                ),
                if (score != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: LoreColors.primaryFixed.withValues(alpha: 0.5),
                      borderRadius: LoreRadius.borderSm,
                    ),
                    child: Text(
                      '${(score! * 100).toInt()}%',
                      style: LoreTypography.labelSm.copyWith(
                        color: LoreColors.primary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            // Snippet
            Text(
              snippet,
              style: LoreTypography.bodySm.copyWith(
                color: LoreColors.onSurfaceVariant,
                height: 1.5,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),

            // Reason (if present)
            if (reason != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.verified_outlined,
                    size: 13,
                    color: LoreColors.primary.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      reason!,
                      style: LoreTypography.bodySm.copyWith(
                        color: LoreColors.secondary,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Evidence expansion panel — expandable detail for a single source.
class EvidenceExpansionPanel extends StatefulWidget {
  final String filename;
  final String snippet;
  final String? location;
  final String? reason;
  final double? score;

  const EvidenceExpansionPanel({
    super.key,
    required this.filename,
    required this.snippet,
    this.location,
    this.reason,
    this.score,
  });

  @override
  State<EvidenceExpansionPanel> createState() => _EvidenceExpansionPanelState();
}

class _EvidenceExpansionPanelState extends State<EvidenceExpansionPanel>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: LoreSpacing.sm),
      decoration: BoxDecoration(
        color: LoreColors.surfaceContainerLow,
        borderRadius: LoreRadius.borderLg,
        border: Border.all(color: LoreColors.structuralLine),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: LoreRadius.borderLg,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(
                    Icons.description_outlined,
                    size: 16,
                    color: LoreColors.secondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.filename,
                      style: LoreTypography.bodyMd.copyWith(
                        fontWeight: FontWeight.w500,
                        color: LoreColors.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.location != null) ...[
                    Text(
                      widget.location!,
                      style: LoreTypography.labelMd.copyWith(
                        color: LoreColors.secondary,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  AnimatedRotation(
                    turns: _isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.expand_more,
                      size: 20,
                      color: LoreColors.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(color: LoreColors.structuralLine, height: 1),
                  const SizedBox(height: 10),
                  Text(
                    widget.snippet,
                    style: LoreTypography.bodySm.copyWith(
                      color: LoreColors.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                  if (widget.reason != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      widget.reason!,
                      style: LoreTypography.bodySm.copyWith(
                        color: LoreColors.secondary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            crossFadeState: _isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}
