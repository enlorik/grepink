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

// This suite exercises the whole MVP path end to end -- ask a question,
// review the grouped claims, toggle a selection, generate a draft, save it
// as a new note, append it to an existing note, and discard the session --
// using fakes throughout. No real network calls and no real API keys.

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
  final List<Note> updatedNotes = [];
  Note? existingNote;

  @override
  Future<Note?> getNoteById(String id) async {
    final note = existingNote;
    if (note != null && note.id == id) return note;
    return null;
  }

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
  Future<void> updateNote(Note note) async {
    updatedNotes.add(note);
    existingNote = note;
  }
}

class _FixedGroundedAnswerProvider implements GroundedAnswerProvider {
  final GroundedAnswer answer;
  final List<String> callOrder;

  _FixedGroundedAnswerProvider(this.answer, {required this.callOrder});

  @override
  Future<GroundedAnswer?> fetchGroundedAnswer(String question) async {
    callOrder.add('provider');
    return answer;
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

class _RecordingLocalEvidenceRetriever implements LocalEvidenceRetriever {
  final List<String> callOrder;

  _RecordingLocalEvidenceRetriever(this.callOrder);

  @override
  Future<List<EvidenceItem>> retrieve(String question) async {
    callOrder.add('local-evidence');
    return const [];
  }
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

Note _existingNote() => Note(
      id: 'existing-note',
      title: 'Existing note',
      content: 'Old content here.',
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

Future<void> _tapSave(WidgetTester tester) async {
  final button = find.byKey(const Key('save-claim-draft-button'));
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

Future<void> _tapDiscard(WidgetTester tester) async {
  final button = find.byKey(const Key('discard-claim-review-button'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  group('SearchScreen end-to-end claim review MVP flow', () {
    testWidgets(
        'ask -> review -> toggle -> draft -> save -> append -> discard',
        (tester) async {
      final callOrder = <String>[];
      final repo = _RecordingNoteDraftReviewRepository()
        ..existingNote = _existingNote();
      final provider = _FixedGroundedAnswerProvider(
        GroundedAnswer(
          question: 'What is photosynthesis?',
          answerText: 'Plants convert light into energy using chlorophyll.',
          citations: const [],
          providerName: 'test-provider',
          generatedAt: DateTime(2026, 1, 1),
        ),
        callOrder: callOrder,
      );
      final service = GroundedAnswerIngestionService(
        provider: provider,
        extractor: _FixedClaimExtractionService([
          _claim('new-1', 'Plants convert light into energy.',
              citationUrls: ['https://example.com/photosynthesis'],
              citationTitles: ['Photosynthesis overview']),
          _claim('better-1', 'Chlorophyll absorbs light.'),
          _claim('known-1', 'Plants need sunlight.'),
        ]),
        deduplicator: _FixedClaimDeduplicationService([
          _result(
            'new-1',
            'Plants convert light into energy.',
            ClaimNoveltyClassification.newClaim,
            citationUrls: ['https://example.com/photosynthesis'],
            citationTitles: ['Photosynthesis overview'],
          ),
          _result(
            'better-1',
            'Chlorophyll absorbs light.',
            ClaimNoveltyClassification.betterSource,
          ),
          _result(
            'known-1',
            'Plants need sunlight.',
            ClaimNoveltyClassification.alreadyKnown,
          ),
        ]),
        localEvidence: _RecordingLocalEvidenceRetriever(callOrder),
      );

      // 1-6: ask a question; local evidence, grounded answer, extraction,
      // and classification all happen, and grouped review results render.
      final container = await _pumpSearchScreen(
        tester,
        ingestionService: service,
        repository: repo,
        availableNotes: [_existingNote()],
      );
      await _askQuestion(tester, 'What is photosynthesis?');

      // Local evidence is retrieved before the external provider is called.
      expect(callOrder, ['local-evidence', 'provider']);

      final reviewState = container.read(claimReviewProvider);
      expect(reviewState.hasReviewItems, isTrue);
      expect(find.byKey(const Key('claim-review-loading-indicator')), findsNothing);

      // 7: new and betterSource claims are selected by default; alreadyKnown
      // is not.
      expect(reviewState.selection!.selectedIds, containsAll(['new-1', 'better-1']));
      expect(reviewState.selection!.selectedIds, isNot(contains('known-1')));

      // 8: user toggles a claim off.
      container.read(claimReviewProvider.notifier).toggle('better-1');
      await tester.pump();
      expect(
        container.read(claimReviewProvider).selection!.selectedIds,
        isNot(contains('better-1')),
      );

      // 9: generate the markdown draft from the remaining selected claim.
      await _generateDraft(tester);
      final draft = container.read(claimReviewProvider).draft;
      expect(draft, isNotNull);
      expect(draft!.markdownContent, contains('Plants convert light into energy.'));
      expect(draft.markdownContent, isNot(contains('Chlorophyll absorbs light.')));
      expect(draft.markdownContent, isNot(contains('Plants need sunlight.')));
      // The raw grounded answer text itself is never drafted, only the
      // selected claim text.
      expect(
        draft.markdownContent,
        isNot(contains('Plants convert light into energy using chlorophyll.')),
      );
      expect(draft.markdownContent, contains('https://example.com/photosynthesis'));

      // 10: save the draft as a new note.
      await _tapSave(tester);
      expect(repo.insertedNotes, hasLength(1));
      expect(repo.insertedNotes.single.content, draft.markdownContent);
      expect(
        repo.insertedNotes.single.content,
        contains('https://example.com/photosynthesis'),
      );

      // 11: the same draft can also be appended to an existing note.
      container
          .read(claimReviewProvider.notifier)
          .selectTargetNote(_existingNote().id);
      await tester.pump();
      await _tapAppend(tester);

      expect(repo.updatedNotes, hasLength(1));
      expect(repo.updatedNotes.single.content, contains('Old content here.'));
      expect(repo.updatedNotes.single.content, contains(draft.markdownContent));

      // 12: discard clears the session without deleting the notes we just
      // created/modified.
      await _tapDiscard(tester);
      final afterDiscard = container.read(claimReviewProvider);
      expect(afterDiscard.hasReviewItems, isFalse);
      expect(afterDiscard.draft, isNull);
      expect(afterDiscard.selection, isNull);
      expect(repo.insertedNotes, hasLength(1));
      expect(repo.updatedNotes, hasLength(1));
    });

    testWidgets('alreadyKnown claims are never saved even if selection is tampered with',
        (tester) async {
      final repo = _RecordingNoteDraftReviewRepository();
      final callOrder = <String>[];
      final provider = _FixedGroundedAnswerProvider(
        GroundedAnswer(
          question: 'q',
          answerText: 'answer',
          citations: const [],
          providerName: 'test-provider',
          generatedAt: DateTime(2026, 1, 1),
        ),
        callOrder: callOrder,
      );
      final service = GroundedAnswerIngestionService(
        provider: provider,
        extractor: _FixedClaimExtractionService([
          _claim('known-1', 'Plants need sunlight.'),
        ]),
        deduplicator: _FixedClaimDeduplicationService([
          _result('known-1', 'Plants need sunlight.', ClaimNoveltyClassification.alreadyKnown),
        ]),
        localEvidence: _RecordingLocalEvidenceRetriever(callOrder),
      );

      final container = await _pumpSearchScreen(
        tester,
        ingestionService: service,
        repository: repo,
      );
      await _askQuestion(tester, 'question');

      // Attempting to select the alreadyKnown claim does not make it
      // saveable -- the notifier itself enforces this, independent of the
      // UI checkbox being disabled.
      container.read(claimReviewProvider.notifier).toggle('known-1');
      await tester.pump();

      final draft = container.read(claimReviewProvider).draft;
      expect(draft == null || !draft.shouldSave, isTrue);
    });
  });
}
