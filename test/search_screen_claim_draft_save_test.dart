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
  bool shouldFail = false;
  Completer<void>? insertGate;

  @override
  Future<Note?> getNoteById(String id) async => null;

  @override
  Future<Note> insertNote({required String title, required String content}) async {
    if (insertGate != null) {
      await insertGate!.future;
    }
    if (shouldFail) {
      throw Exception('insert failed');
    }
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

void main() {
  group('SearchScreen claim draft save as new note', () {
    testWidgets('save action creates one new note with the generated markdown',
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
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);

      final draft = container.read(claimReviewProvider).draft!;
      await _tapSave(tester);

      expect(repo.insertedNotes, hasLength(1));
      expect(repo.insertedNotes.first.content, draft.markdownContent);
      expect(
        container.read(claimReviewProvider).saveStatus,
        ClaimDraftSaveStatus.saved,
      );
      expect(find.text('Saved as a new note.'), findsOneWidget);
    });

    testWidgets('no-save draft does not create a note', (tester) async {
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
      );
      await _askQuestion(tester, 'question');

      // Deselect the only default-selected claim so the draft is empty.
      container.read(claimReviewProvider.notifier).toggle('n1');
      await tester.pumpAndSettle();
      await _generateDraft(tester);

      expect(container.read(claimReviewProvider).draft!.shouldSave, isFalse);

      // No save button is rendered for a no-save draft; calling the notifier
      // directly (as a defensive check) must still refuse to persist.
      expect(find.byKey(const Key('save-claim-draft-button')), findsNothing);
      await container.read(claimReviewProvider.notifier).saveAsNewNote();

      expect(repo.insertedNotes, isEmpty);
      expect(
        container.read(claimReviewProvider).saveStatus,
        ClaimDraftSaveStatus.idle,
      );
    });

    testWidgets('repeated clicks do not duplicate the note after success',
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
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);
      await _tapSave(tester);

      expect(repo.insertedNotes, hasLength(1));

      // The button should now be disabled (or absent), so tapping again
      // (directly through the notifier, since the widget is disabled) must
      // not create a second note.
      await container.read(claimReviewProvider.notifier).saveAsNewNote();

      expect(repo.insertedNotes, hasLength(1));
    });

    testWidgets(
        'regenerating an unchanged draft after saving keeps it marked saved',
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
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);
      await _tapSave(tester);

      expect(repo.insertedNotes, hasLength(1));

      // Tap "Generate draft" again with the same selection. The regenerated
      // markdown is identical to what was just saved, so it must stay
      // reported as saved rather than re-enabling the save button.
      await _generateDraft(tester);

      expect(
        container.read(claimReviewProvider).saveStatus,
        ClaimDraftSaveStatus.saved,
      );
      expect(container.read(claimReviewProvider).isDraftAlreadySaved, isTrue);

      await container.read(claimReviewProvider.notifier).saveAsNewNote();

      expect(repo.insertedNotes, hasLength(1));
    });

    testWidgets('overlapping save calls before the first completes only save once',
        (tester) async {
      final gate = Completer<void>();
      final repo = _RecordingNoteDraftReviewRepository()..insertGate = gate;
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
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);

      final notifier = container.read(claimReviewProvider.notifier);
      // Fire two saves back to back, before the first insertNote resolves.
      final first = notifier.saveAsNewNote();
      final second = notifier.saveAsNewNote();
      gate.complete();
      await Future.wait([first, second]);

      expect(repo.insertedNotes, hasLength(1));
    });

    testWidgets(
        'regenerating the same selection while saving still records the save on completion',
        (tester) async {
      final gate = Completer<void>();
      final repo = _RecordingNoteDraftReviewRepository()..insertGate = gate;
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
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);

      final notifier = container.read(claimReviewProvider.notifier);
      final saving = notifier.saveAsNewNote();

      // Regenerate with the exact same selection while the save is still
      // in flight. saveStatus must stay saving (not reset to idle) so the
      // Save button cannot be tapped again before the insert completes.
      notifier.generateDraft();
      expect(
        container.read(claimReviewProvider).saveStatus,
        ClaimDraftSaveStatus.saving,
      );

      gate.complete();
      await saving;

      // The content that was actually inserted matches the regenerated
      // draft, so it must end up recorded as saved, not left looking
      // unsaved (which would let a repeat tap insert a duplicate note).
      expect(repo.insertedNotes, hasLength(1));
      expect(
        container.read(claimReviewProvider).saveStatus,
        ClaimDraftSaveStatus.saved,
      );
      expect(container.read(claimReviewProvider).isDraftAlreadySaved, isTrue);

      await notifier.saveAsNewNote();

      expect(repo.insertedNotes, hasLength(1));
    });

    testWidgets(
        'a save that resolves after the draft changed does not mark the new draft saved',
        (tester) async {
      final gate = Completer<void>();
      final repo = _RecordingNoteDraftReviewRepository()..insertGate = gate;
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
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);

      final notifier = container.read(claimReviewProvider.notifier);
      final saving = notifier.saveAsNewNote();

      // The draft changes (e.g. the user toggles a claim) while the save
      // from the old draft is still in flight.
      notifier.toggle('n1');
      expect(container.read(claimReviewProvider).draft, isNull);
      expect(
        container.read(claimReviewProvider).saveStatus,
        ClaimDraftSaveStatus.idle,
      );

      gate.complete();
      await saving;

      // The old draft still got persisted (the insert had already started),
      // but the now-current (cleared) draft must not be reported as saved.
      expect(repo.insertedNotes, hasLength(1));
      expect(container.read(claimReviewProvider).draft, isNull);
      expect(
        container.read(claimReviewProvider).saveStatus,
        ClaimDraftSaveStatus.idle,
      );
    });

    testWidgets(
        'returning to draft A while its save is in flight blocks a second save',
        (tester) async {
      final gate = Completer<void>();
      final repo = _RecordingNoteDraftReviewRepository()..insertGate = gate;
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
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);

      final notifier = container.read(claimReviewProvider.notifier);
      final saving = notifier.saveAsNewNote();

      // Toggle away and back — this resets saveStatus to idle and clears the
      // draft, but the first insertNote is still in flight.
      notifier.toggle('n1');
      notifier.toggle('n1');

      // Regenerate the same draft while the save is still pending.
      notifier.generateDraft();

      // The save button must appear disabled (saveStatus == saving) because
      // the content is still in pendingDraftContents.
      expect(
        container.read(claimReviewProvider).saveStatus,
        ClaimDraftSaveStatus.saving,
      );

      // A second saveAsNewNote must be blocked by the pending-content guard.
      await notifier.saveAsNewNote();

      gate.complete();
      await saving;

      expect(repo.insertedNotes, hasLength(1));
      expect(
        container.read(claimReviewProvider).saveStatus,
        ClaimDraftSaveStatus.saved,
      );
    });

    testWidgets(
        'returning to a selection saved while a prior draft was in flight is recognized as already saved',
        (tester) async {
      final gate = Completer<void>();
      final repo = _RecordingNoteDraftReviewRepository()..insertGate = gate;
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
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);

      final notifier = container.read(claimReviewProvider.notifier);
      final saving = notifier.saveAsNewNote();

      // Toggle away from the selection being saved while the insert is
      // still in flight, then toggle back to the exact same selection
      // before the insert resolves.
      notifier.toggle('n1');
      notifier.toggle('n1');
      notifier.generateDraft();
      // The content is still in pendingDraftContents, so generateDraft must
      // restore saveStatus to saving (not idle) to keep the button disabled.
      expect(
        container.read(claimReviewProvider).saveStatus,
        ClaimDraftSaveStatus.saving,
      );

      gate.complete();
      await saving;

      // The in-flight save's content matches the regenerated draft the user
      // returned to, so it should be recognized as already saved rather
      // than allowing a duplicate insert.
      expect(repo.insertedNotes, hasLength(1));
      expect(
        container.read(claimReviewProvider).saveStatus,
        ClaimDraftSaveStatus.saved,
      );
      expect(container.read(claimReviewProvider).isDraftAlreadySaved, isTrue);

      await notifier.saveAsNewNote();

      expect(repo.insertedNotes, hasLength(1));
    });

    testWidgets(
        'saving draft A then B then returning to A does not save A a second time',
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
      // Two distinct new claims so toggling one produces a different draft.
      final service = _buildIngestionService(
        provider: provider,
        claims: [_claim('n1', 'First claim.'), _claim('n2', 'Second claim.')],
        results: [
          _result('n1', 'First claim.', ClaimNoveltyClassification.newClaim),
          _result('n2', 'Second claim.', ClaimNoveltyClassification.newClaim),
        ],
      );

      final container = await _pumpSearchScreen(
        tester,
        ingestionService: service,
        repository: repo,
      );
      await _askQuestion(tester, 'question');

      final notifier = container.read(claimReviewProvider.notifier);

      // Save draft A (both claims selected).
      await _generateDraft(tester);
      final draftAContent = container.read(claimReviewProvider).draft!.markdownContent;
      await _tapSave(tester);
      expect(repo.insertedNotes, hasLength(1));

      // Deselect n1, generate and save draft B (only n2).
      notifier.toggle('n1');
      await tester.pumpAndSettle();
      await _generateDraft(tester);
      final draftBContent = container.read(claimReviewProvider).draft!.markdownContent;
      expect(draftBContent, isNot(draftAContent));
      await _tapSave(tester);
      expect(repo.insertedNotes, hasLength(2));

      // Return to draft A (re-select n1, generate).
      notifier.toggle('n1');
      await tester.pumpAndSettle();
      await _generateDraft(tester);
      expect(container.read(claimReviewProvider).draft!.markdownContent, draftAContent);
      expect(container.read(claimReviewProvider).isDraftAlreadySaved, isTrue);

      // A direct save attempt must be blocked — content already in savedDraftContents.
      await notifier.saveAsNewNote();
      expect(repo.insertedNotes, hasLength(2));
    });

    testWidgets(
        'generating a different draft while A is saving does not leave it stuck in saving',
        (tester) async {
      final gate = Completer<void>();
      final repo = _RecordingNoteDraftReviewRepository()..insertGate = gate;
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
        claims: [_claim('n1', 'First claim.'), _claim('n2', 'Second claim.')],
        results: [
          _result('n1', 'First claim.', ClaimNoveltyClassification.newClaim),
          _result('n2', 'Second claim.', ClaimNoveltyClassification.newClaim),
        ],
      );

      final container = await _pumpSearchScreen(
        tester,
        ingestionService: service,
        repository: repo,
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);

      final notifier = container.read(claimReviewProvider.notifier);
      final saving = notifier.saveAsNewNote();

      // While A's insertNote is blocked, deselect n1 and generate draft B.
      notifier.toggle('n1');
      notifier.generateDraft();
      final draftB = container.read(claimReviewProvider).draft!;

      // B's content is not in pendingDraftContents — it must be idle, not saving.
      expect(
        container.read(claimReviewProvider).saveStatus,
        ClaimDraftSaveStatus.idle,
      );

      // Complete A's save.
      gate.complete();
      await saving;

      // B remains idle — A completing must not change B's status.
      expect(
        container.read(claimReviewProvider).saveStatus,
        ClaimDraftSaveStatus.idle,
      );
      expect(repo.insertedNotes, hasLength(1));
      // B's save button must be enabled so the user can save it.
      expect(container.read(claimReviewProvider).draft!.markdownContent,
          draftB.markdownContent);
    });

    testWidgets(
        'save failure after draft changed surfaces backgroundSaveError '
        'without marking the new draft as failed', (tester) async {
      final gate = Completer<void>();
      final repo = _RecordingNoteDraftReviewRepository()
        ..insertGate = gate
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
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);

      final notifier = container.read(claimReviewProvider.notifier);
      final saving = notifier.saveAsNewNote();

      // Change the draft while the save is in flight.
      notifier.toggle('n1');

      // Let the (failing) insert complete.
      gate.complete();
      await saving;
      await tester.pumpAndSettle();

      // No note was created.
      expect(repo.insertedNotes, isEmpty);

      // The failure must be surfaced as backgroundSaveError, not as an error
      // on the current (cleared) draft.
      expect(container.read(claimReviewProvider).backgroundSaveError, isNotNull);
      expect(
        container.read(claimReviewProvider).saveStatus,
        ClaimDraftSaveStatus.idle,
      );

      // The error banner must be visible in the UI.
      expect(
        find.byKey(const Key('claim-draft-background-save-error')),
        findsOneWidget,
      );

      // Pending is cleared so draft A can be retried.
      expect(container.read(claimReviewProvider).pendingDraftContents, isEmpty);
      expect(container.read(claimReviewProvider).isDraftAlreadySaved, isFalse);
    });

    testWidgets(
        'old-session save success does not add content to the new session',
        (tester) async {
      final gate = Completer<void>();
      final repo = _RecordingNoteDraftReviewRepository()..insertGate = gate;
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
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);

      final notifier = container.read(claimReviewProvider.notifier);
      final saving = notifier.saveAsNewNote();

      // Simulate a new question resetting the session while insertNote is
      // still in flight.
      notifier.reset();

      gate.complete();
      await saving;

      // The insert succeeded, but the new session must not inherit the old
      // draft's savedDraftContents entry.
      expect(repo.insertedNotes, hasLength(1));
      expect(container.read(claimReviewProvider).savedDraftContents, isEmpty);
      expect(container.read(claimReviewProvider).saveStatus, ClaimDraftSaveStatus.idle);
      expect(container.read(claimReviewProvider).pendingDraftContents, isEmpty);
    });

    testWidgets(
        'old-session save failure does not set backgroundSaveError on the new session',
        (tester) async {
      final gate = Completer<void>();
      final repo = _RecordingNoteDraftReviewRepository()
        ..insertGate = gate
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
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);

      final notifier = container.read(claimReviewProvider.notifier);
      final saving = notifier.saveAsNewNote();

      // Simulate a new question resetting the session while insertNote is
      // still in flight.
      notifier.reset();

      gate.complete();
      await saving;

      // The insert failed, but the new session must not receive the
      // backgroundSaveError from the old session's failure.
      expect(repo.insertedNotes, isEmpty);
      expect(container.read(claimReviewProvider).backgroundSaveError, isNull);
      expect(container.read(claimReviewProvider).saveStatus, ClaimDraftSaveStatus.idle);
      expect(container.read(claimReviewProvider).pendingDraftContents, isEmpty);
    });

    testWidgets(
        'save success after draft changed mid-save triggers notes refresh and shows snackbar',
        (tester) async {
      final gate = Completer<void>();
      final repo = _RecordingNoteDraftReviewRepository()..insertGate = gate;
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

      var refreshCalled = false;
      final container = ProviderContainer(
        overrides: [
          knowledgeIngestionServiceProvider.overrideWith(
            (ref) async => _FakeKnowledgeIngestionService(),
          ),
          noteDraftReviewRepositoryProvider.overrideWithValue(repo),
          groundedAnswerIngestionServiceProvider.overrideWithValue(service),
          allNotesProvider.overrideWithValue(const <Note>[]),
          recentNotesProvider.overrideWithValue(const <Note>[]),
          refreshNotesProvider.overrideWithValue(() async { refreshCalled = true; }),
        ],
      );
      addTearDown(container.dispose);
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

      await _askQuestion(tester, 'question');
      await _generateDraft(tester);

      // Tap save but do not settle — insertNote blocks on the gate.
      final button = find.byKey(const Key('save-claim-draft-button'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();

      // Change the draft while the save is in flight.
      container.read(claimReviewProvider.notifier).toggle('n1');
      await tester.pump();

      // Unblock insertNote — saveAsNewNote returns success despite the draft change.
      gate.complete();
      await tester.pumpAndSettle();

      expect(repo.insertedNotes, hasLength(1));
      expect(refreshCalled, isTrue);
      expect(find.text('Claim draft saved as a new note.'), findsOneWidget);
    });

    testWidgets('save failure is shown and does not mark the draft saved',
        (tester) async {
      final repo = _RecordingNoteDraftReviewRepository()..shouldFail = true;
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
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);
      await _tapSave(tester);

      expect(repo.insertedNotes, isEmpty);
      expect(
        container.read(claimReviewProvider).saveStatus,
        ClaimDraftSaveStatus.error,
      );
      expect(find.byKey(const Key('claim-draft-save-error-message')), findsOneWidget);
    });

    testWidgets(
        'generating the same draft while saving keeps saveStatus as saving '
        'and blocks a concurrent second save', (tester) async {
      final gate = Completer<void>();
      final repo = _RecordingNoteDraftReviewRepository()..insertGate = gate;
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
      );
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);

      final notifier = container.read(claimReviewProvider.notifier);
      final saving = notifier.saveAsNewNote();

      // Regenerating the same selection while the insert is in flight must
      // keep saveStatus as saving, not reset it to idle.
      notifier.generateDraft();
      expect(
        container.read(claimReviewProvider).saveStatus,
        ClaimDraftSaveStatus.saving,
      );

      // A second saveAsNewNote call must be blocked by the saving guard.
      final second = notifier.saveAsNewNote();
      gate.complete();
      await Future.wait([saving, second]);

      // Only one note must have been inserted.
      expect(repo.insertedNotes, hasLength(1));
      expect(
        container.read(claimReviewProvider).saveStatus,
        ClaimDraftSaveStatus.saved,
      );
    });

    testWidgets('saved draft retains claim-level source title when URL is not in provider citations',
        (tester) async {
      const url = 'https://claim-source.example.com';
      const claimTitle = 'Claim Level Source';

      final repo = _RecordingNoteDraftReviewRepository();
      const extractedClaim = ExtractedClaim(
        id: 'c1',
        text: 'A claim with a claim-level source.',
        citationUrls: [url],
        citationTitles: [claimTitle],
        sourceAnswerProvider: 'test-provider',
        sourceQuestion: 'q',
        order: 0,
      );
      final service = _buildIngestionService(
        provider: _FixedGroundedAnswerProvider(
          GroundedAnswer(
            question: 'q',
            answerText: 'answer',
            citations: const [], // URL deliberately absent from provider citations
            providerName: 'test-provider',
            generatedAt: DateTime(2026, 1, 1),
          ),
        ),
        claims: [extractedClaim],
        results: [
          const ClaimDeduplicationResult(
            claim: extractedClaim,
            classification: ClaimNoveltyClassification.newClaim,
            matchedLocalEvidence: [],
            reason: 'new',
            citationUrls: [url],
          ),
        ],
      );

      await _pumpSearchScreen(tester, ingestionService: service, repository: repo);
      await _askQuestion(tester, 'question');
      await _generateDraft(tester);
      await _tapSave(tester);

      expect(repo.insertedNotes, hasLength(1));
      expect(repo.insertedNotes.first.content, contains('$claimTitle — $url'));
    });
  });
}
