import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/claim_deduplication_result.dart';
import 'package:grepink/models/evidence_item.dart';
import 'package:grepink/models/extracted_claim.dart';
import 'package:grepink/models/grounded_answer.dart';
import 'package:grepink/models/note.dart';
import 'package:grepink/models/note_draft.dart';
import 'package:grepink/models/claim_review_session_state.dart';
import 'package:grepink/providers/claim_review_provider.dart';
import 'package:grepink/providers/knowledge_ingestion_provider.dart';
import 'package:grepink/providers/note_draft_review_provider.dart';
import 'package:grepink/providers/notes_provider.dart';
import 'package:grepink/screens/search_screen.dart';
import 'package:grepink/services/claim_deduplication_service.dart';
import 'package:grepink/services/claim_extraction_service.dart';
import 'package:grepink/services/grounded_answer_ingestion_service.dart';
import 'package:grepink/services/grounded_answer_provider.dart';
import 'package:grepink/services/knowledge_ingestion_service.dart';
import 'package:grepink/services/local_evidence_retriever.dart';

// ─── Test doubles ────────────────────────────────────────────────────────────

class _FakeKnowledgeIngestionService implements KnowledgeIngestionService {
  @override
  Future<NoteDraft> ingest(String question) async => NoteDraft(
        question: question,
        markdownContent: '',
        action: NoteDraftAction.doNotSave,
        deltas: const [],
        localEvidence: const [],
        webEvidence: const [],
      );
}

class _FakeNoteDraftReviewRepository implements NoteDraftReviewRepository {
  @override
  Future<Note?> getNoteById(String id) async => null;

  @override
  Future<Note> insertNote({required String title, required String content}) async {
    throw UnimplementedError();
  }

  @override
  Future<void> updateNote(Note note) async {}
}

class _CountingGroundedAnswerProvider implements GroundedAnswerProvider {
  int calls = 0;
  final GroundedAnswer answer;

  _CountingGroundedAnswerProvider(this.answer);

  @override
  bool get isConfigured => true;

  @override
  Future<GroundedAnswer?> fetchGroundedAnswer(String question) async {
    calls++;
    return answer;
  }
}

class _FixedClaimExtractionService implements ClaimExtractionService {
  final List<ExtractedClaim> claims;

  _FixedClaimExtractionService(this.claims);

  @override
  List<ExtractedClaim> extract(GroundedAnswer answer) => claims;
}

class _FixedClaimDeduplicationService implements ClaimDeduplicationService {
  final List<ClaimDeduplicationResult> results;

  _FixedClaimDeduplicationService(this.results);

  @override
  Future<List<ClaimDeduplicationResult>> classify(
    List<ExtractedClaim> claims,
    List<EvidenceItem> localEvidence,
  ) async =>
      results;
}

class _EmptyLocalEvidenceRetriever implements LocalEvidenceRetriever {
  @override
  Future<List<EvidenceItem>> retrieve(String question) async => const [];
}

// ─── Fixtures ────────────────────────────────────────────────────────────────

ExtractedClaim _claim(
  String id,
  String text, {
  List<String> citationUrls = const [],
  List<String> citationTitles = const [],
}) =>
    ExtractedClaim(
      id: id,
      text: text,
      citationUrls: citationUrls,
      citationTitles: citationTitles,
      sourceAnswerProvider: 'test-provider',
      sourceQuestion: 'q',
      order: 0,
    );

ClaimDeduplicationResult _result(
  String id,
  String text,
  ClaimNoveltyClassification classification, {
  List<String> citationUrls = const [],
  List<String> citationTitles = const [],
}) =>
    ClaimDeduplicationResult(
      claim: _claim(id, text, citationTitles: citationTitles),
      classification: classification,
      matchedLocalEvidence: const [],
      reason: 'test reason for $id',
      citationUrls: citationUrls,
    );

