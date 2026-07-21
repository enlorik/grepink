import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/claim_deduplication_result.dart';
import 'package:grepink/models/claim_review_item.dart';
import 'package:grepink/models/claim_review_session_state.dart';
import 'package:grepink/models/evidence_item.dart';
import 'package:grepink/models/extracted_claim.dart';
import 'package:grepink/models/grounded_answer.dart';
import 'package:grepink/models/grounded_claim_ingestion_result.dart';
import 'package:grepink/models/note.dart';
import 'package:grepink/models/note_draft.dart';
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
import 'package:grepink/services/provider_name_formatter.dart';
import 'package:grepink/services/selected_claims_draft_builder.dart';

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

class _SimpleNoteDraftReviewRepository implements NoteDraftReviewRepository {
  @override
  Future<Note?> getNoteById(String id) async => null;

  @override
  Future<Note> insertNote(
          {required String title, required String content}) async =>
      Note(
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

/// Blocks until [gate] completes, then returns [answer]. isConfigured = true.
class _GatedGroundedAnswerProvider implements GroundedAnswerProvider {
  final GroundedAnswer answer;
  final Completer<void> gate;
  _GatedGroundedAnswerProvider(this.answer, this.gate);

  @override
  bool get isConfigured => true;

  @override
  Future<GroundedAnswer?> fetchGroundedAnswer(String question) async {
    await gate.future;
    return answer;
  }
}

/// Throws from fetchGroundedAnswer. isConfigured = true so runReview() enters
/// the pipeline and the exception is caught by GroundedAnswerIngestionService.
class _ThrowingGroundedAnswerProvider implements GroundedAnswerProvider {
  final Object error;
  _ThrowingGroundedAnswerProvider(this.error);

  @override
  bool get isConfigured => true;

  @override
  Future<GroundedAnswer?> fetchGroundedAnswer(String question) async =>
      throw error;
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

class _ThrowingClaimReviewMapper implements ClaimReviewMapper {
  final Object error;
  _ThrowingClaimReviewMapper(this.error);

  @override
  List<ClaimReviewGroup> toGroups(GroundedClaimIngestionResult ingestion) =>
      throw error;

  @override
  ClaimReviewSelectionState toSelectionState(
    GroundedClaimIngestionResult ingestion,
  ) =>
      throw error;
}

class _CountingClaimExtractionService implements ClaimExtractionService {
  final ClaimExtractionService inner;
  final void Function() onCall;
  _CountingClaimExtractionService({required this.inner, required this.onCall});

  @override
  List<ExtractedClaim> extract(GroundedAnswer answer) {
    onCall();
    return inner.extract(answer);
  }
}

// ─── Fixtures ─────────────────────────────────────────────────────────────────

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
) =>
    ClaimDeduplicationResult(
      claim: _claim(id, text),
      classification: classification,
      matchedLocalEvidence: const [],
      reason: 'reason for $id',
      citationUrls: const [],
    );

GroundedAnswer _answer({String providerName = 'brave'}) => GroundedAnswer(
      question: 'q',
      answerText: 'answer',
      citations: const [],
      providerName: providerName,
      generatedAt: DateTime(2026, 1, 1),
    );

GroundedAnswerIngestionService _serviceWithOneClaim(
  GroundedAnswerProvider provider,
) =>
    GroundedAnswerIngestionService(
      provider: provider,
      extractor: _FixedClaimExtractionService([_claim('n1', 'A new claim.')]),
      deduplicator: _FixedClaimDeduplicationService([
        _result('n1', 'A new claim.', ClaimNoveltyClassification.newClaim),
      ]),
      localEvidence: _EmptyLocalEvidenceRetriever(),
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
        _SimpleNoteDraftReviewRepository(),
      ),
      groundedAnswerIngestionServiceProvider
          .overrideWithValue(ingestionService),
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

void _expectNoTextContains(WidgetTester tester, String secret) {
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    expect(
      text.data ?? '',
      isNot(contains(secret)),
      reason: 'Secret found in visible Text widget: "${text.data}"',
    );
  }
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  // ── Provider not-configured state ──────────────────────────────────────────

  group('ClaimReviewNotifier providerNotConfigured state', () {
    test('isProviderNotConfigured is false in idle state', () {
      const state = ClaimReviewSessionState();
      expect(state.isProviderNotConfigured, isFalse);
    });

    testWidgets(
        'unconfigured provider produces providerNotConfigured after ask',
        (tester) async {
      final service = GroundedAnswerIngestionService(
        provider: const NullGroundedAnswerProvider(),
        extractor: _FixedClaimExtractionService(const []),
        deduplicator: _FixedClaimDeduplicationService(const []),
        localEvidence: _EmptyLocalEvidenceRetriever(),
      );
      final container =
          await _pumpSearchScreen(tester, ingestionService: service);
      await _askQuestion(tester, 'question');

      expect(
          container.read(claimReviewProvider).isProviderNotConfigured, isTrue);
    });

    testWidgets('providerNotConfigured preserves the trimmed question',
        (tester) async {
      final service = GroundedAnswerIngestionService(
        provider: const NullGroundedAnswerProvider(),
        extractor: _FixedClaimExtractionService(const []),
        deduplicator: _FixedClaimDeduplicationService(const []),
        localEvidence: _EmptyLocalEvidenceRetriever(),
      );
      final container =
          await _pumpSearchScreen(tester, ingestionService: service);
      await _askQuestion(tester, '  my question  ');

      expect(container.read(claimReviewProvider).question, 'my question');
    });

    testWidgets('no loading indicator when provider is not configured',
        (tester) async {
      final service = GroundedAnswerIngestionService(
        provider: const NullGroundedAnswerProvider(),
        extractor: _FixedClaimExtractionService(const []),
        deduplicator: _FixedClaimDeduplicationService(const []),
        localEvidence: _EmptyLocalEvidenceRetriever(),
      );
      await _pumpSearchScreen(tester, ingestionService: service);
      await _askQuestion(tester, 'question');

      expect(find.byKey(const Key('claim-review-loading-indicator')),
          findsNothing);
    });

    testWidgets('no review groups panel when provider is not configured',
        (tester) async {
      final service = GroundedAnswerIngestionService(
        provider: const NullGroundedAnswerProvider(),
        extractor: _FixedClaimExtractionService(const []),
        deduplicator: _FixedClaimDeduplicationService(const []),
        localEvidence: _EmptyLocalEvidenceRetriever(),
      );
      await _pumpSearchScreen(tester, ingestionService: service);
      await _askQuestion(tester, 'question');

      expect(find.byKey(const Key('claim-review-groups-panel')), findsNothing);
    });

    testWidgets(
        'extraction pipeline is never called when provider is not configured',
        (tester) async {
      var extractorCallCount = 0;
      final service = GroundedAnswerIngestionService(
        provider: const NullGroundedAnswerProvider(),
        extractor: _CountingClaimExtractionService(
          inner: _FixedClaimExtractionService(const []),
          onCall: () => extractorCallCount++,
        ),
        deduplicator: _FixedClaimDeduplicationService(const []),
        localEvidence: _EmptyLocalEvidenceRetriever(),
      );
      await _pumpSearchScreen(tester, ingestionService: service);
      await _askQuestion(tester, 'question');

      // isConfigured = false → runReview() returns before calling service.ingest()
      expect(extractorCallCount, 0);
    });

    testWidgets('setup-required card is shown when provider is not configured',
        (tester) async {
      final service = GroundedAnswerIngestionService(
        provider: const NullGroundedAnswerProvider(),
        extractor: _FixedClaimExtractionService(const []),
        deduplicator: _FixedClaimDeduplicationService(const []),
        localEvidence: _EmptyLocalEvidenceRetriever(),
      );
      await _pumpSearchScreen(tester, ingestionService: service);
      await _askQuestion(tester, 'question');

      expect(
        find.byKey(const Key('claim-review-provider-not-configured-state')),
        findsOneWidget,
      );
    });

    testWidgets('setup-required card text does not mention Settings',
        (tester) async {
      final service = GroundedAnswerIngestionService(
        provider: const NullGroundedAnswerProvider(),
        extractor: _FixedClaimExtractionService(const []),
        deduplicator: _FixedClaimDeduplicationService(const []),
        localEvidence: _EmptyLocalEvidenceRetriever(),
      );
      await _pumpSearchScreen(tester, ingestionService: service);
      await _askQuestion(tester, 'question');

      final card =
          find.byKey(const Key('claim-review-provider-not-configured-state'));
      for (final text in tester.widgetList<Text>(
          find.descendant(of: card, matching: find.byType(Text)))) {
        expect(
          (text.data ?? '').toLowerCase(),
          isNot(contains('settings')),
        );
      }
    });

    testWidgets('no Retry button for setup-required state', (tester) async {
      final service = GroundedAnswerIngestionService(
        provider: const NullGroundedAnswerProvider(),
        extractor: _FixedClaimExtractionService(const []),
        deduplicator: _FixedClaimDeduplicationService(const []),
        localEvidence: _EmptyLocalEvidenceRetriever(),
      );
      await _pumpSearchScreen(tester, ingestionService: service);
      await _askQuestion(tester, 'question');

      expect(find.byKey(const Key('claim-review-retry-button')), findsNothing);
    });

    testWidgets('reset() clears providerNotConfigured back to idle',
        (tester) async {
      final service = GroundedAnswerIngestionService(
        provider: const NullGroundedAnswerProvider(),
        extractor: _FixedClaimExtractionService(const []),
        deduplicator: _FixedClaimDeduplicationService(const []),
        localEvidence: _EmptyLocalEvidenceRetriever(),
      );
      final container =
          await _pumpSearchScreen(tester, ingestionService: service);
      await _askQuestion(tester, 'question');
      expect(
          container.read(claimReviewProvider).isProviderNotConfigured, isTrue);

      container.read(claimReviewProvider.notifier).reset();
      await tester.pump();

      expect(
          container.read(claimReviewProvider).isProviderNotConfigured, isFalse);
      expect(
        container.read(claimReviewProvider).status,
        ClaimReviewSessionStatus.idle,
      );
    });

    testWidgets(
        'a configured review after providerNotConfigured succeeds normally',
        (tester) async {
      // Ask with unconfigured → providerNotConfigured.
      final unconfiguredService = GroundedAnswerIngestionService(
        provider: const NullGroundedAnswerProvider(),
        extractor: _FixedClaimExtractionService(const []),
        deduplicator: _FixedClaimDeduplicationService(const []),
        localEvidence: _EmptyLocalEvidenceRetriever(),
      );
      var container = await _pumpSearchScreen(tester,
          ingestionService: unconfiguredService);
      await _askQuestion(tester, 'question');
      expect(
          container.read(claimReviewProvider).isProviderNotConfigured, isTrue);

      // Re-pump with configured service → success.
      final configuredService = _serviceWithOneClaim(
        _FixedGroundedAnswerProvider(_answer()),
      );
      container =
          await _pumpSearchScreen(tester, ingestionService: configuredService);
      await _askQuestion(tester, 'question');

      expect(container.read(claimReviewProvider).isSuccess, isTrue);
      expect(
          container.read(claimReviewProvider).isProviderNotConfigured, isFalse);
    });

    testWidgets(
        'stale gated review is abandoned after reset increments the session token',
        (tester) async {
      // providerNotConfigured uses the same _requestSequence increment as reset().
      // This test verifies the guard: any in-flight request whose requestId no
      // longer matches _requestSequence after a session change is silently dropped.
      final gate = Completer<void>();
      final service =
          _serviceWithOneClaim(_GatedGroundedAnswerProvider(_answer(), gate));
      final container =
          await _pumpSearchScreen(tester, ingestionService: service);

      // Start gated review → loading.
      await tester.enterText(
          find.byKey(const Key('ask-question-field')), 'question');
      await tester.pump();
      await tester.tap(find.byKey(const Key('ask-question-button')));
      await tester.pump();
      await tester.pump();
      expect(container.read(claimReviewProvider).isLoading, isTrue);

      // Reset — increments _requestSequence (same increment providerNotConfigured uses).
      container.read(claimReviewProvider.notifier).reset();
      await tester.pump();
      expect(
        container.read(claimReviewProvider).status,
        ClaimReviewSessionStatus.idle,
      );

      // Unblock the stale request.
      gate.complete();
      await tester.pumpAndSettle();

      // Stale result must not overwrite the post-reset idle state.
      expect(
        container.read(claimReviewProvider).status,
        ClaimReviewSessionStatus.idle,
      );
      expect(find.byKey(const Key('claim-review-groups-panel')), findsNothing);
    });
  });

  // ── Provider attribution display ───────────────────────────────────────────

  group('provider attribution display', () {
    testWidgets('safe provider name is shown after successful review',
        (tester) async {
      final service = _serviceWithOneClaim(
        _FixedGroundedAnswerProvider(_answer(providerName: 'brave')),
      );
      await _pumpSearchScreen(tester, ingestionService: service);
      await _askQuestion(tester, 'question');

      final label = find.byKey(const Key('claim-review-provider-label'));
      expect(label, findsOneWidget);
      expect(tester.widget<Text>(label).data, contains('brave'));
    });

    testWidgets('provider label does not appear while loading', (tester) async {
      final gate = Completer<void>();
      final service =
          _serviceWithOneClaim(_GatedGroundedAnswerProvider(_answer(), gate));
      await _pumpSearchScreen(tester, ingestionService: service);
      await tester.enterText(
          find.byKey(const Key('ask-question-field')), 'question');
      await tester.pump();
      await tester.tap(find.byKey(const Key('ask-question-button')));
      await tester.pump();
      await tester.pump();

      expect(
          find.byKey(const Key('claim-review-provider-label')), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets(
        'provider label does not appear for providerNotConfigured state',
        (tester) async {
      final service = GroundedAnswerIngestionService(
        provider: const NullGroundedAnswerProvider(),
        extractor: _FixedClaimExtractionService(const []),
        deduplicator: _FixedClaimDeduplicationService(const []),
        localEvidence: _EmptyLocalEvidenceRetriever(),
      );
      await _pumpSearchScreen(tester, ingestionService: service);
      await _askQuestion(tester, 'question');

      expect(
          find.byKey(const Key('claim-review-provider-label')), findsNothing);
    });

    testWidgets('provider name never appears in generated markdown',
        (tester) async {
      const builder = SelectedClaimsDraftBuilder();
      const item = ClaimReviewItem(
        id: 'n1',
        text: 'A claim.',
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

    testWidgets(
        'provider exception with secret does not surface to visible Text widgets',
        (tester) async {
      // GroundedAnswerIngestionService.ingest() catches all provider exceptions
      // and returns an empty result — the exception message never reaches the UI.
      final service = GroundedAnswerIngestionService(
        provider: _ThrowingGroundedAnswerProvider(
            Exception('auth failed for key $_secretApiKey')),
        extractor: _FixedClaimExtractionService([_claim('n1', 'A claim.')]),
        deduplicator: _FixedClaimDeduplicationService([
          _result('n1', 'A claim.', ClaimNoveltyClassification.newClaim),
        ]),
        localEvidence: _EmptyLocalEvidenceRetriever(),
      );
      await _pumpSearchScreen(tester, ingestionService: service);
      await _askQuestion(tester, 'question');

      _expectNoTextContains(tester, _secretApiKey);
    });

    testWidgets(
        'mapper exception with secret text is not surfaced to visible Text widgets',
        (tester) async {
      final service = _serviceWithOneClaim(
        _FixedGroundedAnswerProvider(_answer()),
      );
      final container = await _pumpSearchScreen(
        tester,
        ingestionService: service,
        mapper: _ThrowingClaimReviewMapper(Exception(_secretApiKey)),
      );
      await _askQuestion(tester, 'question');

      expect(container.read(claimReviewProvider).isError, isTrue);
      _expectNoTextContains(tester, _secretApiKey);
    });
  });

  // ── safeProviderDisplayName unit tests ────────────────────────────────────

  group('safeProviderDisplayName', () {
    test('normal name is returned trimmed and whitespace-collapsed', () {
      expect(safeProviderDisplayName('  brave  '), 'brave');
      expect(safeProviderDisplayName('my  provider'), 'my provider');
    });

    test('null returns null', () {
      expect(safeProviderDisplayName(null), isNull);
    });

    test('empty string returns null', () {
      expect(safeProviderDisplayName(''), isNull);
    });

    test('whitespace-only returns null', () {
      expect(safeProviderDisplayName('   '), isNull);
    });

    test('newline is rejected', () {
      expect(safeProviderDisplayName('brave\nprovider'), isNull);
    });

    test('carriage return is rejected', () {
      expect(safeProviderDisplayName('brave\rprovider'), isNull);
    });

    test('null control character is rejected', () {
      expect(safeProviderDisplayName('brave\x00provider'), isNull);
    });

    test('name longer than 64 chars is rejected', () {
      expect(safeProviderDisplayName('a' * 65), isNull);
    });

    test('name of exactly 64 chars is accepted', () {
      final exact = 'a' * 64;
      expect(safeProviderDisplayName(exact), exact);
    });

    test('sk- prefix is rejected', () {
      expect(safeProviderDisplayName('sk-live-abc123'), isNull);
    });

    test('embedded sk- is rejected (e.g. "OpenAI sk-live-...")', () {
      expect(safeProviderDisplayName('OpenAI sk-live-abc123'), isNull);
    });

    test('Bearer prefix is rejected case-insensitively', () {
      expect(safeProviderDisplayName('Bearer token123'), isNull);
      expect(safeProviderDisplayName('bearer token123'), isNull);
    });

    test('embedded bearer is rejected (e.g. "Brave Bearer ...")', () {
      expect(safeProviderDisplayName('Brave Bearer abc123'), isNull);
    });

    test('api_key substring is rejected', () {
      expect(safeProviderDisplayName('my_api_key'), isNull);
    });

    test('apikey substring is rejected', () {
      expect(safeProviderDisplayName('myapikey'), isNull);
    });

    test('safe short name is returned unchanged', () {
      expect(safeProviderDisplayName('Brave AI'), 'Brave AI');
    });
  });

  // ── State distinctness ─────────────────────────────────────────────────────

  group('providerNotConfigured is distinct from other review states', () {
    test('idle state is not providerNotConfigured', () {
      const s = ClaimReviewSessionState();
      expect(s.isProviderNotConfigured, isFalse);
      expect(s.isError, isFalse);
    });

    test('error state is not providerNotConfigured', () {
      const s = ClaimReviewSessionState(
        status: ClaimReviewSessionStatus.error,
        errorMessage: 'oops',
      );
      expect(s.isProviderNotConfigured, isFalse);
      expect(s.isError, isTrue);
    });

    testWidgets('error card is shown for error state, not setup-required card',
        (tester) async {
      final service = _serviceWithOneClaim(
        _FixedGroundedAnswerProvider(_answer()),
      );
      final container = await _pumpSearchScreen(
        tester,
        ingestionService: service,
        mapper: _ThrowingClaimReviewMapper(Exception('oops')),
      );
      await _askQuestion(tester, 'question');

      expect(container.read(claimReviewProvider).isError, isTrue);
      expect(
        find.byKey(const Key('claim-review-provider-not-configured-state')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('claim-review-error-state')),
        findsOneWidget,
      );
    });
  });
}
