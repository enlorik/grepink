import 'package:flutter/material.dart';

import '../models/claim_deduplication_result.dart';
import '../models/claim_review_item.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Above this many items, the "Already in your notes" section starts
/// collapsed so a long list of known claims doesn't push the useful
/// (new/better-source) groups below the fold.
const int _alreadyKnownCollapseThreshold = 3;

/// Displays grouped claim review results and lets the user toggle which
/// claims are selected. This panel never saves or persists anything itself —
/// it only reflects and mutates [selectedIds] via [onToggle].
class ClaimReviewGroupsPanel extends StatelessWidget {
  final List<ClaimReviewGroup> groups;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggle;

  const ClaimReviewGroupsPanel({
    super.key,
    required this.groups,
    required this.selectedIds,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final visibleGroups = groups.where((group) => group.items.isNotEmpty).toList();

    if (visibleGroups.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      key: const Key('claim-review-groups-panel'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.dividerBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Claim review', style: AppTextStyles.titleLarge),
          const SizedBox(height: 12),
          for (final group in visibleGroups) ...[
            _ClaimReviewGroupSection(
              group: group,
              selectedIds: selectedIds,
              onToggle: onToggle,
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

class _ClaimReviewGroupSection extends StatelessWidget {
  final ClaimReviewGroup group;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggle;

  const _ClaimReviewGroupSection({
    required this.group,
    required this.selectedIds,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final headerText = '${group.label} (${group.items.length})';

    // Already-known claims aren't saveable and are usually the least
    // actionable group, so they get a compact, collapsible treatment
    // instead of always taking up full space like the other groups.
    if (group.classification == ClaimNoveltyClassification.alreadyKnown) {
      // Key on whether the group starts collapsed so a new review that
      // crosses the collapse threshold recreates the ExpansionTile with the
      // correct initiallyExpanded — preventing stale expansion state from
      // the previous session leaking into the new one.
      final collapsedByDefault = group.items.length > _alreadyKnownCollapseThreshold;
      // Key includes a hash of item IDs so that a new review result (different
      // items) always recreates the tile — even when both results are on the
      // same side of the threshold (same bool, same stale expansion state).
      return _AlreadyKnownGroupSection(
        key: ValueKey(Object.hashAll([
          collapsedByDefault,
          ...group.items.map((i) => i.id),
        ])),
        group: group,
        headerText: headerText,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(headerText, style: AppTextStyles.titleMedium),
        if (group.classification == ClaimNoveltyClassification.betterSource) ...[
          const SizedBox(height: 4),
          Text(
            key: const Key('better-source-helper-text'),
            'Already in your notes, but this source may improve the existing claim.',
            style: AppTextStyles.bodySmall,
          ),
        ],
        const SizedBox(height: 8),
        for (final item in group.items)
          _ClaimReviewItemTile(
            key: Key('claim-review-item-${item.id}'),
            item: item,
            selected: selectedIds.contains(item.id),
            onToggle: () => onToggle(item.id),
          ),
      ],
    );
  }
}

/// Compact, collapsible rendering for the "Already in notes" group. Starts
/// collapsed once there are enough items that showing them all would push
/// the actionable groups below the fold; the user can still expand it.
class _AlreadyKnownGroupSection extends StatelessWidget {
  final ClaimReviewGroup group;
  final String headerText;

  const _AlreadyKnownGroupSection({
    super.key,
    required this.group,
    required this.headerText,
  });

  @override
  Widget build(BuildContext context) {
    final collapsedByDefault = group.items.length > _alreadyKnownCollapseThreshold;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const Key('already-known-section'),
        initiallyExpanded: !collapsedByDefault,
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Text(headerText, style: AppTextStyles.titleMedium),
        subtitle: Text(
          'Not saved — shown so you know Grepink already has this.',
          style: AppTextStyles.bodySmall,
        ),
        children: [
          for (final item in group.items)
            _ClaimReviewItemTile(
              key: Key('claim-review-item-${item.id}'),
              item: item,
              selected: false,
              onToggle: () {},
            ),
        ],
      ),
    );
  }
}

class _ClaimReviewItemTile extends StatelessWidget {
  final ClaimReviewItem item;
  final bool selected;
  final VoidCallback onToggle;

  const _ClaimReviewItemTile({
    super.key,
    required this.item,
    required this.selected,
    required this.onToggle,
  });

  Widget? _buildSubtitle() {
    final lines = <Widget>[];
    if (item.reason.trim().isNotEmpty) {
      lines.add(Text(item.reason, style: AppTextStyles.bodySmall));
    }
    for (var i = 0; i < item.citationUrls.length; i++) {
      final url = item.citationUrls[i];
      final title = i < item.citationTitles.length ? item.citationTitles[i] : '';
      lines.add(
        Text(
          title.trim().isEmpty ? url : '$title ($url)',
          key: Key('claim-review-source-${item.id}-$i'),
          style: AppTextStyles.bodySmall,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    // Only alreadyKnown and betterSource results have confirmed local matches.
    // For newClaim and others the dedup service may return a low-similarity
    // bestMatch in matchedLocalEvidence even though the claim is genuinely new,
    // so showing "Matches your notes" there would be misleading.
    final isConfirmedMatch =
        item.classification == ClaimNoveltyClassification.alreadyKnown ||
        item.classification == ClaimNoveltyClassification.betterSource;
    if (isConfirmedMatch && item.matchedLocalEvidenceIds.isNotEmpty) {
      final matches = <String>[];
      for (var i = 0; i < item.matchedLocalEvidenceIds.length; i++) {
        final title = i < item.matchedLocalEvidenceTitles.length
            ? item.matchedLocalEvidenceTitles[i]
            : '';
        matches.add(
          title.trim().isEmpty ? item.matchedLocalEvidenceIds[i] : title,
        );
      }
      lines.add(
        Text(
          key: Key('claim-review-matched-evidence-${item.id}'),
          'Matches your notes: ${matches.join(', ')}',
          style: AppTextStyles.bodySmall,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    if (lines.isEmpty) return null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: AppColors.aiResponseBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.dividerBorder),
      ),
      child: Material(
        color: Colors.transparent,
        child: CheckboxListTile(
          value: selected,
          onChanged: item.canBeSaved ? (_) => onToggle() : null,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(item.text, style: AppTextStyles.bodyMedium),
          subtitle: _buildSubtitle(),
        ),
      ),
    );
  }
}
