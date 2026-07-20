import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/claim_deduplication_result.dart';
import 'package:grepink/models/claim_review_item.dart';
import 'package:grepink/widgets/claim_review_groups_panel.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

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

ClaimReviewItem _knownItem(String id, {
  List<String> matchedLocalEvidenceIds = const [],
  List<String> matchedLocalEvidenceTitles = const [],
}) =>
    _item(
      id,
      classification: ClaimNoveltyClassification.alreadyKnown,
      canBeSaved: false,
      matchedLocalEvidenceIds: matchedLocalEvidenceIds,
      matchedLocalEvidenceTitles: matchedLocalEvidenceTitles,
    );

ClaimReviewGroup _knownGroup(List<ClaimReviewItem> items) => ClaimReviewGroup(
      label: 'Already in notes',
      classification: ClaimNoveltyClassification.alreadyKnown,
      items: items,
    );

Future<void> _pumpPanel(
  WidgetTester tester, {
  required List<ClaimReviewGroup> groups,
  Set<String> selectedIds = const {},
  ValueChanged<String>? onToggle,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ClaimReviewGroupsPanel(
            groups: groups,
            selectedIds: selectedIds,
            onToggle: onToggle ?? (_) {},
          ),
        ),
      ),
    ),
  );
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  group('ClaimReviewGroupsPanel already-known section', () {
    group('expansion defaults', () {
      for (final count in [1, 2, 3]) {
        testWidgets('$count item(s) start expanded', (tester) async {
          await _pumpPanel(tester, groups: [
            _knownGroup(List.generate(count, (i) => _knownItem('k$i'))),
          ]);

          final tile = tester
              .widget<ExpansionTile>(find.byKey(const Key('already-known-section')));
          expect(tile.initiallyExpanded, isTrue);
        });
      }

      testWidgets('4 items start collapsed', (tester) async {
        await _pumpPanel(tester, groups: [
          _knownGroup(List.generate(4, (i) => _knownItem('k$i'))),
        ]);

        final tile = tester
            .widget<ExpansionTile>(find.byKey(const Key('already-known-section')));
        expect(tile.initiallyExpanded, isFalse);
      });

      testWidgets('5 items start collapsed', (tester) async {
        await _pumpPanel(tester, groups: [
          _knownGroup(List.generate(5, (i) => _knownItem('k$i'))),
        ]);

        final tile = tester
            .widget<ExpansionTile>(find.byKey(const Key('already-known-section')));
        expect(tile.initiallyExpanded, isFalse);
      });
    });

    testWidgets('renders as a collapsible section with item count in heading',
        (tester) async {
      await _pumpPanel(tester, groups: [
        _knownGroup([_knownItem('k1'), _knownItem('k2')]),
      ]);

      expect(find.byKey(const Key('already-known-section')), findsOneWidget);
      expect(find.textContaining('Already in notes (2)'), findsOneWidget);
    });

    testWidgets('shows the not-saved explanation', (tester) async {
      await _pumpPanel(tester, groups: [
        _knownGroup([_knownItem('k1')]),
      ]);

      expect(
        find.textContaining('Not saved'),
        findsOneWidget,
      );
    });

    testWidgets('user can expand and collapse the section', (tester) async {
      await _pumpPanel(tester, groups: [
        _knownGroup(List.generate(5, (i) => _knownItem('k$i'))),
      ]);

      // The tile header (title text) is the tap target; tapping the
      // ExpansionTile widget key can land in the children area once expanded.
      final headerFinder = find.text('Already in notes (5)');
      final itemFinder = find.byKey(const Key('claim-review-item-k0'));

      // Starts collapsed (5 > threshold); tap header to expand.
      await tester.tap(headerFinder);
      await tester.pumpAndSettle();
      // After expansion the item is in the tree.
      expect(itemFinder, findsOneWidget);

      // Tap header again to collapse — ExpansionTile removes children from
      // the tree (maintainState defaults to false).
      await tester.tap(headerFinder);
      await tester.pumpAndSettle();
      expect(itemFinder, findsNothing);
    });

    testWidgets(
        'new review result reapplies correct default: small → large starts collapsed',
        (tester) async {
      // First: 2 items → starts expanded.
      await _pumpPanel(tester, groups: [
        _knownGroup([_knownItem('k0'), _knownItem('k1')]),
      ]);
      var tile = tester
          .widget<ExpansionTile>(find.byKey(const Key('already-known-section')));
      expect(tile.initiallyExpanded, isTrue);

      // Second: 5 items → must start collapsed (crossing threshold recreates tile).
      await _pumpPanel(tester, groups: [
        _knownGroup(List.generate(5, (i) => _knownItem('k$i'))),
      ]);
      tile = tester
          .widget<ExpansionTile>(find.byKey(const Key('already-known-section')));
      expect(tile.initiallyExpanded, isFalse);
    });

    testWidgets(
        'new review result reapplies correct default: large → small starts expanded',
        (tester) async {
      // First: 5 items → starts collapsed.
      await _pumpPanel(tester, groups: [
        _knownGroup(List.generate(5, (i) => _knownItem('k$i'))),
      ]);
      var tile = tester
          .widget<ExpansionTile>(find.byKey(const Key('already-known-section')));
      expect(tile.initiallyExpanded, isFalse);

      // Second: 2 items → must start expanded.
      await _pumpPanel(tester, groups: [
        _knownGroup([_knownItem('k0'), _knownItem('k1')]),
      ]);
      tile = tester
          .widget<ExpansionTile>(find.byKey(const Key('already-known-section')));
      expect(tile.initiallyExpanded, isTrue);
    });

    testWidgets(
        'regression: large → large resets to collapsed (same-bool key must not reuse expansion state)',
        (tester) async {
      // First review: 5 items → collapsed by default.
      await _pumpPanel(tester, groups: [
        _knownGroup(List.generate(5, (i) => _knownItem('a$i'))),
      ]);
      // User expands it manually.
      await tester.tap(find.text('Already in notes (5)'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('claim-review-item-a0')), findsOneWidget);

      // Second review: different 4 items — still above threshold, must reset
      // to collapsed even though collapsedByDefault is still true.
      await _pumpPanel(tester, groups: [
        _knownGroup(List.generate(4, (i) => _knownItem('b$i'))),
      ]);
      final tile = tester
          .widget<ExpansionTile>(find.byKey(const Key('already-known-section')));
      expect(tile.initiallyExpanded, isFalse);
    });

    testWidgets('already-known claims render unchecked and disabled',
        (tester) async {
      await _pumpPanel(
        tester,
        groups: [_knownGroup([_knownItem('k1')])],
        // Even if selectedIds unexpectedly contains the id, tile must
        // render disabled and unchecked.
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

    testWidgets('tapping already-known tile does not invoke onToggle',
        (tester) async {
      var toggleCalled = false;
      await _pumpPanel(
        tester,
        groups: [_knownGroup([_knownItem('k1')])],
        onToggle: (_) => toggleCalled = true,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('claim-review-item-k1')));
      await tester.pumpAndSettle();

      expect(toggleCalled, isFalse);
    });
  });

  group('ClaimReviewGroupsPanel matched-evidence display', () {
    testWidgets('matched local note title is shown', (tester) async {
      await _pumpPanel(tester, groups: [
        _knownGroup([
          _knownItem('k1',
              matchedLocalEvidenceIds: ['ev-1'],
              matchedLocalEvidenceTitles: ['My existing note']),
        ]),
      ]);
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('claim-review-matched-evidence-k1')),
          findsOneWidget);
      expect(find.textContaining('My existing note'), findsOneWidget);
    });

    testWidgets('blank title falls back to the evidence ID', (tester) async {
      await _pumpPanel(tester, groups: [
        _knownGroup([
          _knownItem('k1',
              matchedLocalEvidenceIds: ['ev-1'],
              matchedLocalEvidenceTitles: ['']),
        ]),
      ]);
      await tester.pumpAndSettle();

      expect(find.textContaining('ev-1'), findsOneWidget);
    });

    testWidgets('missing title (shorter list) falls back to evidence ID without throwing',
        (tester) async {
      await _pumpPanel(tester, groups: [
        _knownGroup([
          _knownItem('k1',
              matchedLocalEvidenceIds: ['ev-1', 'ev-2'],
              matchedLocalEvidenceTitles: ['Note A']), // only one title for two IDs
        ]),
      ]);
      await tester.pumpAndSettle();

      expect(find.textContaining('Note A'), findsOneWidget);
      expect(find.textContaining('ev-2'), findsOneWidget); // fallback for missing title
    });

    testWidgets('multiple matched notes are all represented', (tester) async {
      await _pumpPanel(tester, groups: [
        _knownGroup([
          _knownItem('k1',
              matchedLocalEvidenceIds: ['ev-1', 'ev-2'],
              matchedLocalEvidenceTitles: ['Note A', 'Note B']),
        ]),
      ]);
      await tester.pumpAndSettle();

      expect(find.textContaining('Note A'), findsOneWidget);
      expect(find.textContaining('Note B'), findsOneWidget);
    });

    testWidgets('no matched-note line when there are no evidence IDs',
        (tester) async {
      await _pumpPanel(tester, groups: [
        _knownGroup([_knownItem('k1')]), // no matchedLocalEvidenceIds
      ]);
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('claim-review-matched-evidence-k1')),
          findsNothing);
      expect(find.textContaining('Matches your notes'), findsNothing);
    });

    testWidgets(
        'no matched-note line for newClaim even with evidence IDs (low-similarity bestMatch)',
        (tester) async {
      await _pumpPanel(tester, groups: [
        ClaimReviewGroup(
          label: 'New claims',
          classification: ClaimNoveltyClassification.newClaim,
          items: [
            _item('n1',
                matchedLocalEvidenceIds: ['ev-1'],
                matchedLocalEvidenceTitles: ['Some note']),
          ],
        ),
      ]);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('claim-review-matched-evidence-n1')),
          findsNothing);
      expect(find.textContaining('Matches your notes'), findsNothing);
    });
  });

  group('ClaimReviewGroupsPanel better-source helper text', () {
    testWidgets('explains that the better source may improve an existing note',
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

    testWidgets('helper text does not appear for new-claim groups', (tester) async {
      await _pumpPanel(tester, groups: [
        ClaimReviewGroup(
          label: 'New claims',
          classification: ClaimNoveltyClassification.newClaim,
          items: [_item('n1')],
        ),
      ]);

      expect(find.byKey(const Key('better-source-helper-text')), findsNothing);
    });

    testWidgets('better-source claims remain selected and interactive',
        (tester) async {
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

  group('ClaimReviewGroupsPanel ordinary group rendering', () {
    testWidgets('new-claim group renders with selectable enabled tiles',
        (tester) async {
      await _pumpPanel(tester, groups: [
        ClaimReviewGroup(
          label: 'New claims',
          classification: ClaimNoveltyClassification.newClaim,
          items: [_item('n1')],
        ),
      ]);

      final checkbox = tester.widget<CheckboxListTile>(
        find.descendant(
          of: find.byKey(const Key('claim-review-item-n1')),
          matching: find.byType(CheckboxListTile),
        ),
      );
      expect(checkbox.onChanged, isNotNull);
    });

    testWidgets('contradiction group renders with canBeSaved tiles enabled',
        (tester) async {
      await _pumpPanel(tester, groups: [
        ClaimReviewGroup(
          label: 'Contradictions',
          classification: ClaimNoveltyClassification.contradiction,
          items: [
            _item('c1', classification: ClaimNoveltyClassification.contradiction),
          ],
        ),
      ]);

      final checkbox = tester.widget<CheckboxListTile>(
        find.descendant(
          of: find.byKey(const Key('claim-review-item-c1')),
          matching: find.byType(CheckboxListTile),
        ),
      );
      expect(checkbox.onChanged, isNotNull);
    });

    testWidgets('uncertain group renders with canBeSaved=false tiles disabled',
        (tester) async {
      await _pumpPanel(tester, groups: [
        ClaimReviewGroup(
          label: 'Uncertain',
          classification: ClaimNoveltyClassification.uncertain,
          items: [
            _item('u1',
                classification: ClaimNoveltyClassification.uncertain,
                canBeSaved: false),
          ],
        ),
      ]);

      final checkbox = tester.widget<CheckboxListTile>(
        find.descendant(
          of: find.byKey(const Key('claim-review-item-u1')),
          matching: find.byType(CheckboxListTile),
        ),
      );
      expect(checkbox.onChanged, isNull);
    });

    testWidgets('empty groups are not rendered', (tester) async {
      await _pumpPanel(tester, groups: [
        const ClaimReviewGroup(
          label: 'New claims',
          classification: ClaimNoveltyClassification.newClaim,
          items: [],
        ),
        ClaimReviewGroup(
          label: 'Better sources',
          classification: ClaimNoveltyClassification.betterSource,
          items: [_item('b1', classification: ClaimNoveltyClassification.betterSource)],
        ),
      ]);

      expect(find.text('New claims (0)'), findsNothing);
      expect(find.textContaining('Better sources'), findsOneWidget);
    });
  });
}
