import 'claim_deduplication_result.dart';

class ClaimReviewItem {
  final String id;
  final String text;
  final ClaimNoveltyClassification classification;
  final List<String> citationUrls;
  final List<String> citationTitles;
  final bool selectedByDefault;
  final String reason;
  final List<String> matchedLocalEvidenceIds;
  final bool canBeSaved;

  const ClaimReviewItem({
    required this.id,
    required this.text,
    required this.classification,
    required this.citationUrls,
    required this.citationTitles,
    required this.selectedByDefault,
    required this.reason,
    required this.matchedLocalEvidenceIds,
    required this.canBeSaved,
  });
}

class ClaimReviewGroup {
  final String label;
  final ClaimNoveltyClassification classification;
  final List<ClaimReviewItem> items;

  const ClaimReviewGroup({
    required this.label,
    required this.classification,
    required this.items,
  });

  bool get isEmpty => items.isEmpty;
}

class ClaimReviewSelectionState {
  final List<ClaimReviewItem> allItems;
  final Set<String> selectedIds;

  const ClaimReviewSelectionState({
    required this.allItems,
    required this.selectedIds,
  });

  List<ClaimReviewItem> get selectedSaveableItems => allItems
      .where((item) => item.canBeSaved && selectedIds.contains(item.id))
      .toList();

  ClaimReviewSelectionState toggle(String id) {
    final next = Set<String>.from(selectedIds);
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    return ClaimReviewSelectionState(allItems: allItems, selectedIds: next);
  }
}
