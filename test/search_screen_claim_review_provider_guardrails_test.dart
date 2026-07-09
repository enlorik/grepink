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
import 'package:grepink/models/grounded_claim_ingestion_result.dart';
import 'package:grepink/providers/claim_review_provider.dart';
import 'package:grepink/providers/knowledge_ingestion_provider.dart';
import 'package:grepink/providers/note_draft_review_provider.dart';
import 'package:grepink/providers/notes_provider.dart';
import 'package:grepink/screens/search_screen.dart';
import 'package:grepink/services/claim_deduplication_service.dart';
import 'package:grepink/services/claim_extraction_service.dart';
import 'package:grepink/services/claim_review_mapper.dart';
import 'package:grepink/services/grounded_answer_ingestion_service.dart';
import 'package:grepink/services/grounded_answer_provider.dart';
import 'package:grepink/services/knowledge_ingestion_service.dart';
import 'package:grepink/services/local_evidence_retriever.dart';
import 'package:grepink/services/selected_claims_draft_builder.dart';

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

class _RecordingNoteDraftReviewRepository implements NoteDraftReviewRepository {
  @override
  Future<Note?> getNoteById(String id) async => null;

  @override
  Future<Note> insertNote({required String title, required String content}) async {
    return Note(
      id: 'note-1',
      title: title,
      content: content,
      tags: const [],
      keywords: const [],
      isPinned: false,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      embeddingPending: false,
    );
  }

  @override
  Future<void> updateNote(Note note) async {}
}

class _FixedGroundedAnswerProvider implements GroundedAnswerProvider {
  final GroundedAnswer answer;
  _FixedGroundedAnswerProvider(this.answer);
  @override
  Future<GroundedAnswer?> fetchGroundedAnswer(String question) async => answer;
}

/// Simulates a provider whose underlying HTTP client leaks a secret in an
/// exception message (e.g. a misconfigured client echoing its auth header).
class _ThrowingGroundedAnswerProvider implements GroundedAnswerProvider {
  final Object error;
  _ThrowingGroundedAnswerProvider(this.error);
  @override
  Future<GroundedAnswer?> fetchGroundedAnswer(String question) async {
    throw error;
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
  ) async => results;
}

class _EmptyLocalEvidenceRetriever implements LocalEvidenceRetriever {
  @override
  Future<List<EvidenceItem>> retrieve(String question) async => const [];
}

/// Throws instead of mapping, so runReview()'s error path can be exercised
/// without relying on GroundedAnswerIngestionService (which never throws).
class _ThrowingClaimReviewMapper implements ClaimReviewMapper {
  final Object error;
  _ThrowingClaimReviewMapper(this.error);

  @override
  List<ClaimReviewGroup> toGroups(GroundedClaimIngestionResult ingestion) {
    throw error;
  }

  @override
  ClaimReviewSelectionState toSelectionState(
    GroundedClaimIngestionResult ingestion,
  ) {
    throw error;
  }
}

// ─── Fixtures ────────────────────────────────────────────────────────────────

const _secretApiKey = 'sk-live-supersecretkey123';

ExtractedClaim _claim(String id, String text) => ExtractedClaim(
      id: id,
      text: text,
      citationUrls: const [],
      citationTitles: const [],
      sourceAnswerProvider: 'brave',
      sourceQuestion: 'q',
      order: 0,
    );

ClaimDeduplicationResult _result(
  String id,
  String text,
  ClaimNoveltyClassification classification,
) => ClaimDeduplicationResult(
      claim: _claim(id, text),
      classification: classification,
      matchedLocalEvidence: const [],
      reason: 'test reason for $id',
      citationUrls: const [],
    );

GroundedAnswer _answer({String providerName = 'brave'}) => GroundedAnswer(
      question: 'q',
      answerText: 'answer',
      citations: const [],
      providerName: providerName,
      generatedAt: DateTime(2026, 1, 1),
    );

