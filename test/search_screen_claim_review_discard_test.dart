import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/claim_deduplication_result.dart';
import 'package:grepink/models/claim_review_session_state.dart';
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

class _RecordingNoteDraftReviewRepository implements NoteDraftReviewRepository {
  final List<Note> insertedNotes = [];

  @override
  Future<Note?> getNoteById(String id) async => null;

  @override
  Future<Note> insertNote({required String title, required String content}) async {
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
  Future<void> updateNote(Note note) async {}
}

class _GatedNoteDraftReviewRepository implements NoteDraftReviewRepository {
  final List<Note> insertedNotes = [];
  final Completer<void> gate;

  _GatedNoteDraftReviewRepository(this.gate);

  @override
  Future<Note?> getNoteById(String id) async => null;

  @override
  Future<Note> insertNote({required String title, required String content}) async {
    await gate.future;
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
  Future<void> updateNote(Note note) async {}
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
  ) async =>
      results;
}

class _EmptyLocalEvidenceRetriever implements LocalEvidenceRetriever {
  @override
  Future<List<EvidenceItem>> retrieve(String question) async => const [];
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
  required NoteDraftReviewRepository repository,
}) async {
  final container = ProviderContainer(
    overrides: [
      knowledgeIngestionServiceProvider.overrideWith(
        (ref) async => _FakeKnowledgeIngestionService(),
      ),
      noteDraftReviewRepositoryProvider.overrideWithValue(repository),
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

Future<void> _tapSave(WidgetTester tester) async {
  final button = find.byKey(const Key('save-claim-draft-button'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _tapDiscard(WidgetTester tester) async {
  final button = find.byKey(const Key('discard-claim-review-button'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

GroundedAnswerIngestionService _serviceWithOneNewClaim(
  GroundedAnswerProvider provider,
) =>
    _buildIngestionService(
      provider: provider,
      claims: [_claim('n1', 'A brand new claim.')],
      results: [
        _result('n1', 'A brand new claim.', ClaimNoveltyClassification.newClaim),
      ],
    );

void main() {
  group('SearchScreen claim review discard', () {
    testWidgets('discard clears grouped review results', (tester) async {
      final repo = _RecordingNoteDraftReviewRepository();
      final provider = _FixedGroundedAnswerProvider(
        GroundedAnswer(
          question: 'q',
          answerText: 'answer',
          citations: const [],
          providerName: 'test-provider',
          generatedAt: DateTime(2026, 1, 1),
        ),
      );
      final service = _serviceWithOneNewClaim(provider);

      final container = await _pumpSearchScreen(
        tester,
        ingestionService: service,
        repository: repo,
      );
      await _askQuestion(tester, 'question');

      expect(container.read(claimReviewProvider).hasReviewItems, isTrue);

      await _tapDiscard(tester);

      expect(container.read(claimReviewProvider).hasReviewItems, isFalse);
      expect(container.read(claimReviewProvider).groups, isEmpty);
    });

    testWidgets('discard clears the generated draft', (tester) async {
      final repo = _RecordingNoteDraftReviewRepository();
      final provider = _FixedGroundedAnswerProvider(
        GroundedAnswer(
          question: 'q',
          answerText: 'answer',
          citations: const [],
          providerName: 'test-provider',
          generatedAt: DateTime(2026, 1, 1),
        ),
      );
      final service = _serviceWithOneNewClaim(provider);

      final container = await _pumpSearchScreen(
        tester,
        ingestionService: service,
        repository: repo,
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);

      expect(container.read(claimReviewProvider).draft, isNotNull);

      await _tapDiscard(tester);

      expect(container.read(claimReviewProvider).draft, isNull);
      expect(find.byKey(const Key('claim-draft-preview-panel')), findsNothing);
    });

    testWidgets('discard clears selected claim IDs', (tester) async {
      final repo = _RecordingNoteDraftReviewRepository();
      final provider = _FixedGroundedAnswerProvider(
        GroundedAnswer(
          question: 'q',
          answerText: 'answer',
          citations: const [],
          providerName: 'test-provider',
          generatedAt: DateTime(2026, 1, 1),
        ),
      );
      final service = _serviceWithOneNewClaim(provider);

      final container = await _pumpSearchScreen(
        tester,
        ingestionService: service,
        repository: repo,
      );
      await _askQuestion(tester, 'question');

      expect(
        container.read(claimReviewProvider).selection!.selectedIds,
        isNotEmpty,
      );

      await _tapDiscard(tester);

      expect(container.read(claimReviewProvider).selection, isNull);
    });

    testWidgets('discard does not delete existing notes', (tester) async {
      final repo = _RecordingNoteDraftReviewRepository();
      final provider = _FixedGroundedAnswerProvider(
        GroundedAnswer(
          question: 'q',
          answerText: 'answer',
          citations: const [],
          providerName: 'test-provider',
          generatedAt: DateTime(2026, 1, 1),
        ),
      );
      final service = _serviceWithOneNewClaim(provider);

      await _pumpSearchScreen(
        tester,
        ingestionService: service,
        repository: repo,
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);
      await _tapSave(tester);

      expect(repo.insertedNotes, hasLength(1));

      await _tapDiscard(tester);

      expect(repo.insertedNotes, hasLength(1));
    });

    testWidgets('discard after a successful save does not undo the saved note',
        (tester) async {
      final repo = _RecordingNoteDraftReviewRepository();
      final provider = _FixedGroundedAnswerProvider(
        GroundedAnswer(
          question: 'q',
          answerText: 'answer',
          citations: const [],
          providerName: 'test-provider',
          generatedAt: DateTime(2026, 1, 1),
        ),
      );
      final service = _serviceWithOneNewClaim(provider);

      final container = await _pumpSearchScreen(
        tester,
        ingestionService: service,
        repository: repo,
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);
      await _tapSave(tester);

      expect(repo.insertedNotes, hasLength(1));
      final savedNote = repo.insertedNotes.single;

      await _tapDiscard(tester);

      // The saved note is untouched: same id and content, still the only
      // note the repository knows about. Discard only clears UI state.
      expect(repo.insertedNotes, hasLength(1));
      expect(repo.insertedNotes.single.id, savedNote.id);
      expect(repo.insertedNotes.single.content, savedNote.content);
      expect(container.read(claimReviewProvider).draft, isNull);
      expect(
        container.read(claimReviewProvider).saveStatus,
        ClaimDraftSaveStatus.idle,
      );
    });

    testWidgets('discard button is disabled while a save is in flight',
        (tester) async {
      final gate = Completer<void>();
      final repo = _GatedNoteDraftReviewRepository(gate);
      final provider = _FixedGroundedAnswerProvider(
        GroundedAnswer(
          question: 'q',
          answerText: 'answer',
          citations: const [],
          providerName: 'test-provider',
          generatedAt: DateTime(2026, 1, 1),
        ),
      );
      final service = _serviceWithOneNewClaim(provider);

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
      await tester.pump();

      expect(
        container.read(claimReviewProvider).saveStatus,
        ClaimDraftSaveStatus.saving,
      );

      final discardButton = tester.widget<TextButton>(
        find.byKey(const Key('discard-claim-review-button')),
      );
      expect(discardButton.onPressed, isNull);

      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('discard button is not shown when there is nothing to discard',
        (tester) async {
      final repo = _RecordingNoteDraftReviewRepository();
      final provider = _FixedGroundedAnswerProvider(
        GroundedAnswer(
          question: 'q',
          answerText: 'answer',
          citations: const [],
          providerName: 'test-provider',
          generatedAt: DateTime(2026, 1, 1),
        ),
      );
      final service = _serviceWithOneNewClaim(provider);

      await _pumpSearchScreen(
        tester,
        ingestionService: service,
        repository: repo,
      );

      expect(find.byKey(const Key('discard-claim-review-button')), findsNothing);
    });
  });
}
