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
  });
}
