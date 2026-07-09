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
  final List<Note> insertedNotes = [];
  Object? failWith;

  @override
  Future<Note?> getNoteById(String id) async => null;

  @override
  Future<Note> insertNote({required String title, required String content}) async {
    if (failWith != null) throw failWith!;
    final note = Note(
      id: 'note-${insertedNotes.length}',
      title: title,
      content: content,
      tags: const [],
      keywords: const [],
      isPinned: false,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      embeddingPending: false,
    );
    insertedNotes.add(note);
    return note;
  }

  @override
  Future<void> updateNote(Note note) async {
    if (failWith != null) throw failWith!;
  }
}

class _AppendableNoteDraftReviewRepository implements NoteDraftReviewRepository {
  Note? existingNote;
  Object? failWith;
  final List<Note> updatedNotes = [];

  @override
  Future<Note?> getNoteById(String id) async {
    final note = existingNote;
    if (note != null && note.id == id) return note;
    return null;
  }

  @override
  Future<Note> insertNote({required String title, required String content}) {
    throw UnimplementedError('not used by the append flow');
  }

  @override
  Future<void> updateNote(Note note) async {
    if (failWith != null) throw failWith!;
    updatedNotes.add(note);
    existingNote = note;
  }
}

/// Returns null, simulating the grounded-answer provider finding nothing.
class _NullGroundedAnswerProvider implements GroundedAnswerProvider {
  const _NullGroundedAnswerProvider();

  @override
  Future<GroundedAnswer?> fetchGroundedAnswer(String question) async => null;
}

/// Never resolves until [gate] completes, so tests can observe the loading
/// window between tapping Ask and the answer coming back.
class _GatedGroundedAnswerProvider implements GroundedAnswerProvider {
  final GroundedAnswer answer;
  final Completer<void> gate;

  _GatedGroundedAnswerProvider(this.answer, this.gate);

  @override
  Future<GroundedAnswer?> fetchGroundedAnswer(String question) async {
    await gate.future;
    return answer;
  }
}

class _FixedGroundedAnswerProvider implements GroundedAnswerProvider {
  final GroundedAnswer answer;
  _FixedGroundedAnswerProvider(this.answer);
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
) => ClaimDeduplicationResult(
      claim: _claim(id, text),
      classification: classification,
      matchedLocalEvidence: const [],
      reason: 'test reason for $id',
      citationUrls: const [],
    );

GroundedAnswer _answer() => GroundedAnswer(
      question: 'q',
      answerText: 'answer',
      citations: const [],
      providerName: 'test-provider',
      generatedAt: DateTime(2026, 1, 1),
    );