Future<ProviderContainer> _pumpSearchScreen(
  WidgetTester tester, {
  required GroundedAnswerIngestionService ingestionService,
  ClaimReviewMapper? mapper,
}) async {
  final container = ProviderContainer(
    overrides: [
      knowledgeIngestionServiceProvider.overrideWith(
        (ref) async => _FakeKnowledgeIngestionService(),
      ),
      noteDraftReviewRepositoryProvider.overrideWithValue(
        _RecordingNoteDraftReviewRepository(),
      ),
      groundedAnswerIngestionServiceProvider.overrideWithValue(ingestionService),
      if (mapper != null) claimReviewMapperProvider.overrideWithValue(mapper),
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

/// Asserts that [secret] does not appear in any visible [Text] widget.
void _expectNoTextContains(WidgetTester tester, String secret) {
  final texts = tester.widgetList<Text>(find.byType(Text));
  for (final text in texts) {
    expect(text.data ?? '', isNot(contains(secret)));
  }
}

void main() {
  group('SearchScreen grounded provider guardrails', () {
    testWidgets('missing provider config shows a setup-required state',
        (tester) async {
      final service = GroundedAnswerIngestionService(
        provider: const NullGroundedAnswerProvider(),
        extractor: _FixedClaimExtractionService(const []),
        deduplicator: _FixedClaimDeduplicationService(const []),
        localEvidence: _EmptyLocalEvidenceRetriever(),
      );

      final container = await _pumpSearchScreen(tester, ingestionService: service);
      await _askQuestion(tester, 'question');

      expect(container.read(claimReviewProvider).isProviderNotConfigured, isTrue);
      expect(
        find.byKey(const Key('claim-review-provider-not-configured-state')),
        findsOneWidget,
      );
      // The pipeline must never actually run when unconfigured.
      expect(find.byKey(const Key('claim-review-loading-indicator')), findsNothing);
      expect(find.byKey(const Key('claim-review-groups-panel')), findsNothing);
    });

    testWidgets('providerName appears as a safe label once review succeeds',
        (tester) async {
      final service = GroundedAnswerIngestionService(
        provider: _FixedGroundedAnswerProvider(_answer(providerName: 'brave')),
        extractor: _FixedClaimExtractionService([_claim('n1', 'A brand new claim.')]),
        deduplicator: _FixedClaimDeduplicationService([
          _result('n1', 'A brand new claim.', ClaimNoveltyClassification.newClaim),
        ]),
        localEvidence: _EmptyLocalEvidenceRetriever(),
      );

      await _pumpSearchScreen(tester, ingestionService: service);
      await _askQuestion(tester, 'question');

      final labelFinder = find.byKey(const Key('claim-review-provider-label'));
      expect(labelFinder, findsOneWidget);
      final label = tester.widget<Text>(labelFinder);
      expect(label.data, contains('brave'));
    });

    test('generated markdown never includes the raw provider name value', () {
      const builder = SelectedClaimsDraftBuilder();
      const item = ClaimReviewItem(
        id: 'n1',
        text: 'A brand new claim.',
        classification: ClaimNoveltyClassification.newClaim,
        citationUrls: [],
        citationTitles: [],
        selectedByDefault: true,
        reason: 'test',
        matchedLocalEvidenceIds: [],
        canBeSaved: true,
      );

      final result = builder.build(
        question: 'question',
        selected: [item],
        providerName: _secretApiKey,
        citations: const [],
      );

      expect(result.markdownContent, isNot(contains(_secretApiKey)));
    });

    testWidgets('visible errors do not contain API key patterns',
        (tester) async {
      final service = GroundedAnswerIngestionService(
        provider: _FixedGroundedAnswerProvider(_answer()),
        extractor: _FixedClaimExtractionService([_claim('n1', 'A brand new claim.')]),
        deduplicator: _FixedClaimDeduplicationService([
          _result('n1', 'A brand new claim.', ClaimNoveltyClassification.newClaim),
        ]),
        localEvidence: _EmptyLocalEvidenceRetriever(),
      );
      final mapper = _ThrowingClaimReviewMapper(Exception(_secretApiKey));

      final container = await _pumpSearchScreen(
        tester,
        ingestionService: service,
        mapper: mapper,
      );
      await _askQuestion(tester, 'question');

      expect(container.read(claimReviewProvider).isError, isTrue);
      _expectNoTextContains(tester, _secretApiKey);
    });

    testWidgets('a provider exception does not reveal secrets anywhere on screen',
        (tester) async {
      final service = GroundedAnswerIngestionService(
        provider: _ThrowingGroundedAnswerProvider(
          Exception('auth failed for key $_secretApiKey'),
        ),
        extractor: _FixedClaimExtractionService([_claim('n1', 'A brand new claim.')]),
        deduplicator: _FixedClaimDeduplicationService([
          _result('n1', 'A brand new claim.', ClaimNoveltyClassification.newClaim),
        ]),
        localEvidence: _EmptyLocalEvidenceRetriever(),
      );

      final container = await _pumpSearchScreen(tester, ingestionService: service);
      await _askQuestion(tester, 'question');

      expect(container.read(claimReviewProvider).isError, isFalse);
      _expectNoTextContains(tester, _secretApiKey);
    });
  });
}
