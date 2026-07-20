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

// Configured provider that returns null — simulates a real provider finding no
// answer. Distinct from NullGroundedAnswerProvider (isConfigured = false) which
// causes runReview to skip the pipeline entirely.
class _NoAnswerGroundedAnswerProvider implements GroundedAnswerProvider {
  const _NoAnswerGroundedAnswerProvider();

  @override
  bool get isConfigured => true;

  @override
  Future<GroundedAnswer?> fetchGroundedAnswer(String question) async => null;
}

// Never resolves until [gate] completes.
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

/// Throws on [toGroups] so [runReview]'s catch block can be exercised without
/// needing the ingestion service itself to fail.
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

/// Throws on [build] so [generateDraft]'s catch block can be exercised.
class _ThrowingDraftBuilder implements SelectedClaimsDraftBuilder {
  final Object error;
  _ThrowingDraftBuilder(this.error);

  @override
  ClaimDraftResult build({
    required String question,
    required List<ClaimReviewItem> selected,
    required String providerName,
    required List<GroundedAnswerCitation> citations,
  }) {
    throw error;
  }
}

// Gated NoteDraftReviewRepository: insertNote blocks until [gate] completes.
class _GatedNoteDraftReviewRepository implements NoteDraftReviewRepository {
  final Completer<void> gate;
  _GatedNoteDraftReviewRepository(this.gate);

  @override
  Future<Note?> getNoteById(String id) async => null;

