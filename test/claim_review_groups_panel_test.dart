import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/claim_deduplication_result.dart';
import 'package:grepink/models/claim_review_item.dart';
import 'package:grepink/widgets/claim_review_groups_panel.dart';

ClaimReviewItem _item(
  String id, {
  ClaimNoveltyClassification classification = ClaimNoveltyClassification.newClaim,
  bool canBeSaved = true,
  List<String> matchedLocalEvidenceIds = const [],
  List<String> matchedLocalEvidenceTitles = const [],
}) =>
    ClaimReviewItem(
      id: id,
      text: 'Claim $id',
      classification: classification,
      citationUrls: const [],
      citationTitles: const [],
      selectedByDefault: false,
      reason: 'because',
      matchedLocalEvidenceIds: matchedLocalEvidenceIds,
      matchedLocalEvidenceTitles: matchedLocalEvidenceTitles,
      canBeSaved: canBeSaved,
    );

Future<void> _pumpPanel(
  WidgetTester tester, {
  required List<ClaimReviewGroup> groups,
  Set<String> selectedIds = const {},
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ClaimReviewGroupsPanel(
            groups: groups,
            selectedIds: selectedIds,
            onToggle: (_) {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('ClaimReviewGroupsPanel already-known section', () {
    testWidgets('renders as a collapsible section', (tester) async {
      await _pumpPanel(tester, groups: [
        ClaimReviewGroup(
          label: 'Already in notes',
          classification: ClaimNoveltyClassification.alreadyKnown,
          items: [_item('k1', classification: ClaimNoveltyClassification.alreadyKnown, canBeSaved: false)],
        ),
      ]);

      expect(find.byKey(const Key('already-known-section')), findsOneWidget);
      final tile =
          tester.widget<ExpansionTile>(find.byKey(const Key('already-known-section')));
      expect(tile.initiallyExpanded, isTrue);
    });

    testWidgets('collapses by default when there are many items', (tester) async {
      await _pumpPanel(tester, groups: [
        ClaimReviewGroup(
          label: 'Already in notes',
          classification: ClaimNoveltyClassification.alreadyKnown,
          items: List.generate(
            5,
            (i) => _item(
              'k$i',
              classification: ClaimNoveltyClassification.alreadyKnown,
              canBeSaved: false,
            ),
          ),
        ),
      ]);

      final tile =
          tester.widget<ExpansionTile>(find.byKey(const Key('already-known-section')));
      expect(tile.initiallyExpanded, isFalse);
    });

    testWidgets('matched local evidence is shown for already-known claims',
        (tester) async {
      await _pumpPanel(tester, groups: [
        ClaimReviewGroup(
          label: 'Already in notes',
          classification: ClaimNoveltyClassification.alreadyKnown,
          items: [
            _item(
              'k1',
              classification: ClaimNoveltyClassification.alreadyKnown,
              canBeSaved: false,
              matchedLocalEvidenceIds: ['ev-1'],
              matchedLocalEvidenceTitles: ['My existing note'],
            ),
          ],
        ),
      ]);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('claim-review-matched-evidence-k1')),
        findsOneWidget,
      );
      expect(find.textContaining('My existing note'), findsOneWidget);
    });

    testWidgets('falls back to the evidence id when no title is available',
        (tester) async {
      await _pumpPanel(tester, groups: [
        ClaimReviewGroup(
          label: 'Already in notes',
          classification: ClaimNoveltyClassification.alreadyKnown,
          items: [
            _item(
              'k1',
              classification: ClaimNoveltyClassification.alreadyKnown,
              canBeSaved: false,
              matchedLocalEvidenceIds: ['ev-1'],
            ),
          ],
        ),
      ]);
      await tester.pumpAndSettle();

      expect(find.textContaining('ev-1'), findsOneWidget);
    });

    testWidgets('already-known claims render unselected and disabled',
        (tester) async {
      await _pumpPanel(
        tester,
        groups: [
          ClaimReviewGroup(
            label: 'Already in notes',
            classification: ClaimNoveltyClassification.alreadyKnown,
            items: [
              _item('k1', classification: ClaimNoveltyClassification.alreadyKnown, canBeSaved: false),
            ],
          ),
        ],
        // Selection state should never contain an alreadyKnown id in
        // practice, but even if it somehow did, the tile must render
        // disabled and unselected.
        selectedIds: {'k1'},
      );
      await tester.pumpAndSettle();

      final checkbox = tester.widget<CheckboxListTile>(
        find.descendant(
          of: find.byKey(const Key('claim-review-item-k1')),
          matching: find.byType(CheckboxListTile),
        ),
      );
      expect(checkbox.onChanged, isNull);
      expect(checkbox.value, isFalse);
    });
  });

  group('ClaimReviewGroupsPanel new-claim helper text', () {
    testWidgets('explains that new claims are selected by default', (tester) async {
      await _pumpPanel(tester, groups: [
        ClaimReviewGroup(
          label: 'New claims',
          classification: ClaimNoveltyClassification.newClaim,
          items: [_item('n1', classification: ClaimNoveltyClassification.newClaim)],
        ),
      ]);

      expect(find.byKey(const Key('new-claim-helper-text')), findsOneWidget);
    });
  });

  group('ClaimReviewGroupsPanel contradiction helper text', () {
    testWidgets('appears when a contradiction group exists', (tester) async {
      await _pumpPanel(tester, groups: [
        ClaimReviewGroup(
          label: 'Possible contradictions to review',
          classification: ClaimNoveltyClassification.contradiction,
          items: [
            _item('c1', classification: ClaimNoveltyClassification.contradiction),
          ],
        ),
      ]);

      expect(find.byKey(const Key('contradiction-helper-text')), findsOneWidget);
    });

    testWidgets('does not appear when there is no contradiction group',
        (tester) async {
      await _pumpPanel(tester, groups: [
        ClaimReviewGroup(
          label: 'New claims',
          classification: ClaimNoveltyClassification.newClaim,
          items: [_item('n1', classification: ClaimNoveltyClassification.newClaim)],
        ),
      ]);

      expect(find.byKey(const Key('contradiction-helper-text')), findsNothing);
    });
  });

  group('ClaimReviewGroupsPanel better-source helper text', () {
    testWidgets('explains that a better source can improve an existing note',
        (tester) async {
      await _pumpPanel(tester, groups: [
        ClaimReviewGroup(
          label: 'Better sources',
          classification: ClaimNoveltyClassification.betterSource,
          items: [_item('b1', classification: ClaimNoveltyClassification.betterSource)],
        ),
      ]);

      expect(find.byKey(const Key('better-source-helper-text')), findsOneWidget);
    });

    testWidgets('better-source claims remain selectable', (tester) async {
      await _pumpPanel(
        tester,
        groups: [
          ClaimReviewGroup(
            label: 'Better sources',
            classification: ClaimNoveltyClassification.betterSource,
            items: [_item('b1', classification: ClaimNoveltyClassification.betterSource)],
          ),
        ],
        selectedIds: {'b1'},
      );

      final checkbox = tester.widget<CheckboxListTile>(
        find.descendant(
          of: find.byKey(const Key('claim-review-item-b1')),
          matching: find.byType(CheckboxListTile),
        ),
      );
      expect(checkbox.onChanged, isNotNull);
      expect(checkbox.value, isTrue);
    });
  });
}
