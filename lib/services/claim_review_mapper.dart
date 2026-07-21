import '../models/claim_deduplication_result.dart';
import '../models/claim_review_item.dart';
import '../models/grounded_claim_ingestion_result.dart';

class ClaimReviewMapper {
  const ClaimReviewMapper();

  /// Maps a [GroundedClaimIngestionResult] to an ordered list of [ClaimReviewGroup]s.
  ///
  /// Group order: New → Better source → Possible contradiction → Uncertain → Already known.
  /// Empty groups are included so the UI can decide whether to hide them.
  List<ClaimReviewGroup> toGroups(GroundedClaimIngestionResult ingestion) {
    return [
      ClaimReviewGroup(
        label: 'New claims',
        classification: ClaimNoveltyClassification.newClaim,
        items: _toItems(
          ingestion.newClaims,
          selectedByDefault: true,
          canBeSaved: true,
        ),
      ),
      ClaimReviewGroup(
        label: 'Better sources',
        classification: ClaimNoveltyClassification.betterSource,
        items: _toItems(
          ingestion.betterSourceClaims,
          selectedByDefault: true,
          canBeSaved: true,
        ),
      ),
      ClaimReviewGroup(
        label: 'Possible contradictions to review',
        classification: ClaimNoveltyClassification.contradiction,
        items: _toItems(
          ingestion.contradictionClaims,
          selectedByDefault: false,
          canBeSaved: true,
        ),
      ),
      ClaimReviewGroup(
        label: 'Uncertain',
        classification: ClaimNoveltyClassification.uncertain,
        items: _toItems(
          ingestion.uncertainClaims,
          selectedByDefault: false,
          canBeSaved: false,
        ),
      ),
      ClaimReviewGroup(
        label: 'Already in notes',
        classification: ClaimNoveltyClassification.alreadyKnown,
        items: _toItems(
          ingestion.knownClaims,
          selectedByDefault: false,
          canBeSaved: false,
        ),
      ),
    ];
  }

  /// Builds a [ClaimReviewSelectionState] with defaults applied.
  ClaimReviewSelectionState toSelectionState(
      GroundedClaimIngestionResult ingestion) {
    final groups = toGroups(ingestion);
    final all = groups.expand((g) => g.items).toList();
    final defaultSelected = all
        .where((item) => item.selectedByDefault)
        .map((item) => item.id)
        .toSet();
    return ClaimReviewSelectionState(
      allItems: all,
      selectedIds: defaultSelected,
    );
  }

  List<ClaimReviewItem> _toItems(
    List<ClaimDeduplicationResult> results, {
    required bool selectedByDefault,
    required bool canBeSaved,
  }) {
    return results.map((r) {
      return ClaimReviewItem(
        id: r.claim.id,
        text: r.claim.text,
        classification: r.classification,
        citationUrls: List.unmodifiable(r.citationUrls),
        citationTitles: List.unmodifiable(r.claim.citationTitles),
        selectedByDefault: selectedByDefault,
        reason: r.reason,
        matchedLocalEvidenceIds:
            List.unmodifiable(r.matchedLocalEvidence.map((e) => e.id)),
        matchedLocalEvidenceTitles:
            List.unmodifiable(r.matchedLocalEvidence.map((e) => e.title)),
        canBeSaved: canBeSaved,
      );
    }).toList();
  }
}