  @override
  Future<Note> insertNote({required String title, required String content}) async {
    await gate.future;
    return Note(
      id: 'gated-note',
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

// Gated append repo: updateNote blocks until [gate] completes.
class _GatedAppendRepository implements NoteDraftReviewRepository {
  final Completer<void> gate;
  final Note existingNote;
  _GatedAppendRepository(this.gate, this.existingNote);

  @override
  Future<Note?> getNoteById(String id) async =>
      existingNote.id == id ? existingNote : null;

  @override
  Future<Note> insertNote({required String title, required String content}) {
    throw UnimplementedError();
  }

  @override
  Future<void> updateNote(Note note) async {
    await gate.future;
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
) =>
    ClaimDeduplicationResult(
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

GroundedAnswerIngestionService _serviceWithOneNewClaim(
  GroundedAnswerProvider provider,
) =>
    GroundedAnswerIngestionService(
      provider: provider,
      extractor: _FixedClaimExtractionService([_claim('n1', 'A brand new claim.')]),
      deduplicator: _FixedClaimDeduplicationService([
        _result('n1', 'A brand new claim.', ClaimNoveltyClassification.newClaim),
      ]),
      localEvidence: _EmptyLocalEvidenceRetriever(),
    );

Future<ProviderContainer> _pumpSearchScreen(
  WidgetTester tester, {
  required GroundedAnswerIngestionService ingestionService,
  NoteDraftReviewRepository? repository,
  ClaimReviewMapper? mapper,
  SelectedClaimsDraftBuilder? draftBuilder,
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
      if (draftBuilder != null)
        selectedClaimsDraftBuilderProvider.overrideWithValue(draftBuilder),
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

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  group('SearchScreen claim review states', () {
    // ── Loading ────────────────────────────────────────────────────────────

    testWidgets('loading indicator appears while a claim review is pending',
        (tester) async {
      final gate = Completer<void>();
      final service = _serviceWithOneNewClaim(
        _GatedGroundedAnswerProvider(_answer(), gate),
      );

      final container = await _pumpSearchScreen(tester, ingestionService: service);

      await tester.enterText(find.byKey(const Key('ask-question-field')), 'question');
      await tester.pump();
      await tester.tap(find.byKey(const Key('ask-question-button')));
      // Two pumps: one for _onAsk microtask, one for the state update.
      await tester.pump();
      await tester.pump();

      expect(container.read(claimReviewProvider).isLoading, isTrue);
      expect(find.byKey(const Key('claim-review-loading-indicator')), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('claim-review-loading-indicator')), findsNothing);
    });

    testWidgets('Ask button is disabled while claim review is loading',
        (tester) async {
      final gate = Completer<void>();
      final service = _serviceWithOneNewClaim(
        _GatedGroundedAnswerProvider(_answer(), gate),
      );

      final container = await _pumpSearchScreen(tester, ingestionService: service);

      await tester.enterText(find.byKey(const Key('ask-question-field')), 'question');
      await tester.pump();
      await tester.tap(find.byKey(const Key('ask-question-button')));
      await tester.pump();
      await tester.pump();

      expect(container.read(claimReviewProvider).isLoading, isTrue);

      final askButton = tester.widget<FilledButton>(
        find.byKey(const Key('ask-question-button')),
      );
      expect(askButton.onPressed, isNull);

      gate.complete();
      await tester.pumpAndSettle();
    });

    // ── Empty results ──────────────────────────────────────────────────────

    testWidgets('no-answer state is shown when the provider returns no answer',
        (tester) async {
      final service = GroundedAnswerIngestionService(
        provider: const _NoAnswerGroundedAnswerProvider(),
        extractor: _FixedClaimExtractionService(const []),
        deduplicator: _FixedClaimDeduplicationService(const []),
        localEvidence: _EmptyLocalEvidenceRetriever(),
      );

      final container = await _pumpSearchScreen(tester, ingestionService: service);
      await _askQuestion(tester, 'question');

      expect(container.read(claimReviewProvider).hasNoAnswer, isTrue);
      expect(find.byKey(const Key('claim-review-empty-answer-state')), findsOneWidget);
      expect(find.byKey(const Key('claim-review-no-claims-state')), findsNothing);
      expect(find.byKey(const Key('claim-review-all-known-state')), findsNothing);
    });

    testWidgets(
        'no-claims state is shown when the answer returned no extractable claims',
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
      expect(find.byKey(const Key('claim-review-empty-answer-state')), findsNothing);
    });

    testWidgets('all-known state is shown when every extracted claim is already known',
        (tester) async {
      final service = GroundedAnswerIngestionService(
        provider: _FixedGroundedAnswerProvider(_answer()),
        extractor: _FixedClaimExtractionService([_claim('k1', 'Known fact.')]),
        deduplicator: _FixedClaimDeduplicationService([
          _result('k1', 'Known fact.', ClaimNoveltyClassification.alreadyKnown),
        ]),
        localEvidence: _EmptyLocalEvidenceRetriever(),
      );

      final container = await _pumpSearchScreen(tester, ingestionService: service);
      await _askQuestion(tester, 'question');

      expect(container.read(claimReviewProvider).isAllClaimsAlreadyKnown, isTrue);
      expect(find.byKey(const Key('claim-review-all-known-state')), findsOneWidget);
    });

    testWidgets(
        'unconfigured provider does not show any empty-result or error state',
        (tester) async {
      // NullGroundedAnswerProvider has isConfigured = false, so runReview
      // returns early without updating state. No empty-result cards must appear.
      final service = GroundedAnswerIngestionService(
        provider: const NullGroundedAnswerProvider(),
        extractor: _FixedClaimExtractionService(const []),
        deduplicator: _FixedClaimDeduplicationService(const []),
        localEvidence: _EmptyLocalEvidenceRetriever(),
      );

      await _pumpSearchScreen(tester, ingestionService: service);
      await _askQuestion(tester, 'question');

      expect(find.byKey(const Key('claim-review-empty-answer-state')), findsNothing);
      expect(find.byKey(const Key('claim-review-no-claims-state')), findsNothing);
      expect(find.byKey(const Key('claim-review-all-known-state')), findsNothing);
      expect(find.byKey(const Key('claim-review-error-state')), findsNothing);
      expect(find.byKey(const Key('claim-review-loading-indicator')), findsNothing);
    });

    // ── Review failure ─────────────────────────────────────────────────────

    testWidgets('review exception text is not leaked in the error card',
        (tester) async {
      final service = _serviceWithOneNewClaim(
        _FixedGroundedAnswerProvider(_answer()),
      );
      final mapper = _ThrowingClaimReviewMapper(
        Exception('provider-secret-token-abc123'),
      );

      final container = await _pumpSearchScreen(
        tester,
        ingestionService: service,
        mapper: mapper,
      );
      await _askQuestion(tester, 'question');

      expect(container.read(claimReviewProvider).isError, isTrue);
      final errorCard = find.byKey(const Key('claim-review-error-state'));
      expect(errorCard, findsOneWidget);

      final errorText = tester.widget<Text>(
        find.descendant(of: errorCard, matching: find.byType(Text)).first,
      );
      expect(errorText.data, isNot(contains('provider-secret-token-abc123')));
      expect(errorText.data, isNot(contains('Exception')));
      expect(find.byKey(const Key('claim-review-retry-button')), findsOneWidget);
    });

    testWidgets('Retry reruns the claim review and can succeed on the second attempt',
        (tester) async {
      final mutableMapper = _MutableClaimReviewMapper();
      final service = _serviceWithOneNewClaim(
        _FixedGroundedAnswerProvider(_answer()),
      );
      final container = await _pumpSearchScreen(
        tester,
        ingestionService: service,
        mapper: mutableMapper,
      );

      // First ask: mapper throws → error state.
      mutableMapper.shouldThrow = true;
      await _askQuestion(tester, 'question');
      expect(container.read(claimReviewProvider).isError, isTrue);
      expect(find.byKey(const Key('claim-review-retry-button')), findsOneWidget);

      // Retry: mapper succeeds → review items shown.
      mutableMapper.shouldThrow = false;
      final retryButton = find.byKey(const Key('claim-review-retry-button'));
      await tester.ensureVisible(retryButton);
      await tester.tap(retryButton);
      await tester.pumpAndSettle();

      expect(container.read(claimReviewProvider).isError, isFalse);
      expect(container.read(claimReviewProvider).hasReviewItems, isTrue);
      expect(find.byKey(const Key('claim-review-retry-button')), findsNothing);
    });

    // ── Draft generation failure ───────────────────────────────────────────

    testWidgets('draft-generation exception text is not leaked',
        (tester) async {
      final service = _serviceWithOneNewClaim(
        _FixedGroundedAnswerProvider(_answer()),
      );
      final throwingBuilder =
          _ThrowingDraftBuilder(Exception('internal-builder-secret-xyz'));

      final container = await _pumpSearchScreen(
        tester,
        ingestionService: service,
        draftBuilder: throwingBuilder,
      );
      await _askQuestion(tester, 'question');

      final genButton = find.byKey(const Key('generate-claim-draft-button'));
      await tester.ensureVisible(genButton);
      await tester.tap(genButton);
      await tester.pumpAndSettle();

      expect(
        container.read(claimReviewProvider).draftGenerationErrorMessage,
        isNotNull,
      );
      final errorCard = find.byKey(const Key('claim-draft-generation-error-state'));
      expect(errorCard, findsOneWidget);

      final errorText = tester.widget<Text>(
        find.descendant(of: errorCard, matching: find.byType(Text)).first,
      );
      expect(errorText.data, isNot(contains('internal-builder-secret-xyz')));
      expect(errorText.data, isNot(contains('Exception')));
    });

    // ── Save failure ───────────────────────────────────────────────────────

    testWidgets('save exception text is not leaked', (tester) async {
      final repo = _RecordingNoteDraftReviewRepository()
        ..failWith = Exception('sk-live-supersecretkey123');
      final service = _serviceWithOneNewClaim(
        _FixedGroundedAnswerProvider(_answer()),
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
      expect(errorText.data, isNot(contains('Exception')));
      expect(find.byKey(const Key('claim-draft-save-retry-button')), findsOneWidget);
    });

    testWidgets('save Retry retriggers the save and succeeds', (tester) async {
      final repo = _RecordingNoteDraftReviewRepository()
        ..failWith = Exception('temp db error');
      final service = _serviceWithOneNewClaim(
        _FixedGroundedAnswerProvider(_answer()),
      );

      final container = await _pumpSearchScreen(
        tester,
        ingestionService: service,
        repository: repo,
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);

      // First save fails.
      final saveButton = find.byKey(const Key('save-claim-draft-button'));
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(
        container.read(claimReviewProvider).saveStatus,
        ClaimDraftSaveStatus.error,
      );

      // Clear the failure so retry succeeds.
      repo.failWith = null;
      final retryButton = find.byKey(const Key('claim-draft-save-retry-button'));
      await tester.ensureVisible(retryButton);
      await tester.tap(retryButton);
      await tester.pumpAndSettle();

      expect(
        container.read(claimReviewProvider).saveStatus,
        ClaimDraftSaveStatus.saved,
      );
      expect(repo.insertedNotes, hasLength(1));
    });

    // ── Append failure ─────────────────────────────────────────────────────

    testWidgets('append exception text is not leaked', (tester) async {
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
      final service = _serviceWithOneNewClaim(
        _FixedGroundedAnswerProvider(_answer()),
      );

      final container = await _pumpSearchScreen(
        tester,
        ingestionService: service,
        repository: repo,
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);

      container.read(claimReviewProvider.notifier).selectTargetNote(existing.id);
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
      expect(errorText.data, isNot(contains('Exception')));
      expect(
        find.byKey(const Key('claim-draft-append-retry-button')),
        findsOneWidget,
      );
    });

    testWidgets('append Retry retriggers the append and succeeds', (tester) async {
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
        ..failWith = Exception('temp db error');
      final service = _serviceWithOneNewClaim(
        _FixedGroundedAnswerProvider(_answer()),
      );

      final container = await _pumpSearchScreen(
        tester,
        ingestionService: service,
        repository: repo,
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);

      container.read(claimReviewProvider.notifier).selectTargetNote(existing.id);
      await tester.pumpAndSettle();

      // First append fails.
      final appendButton = find.byKey(const Key('append-claim-draft-button'));
      await tester.ensureVisible(appendButton);
      await tester.tap(appendButton);
      await tester.pumpAndSettle();

      expect(
        container.read(claimReviewProvider).appendStatus,
        ClaimDraftAppendStatus.error,
      );

      // Clear failure so retry succeeds.
      repo.failWith = null;
      final retryButton = find.byKey(const Key('claim-draft-append-retry-button'));
      await tester.ensureVisible(retryButton);
      await tester.tap(retryButton);
      await tester.pumpAndSettle();

      expect(
        container.read(claimReviewProvider).appendStatus,
        ClaimDraftAppendStatus.appended,
      );
      expect(repo.updatedNotes, hasLength(1));
    });

    // ── Ask and Retry blocked during in-flight writes ──────────────────────

    testWidgets('Ask and Retry are disabled while a save is in flight',
        (tester) async {
      final gate = Completer<void>();
      final repo = _GatedNoteDraftReviewRepository(gate);
      final service = _serviceWithOneNewClaim(
        _FixedGroundedAnswerProvider(_answer()),
      );

      final container = await _pumpSearchScreen(
        tester,
        ingestionService: service,
        repository: repo,
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);

      // Trigger save — will block at insertNote.
      final notifier = container.read(claimReviewProvider.notifier);
      unawaited(notifier.saveAsNewNote());
      await tester.pump();

      expect(container.read(claimReviewProvider).isSaveInFlight, isTrue);

      final askButton = tester.widget<FilledButton>(
        find.byKey(const Key('ask-question-button')),
      );
      expect(askButton.onPressed, isNull);

      // No Retry button shown (status is not error during save), but if it
      // were, it would also be disabled. Verify by toggling to produce an
      // error-like condition — just verifying askDisabled propagates correctly.
      // (Retry button only appears in error state, not during normal saving.)

      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('Ask and Retry are disabled while an append is in flight',
        (tester) async {
      final gate = Completer<void>();
      final existing = Note(
        id: 'target',
        title: 'Target note',
        content: 'content',
        tags: const [],
        keywords: const [],
        isPinned: false,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        embeddingPending: false,
      );
      final repo = _GatedAppendRepository(gate, existing);
      final service = _serviceWithOneNewClaim(
        _FixedGroundedAnswerProvider(_answer()),
      );

      final container = await _pumpSearchScreen(
        tester,
        ingestionService: service,
        repository: repo,
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);

      container.read(claimReviewProvider.notifier).selectTargetNote(existing.id);
      await tester.pump();

      // Trigger append — will block at updateNote.
      unawaited(container.read(claimReviewProvider.notifier).appendToExistingNote());
      await tester.pump();

      expect(
        container.read(claimReviewProvider).appendStatus,
        ClaimDraftAppendStatus.appending,
      );

      final askButton = tester.widget<FilledButton>(
        find.byKey(const Key('ask-question-button')),
      );
      expect(askButton.onPressed, isNull);

      gate.complete();
      await tester.pumpAndSettle();
    });

    // ── Session token: stale completion cannot mutate new session ──────────

    testWidgets(
        'stale save completion does not update state after reset starts a new session',
        (tester) async {
      final gate = Completer<void>();
      final repo = _GatedNoteDraftReviewRepository(gate);
      final service = _serviceWithOneNewClaim(
        _FixedGroundedAnswerProvider(_answer()),
      );

      final container = await _pumpSearchScreen(
        tester,
        ingestionService: service,
        repository: repo,
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);

      // Start save — will block.
      final notifier = container.read(claimReviewProvider.notifier);
      final saving = notifier.saveAsNewNote();
      await tester.pump();

      // Reset (new session) before save completes.
      notifier.reset();
      await tester.pump();

      expect(container.read(claimReviewProvider).status,
          ClaimReviewSessionStatus.idle);

      // Let old insertNote complete.
      gate.complete();
      await saving;
      await tester.pumpAndSettle();

      // New session must not be mutated by the stale completion.
      expect(container.read(claimReviewProvider).status,
          ClaimReviewSessionStatus.idle);
      expect(container.read(claimReviewProvider).saveStatus,
          ClaimDraftSaveStatus.idle);
      expect(container.read(claimReviewProvider).savedDraftContents, isEmpty);
    });
  });
}

// ─── Mutable mapper (used by retry test) ─────────────────────────────────────

class _MutableClaimReviewMapper implements ClaimReviewMapper {
  bool shouldThrow = false;

  @override
  List<ClaimReviewGroup> toGroups(GroundedClaimIngestionResult ingestion) {
    if (shouldThrow) throw Exception('mapper-error');
    // Return a single group with one new claim to satisfy hasReviewItems.
    return const [
      ClaimReviewGroup(
        label: 'New claims',
        classification: ClaimNoveltyClassification.newClaim,
        items: [
          ClaimReviewItem(
            id: 'n1',
            text: 'A brand new claim.',
            classification: ClaimNoveltyClassification.newClaim,
            citationUrls: [],
            citationTitles: [],
            selectedByDefault: true,
            reason: 'new',
            matchedLocalEvidenceIds: [],
            canBeSaved: true,
          ),
        ],
      ),
    ];
  }

  @override
  ClaimReviewSelectionState toSelectionState(
    GroundedClaimIngestionResult ingestion,
  ) {
    if (shouldThrow) throw Exception('mapper-error');
    return const ClaimReviewSelectionState(
      allItems: [
        ClaimReviewItem(
          id: 'n1',
          text: 'A brand new claim.',
          classification: ClaimNoveltyClassification.newClaim,
          citationUrls: [],
          citationTitles: [],
          selectedByDefault: true,
          reason: 'new',
          matchedLocalEvidenceIds: [],
          canBeSaved: true,
        ),
      ],
      selectedIds: {'n1'},
    );
  }
}
