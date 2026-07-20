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

class _AppendableNoteDraftReviewRepository
    implements NoteDraftReviewRepository {
  Note? existingNote;
  bool shouldFail = false;
  Completer<void>? updateGate;
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
    if (updateGate != null) {
      await updateGate!.future;
    }
    if (shouldFail) {
      throw Exception('update failed');
    }
    updatedNotes.add(note);
    existingNote = note;
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

// Supports both insertNote (save flow) and getNoteById/updateNote (append flow).
class _SaveableAndAppendableRepository implements NoteDraftReviewRepository {
  Note? existingNote;
  final List<Note> insertedNotes = [];
  final List<Note> updatedNotes = [];

  @override
  Future<Note?> getNoteById(String id) async {
    final note = existingNote;
    if (note != null && note.id == id) return note;
    return null;
  }

  @override
  Future<Note> insertNote({required String title, required String content}) async {
    final note = Note(
      id: 'saved-note-${insertedNotes.length}',
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
    updatedNotes.add(note);
    existingNote = note;
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

Note _existingNote({String content = 'Old content here.'}) => Note(
      id: 'existing-note',
      title: 'Existing note',
      content: content,
      tags: const [],
      keywords: const [],
      isPinned: false,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      embeddingPending: false,
    );

Future<ProviderContainer> _pumpSearchScreen(
  WidgetTester tester, {
  required GroundedAnswerIngestionService ingestionService,
  required NoteDraftReviewRepository repository,
  List<Note> availableNotes = const [],
}) async {
  final container = ProviderContainer(
    overrides: [
      knowledgeIngestionServiceProvider.overrideWith(
        (ref) async => _FakeKnowledgeIngestionService(),
      ),
      noteDraftReviewRepositoryProvider.overrideWithValue(repository),
      groundedAnswerIngestionServiceProvider.overrideWithValue(ingestionService),
      allNotesProvider.overrideWithValue(availableNotes),
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

Future<void> _tapAppend(WidgetTester tester) async {
  final button = find.byKey(const Key('append-claim-draft-button'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  group('SearchScreen claim draft append to existing note', () {
    testWidgets('append preserves old note content and adds the draft',
        (tester) async {
      final existing = _existingNote(content: 'Old content here.');
      final repo = _AppendableNoteDraftReviewRepository()
        ..existingNote = existing;
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

      final container = await _pumpSearchScreen(
        tester,
        ingestionService: service,
        repository: repo,
        availableNotes: [existing],
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);

      final generatedMarkdown = container.read(claimReviewProvider).draft!.markdownContent;
      container.read(claimReviewProvider.notifier).selectTargetNote(existing.id);
      await _tapAppend(tester);

      expect(repo.updatedNotes, hasLength(1));
      final updatedContent = repo.updatedNotes.single.content;
      expect(updatedContent, contains('Old content here.'));
      expect(updatedContent, contains(generatedMarkdown.trim()));
    });

    testWidgets('append inserts a separator between old and new content',
        (tester) async {
      final existing = _existingNote(content: 'Old content here.');
      final repo = _AppendableNoteDraftReviewRepository()
        ..existingNote = existing;
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

      final container = await _pumpSearchScreen(
        tester,
        ingestionService: service,
        repository: repo,
        availableNotes: [existing],
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);
      container.read(claimReviewProvider.notifier).selectTargetNote(existing.id);
      await _tapAppend(tester);

      final updatedContent = repo.updatedNotes.single.content;
      final oldIndex = updatedContent.indexOf('Old content here.');
      final separatorIndex = updatedContent.indexOf('---');
      final draftIndex =
          updatedContent.indexOf(container.read(claimReviewProvider).draft!.markdownContent.trim());

      expect(oldIndex, greaterThanOrEqualTo(0));
      expect(separatorIndex, greaterThan(oldIndex));
      expect(draftIndex, greaterThan(separatorIndex));
    });

    testWidgets('repeated append calls do not duplicate the content',
        (tester) async {
      final existing = _existingNote(content: 'Old content here.');
      final repo = _AppendableNoteDraftReviewRepository()
        ..existingNote = existing;
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

      final container = await _pumpSearchScreen(
        tester,
        ingestionService: service,
        repository: repo,
        availableNotes: [existing],
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);
      container.read(claimReviewProvider.notifier).selectTargetNote(existing.id);
      await _tapAppend(tester);

      expect(repo.updatedNotes, hasLength(1));

      // The button should now be disabled (or absent), so tapping again
      // (directly through the notifier, since the widget is disabled) must
      // not append the same content a second time.
      await container.read(claimReviewProvider.notifier).appendToExistingNote();

      expect(repo.updatedNotes, hasLength(1));
    });

    testWidgets(
        'selecting a different target note allows appending the same draft again',
        (tester) async {
      final existingA = _existingNote(content: 'Note A content.');
      final existingB = Note(
        id: 'existing-note-b',
        title: 'Existing note B',
        content: 'Note B content.',
        tags: const [],
        keywords: const [],
        isPinned: false,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        embeddingPending: false,
      );
      final repo = _AppendableNoteDraftReviewRepository()
        ..existingNote = existingA;
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

      final container = await _pumpSearchScreen(
        tester,
        ingestionService: service,
        repository: repo,
        availableNotes: [existingA, existingB],
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);
      final notifier = container.read(claimReviewProvider.notifier);
      notifier.selectTargetNote(existingA.id);
      await _tapAppend(tester);

      expect(repo.updatedNotes, hasLength(1));
      expect(
        container.read(claimReviewProvider).appendStatus,
        ClaimDraftAppendStatus.appended,
      );

      // Repository's getNoteById only knows about one note at a time in
      // this fake; point it at note B before switching the target.
      repo.existingNote = existingB;
      notifier.selectTargetNote(existingB.id);
      await tester.pump();
      expect(
        container.read(claimReviewProvider).appendStatus,
        ClaimDraftAppendStatus.idle,
      );
      await _tapAppend(tester);

      expect(repo.updatedNotes, hasLength(2));
      expect(repo.updatedNotes.last.content, contains('Note B content.'));
    });

    testWidgets(
        're-selecting the same target note after appending does not re-enable append',
        (tester) async {
      final existing = _existingNote(content: 'Old content here.');
      final repo = _AppendableNoteDraftReviewRepository()
        ..existingNote = existing;
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

      final container = await _pumpSearchScreen(
        tester,
        ingestionService: service,
        repository: repo,
        availableNotes: [existing],
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);
      final notifier = container.read(claimReviewProvider.notifier);
      notifier.selectTargetNote(existing.id);
      await _tapAppend(tester);

      expect(repo.updatedNotes, hasLength(1));

      // Re-picking the exact same note from the dropdown (which can fire
      // onChanged even for an unchanged value) must not undo the
      // already-appended guard.
      notifier.selectTargetNote(existing.id);
      await tester.pump();
      expect(
        container.read(claimReviewProvider).appendStatus,
        ClaimDraftAppendStatus.appended,
      );

      await notifier.appendToExistingNote();

      expect(repo.updatedNotes, hasLength(1));
    });

    testWidgets(
        'regenerating an unchanged draft after appending keeps it marked appended',
        (tester) async {
      final existing = _existingNote(content: 'Old content here.');
      final repo = _AppendableNoteDraftReviewRepository()
        ..existingNote = existing;
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

      final container = await _pumpSearchScreen(
        tester,
        ingestionService: service,
        repository: repo,
        availableNotes: [existing],
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);
      final notifier = container.read(claimReviewProvider.notifier);
      notifier.selectTargetNote(existing.id);
      await _tapAppend(tester);

      expect(repo.updatedNotes, hasLength(1));

      // Tap "Generate draft" again with the same selection and the same
      // target still picked. The regenerated markdown is identical to what
      // was just appended, so it must stay reported as appended rather than
      // re-enabling the append button.
      await _generateDraft(tester);

      expect(
        container.read(claimReviewProvider).appendStatus,
        ClaimDraftAppendStatus.appended,
      );
      expect(container.read(claimReviewProvider).isDraftAlreadyAppended, isTrue);

      await notifier.appendToExistingNote();

      expect(repo.updatedNotes, hasLength(1));
    });

    testWidgets(
        'switching away and back to a previously appended target does not allow a duplicate',
        (tester) async {
      final existingA = _existingNote(content: 'Note A content.');
      final existingB = Note(
        id: 'existing-note-b',
        title: 'Existing note B',
        content: 'Note B content.',
        tags: const [],
        keywords: const [],
        isPinned: false,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        embeddingPending: false,
      );
      final repo = _AppendableNoteDraftReviewRepository()
        ..existingNote = existingA;
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

      final container = await _pumpSearchScreen(
        tester,
        ingestionService: service,
        repository: repo,
        availableNotes: [existingA, existingB],
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);
      final notifier = container.read(claimReviewProvider.notifier);
      notifier.selectTargetNote(existingA.id);
      await _tapAppend(tester);

      expect(repo.updatedNotes, hasLength(1));

      // Switch to note B (a legitimately different, unappended target)...
      repo.existingNote = existingB;
      notifier.selectTargetNote(existingB.id);
      await tester.pump();
      expect(
        container.read(claimReviewProvider).appendStatus,
        ClaimDraftAppendStatus.idle,
      );

      // ...then switch back to note A, which already has this exact draft
      // appended. That must be recognized as already done, not a fresh
      // target to append to again.
      notifier.selectTargetNote(existingA.id);
      await tester.pump();

      expect(
        container.read(claimReviewProvider).appendStatus,
        ClaimDraftAppendStatus.appended,
      );

      await notifier.appendToExistingNote();

      expect(repo.updatedNotes, hasLength(1));
    });

    testWidgets(
        'appending the same draft to two different notes remembers both as already appended',
        (tester) async {
      final existingA = _existingNote(content: 'Note A content.');
      final existingB = Note(
        id: 'existing-note-b',
        title: 'Existing note B',
        content: 'Note B content.',
        tags: const [],
        keywords: const [],
        isPinned: false,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        embeddingPending: false,
      );
      final repo = _AppendableNoteDraftReviewRepository()
        ..existingNote = existingA;
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

      final container = await _pumpSearchScreen(
        tester,
        ingestionService: service,
        repository: repo,
        availableNotes: [existingA, existingB],
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);
      final notifier = container.read(claimReviewProvider.notifier);

      // Append the same draft to A, then to B.
      notifier.selectTargetNote(existingA.id);
      await _tapAppend(tester);
      expect(repo.updatedNotes, hasLength(1));

      repo.existingNote = existingB;
      notifier.selectTargetNote(existingB.id);
      await tester.pump();
      await _tapAppend(tester);
      expect(repo.updatedNotes, hasLength(2));

      // Selecting A again must recognize it as already appended too (not
      // just the most recently appended note), and refuse a repeat append.
      repo.existingNote = existingA;
      notifier.selectTargetNote(existingA.id);
      await tester.pump();

      expect(
        container.read(claimReviewProvider).appendStatus,
        ClaimDraftAppendStatus.appended,
      );
      expect(container.read(claimReviewProvider).isDraftAlreadyAppended, isTrue);

      await notifier.appendToExistingNote();

      expect(repo.updatedNotes, hasLength(2));
    });

    testWidgets(
        'selecting a target while an append is in flight does not start a second append',
        (tester) async {
      final existingA = _existingNote(content: 'Note A content.');
      final existingB = Note(
        id: 'existing-note-b',
        title: 'Existing note B',
        content: 'Note B content.',
        tags: const [],
        keywords: const [],
        isPinned: false,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        embeddingPending: false,
      );
      final gate = Completer<void>();
      final repo = _AppendableNoteDraftReviewRepository()
        ..existingNote = existingA
        ..updateGate = gate;
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

      final container = await _pumpSearchScreen(
        tester,
        ingestionService: service,
        repository: repo,
        availableNotes: [existingA, existingB],
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);
      final notifier = container.read(claimReviewProvider.notifier);
      notifier.selectTargetNote(existingA.id);

      // Start the append but don't let updateNote resolve yet.
      final appending = notifier.appendToExistingNote();
      await tester.pump();
      expect(
        container.read(claimReviewProvider).appendStatus,
        ClaimDraftAppendStatus.appending,
      );

      // Attempting to change the target (and a second append call) while
      // the first is still in flight must not be allowed through.
      notifier.selectTargetNote(existingB.id);
      expect(
        container.read(claimReviewProvider).targetNoteId,
        existingA.id,
      );
      await notifier.appendToExistingNote();

      gate.complete();
      await appending;

      expect(repo.updatedNotes, hasLength(1));
    });

    testWidgets(
        'returning to a draft content appended earlier is still recognized after appending a different draft',
        (tester) async {
      final existing = _existingNote(content: 'Old content here.');
      final repo = _AppendableNoteDraftReviewRepository()
        ..existingNote = existing;
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
          _claim('n2', 'Another brand new claim.'),
        ],
        results: [
          _result('n1', 'A brand new claim.', ClaimNoveltyClassification.newClaim),
          _result(
            'n2',
            'Another brand new claim.',
            ClaimNoveltyClassification.newClaim,
          ),
        ],
      );

      final container = await _pumpSearchScreen(
        tester,
        ingestionService: service,
        repository: repo,
        availableNotes: [existing],
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);
      final notifier = container.read(claimReviewProvider.notifier);
      final draftX = container.read(claimReviewProvider).draft!.markdownContent;
      notifier.selectTargetNote(existing.id);
      await _tapAppend(tester);

      expect(repo.updatedNotes, hasLength(1));

      // Deselect one claim to produce a genuinely different draft (Y), and
      // append that too.
      notifier.toggle('n2');
      await tester.pumpAndSettle();
      await _generateDraft(tester);
      final draftY = container.read(claimReviewProvider).draft!.markdownContent;
      expect(draftY, isNot(equals(draftX)));
      expect(
        container.read(claimReviewProvider).appendStatus,
        ClaimDraftAppendStatus.idle,
      );
      await _tapAppend(tester);

      expect(repo.updatedNotes, hasLength(2));

      // Reselect the claim to regenerate the original draft X. Even though
      // Y was the most recently appended content, X/existing was appended
      // earlier and must still be recognized as already done.
      notifier.toggle('n2');
      await tester.pumpAndSettle();
      await _generateDraft(tester);

      expect(
        container.read(claimReviewProvider).draft!.markdownContent,
        draftX,
      );
      expect(
        container.read(claimReviewProvider).appendStatus,
        ClaimDraftAppendStatus.appended,
      );
      expect(container.read(claimReviewProvider).isDraftAlreadyAppended, isTrue);

      await notifier.appendToExistingNote();

      expect(repo.updatedNotes, hasLength(2));
    });

    testWidgets(
        'target note disappearing from the list does not crash the dropdown',
        (tester) async {
      final existingA = _existingNote(content: 'Note A content.');
      final existingB = Note(
        id: 'existing-note-b',
        title: 'Existing note B',
        content: 'Note B content.',
        tags: const [],
        keywords: const [],
        isPinned: false,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        embeddingPending: false,
      );
      final repo = _AppendableNoteDraftReviewRepository()
        ..existingNote = existingA;
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

      final container = await _pumpSearchScreen(
        tester,
        ingestionService: service,
        repository: repo,
        availableNotes: [existingA, existingB],
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);
      container.read(claimReviewProvider.notifier).selectTargetNote(existingA.id);
      await tester.pump();

      // Note A (the selected target) disappears from the available list
      // (e.g. deleted elsewhere) while note B remains, so the dropdown's
      // items are non-empty but no longer include the stale selected value.
      // Rebuilding it must fall back to no selection instead of throwing.
      container.updateOverrides([
        knowledgeIngestionServiceProvider.overrideWith(
          (ref) async => _FakeKnowledgeIngestionService(),
        ),
        noteDraftReviewRepositoryProvider.overrideWithValue(repo),
        groundedAnswerIngestionServiceProvider.overrideWithValue(service),
        allNotesProvider.overrideWithValue([existingB]),
        recentNotesProvider.overrideWithValue(const <Note>[]),
        refreshNotesProvider.overrideWithValue(() async {}),
      ]);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('no-save draft does not modify a note', (tester) async {
      final existing = _existingNote();
      final repo = _AppendableNoteDraftReviewRepository()
        ..existingNote = existing;
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

      final container = await _pumpSearchScreen(
        tester,
        ingestionService: service,
        repository: repo,
        availableNotes: [existing],
      );
      await _askQuestion(tester, 'question');

      // Deselect the only default-selected claim so the draft is empty.
      container.read(claimReviewProvider.notifier).toggle('n1');
      await tester.pumpAndSettle();
      await _generateDraft(tester);

      expect(container.read(claimReviewProvider).draft!.shouldSave, isFalse);

      // No append button is rendered for a no-save draft; calling the
      // notifier directly (as a defensive check) must still refuse to
      // modify anything.
      expect(find.byKey(const Key('append-claim-draft-button')), findsNothing);
      container.read(claimReviewProvider.notifier).selectTargetNote(existing.id);
      await container.read(claimReviewProvider.notifier).appendToExistingNote();

      expect(repo.updatedNotes, isEmpty);
      expect(
        container.read(claimReviewProvider).appendStatus,
        ClaimDraftAppendStatus.idle,
      );
    });

    testWidgets('append failure is shown and does not mark the draft appended',
        (tester) async {
      final existing = _existingNote();
      final repo = _AppendableNoteDraftReviewRepository()
        ..existingNote = existing
        ..shouldFail = true;
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

      final container = await _pumpSearchScreen(
        tester,
        ingestionService: service,
        repository: repo,
        availableNotes: [existing],
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);
      container.read(claimReviewProvider.notifier).selectTargetNote(existing.id);
      await _tapAppend(tester);

      expect(repo.updatedNotes, isEmpty);
      expect(
        container.read(claimReviewProvider).appendStatus,
        ClaimDraftAppendStatus.error,
      );
      expect(
        find.byKey(const Key('claim-draft-append-error-message')),
        findsOneWidget,
      );
    });

    testWidgets('missing target note shows an error without appending',
        (tester) async {
      final existing = _existingNote();
      final repo = _AppendableNoteDraftReviewRepository()
        ..existingNote = existing;
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

      final container = await _pumpSearchScreen(
        tester,
        ingestionService: service,
        repository: repo,
        availableNotes: [existing],
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);

      // No target note selected before tapping append.
      await _tapAppend(tester);

      expect(repo.updatedNotes, isEmpty);
      expect(
        container.read(claimReviewProvider).appendStatus,
        ClaimDraftAppendStatus.error,
      );
    });

    testWidgets(
        'toggling a claim while an append is in flight does not reset appendStatus to idle',
        (tester) async {
      final gate = Completer<void>();
      final existing = _existingNote(content: 'Old content here.');
      final repo = _AppendableNoteDraftReviewRepository()
        ..existingNote = existing
        ..updateGate = gate;
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

      final container = await _pumpSearchScreen(
        tester,
        ingestionService: service,
        repository: repo,
        availableNotes: [existing],
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);
      final notifier = container.read(claimReviewProvider.notifier);
      notifier.selectTargetNote(existing.id);

      // Start the append but hold updateNote so it stays in flight.
      final appending = notifier.appendToExistingNote();
      await tester.pump();
      expect(
        container.read(claimReviewProvider).appendStatus,
        ClaimDraftAppendStatus.appending,
      );

      // Toggling a claim clears the draft but must NOT reset appendStatus to
      // idle — doing so would allow a second concurrent append to start while
      // the first write is still in progress.
      notifier.toggle('n1');
      await tester.pump();
      expect(
        container.read(claimReviewProvider).appendStatus,
        ClaimDraftAppendStatus.appending,
      );

      // Completing the write must release the lock (→ idle) since the draft
      // changed mid-append, and record the append in history.
      gate.complete();
      await appending;
      await tester.pump();

      expect(repo.updatedNotes, hasLength(1));
      expect(
        container.read(claimReviewProvider).appendStatus,
        ClaimDraftAppendStatus.idle,
      );
      // The write succeeded, so the note ID is recorded in appendedTargets
      // even though the UI draft was cleared by the toggle.
      final appendedTargets =
          container.read(claimReviewProvider).appendedTargetsByContent;
      expect(
        appendedTargets.values.any((ids) => ids.contains(existing.id)),
        isTrue,
      );
    });

    testWidgets(
        'generating a new draft while an append is in flight does not reset appendStatus to idle',
        (tester) async {
      final gate = Completer<void>();
      final existing = _existingNote(content: 'Old content here.');
      final repo = _AppendableNoteDraftReviewRepository()
        ..existingNote = existing
        ..updateGate = gate;
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

      final container = await _pumpSearchScreen(
        tester,
        ingestionService: service,
        repository: repo,
        availableNotes: [existing],
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);
      final notifier = container.read(claimReviewProvider.notifier);
      notifier.selectTargetNote(existing.id);

      // Start the append but hold updateNote so it stays in flight.
      final appending = notifier.appendToExistingNote();
      await tester.pump();
      expect(
        container.read(claimReviewProvider).appendStatus,
        ClaimDraftAppendStatus.appending,
      );

      // Toggle a claim so the selection changes — this also clears the draft
      // but must NOT reset appendStatus (toggle fix already covers this).
      notifier.toggle('n1');
      await tester.pump();
      expect(
        container.read(claimReviewProvider).appendStatus,
        ClaimDraftAppendStatus.appending,
      );

      // Regenerating with a changed selection produces a different draft.
      // generateDraft() must NOT reset appendStatus to idle while an append
      // is in flight — doing so re-enables the append button and could start
      // a second concurrent write against the same target note.
      await _generateDraft(tester);
      expect(
        container.read(claimReviewProvider).appendStatus,
        ClaimDraftAppendStatus.appending,
      );

      // Completing the in-flight write releases the lock (→ idle) since the
      // draft changed mid-append, and records the target in history.
      gate.complete();
      await appending;
      await tester.pump();

      expect(repo.updatedNotes, hasLength(1));
      expect(
        container.read(claimReviewProvider).appendStatus,
        ClaimDraftAppendStatus.idle,
      );
    });

    testWidgets(
        'append button is disabled and append is a no-op after saving as new note',
        (tester) async {
      final existing = _existingNote(content: 'Old content here.');
      final repo = _SaveableAndAppendableRepository()..existingNote = existing;
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

      final container = await _pumpSearchScreen(
        tester,
        ingestionService: service,
        repository: repo,
        availableNotes: [existing],
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);
      final notifier = container.read(claimReviewProvider.notifier);
      notifier.selectTargetNote(existing.id);

      // Save the draft as a new note first.
      await notifier.saveAsNewNote();
      await tester.pump();

      expect(
        container.read(claimReviewProvider).saveStatus,
        ClaimDraftSaveStatus.saved,
        reason: 'save must have succeeded before the append guard is meaningful',
      );

      // The append button must be disabled — isDraftAlreadySaved blocks it.
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('append-claim-draft-button')),
      );
      expect(button.onPressed, isNull);

      // Calling appendToExistingNote directly must also be a no-op.
      await notifier.appendToExistingNote();
      await tester.pump();

      expect(
        repo.updatedNotes,
        isEmpty,
        reason: 'provider guard must block append when draft is already saved',
      );
      expect(
        container.read(claimReviewProvider).appendStatus,
        ClaimDraftAppendStatus.idle,
      );
    });
  });
}
