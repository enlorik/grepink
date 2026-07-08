import 'package:flutter/material.dart';

import '../models/claim_review_item.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${group.label} (${group.items.length})',
          style: AppTextStyles.titleMedium,
        ),
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
          key: Key('claim-review-source-${item.id}-$i'),
          title.trim().isEmpty ? url : '$title ($url)',
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
      child: CheckboxListTile(
        value: selected,
        onChanged: item.canBeSaved ? (_) => onToggle() : null,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(item.text, style: AppTextStyles.bodyMedium),
        subtitle: _buildSubtitle(),
      ),
    );
  }
}