GroundedAnswerIngestionService _buildIngestionService({
  required _CountingGroundedAnswerProvider provider,
  required List<ExtractedClaim> claims,
  required List<ClaimDeduplicationResult> results,
}) {
  return GroundedAnswerIngestionService(
    provider: provider,
    extractor: _FixedClaimExtractionService(claims),
    deduplicator: _FixedClaimDeduplicationService(results),
    localEvidence: _EmptyLocalEvidenceRetriever(),
  );
}

Future<ProviderContainer> _pumpSearchScreen(
  WidgetTester tester, {
  required GroundedAnswerIngestionService ingestionService,
}) async {
  final container = ProviderContainer(
    overrides: [
      knowledgeIngestionServiceProvider.overrideWith(
        (ref) async => _FakeKnowledgeIngestionService(),
      ),
      noteDraftReviewRepositoryProvider.overrideWithValue(
        _FakeNoteDraftReviewRepository(),
      ),
      groundedAnswerIngestionServiceProvider.overrideWithValue(ingestionService),
      allNotesProvider.overrideWithValue(const <Note>[]),
      recentNotesProvider.overrideWithValue(const <Note>[]),
      refreshNotesProvider.overrideWithValue(() async {}),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: SearchScreen(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  addTearDown(container.dispose);
  return container;
}

Future<void> _askQuestion(WidgetTester tester, String question) async {
  await tester.enterText(find.byKey(const Key('ask-question-field')), question);
  await tester.pump();
  await tester.tap(find.byKey(const Key('ask-question-button')));
  await tester.pumpAndSettle();
}

class _CreateNoteKnowledgeIngestionService implements KnowledgeIngestionService {
  @override
  Future<NoteDraft> ingest(String question) async => NoteDraft(
        question: question,
        markdownContent: '# Note\n- Content',
        action: NoteDraftAction.createNewNote,
        deltas: const [],
        localEvidence: const [],
        webEvidence: const [],
      );
}

Future<ProviderContainer> _pumpSearchScreenWithDraftReview(
  WidgetTester tester, {
  required GroundedAnswerIngestionService ingestionService,
}) async {
  final container = ProviderContainer(
    overrides: [
      knowledgeIngestionServiceProvider.overrideWith(
        (ref) async => _CreateNoteKnowledgeIngestionService(),
      ),
      noteDraftReviewRepositoryProvider.overrideWithValue(
        _FakeNoteDraftReviewRepository(),
      ),
      groundedAnswerIngestionServiceProvider.overrideWithValue(ingestionService),
      allNotesProvider.overrideWithValue(const <Note>[]),
      recentNotesProvider.overrideWithValue(const <Note>[]),
      refreshNotesProvider.overrideWithValue(() async {}),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: SearchScreen(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('SearchScreen claim review flow', () {
    testWidgets('asking a question invokes the grounded-answer ingestion service',
        (tester) async {
      final provider = _CountingGroundedAnswerProvider(
        GroundedAnswer(
          question: 'What is photosynthesis?',
          answerText: 'Plants convert light into energy.',
          citations: const [],
          providerName: 'test-provider',
          generatedAt: DateTime(2026, 1, 1),
        ),
      );
      final service = _buildIngestionService(
        provider: provider,
        claims: [_claim('n1', 'Plants convert light into energy.')],
        results: [
          _result('n1', 'Plants convert light into energy.',
              ClaimNoveltyClassification.newClaim),
        ],
      );

      await _pumpSearchScreen(tester, ingestionService: service);
      await _askQuestion(tester, 'What is photosynthesis?');

      expect(provider.calls, 1);
    });

    testWidgets('grouped claims are rendered under their labels', (tester) async {
      final provider = _CountingGroundedAnswerProvider(
        GroundedAnswer(
          question: 'q',
          answerText: 'answer',
          citations: const [],
          providerName: 'test-provider',
          generatedAt: DateTime(2026, 1, 1),
        ),
      );
      final service = _buildIngestionService(
        provider: provider,
        claims: [
          _claim('n1', 'A brand new claim.'),
          _claim('b1', 'A claim with a better source.'),
          _claim('c1', 'A contradicting claim.'),
          _claim('u1', 'An uncertain claim.'),
          _claim('k1', 'An already known claim.'),
        ],
        results: [
          _result('n1', 'A brand new claim.', ClaimNoveltyClassification.newClaim),
          _result('b1', 'A claim with a better source.',
              ClaimNoveltyClassification.betterSource),
          _result('c1', 'A contradicting claim.',
              ClaimNoveltyClassification.contradiction),
          _result('u1', 'An uncertain claim.', ClaimNoveltyClassification.uncertain),
          _result('k1', 'An already known claim.',
              ClaimNoveltyClassification.alreadyKnown),
        ],
      );

      await _pumpSearchScreen(tester, ingestionService: service);
      await _askQuestion(tester, 'question');

      expect(find.text('New claims (1)'), findsOneWidget);
      expect(find.text('Better sources (1)'), findsOneWidget);
      expect(find.text('Possible contradictions to review (1)'), findsOneWidget);
      expect(find.text('Uncertain (1)'), findsOneWidget);
      expect(find.text('Already in notes (1)'), findsOneWidget);

      expect(find.text('A brand new claim.'), findsOneWidget);
      expect(find.text('A claim with a better source.'), findsOneWidget);
      expect(find.text('A contradicting claim.'), findsOneWidget);
      expect(find.text('An uncertain claim.'), findsOneWidget);
      expect(find.text('An already known claim.'), findsOneWidget);
    });

    testWidgets(
        'default selected claim IDs match ClaimReviewSelectionState, '
        'and alreadyKnown claims are visible but unselected', (tester) async {
      final provider = _CountingGroundedAnswerProvider(
        GroundedAnswer(
          question: 'q',
          answerText: 'answer',
          citations: const [],
          providerName: 'test-provider',
          generatedAt: DateTime(2026, 1, 1),
        ),
      );
      final service = _buildIngestionService(
        provider: provider,
        claims: [
          _claim('n1', 'A brand new claim.'),
          _claim('b1', 'A claim with a better source.'),
          _claim('c1', 'A contradicting claim.'),
          _claim('u1', 'An uncertain claim.'),
          _claim('k1', 'An already known claim.'),
        ],
        results: [
          _result('n1', 'A brand new claim.', ClaimNoveltyClassification.newClaim),
          _result('b1', 'A claim with a better source.',
              ClaimNoveltyClassification.betterSource),
          _result('c1', 'A contradicting claim.',
              ClaimNoveltyClassification.contradiction),
          _result('u1', 'An uncertain claim.', ClaimNoveltyClassification.uncertain),
          _result('k1', 'An already known claim.',
              ClaimNoveltyClassification.alreadyKnown),
        ],
      );
      final container = await _pumpSearchScreen(tester, ingestionService: service);
      await _askQuestion(tester, 'question');

      final selection = container.read(claimReviewProvider).selection!;
      expect(selection.selectedIds, containsAll(['n1', 'b1']));
      expect(selection.selectedIds, isNot(contains('c1')));
      expect(selection.selectedIds, isNot(contains('u1')));
      expect(selection.selectedIds, isNot(contains('k1')));

      CheckboxListTile tileFor(String claimId) => tester.widget<CheckboxListTile>(
            find.descendant(
              of: find.byKey(Key('claim-review-item-$claimId')),
              matching: find.byType(CheckboxListTile),
            ),
          );

      expect(tileFor('n1').value, isTrue);
      expect(tileFor('b1').value, isTrue);
      expect(tileFor('c1').value, isFalse);
      expect(tileFor('u1').value, isFalse);
      expect(tileFor('k1').value, isFalse);
    });

    testWidgets('toggling a claim updates the selection state', (tester) async {
      final provider = _CountingGroundedAnswerProvider(
        GroundedAnswer(
          question: 'q',
          answerText: 'answer',
          citations: const [],
          providerName: 'test-provider',
          generatedAt: DateTime(2026, 1, 1),
        ),
      );
      final service = _buildIngestionService(
        provider: provider,
        claims: [_claim('n1', 'A brand new claim.')],
        results: [
          _result('n1', 'A brand new claim.', ClaimNoveltyClassification.newClaim),
        ],
      );
      final container = await _pumpSearchScreen(tester, ingestionService: service);
      await _askQuestion(tester, 'question');

      expect(container.read(claimReviewProvider).selection!.selectedIds,
          contains('n1'));

      final claimTile = find.descendant(
        of: find.byKey(const Key('claim-review-item-n1')),
        matching: find.byType(CheckboxListTile),
      );
      await tester.ensureVisible(claimTile);
      await tester.tap(claimTile);
      await tester.pumpAndSettle();

      expect(container.read(claimReviewProvider).selection!.selectedIds,
          isNot(contains('n1')));
    });

    testWidgets('citation urls are shown for a claim with sources', (tester) async {
      final provider = _CountingGroundedAnswerProvider(
        GroundedAnswer(
          question: 'q',
          answerText: 'answer',
          citations: const [],
          providerName: 'test-provider',
          generatedAt: DateTime(2026, 1, 1),
        ),
      );
      final service = _buildIngestionService(
        provider: provider,
        claims: [
          _claim(
            'n1',
            'A brand new claim.',
            citationUrls: const ['https://example.com/a', 'https://example.com/b'],
            citationTitles: const ['Example A', ''],
          ),
        ],
        results: [
          _result(
            'n1',
            'A brand new claim.',
            ClaimNoveltyClassification.newClaim,
            citationUrls: const ['https://example.com/a', 'https://example.com/b'],
            citationTitles: const ['Example A', ''],
          ),
        ],
      );

      await _pumpSearchScreen(tester, ingestionService: service);
      await _askQuestion(tester, 'question');

      expect(find.text('Example A (https://example.com/a)'), findsOneWidget);
      expect(find.text('https://example.com/b'), findsOneWidget);
    });

    testWidgets(
        'asking a question with NullGroundedAnswerProvider produces providerNotConfigured',
        (tester) async {
      final service = GroundedAnswerIngestionService(
        provider: const NullGroundedAnswerProvider(),
        extractor: _FixedClaimExtractionService(const []),
        deduplicator: _FixedClaimDeduplicationService(const []),
        localEvidence: _EmptyLocalEvidenceRetriever(),
      );

      final container = await _pumpSearchScreen(tester, ingestionService: service);
      await _askQuestion(tester, 'What is photosynthesis?');

      final state = container.read(claimReviewProvider);
      expect(state.status, ClaimReviewSessionStatus.providerNotConfigured);
      expect(state.groups, isEmpty);
      expect(state.selection, isNull);
    });

    testWidgets(
        'discard resets claim review state and invalidates any in-flight review',
        (tester) async {
      final provider = _CountingGroundedAnswerProvider(
        GroundedAnswer(
          question: 'q',
          answerText: 'answer',
          citations: const [],
          providerName: 'test-provider',
          generatedAt: DateTime(2026, 1, 1),
        ),
      );
      final service = _buildIngestionService(
        provider: provider,
        claims: [_claim('n1', 'A brand new claim.')],
        results: [
          _result('n1', 'A brand new claim.', ClaimNoveltyClassification.newClaim),
        ],
      );

      final container = await _pumpSearchScreenWithDraftReview(
        tester,
        ingestionService: service,
      );
      await _askQuestion(tester, 'question');

      // Claim review groups must be visible after the ask completes.
      expect(find.byKey(const Key('claim-review-groups-panel')), findsOneWidget);
      expect(container.read(claimReviewProvider).hasReviewItems, isTrue);

      // Tap Discard on the note draft review widget.
      await tester.ensureVisible(find.text('Discard'));
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      // Discard must reset claimReviewProvider so no stale groups remain.
      expect(find.byKey(const Key('claim-review-groups-panel')), findsNothing);
      expect(container.read(claimReviewProvider).hasReviewItems, isFalse);
      expect(container.read(claimReviewProvider).selection, isNull);
      expect(container.read(claimReviewProvider).groups, isEmpty);
    });
  });
}
