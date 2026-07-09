import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/claim_deduplication_result.dart';
import 'package:grepink/models/evidence_item.dart';
import 'package:grepink/models/extracted_claim.dart';
import 'package:grepink/models/grounded_claim_ingestion_result.dart';
import 'package:grepink/services/claim_review_mapper.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

ClaimDeduplicationResult _result({
  String id = 'claim-1',
  String text = 'Some claim.',
  ClaimNoveltyClassification classification = ClaimNoveltyClassification.newClaim,
  List<String> citationUrls = const [],
  List<EvidenceItem> matchedLocal = const [],
  String reason = 'test reason',
}) =>
    ClaimDeduplicationResult(
      claim: ExtractedClaim(
        id: id,
        text: text,
        citationUrls: citationUrls,
        citationTitles: const [],
        sourceAnswerProvider: 'test',
        sourceQuestion: 'q',
        order: 0,
      ),
      classification: classification,
      matchedLocalEvidence: matchedLocal,
      reason: reason,
      citationUrls: citationUrls,
    );

EvidenceItem _evidence(String id, {String title = 'Note'}) => EvidenceItem(
      id: id,
      type: EvidenceType.localNote,
      title: title,
      content: 'content',
    );

GroundedClaimIngestionResult _ingestion({
  List<ClaimDeduplicationResult> newClaims = const [],
  List<ClaimDeduplicationResult> knownClaims = const [],
  List<ClaimDeduplicationResult> betterSourceClaims = const [],
  List<ClaimDeduplicationResult> contradictionClaims = const [],
  List<ClaimDeduplicationResult> uncertainClaims = const [],
}) =>
    GroundedClaimIngestionResult(
      question: 'What is gravity?',
      answerText: 'answer',
      providerName: 'test',
      newClaims: newClaims,
      knownClaims: knownClaims,
      betterSourceClaims: betterSourceClaims,
      contradictionClaims: contradictionClaims,
      uncertainClaims: uncertainClaims,
      citations: const [],
    );

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  const mapper = ClaimReviewMapper();

  group('ClaimReviewMapper.toGroups', () {
    test('new claims are selected by default', () {
      final groups = mapper.toGroups(_ingestion(
        newClaims: [_result(id: 'n1', classification: ClaimNoveltyClassification.newClaim)],
      ));

      final newGroup = groups.firstWhere(
          (g) => g.classification == ClaimNoveltyClassification.newClaim);
      expect(newGroup.items.first.selectedByDefault, isTrue);
    });

    test('already-known claims are not selected by default', () {
      final groups = mapper.toGroups(_ingestion(
        knownClaims: [_result(id: 'k1', classification: ClaimNoveltyClassification.alreadyKnown)],
      ));

      final knownGroup = groups.firstWhere(
          (g) => g.classification == ClaimNoveltyClassification.alreadyKnown);
      expect(knownGroup.items.first.selectedByDefault, isFalse);
    });

    test('better-source claims are selected by default and preserve citation URLs', () {
      final urls = ['https://better-source.com'];
      final groups = mapper.toGroups(_ingestion(
        betterSourceClaims: [
          _result(
            id: 'b1',
            classification: ClaimNoveltyClassification.betterSource,
            citationUrls: urls,
          ),
        ],
      ));

      final betterGroup = groups.firstWhere(
          (g) => g.classification == ClaimNoveltyClassification.betterSource);
      expect(betterGroup.items.first.selectedByDefault, isTrue);
      expect(betterGroup.items.first.citationUrls, containsAll(urls));
    });

    test('contradiction claims are not selected by default', () {
      final groups = mapper.toGroups(_ingestion(
        contradictionClaims: [
          _result(id: 'c1', classification: ClaimNoveltyClassification.contradiction),
        ],
      ));

      final group = groups.firstWhere(
          (g) => g.classification == ClaimNoveltyClassification.contradiction);
      expect(group.items.first.selectedByDefault, isFalse);
    });

    test('group order is stable: new → better → contradiction → uncertain → known', () {
      final groups = mapper.toGroups(_ingestion(
        newClaims: [_result(id: 'n', classification: ClaimNoveltyClassification.newClaim)],
        betterSourceClaims: [_result(id: 'b', classification: ClaimNoveltyClassification.betterSource)],
        contradictionClaims: [_result(id: 'c', classification: ClaimNoveltyClassification.contradiction)],
        uncertainClaims: [_result(id: 'u', classification: ClaimNoveltyClassification.uncertain)],
        knownClaims: [_result(id: 'k', classification: ClaimNoveltyClassification.alreadyKnown)],
      ));

      expect(groups.map((g) => g.classification).toList(), [
        ClaimNoveltyClassification.newClaim,
        ClaimNoveltyClassification.betterSource,
        ClaimNoveltyClassification.contradiction,
        ClaimNoveltyClassification.uncertain,
        ClaimNoveltyClassification.alreadyKnown,
      ]);
    });

    test('empty ingestion result creates 5 empty groups', () {
      final groups = mapper.toGroups(_ingestion());

      expect(groups.length, 5);
      expect(groups.every((g) => g.isEmpty), isTrue);
    });

    test('matched local evidence IDs are preserved in review items', () {
      final ev = _evidence('local-ev-1');
      final groups = mapper.toGroups(_ingestion(
        knownClaims: [
          _result(
            id: 'k1',
            classification: ClaimNoveltyClassification.alreadyKnown,
            matchedLocal: [ev],
          ),
        ],
      ));

      final item = groups
          .firstWhere((g) => g.classification == ClaimNoveltyClassification.alreadyKnown)
          .items
          .first;
      expect(item.matchedLocalEvidenceIds, contains('local-ev-1'));
    });

    test('matched local evidence titles are preserved in review items', () {
      final ev = _evidence('local-ev-1', title: 'My existing note');
      final groups = mapper.toGroups(_ingestion(
        knownClaims: [
          _result(
            id: 'k1',
            classification: ClaimNoveltyClassification.alreadyKnown,
            matchedLocal: [ev],
          ),
        ],
      ));

      final item = groups
          .firstWhere((g) => g.classification == ClaimNoveltyClassification.alreadyKnown)
          .items
          .first;
      expect(item.matchedLocalEvidenceTitles, contains('My existing note'));
    });

    test('no source URLs are dropped from review items', () {
      const urls = ['https://src1.com', 'https://src2.com'];
      final groups = mapper.toGroups(_ingestion(
        newClaims: [
          _result(
            id: 'n1',
            classification: ClaimNoveltyClassification.newClaim,
            citationUrls: urls,
          ),
        ],
      ));

      final item = groups
          .firstWhere((g) => g.classification == ClaimNoveltyClassification.newClaim)
          .items
          .first;
      expect(item.citationUrls, containsAll(urls));
    });

    test('no API keys or secrets appear in review item reason', () {
      final groups = mapper.toGroups(_ingestion(
        newClaims: [_result(id: 'n1', reason: 'Normal reason text.')],
      ));

      for (final group in groups) {
        for (final item in group.items) {
          expect(item.reason, isNot(contains('sk-')));
          expect(item.reason, isNot(contains('Bearer ')));
        }
      }
    });
  });

  group('ClaimReviewSelectionState', () {
    test('selected saveable items returns only saveable and selected claims', () {
      final ingestion = _ingestion(
        newClaims: [
          _result(id: 'new1', classification: ClaimNoveltyClassification.newClaim),
        ],
        knownClaims: [
          _result(id: 'known1', classification: ClaimNoveltyClassification.alreadyKnown),
        ],
      );

      final state = mapper.toSelectionState(ingestion);

      final saveable = state.selectedSaveableItems;
      expect(saveable.map((i) => i.id), contains('new1'));
      expect(saveable.map((i) => i.id), isNot(contains('known1')));
    });

    test('toggle adds a non-selected item', () {
      final ingestion = _ingestion(
        knownClaims: [
          _result(id: 'k1', classification: ClaimNoveltyClassification.alreadyKnown),
        ],
      );

      final state = mapper.toSelectionState(ingestion);
      expect(state.selectedIds, isNot(contains('k1')));

      final toggled = state.toggle('k1');
      expect(toggled.selectedIds, contains('k1'));
    });

    test('toggle removes an already-selected item', () {
      final ingestion = _ingestion(
        newClaims: [
          _result(id: 'n1', classification: ClaimNoveltyClassification.newClaim),
        ],
      );

      final state = mapper.toSelectionState(ingestion);
      expect(state.selectedIds, contains('n1'));

      final toggled = state.toggle('n1');
      expect(toggled.selectedIds, isNot(contains('n1')));
    });
  });
}
