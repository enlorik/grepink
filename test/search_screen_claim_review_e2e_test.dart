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

class _RecordingRepository implements NoteDraftReviewRepository {
  final List<Note> insertedNotes = [];
  final List<Note> updatedNotes = [];
  Note? _storedNote;

  void seedNote(Note note) => _storedNote = note;

  @override
  Future<Note?> getNoteById(String id) async {
    final n = _storedNote;
    return (n != null && n.id == id) ? n : null;
  }

  @override
  Future<Note> insertNote({
    required String title,
    required String content,
  }) async {
    final note = Note(
      id: 'inserted-${insertedNotes.length}',
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
    _storedNote = note;
  }
}

class _RecordingGroundedAnswerProvider implements GroundedAnswerProvider {
  final GroundedAnswer _answer;
  int callCount = 0;

  _RecordingGroundedAnswerProvider(this._answer);

  @override
  bool get isConfigured => true;

  @override
  Future<GroundedAnswer?> fetchGroundedAnswer(String question) async {
    callCount++;
    return _answer;
  }
}

class _RecordingLocalEvidenceRetriever implements LocalEvidenceRetriever {
  int callCount = 0;

  @override
  Future<List<EvidenceItem>> retrieve(String question) async {
    callCount++;
    return const [];
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

// ─── Fixtures ────────────────────────────────────────────────────────────────

const _providerName = 'test-provider';
const _rawAnswerProse = 'Raw answer prose that must never appear in the draft.';

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
      sourceAnswerProvider: _providerName,
      sourceQuestion: 'q',
      order: 0,
    );

ClaimDeduplicationResult _result(
  String id,
  String text,
  ClaimNoveltyClassification cls, {
  List<String> citationUrls = const [],
  List<String> citationTitles = const [],
}) =>
    ClaimDeduplicationResult(
      claim: _claim(id, text,
          citationUrls: citationUrls, citationTitles: citationTitles),
      classification: cls,
      matchedLocalEvidence: const [],
      reason: 'reason-$id',
      citationUrls: citationUrls,
    );

Note _targetNote() => Note(
      id: 'target-note',
      title: 'Target note',
      content: 'Pre-existing content.',
      tags: const [],
      keywords: const [],
      isPinned: false,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      embeddingPending: false,
    );

// ─── Pump helpers ─────────────────────────────────────────────────────────────

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required GroundedAnswerIngestionService ingestionService,
  required NoteDraftReviewRepository repository,
  List<Note> notes = const [],
}) async {
  final container = ProviderContainer(
    overrides: [
      knowledgeIngestionServiceProvider.overrideWith(
        (ref) async => _FakeKnowledgeIngestionService(),
      ),
      noteDraftReviewRepositoryProvider.overrideWithValue(repository),
      groundedAnswerIngestionServiceProvider
          .overrideWithValue(ingestionService),
      allNotesProvider.overrideWithValue(notes),
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

Future<void> _ask(WidgetTester tester, String question) async {
  await tester.enterText(find.byKey(const Key('ask-question-field')), question);
  await tester.pump();
  await tester.tap(find.byKey(const Key('ask-question-button')));
  await tester.pumpAndSettle();
}

Future<void> _generateDraft(WidgetTester tester) async {
  final btn = find.byKey(const Key('generate-claim-draft-button'));
  await tester.ensureVisible(btn);
  await tester.tap(btn);
  await tester.pumpAndSettle();
}

Future<void> _tapSave(WidgetTester tester) async {
  final btn = find.byKey(const Key('save-claim-draft-button'));
  await tester.ensureVisible(btn);
  await tester.tap(btn);
  await tester.pumpAndSettle();
}

Future<void> _tapAppend(WidgetTester tester) async {
  final btn = find.byKey(const Key('append-claim-draft-button'));
  await tester.ensureVisible(btn);
  await tester.tap(btn);
  await tester.pumpAndSettle();
}

Future<void> _tapDiscard(WidgetTester tester) async {
  final btn = find.byKey(const Key('discard-claim-review-button'));
  await tester.ensureVisible(btn);
  await tester.tap(btn);
  await tester.pumpAndSettle();
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('SearchScreen claim review MVP end-to-end', () {
    // ── Test 1: Full MVP flow ─────────────────────────────────────────────

    testWidgets(
        'ask → review → toggle → draft A (save) → draft B (append) → discard',
        (tester) async {
      final answerProvider = _RecordingGroundedAnswerProvider(
        GroundedAnswer(
          question: 'What is photosynthesis?',
          answerText: _rawAnswerProse,
          citations: const [],
          providerName: _providerName,
          generatedAt: DateTime(2026, 1, 1),
        ),
      );
      final evidenceRetriever = _RecordingLocalEvidenceRetriever();

      final service = GroundedAnswerIngestionService(
        provider: answerProvider,
        extractor: _FixedClaimExtractionService([
          _claim(
            'new-1',
            'Plants convert light into energy.',
            citationUrls: ['https://example.com/photo'],
            citationTitles: ['Photosynthesis overview'],
          ),
          _claim('better-1', 'Chlorophyll absorbs red and blue light.'),
          _claim('known-1', 'Plants need sunlight.'),
        ]),
        deduplicator: _FixedClaimDeduplicationService([
          _result(
            'new-1',
            'Plants convert light into energy.',
            ClaimNoveltyClassification.newClaim,
            citationUrls: ['https://example.com/photo'],
            citationTitles: ['Photosynthesis overview'],
          ),
          _result(
            'better-1',
            'Chlorophyll absorbs red and blue light.',
            ClaimNoveltyClassification.betterSource,
          ),
          _result(
            'known-1',
            'Plants need sunlight.',
            ClaimNoveltyClassification.alreadyKnown,
          ),
        ]),
        localEvidence: evidenceRetriever,
      );

      final repo = _RecordingRepository()..seedNote(_targetNote());

      // ── A. Ask and review ────────────────────────────────────────────

      final container = await _pump(
        tester,
        ingestionService: service,
        repository: repo,
        notes: [_targetNote()],
      );
      await _ask(tester, 'What is photosynthesis?');

      // Provider called exactly once; local evidence retrieved.
      expect(answerProvider.callCount, 1);
      expect(evidenceRetriever.callCount, 1);

      // Review groups render; no loading indicator; no setup-required card.
      expect(container.read(claimReviewProvider).hasReviewItems, isTrue);
      expect(find.byKey(const Key('claim-review-loading-indicator')),
          findsNothing);
      expect(
          find.byKey(const Key('claim-review-provider-not-configured-state')),
          findsNothing);

      // Safe provider label is shown.
      final labelFinder = find.byKey(const Key('claim-review-provider-label'));
      expect(labelFinder, findsOneWidget);
      expect(tester.widget<Text>(labelFinder).data, contains(_providerName));

      // Default selection: new and betterSource selected; alreadyKnown not.
      final sel = container.read(claimReviewProvider).selection!;
      expect(sel.selectedIds, containsAll(['new-1', 'better-1']));
      expect(sel.selectedIds, isNot(contains('known-1')));

      // alreadyKnown is unsaveable regardless of selection.
      final knownItem = sel.allItems.firstWhere((i) => i.id == 'known-1');
      expect(knownItem.canBeSaved, isFalse);

      // betterSource is saveable.
      final betterItem = sel.allItems.firstWhere((i) => i.id == 'better-1');
      expect(betterItem.canBeSaved, isTrue);

      // ── B. Draft A — new claim only ──────────────────────────────────

      // Toggle better-1 off.
      container.read(claimReviewProvider.notifier).toggle('better-1');
      await tester.pump();
      expect(container.read(claimReviewProvider).selection!.selectedIds,
          isNot(contains('better-1')));

      await _generateDraft(tester);

      final stateAfterDraftA = container.read(claimReviewProvider);
      final draftA = stateAfterDraftA.draft!;

      // Draft A content.
      expect(draftA.markdownContent,
          contains('Plants convert light into energy.'));
      expect(draftA.markdownContent,
          isNot(contains('Chlorophyll absorbs red and blue light.')));
      expect(draftA.markdownContent, isNot(contains('Plants need sunlight.')));
      // Raw answer prose must not appear in the draft.
      expect(draftA.markdownContent, isNot(contains(_rawAnswerProse)));
      // Provider display name must not appear in the draft.
      expect(draftA.markdownContent, isNot(contains(_providerName)));
      // Claim-level source URL and title survive.
      expect(draftA.markdownContent, contains('https://example.com/photo'));
      expect(draftA.markdownContent, contains('Photosynthesis overview'));
      expect(draftA.shouldSave, isTrue);

      // Save draft A as a new note.
      await _tapSave(tester);

      expect(repo.insertedNotes, hasLength(1));
      final savedNote = repo.insertedNotes.single;
      expect(savedNote.content, draftA.markdownContent);
      expect(savedNote.content, contains('https://example.com/photo'));
      expect(savedNote.content, isNot(contains(_providerName)));
      expect(savedNote.content, isNot(contains(_rawAnswerProse)));

      final stateAfterSave = container.read(claimReviewProvider);
      expect(stateAfterSave.saveStatus, ClaimDraftSaveStatus.saved);
      expect(stateAfterSave.isDraftAlreadySaved, isTrue);

      // ── C. Double-persistence protection ────────────────────────────

      // Append must be blocked after save for the same draft A content.
      container
          .read(claimReviewProvider.notifier)
          .selectTargetNote(_targetNote().id);
      await tester.pump();

      // Direct notifier call must not update the repository.
      await container.read(claimReviewProvider.notifier).appendToExistingNote();
      expect(repo.updatedNotes, isEmpty);

      // Repeated Save must not insert another note.
      final secondSaveOutcome =
          await container.read(claimReviewProvider.notifier).saveAsNewNote();
      expect(secondSaveOutcome, ClaimDraftSaveOutcome.ignored);
      expect(repo.insertedNotes, hasLength(1));

      // ── D. Draft B — new + better-source ─────────────────────────────

      // Toggle better-1 back on; this clears the current draft.
      container.read(claimReviewProvider.notifier).toggle('better-1');
      await tester.pump();
      expect(container.read(claimReviewProvider).draft, isNull);

      await _generateDraft(tester);

      final draftB = container.read(claimReviewProvider).draft!;
      expect(draftB.markdownContent,
          contains('Plants convert light into energy.'));
      expect(draftB.markdownContent,
          contains('Chlorophyll absorbs red and blue light.'));
      // Draft B is different from draft A.
      expect(draftB.markdownContent, isNot(equals(draftA.markdownContent)));
      expect(draftB.shouldSave, isTrue);

      // Append draft B to the target note.
      container
          .read(claimReviewProvider.notifier)
          .selectTargetNote(_targetNote().id);
      await tester.pump();
      await _tapAppend(tester);

      expect(repo.updatedNotes, hasLength(1));
      final updatedNote = repo.updatedNotes.single;
      // Target note's original content is preserved.
      expect(updatedNote.content, contains('Pre-existing content.'));
      // Draft B is appended after the original content.
      expect(updatedNote.content, contains(draftB.markdownContent));
      // Source links are present.
      expect(updatedNote.content, contains('https://example.com/photo'));
      // No additional insert occurred for draft B.
      expect(repo.insertedNotes, hasLength(1));
      // embeddingPending is set per current append behavior.
      expect(updatedNote.embeddingPending, isTrue);

      // Repeating append to the same target must not duplicate draft B.
      await _tapAppend(tester);
      expect(repo.updatedNotes, hasLength(1));

      // ── E. Discard ───────────────────────────────────────────────────

      await _tapDiscard(tester);

      final afterDiscard = container.read(claimReviewProvider);
      expect(afterDiscard.hasReviewItems, isFalse);
      expect(afterDiscard.draft, isNull);
      expect(afterDiscard.selection, isNull);
      expect(afterDiscard.status, ClaimReviewSessionStatus.idle);
      // Provider label is gone (panel not rendered when no review items).
      expect(
          find.byKey(const Key('claim-review-provider-label')), findsNothing);

      // Persisted records are untouched.
      expect(repo.insertedNotes, hasLength(1));
      expect(repo.updatedNotes, hasLength(1));
    });

    // ── Test 2: Already-known tampering regression ────────────────────

    testWidgets(
        'alreadyKnown tampering: notifier-level misuse cannot persist a known claim',
        (tester) async {
      const knownClaimId = 'known-1';

      final service = GroundedAnswerIngestionService(
        provider: _RecordingGroundedAnswerProvider(
          GroundedAnswer(
            question: 'q',
            answerText: 'answer',
            citations: const [],
            providerName: _providerName,
            generatedAt: DateTime(2026, 1, 1),
          ),
        ),
        extractor: _FixedClaimExtractionService([
          _claim(knownClaimId, 'Plants need sunlight.'),
        ]),
        deduplicator: _FixedClaimDeduplicationService([
          _result(
            knownClaimId,
            'Plants need sunlight.',
            ClaimNoveltyClassification.alreadyKnown,
          ),
        ]),
        localEvidence: _RecordingLocalEvidenceRetriever(),
      );

      final repo = _RecordingRepository()..seedNote(_targetNote());
      final container = await _pump(
        tester,
        ingestionService: service,
        repository: repo,
        notes: [_targetNote()],
      );
      await _ask(tester, 'q');

      // Simulate tampered/corrupted selection state by calling toggle directly
      // on the notifier, bypassing the disabled UI checkbox.
      container.read(claimReviewProvider.notifier).toggle(knownClaimId);
      await tester.pump();

      // Even after toggle, selectedSaveableItems must be empty because
      // alreadyKnown items have canBeSaved = false.
      final sel = container.read(claimReviewProvider).selection!;
      expect(sel.selectedSaveableItems, isEmpty);

      // generateDraft() on an empty saveable selection must not produce a
      // saveable draft.
      container.read(claimReviewProvider.notifier).generateDraft();
      await tester.pump();

      final draft = container.read(claimReviewProvider).draft;
      expect(draft == null || !draft.shouldSave, isTrue,
          reason:
              'draft must be null or not saveable when only alreadyKnown is selected');

      // saveAsNewNote() must be ignored — no insert must occur.
      final saveOutcome =
          await container.read(claimReviewProvider.notifier).saveAsNewNote();
      expect(saveOutcome, ClaimDraftSaveOutcome.ignored);
      expect(repo.insertedNotes, isEmpty);

      // appendToExistingNote() must also be ignored — no update must occur.
      container
          .read(claimReviewProvider.notifier)
          .selectTargetNote(_targetNote().id);
      await container.read(claimReviewProvider.notifier).appendToExistingNote();
      expect(repo.updatedNotes, isEmpty);
    });
  });
}
