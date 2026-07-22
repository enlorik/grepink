import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/claim_deduplication_result.dart';
import 'package:grepink/models/claim_review_item.dart';
import 'package:grepink/models/evidence_item.dart';
import 'package:grepink/models/extracted_claim.dart';
import 'package:grepink/models/grounded_answer.dart';
import 'package:grepink/models/note.dart';
import 'package:grepink/models/note_draft.dart';
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

// ─── Test doubles ─────────────────────────────────────────────────────────────

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
  Future<Note> insertNote(
          {required String title, required String content}) async =>
      throw UnimplementedError();

  @override
  Future<void> updateNote(Note note) async {}
}

class _FixedGroundedAnswerProvider implements GroundedAnswerProvider {
  final GroundedAnswer answer;
  _FixedGroundedAnswerProvider(this.answer);

  @override
  bool get isConfigured => true;

  @override
  Future<GroundedAnswer?> fetchGroundedAnswer(String question) async => answer;
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

// ─── Fixtures ─────────────────────────────────────────────────────────────────

ExtractedClaim _claim(String id, String text) => ExtractedClaim(
      id: id,
      text: text,
      citationUrls: const [],
      citationTitles: const [],
      sourceAnswerProvider: 'test-provider',
      sourceQuestion: 'q',
      order: 0,
    );

ClaimDeduplicationResult _result(
  String id,
  String text,
  ClaimNoveltyClassification classification,
) =>
    ClaimDeduplicationResult(
      claim: _claim(id, text),
      classification: classification,
      matchedLocalEvidence: const [],
      reason: 'test reason for $id',
      citationUrls: const [],
    );

GroundedAnswerIngestionService _buildService({
  required List<ExtractedClaim> claims,
  required List<ClaimDeduplicationResult> results,
}) =>
    GroundedAnswerIngestionService(
      provider: _FixedGroundedAnswerProvider(
        GroundedAnswer(
          question: 'q',
          answerText: 'answer',
          citations: const [],
          providerName: 'test-provider',
          generatedAt: DateTime(2026, 1, 1),
        ),
      ),
      extractor: _FixedClaimExtractionService(claims),
      deduplicator: _FixedClaimDeduplicationService(results),
      localEvidence: _EmptyLocalEvidenceRetriever(),
    );

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
      groundedAnswerIngestionServiceProvider
          .overrideWithValue(ingestionService),
      allNotesProvider.overrideWithValue(const <Note>[]),
      recentNotesProvider.overrideWithValue(const <Note>[]),
      refreshNotesProvider.overrideWithValue(() async {}),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: SearchScreen(),
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

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('Generate button disabled state', () {
    testWidgets(
      'disabled with selection-guidance helper when saveable claims exist but none selected',
      (tester) async {
        final service = _buildService(
          claims: [_claim('n1', 'A new claim.')],
          results: [
            _result('n1', 'A new claim.', ClaimNoveltyClassification.newClaim),
          ],
        );
        final container =
            await _pumpSearchScreen(tester, ingestionService: service);
        await _askQuestion(tester, 'question');

        // n1 (newClaim) is selected by default; deselect it.
        container.read(claimReviewProvider.notifier).toggle('n1');
        await tester.pumpAndSettle();

        final btnFinder = find.byKey(const Key('generate-claim-draft-button'));
        await tester.ensureVisible(btnFinder);
        expect(find.byKey(const Key('generate-draft-disabled-helper')),
            findsOneWidget);
        expect(
          find.text(
            'Select at least one claim to generate a draft. Contradictions are not selected by default.',
          ),
          findsOneWidget,
        );

        // Tapping the disabled button must not produce a draft.
        await tester.tap(btnFinder);
        await tester.pumpAndSettle();
        expect(container.read(claimReviewProvider).draft, isNull);
      },
    );

    testWidgets(
      'disabled with no-claims helper when only uncertain claims exist',
      (tester) async {
        final service = _buildService(
          claims: [_claim('u1', 'An uncertain claim.')],
          results: [
            _result(
              'u1',
              'An uncertain claim.',
              ClaimNoveltyClassification.uncertain,
            ),
          ],
        );
        await _pumpSearchScreen(tester, ingestionService: service);
        await _askQuestion(tester, 'question');

        final btnFinder = find.byKey(const Key('generate-claim-draft-button'));
        await tester.ensureVisible(btnFinder);
        expect(find.byKey(const Key('generate-draft-disabled-helper')),
            findsOneWidget);
        expect(
          find.text('No claims in this review can be added to a draft.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'enabled with no helper when a saveable claim is selected',
      (tester) async {
        final service = _buildService(
          claims: [_claim('n1', 'A new claim.')],
          results: [
            _result('n1', 'A new claim.', ClaimNoveltyClassification.newClaim),
          ],
        );
        final container =
            await _pumpSearchScreen(tester, ingestionService: service);
        await _askQuestion(tester, 'question');

        // n1 is selected by default — button must be enabled.
        final btnFinder = find.byKey(const Key('generate-claim-draft-button'));
        await tester.ensureVisible(btnFinder);
        expect(find.byKey(const Key('generate-draft-disabled-helper')),
            findsNothing);

        // Tapping the enabled button must produce a draft.
        await tester.tap(btnFinder);
        await tester.pumpAndSettle();
        expect(container.read(claimReviewProvider).draft, isNotNull);
      },
    );

    testWidgets(
      'enabled after selecting a contradiction that was not selected by default',
      (tester) async {
        final service = _buildService(
          claims: [_claim('c1', 'A contradicting claim.')],
          results: [
            _result(
              'c1',
              'A contradicting claim.',
              ClaimNoveltyClassification.contradiction,
            ),
          ],
        );
        final container =
            await _pumpSearchScreen(tester, ingestionService: service);
        await _askQuestion(tester, 'question');

        // Contradiction is not selected by default — button is disabled.
        expect(find.byKey(const Key('generate-draft-disabled-helper')),
            findsOneWidget);
        expect(
          find.text(
            'Select at least one claim to generate a draft. Contradictions are not selected by default.',
          ),
          findsOneWidget,
        );

        // Select the contradiction.
        container.read(claimReviewProvider.notifier).toggle('c1');
        await tester.pumpAndSettle();

        // Button must now be enabled.
        expect(find.byKey(const Key('generate-draft-disabled-helper')),
            findsNothing);

        final btnFinder = find.byKey(const Key('generate-claim-draft-button'));
        await tester.ensureVisible(btnFinder);
        await tester.tap(btnFinder);
        await tester.pumpAndSettle();
        expect(container.read(claimReviewProvider).draft, isNotNull);
      },
    );
  });

  group('Claim draft preview panel empty-state copy', () {
    testWidgets(
      'shows updated no-save text when draft has no saveable claims',
      (tester) async {
        final service = _buildService(
          claims: [_claim('n1', 'A new claim.')],
          results: [
            _result('n1', 'A new claim.', ClaimNoveltyClassification.newClaim),
          ],
        );
        final container =
            await _pumpSearchScreen(tester, ingestionService: service);
        await _askQuestion(tester, 'question');

        // Deselect the only saveable claim, then generate via notifier directly
        // (bypassing the now-disabled UI button).
        container.read(claimReviewProvider.notifier).toggle('n1');
        container.read(claimReviewProvider.notifier).generateDraft();
        await tester.pumpAndSettle();

        expect(
            find.byKey(const Key('claim-draft-empty-state')), findsOneWidget);
        expect(
          find.text('No saveable claims are selected for this draft.'),
          findsOneWidget,
        );
        expect(
            find.byKey(const Key('claim-draft-preview-panel')), findsNothing);
      },
    );
  });
}
