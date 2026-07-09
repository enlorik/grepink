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
  });
}
