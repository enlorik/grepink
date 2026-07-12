import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/claim_deduplication_result.dart';
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
  required GroundedAnswerProvider provider,
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

Future<void> _generateDraft(WidgetTester tester) async {
  final button = find.byKey(const Key('generate-claim-draft-button'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  group('SearchScreen claim draft generation', () {
    testWidgets('selected new claims appear in markdown preview', (tester) async {
      final provider = _FixedGroundedAnswerProvider(
        GroundedAnswer(
          question: 'q',
          answerText: 'answer',
          citations: const [
            GroundedAnswerCitation(id: 'c1', title: 'Source A', url: 'https://a.example'),
          ],
          providerName: 'test-provider',
          generatedAt: DateTime(2026, 1, 1),
        ),
      );
      final service = _buildIngestionService(
        provider: provider,
        claims: [
          _claim('n1', 'A brand new claim.', citationUrls: const ['https://a.example']),
        ],
        results: [
          _result('n1', 'A brand new claim.', ClaimNoveltyClassification.newClaim,
              citationUrls: const ['https://a.example']),
        ],
      );

      final container = await _pumpSearchScreen(tester, ingestionService: service);
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);

      final draft = container.read(claimReviewProvider).draft;
      expect(draft, isNotNull);
      expect(draft!.markdownContent, contains('A brand new claim.'));
      expect(find.byKey(const Key('claim-draft-preview-panel')), findsOneWidget);
    });

    testWidgets('selected betterSource claims appear in markdown preview',
        (tester) async {
      final provider = _FixedGroundedAnswerProvider(
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
        claims: [_claim('b1', 'A claim with a better source.')],
        results: [
          _result('b1', 'A claim with a better source.',
              ClaimNoveltyClassification.betterSource),
        ],
      );

      final container = await _pumpSearchScreen(tester, ingestionService: service);
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);

      final draft = container.read(claimReviewProvider).draft;
      expect(draft!.markdownContent, contains('A claim with a better source.'));
    });

    testWidgets('unselected claims do not appear in markdown preview',
        (tester) async {
      final provider = _FixedGroundedAnswerProvider(
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
          _claim('c1', 'A contradicting claim.'),
        ],
        results: [
          _result('n1', 'A brand new claim.', ClaimNoveltyClassification.newClaim),
          _result('c1', 'A contradicting claim.',
              ClaimNoveltyClassification.contradiction),
        ],
      );

      final container = await _pumpSearchScreen(tester, ingestionService: service);
      await _askQuestion(tester, 'question');
      // c1 (contradiction) is not selected by default; leave it untouched.
      await _generateDraft(tester);

      final draft = container.read(claimReviewProvider).draft;
      expect(draft!.markdownContent, contains('A brand new claim.'));
      expect(draft.markdownContent, isNot(contains('A contradicting claim.')));
    });

    testWidgets(
        'alreadyKnown claims do not appear even if somehow selected',
        (tester) async {
      final provider = _FixedGroundedAnswerProvider(
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
          _claim('k1', 'An already known claim.'),
        ],
        results: [
          _result('n1', 'A brand new claim.', ClaimNoveltyClassification.newClaim),
          _result('k1', 'An already known claim.',
              ClaimNoveltyClassification.alreadyKnown),
        ],
      );

      final container = await _pumpSearchScreen(tester, ingestionService: service);
      await _askQuestion(tester, 'question');

      // alreadyKnown claims are not selected by default; force-select it to
      // confirm the draft builder still excludes it (canBeSaved is false).
      container.read(claimReviewProvider.notifier).toggle('k1');
      await tester.pumpAndSettle();
      expect(
        container.read(claimReviewProvider).selection!.selectedIds,
        contains('k1'),
      );

      await _generateDraft(tester);

      final draft = container.read(claimReviewProvider).draft;
      expect(draft!.markdownContent, isNot(contains('An already known claim.')));
    });

    testWidgets('empty selection shows no-save empty state', (tester) async {
      final provider = _FixedGroundedAnswerProvider(
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

      // Deselect the only selected (default-selected) claim.
      container.read(claimReviewProvider.notifier).toggle('n1');
      await tester.pumpAndSettle();

      await _generateDraft(tester);

      final draft = container.read(claimReviewProvider).draft;
      expect(draft!.shouldSave, isFalse);
      expect(find.byKey(const Key('claim-draft-empty-state')), findsOneWidget);
      expect(find.byKey(const Key('claim-draft-preview-panel')), findsNothing);
    });

    testWidgets('generated markdown includes sources', (tester) async {
      final provider = _FixedGroundedAnswerProvider(
        GroundedAnswer(
          question: 'q',
          answerText: 'answer',
          citations: const [
            GroundedAnswerCitation(id: 'c1', title: 'Example A', url: 'https://example.com/a'),
          ],
          providerName: 'test-provider',
          generatedAt: DateTime(2026, 1, 1),
        ),
      );
      final service = _buildIngestionService(
        provider: provider,
        claims: [
          _claim('n1', 'A brand new claim.',
              citationUrls: const ['https://example.com/a']),
        ],
        results: [
          _result('n1', 'A brand new claim.', ClaimNoveltyClassification.newClaim,
              citationUrls: const ['https://example.com/a']),
        ],
      );

      final container = await _pumpSearchScreen(tester, ingestionService: service);
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);

      final draft = container.read(claimReviewProvider).draft;
      expect(draft!.markdownContent, contains('## Sources'));
      expect(draft.markdownContent, contains('https://example.com/a'));
      expect(draft.sourceCount, 1);
      expect(find.byKey(const Key('claim-draft-source-count')), findsOneWidget);
      expect(find.text('1 source'), findsOneWidget);
    });
  });
}