Future<ProviderContainer> _pumpSearchScreen(
  WidgetTester tester, {
  required GroundedAnswerIngestionService ingestionService,
  NoteDraftReviewRepository? repository,
  ClaimReviewMapper? mapper,
}) async {
  final container = ProviderContainer(
    overrides: [
      knowledgeIngestionServiceProvider.overrideWith(
        (ref) async => _FakeKnowledgeIngestionService(),
      ),
      noteDraftReviewRepositoryProvider.overrideWithValue(
        repository ?? _RecordingNoteDraftReviewRepository(),
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

Future<void> _generateDraft(WidgetTester tester) async {
  final button = find.byKey(const Key('generate-claim-draft-button'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  group('SearchScreen claim review states', () {
    testWidgets('loading indicator appears while a question is being reviewed',
        (tester) async {
      final gate = Completer<void>();
      final service = GroundedAnswerIngestionService(
        provider: _GatedGroundedAnswerProvider(_answer(), gate),
        extractor: _FixedClaimExtractionService([_claim('n1', 'A brand new claim.')]),
        deduplicator: _FixedClaimDeduplicationService([
          _result('n1', 'A brand new claim.', ClaimNoveltyClassification.newClaim),
        ]),
        localEvidence: _EmptyLocalEvidenceRetriever(),
      );

      final container = await _pumpSearchScreen(tester, ingestionService: service);

      await tester.enterText(find.byKey(const Key('ask-question-field')), 'question');
      await tester.pump();
      await tester.tap(find.byKey(const Key('ask-question-button')));
      await tester.pump();
      await tester.pump();

      expect(container.read(claimReviewProvider).isLoading, isTrue);
      expect(find.byKey(const Key('claim-review-loading-indicator')), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('claim-review-loading-indicator')), findsNothing);
    });

    testWidgets('shows an empty state when the provider returns no answer',
        (tester) async {
      final service = GroundedAnswerIngestionService(
        provider: const _NullGroundedAnswerProvider(),
        extractor: _FixedClaimExtractionService(const []),
        deduplicator: _FixedClaimDeduplicationService(const []),
        localEvidence: _EmptyLocalEvidenceRetriever(),
      );

      final container = await _pumpSearchScreen(tester, ingestionService: service);
      await _askQuestion(tester, 'question');

      expect(container.read(claimReviewProvider).hasNoAnswer, isTrue);
      expect(find.byKey(const Key('claim-review-empty-answer-state')), findsOneWidget);
    });

    testWidgets('shows an empty state when no claims were extracted from the answer',
        (tester) async {
      final service = GroundedAnswerIngestionService(
        provider: _FixedGroundedAnswerProvider(_answer()),
        extractor: _FixedClaimExtractionService(const []),
        deduplicator: _FixedClaimDeduplicationService(const []),
        localEvidence: _EmptyLocalEvidenceRetriever(),
      );

      final container = await _pumpSearchScreen(tester, ingestionService: service);
      await _askQuestion(tester, 'question');

      expect(container.read(claimReviewProvider).hasNoClaimsExtracted, isTrue);
      expect(find.byKey(const Key('claim-review-no-claims-state')), findsOneWidget);
    });

    testWidgets('shows a nothing-new state when every claim is already known',
        (tester) async {
      final service = GroundedAnswerIngestionService(
        provider: _FixedGroundedAnswerProvider(_answer()),
        extractor: _FixedClaimExtractionService([_claim('n1', 'Known fact.')]),
        deduplicator: _FixedClaimDeduplicationService([
          _result('n1', 'Known fact.', ClaimNoveltyClassification.alreadyKnown),
        ]),
        localEvidence: _EmptyLocalEvidenceRetriever(),
      );

      final container = await _pumpSearchScreen(tester, ingestionService: service);
      await _askQuestion(tester, 'question');

      expect(container.read(claimReviewProvider).isAllClaimsAlreadyKnown, isTrue);
      expect(find.byKey(const Key('claim-review-all-known-state')), findsOneWidget);
    });

    testWidgets(
        'shows a safe error state and a retry action when reviewing claims fails',
        (tester) async {
      final service = GroundedAnswerIngestionService(
        provider: _FixedGroundedAnswerProvider(_answer()),
        extractor: _FixedClaimExtractionService([_claim('n1', 'A brand new claim.')]),
        deduplicator: _FixedClaimDeduplicationService([
          _result('n1', 'A brand new claim.', ClaimNoveltyClassification.newClaim),
        ]),
        localEvidence: _EmptyLocalEvidenceRetriever(),
      );
      final mapper =
          _ThrowingClaimReviewMapper(Exception('provider-secret-token-abc123'));

      final container =
          await _pumpSearchScreen(tester, ingestionService: service, mapper: mapper);
      await _askQuestion(tester, 'question');

      expect(container.read(claimReviewProvider).isError, isTrue);
      final errorFinder = find.byKey(const Key('claim-review-error-state'));
      expect(errorFinder, findsOneWidget);

      final errorText = tester.widget<Text>(
        find.descendant(of: errorFinder, matching: find.byType(Text)),
      );
      expect(errorText.data, isNot(contains('provider-secret-token-abc123')));
      expect(errorText.data, isNot(contains('Exception')));

      expect(find.byKey(const Key('claim-review-retry-button')), findsOneWidget);
    });

    testWidgets('save failure shows a safe error message with no leaked details',
        (tester) async {
      final repo = _RecordingNoteDraftReviewRepository()
        ..failWith = Exception('sk-live-supersecretkey123');
      final service = GroundedAnswerIngestionService(
        provider: _FixedGroundedAnswerProvider(_answer()),
        extractor: _FixedClaimExtractionService([_claim('n1', 'A brand new claim.')]),
        deduplicator: _FixedClaimDeduplicationService([
          _result('n1', 'A brand new claim.', ClaimNoveltyClassification.newClaim),
        ]),
        localEvidence: _EmptyLocalEvidenceRetriever(),
      );

      final container = await _pumpSearchScreen(
        tester,
        ingestionService: service,
        repository: repo,
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);

      final saveButton = find.byKey(const Key('save-claim-draft-button'));
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(
        container.read(claimReviewProvider).saveStatus,
        ClaimDraftSaveStatus.error,
      );

      final errorText = tester.widget<Text>(
        find.byKey(const Key('claim-draft-save-error-message')),
      );
      expect(errorText.data, isNot(contains('sk-live-supersecretkey123')));
      expect(find.byKey(const Key('claim-draft-save-retry-button')), findsOneWidget);
    });

    testWidgets('append failure shows a safe error message with no leaked details',
        (tester) async {
      final existing = Note(
        id: 'existing-note',
        title: 'Existing note',
        content: 'Old content.',
        tags: const [],
        keywords: const [],
        isPinned: false,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        embeddingPending: false,
      );
      final repo = _AppendableNoteDraftReviewRepository()
        ..existingNote = existing
        ..failWith = Exception('sk-live-supersecretkey123');
      final service = GroundedAnswerIngestionService(
        provider: _FixedGroundedAnswerProvider(_answer()),
        extractor: _FixedClaimExtractionService([_claim('n1', 'A brand new claim.')]),
        deduplicator: _FixedClaimDeduplicationService([
          _result('n1', 'A brand new claim.', ClaimNoveltyClassification.newClaim),
        ]),
        localEvidence: _EmptyLocalEvidenceRetriever(),
      );

      final container = await _pumpSearchScreen(
        tester,
        ingestionService: service,
        repository: repo,
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);

      final notifier = container.read(claimReviewProvider.notifier);
      notifier.selectTargetNote(existing.id);
      await tester.pumpAndSettle();

      final appendButton = find.byKey(const Key('append-claim-draft-button'));
      await tester.ensureVisible(appendButton);
      await tester.tap(appendButton);
      await tester.pumpAndSettle();

      expect(
        container.read(claimReviewProvider).appendStatus,
        ClaimDraftAppendStatus.error,
      );

      final errorText = tester.widget<Text>(
        find.byKey(const Key('claim-draft-append-error-message')),
      );
      expect(errorText.data, isNot(contains('sk-live-supersecretkey123')));
      expect(find.byKey(const Key('claim-draft-append-retry-button')), findsOneWidget);
    });
  });
}
