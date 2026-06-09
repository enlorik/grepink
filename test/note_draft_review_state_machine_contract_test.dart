import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/evidence_item.dart';
import 'package:grepink/models/knowledge_delta.dart';
import 'package:grepink/models/note.dart';
import 'package:grepink/models/note_draft.dart';
import 'package:grepink/models/note_draft_review_state.dart';
import 'package:grepink/providers/note_draft_review_provider.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _TrackingRepository implements NoteDraftReviewRepository {
  int insertCalls = 0;
  int updateCalls = 0;
  int getCalls = 0;
  Map<String, Note> notesById = {};

  @override
  Future<Note?> getNoteById(String id) async {
    getCalls++;
    return notesById[id];
  }

  @override
  Future<Note> insertNote({required String title, required String content}) async {
    insertCalls++;
    final now = DateTime(2026, 6, 1);
    final note = Note(
      id: 'inserted-$insertCalls',
      title: title,
      content: content,
      tags: const [],
      keywords: const [],
      isPinned: false,
      createdAt: now,
      updatedAt: now,
      embeddingPending: true,
    );
    notesById[note.id] = note;
    return note;
  }

  @override
  Future<void> updateNote(Note note) async {
    updateCalls++;
    notesById[note.id] = note;
  }
}

class _FailingRepository implements NoteDraftReviewRepository {
  @override
  Future<Note?> getNoteById(String id) async => null;

  @override
  Future<Note> insertNote({required String title, required String content}) =>
      throw Exception('database unavailable');

  @override
  Future<void> updateNote(Note note) =>
      throw Exception('database unavailable');
}

/// Finds the target note successfully but throws when updateNote is called.
class _FailingUpdateRepository implements NoteDraftReviewRepository {
  final Note noteToReturn;

  _FailingUpdateRepository(this.noteToReturn);

  @override
  Future<Note?> getNoteById(String id) async => noteToReturn;

  @override
  Future<Note> insertNote({required String title, required String content}) =>
      throw Exception('not expected');

  @override
  Future<void> updateNote(Note note) =>
      throw Exception('update database unavailable');
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _evidence = EvidenceItem(
  id: 'e1',
  type: EvidenceType.webSearch,
  title: 'Test source',
  content: 'Source content',
  sourceUrl: 'https://example.com/source',
);

NoteDraft _draft({
  String question = 'What is the answer?',
  NoteDraftAction action = NoteDraftAction.createNewNote,
}) {
  return NoteDraft(
    question: question,
    markdownContent: '# Draft\n\nSome content',
    action: action,
    deltas: const [
      KnowledgeDelta(evidence: _evidence, deltaType: DeltaType.newClaim, reason: 'test'),
    ],
    localEvidence: const [],
    webEvidence: const [_evidence],
  );
}

Note _existingNote({String id = 'note-1', String content = 'Existing content'}) {
  final now = DateTime(2026, 6, 1);
  return Note(
    id: id,
    title: 'Existing note',
    content: content,
    tags: const [],
    keywords: const [],
    isPinned: false,
    createdAt: now,
    updatedAt: now,
    embeddingPending: false,
  );
}

ProviderContainer _container(NoteDraftReviewRepository repo) {
  final container = ProviderContainer(
    overrides: [noteDraftReviewRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return container;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('NoteDraftReviewNotifier — state machine contract', () {
    group('startReview', () {
      test('sets status to reviewing and stores the draft', () {
        final repo = _TrackingRepository();
        final container = _container(repo);
        final notifier = container.read(noteDraftReviewProvider.notifier);
        final draft = _draft();

        notifier.startReview(draft);

        final state = container.read(noteDraftReviewProvider);
        expect(state.status, NoteDraftReviewStatus.reviewing);
        expect(state.noteDraft, same(draft));
        expect(state.hasDraft, isTrue);
        expect(state.errorMessage, isNull);
      });

      test('sets default decision to saveAsNewNote for createNewNote action', () {
        final container = _container(_TrackingRepository());
        container
            .read(noteDraftReviewProvider.notifier)
            .startReview(_draft(action: NoteDraftAction.createNewNote));

        expect(
          container.read(noteDraftReviewProvider).selectedDecision,
          NoteDraftReviewDecision.saveAsNewNote,
        );
      });

      test('sets default decision to appendToExistingNote for append action', () {
        final container = _container(_TrackingRepository());
        container
            .read(noteDraftReviewProvider.notifier)
            .startReview(_draft(action: NoteDraftAction.appendToExistingNote));

        expect(
          container.read(noteDraftReviewProvider).selectedDecision,
          NoteDraftReviewDecision.appendToExistingNote,
        );
      });

      test('does not auto-save — no repository calls on startReview', () {
        final repo = _TrackingRepository();
        final container = _container(repo);

        container.read(noteDraftReviewProvider.notifier).startReview(_draft());

        expect(repo.insertCalls, 0);
        expect(repo.updateCalls, 0);
      });
    });

    group('saveAsNewNote', () {
      test('transitions to saving then saved, and returns the created note', () async {
        final repo = _TrackingRepository();
        final container = _container(repo);
        final notifier = container.read(noteDraftReviewProvider.notifier);

        notifier.startReview(_draft(question: 'Contract question'));
        final createdNote = await notifier.saveAsNewNote();

        expect(createdNote, isNotNull);
        expect(createdNote!.title, 'Contract question');
        expect(repo.insertCalls, 1);
        expect(
          container.read(noteDraftReviewProvider).status,
          NoteDraftReviewStatus.saved,
        );
      });

      test('draft is NOT cleared after save — remains accessible for reference', () async {
        final repo = _TrackingRepository();
        final container = _container(repo);
        final notifier = container.read(noteDraftReviewProvider.notifier);
        final draft = _draft();

        notifier.startReview(draft);
        await notifier.saveAsNewNote();

        expect(container.read(noteDraftReviewProvider).noteDraft, same(draft));
      });

      test('repository failure surfaces error state instead of silently failing', () async {
        final container = _container(_FailingRepository());
        final notifier = container.read(noteDraftReviewProvider.notifier);

        notifier.startReview(_draft());
        final result = await notifier.saveAsNewNote();

        expect(result, isNull);
        expect(
          container.read(noteDraftReviewProvider).status,
          NoteDraftReviewStatus.error,
        );
        expect(
          container.read(noteDraftReviewProvider).errorMessage,
          isNotEmpty,
        );
      });

      test('draft is preserved after a save failure', () async {
        final container = _container(_FailingRepository());
        final notifier = container.read(noteDraftReviewProvider.notifier);
        final draft = _draft();

        notifier.startReview(draft);
        await notifier.saveAsNewNote();

        expect(container.read(noteDraftReviewProvider).noteDraft, same(draft));
        expect(container.read(noteDraftReviewProvider).hasDraft, isTrue);
      });
    });

    group('appendToExistingNote', () {
      test('requires a non-empty targetNoteId — returns error immediately', () async {
        final repo = _TrackingRepository();
        final container = _container(repo);
        final notifier = container.read(noteDraftReviewProvider.notifier);

        notifier.startReview(_draft(action: NoteDraftAction.appendToExistingNote));
        final result = await notifier.appendToExistingNote();

        expect(result, isNull);
        expect(repo.updateCalls, 0);
        expect(
          container.read(noteDraftReviewProvider).status,
          NoteDraftReviewStatus.error,
        );
        expect(
          container.read(noteDraftReviewProvider).errorMessage,
          contains('Select a target note'),
        );
      });

      test('requires a note that actually exists in the repository', () async {
        final repo = _TrackingRepository();
        final container = _container(repo);
        final notifier = container.read(noteDraftReviewProvider.notifier);

        notifier.startReview(_draft(action: NoteDraftAction.appendToExistingNote));
        notifier.selectTargetNote('non-existent-note-id');
        final result = await notifier.appendToExistingNote();

        expect(result, isNull);
        expect(repo.updateCalls, 0);
        expect(
          container.read(noteDraftReviewProvider).status,
          NoteDraftReviewStatus.error,
        );
        expect(
          container.read(noteDraftReviewProvider).errorMessage,
          contains('no longer exists'),
        );
      });

      test('succeeds and transitions to saved when target note exists', () async {
        final repo = _TrackingRepository();
        repo.notesById['note-1'] = _existingNote();
        final container = _container(repo);
        final notifier = container.read(noteDraftReviewProvider.notifier);

        notifier.startReview(_draft(action: NoteDraftAction.appendToExistingNote));
        notifier.selectTargetNote('note-1');
        final updatedNote = await notifier.appendToExistingNote();

        expect(updatedNote, isNotNull);
        expect(repo.updateCalls, 1);
        expect(
          container.read(noteDraftReviewProvider).status,
          NoteDraftReviewStatus.saved,
        );
      });

      test('repository failure on updateNote surfaces error state', () async {
        final existingNote = _existingNote();
        final container = _container(_FailingUpdateRepository(existingNote));
        final notifier = container.read(noteDraftReviewProvider.notifier);

        notifier.startReview(_draft(action: NoteDraftAction.appendToExistingNote));
        notifier.selectTargetNote(existingNote.id);
        final result = await notifier.appendToExistingNote();

        expect(result, isNull,
            reason: 'updateNote threw so no updated note should be returned');
        expect(
          container.read(noteDraftReviewProvider).status,
          NoteDraftReviewStatus.error,
        );
        expect(
          container.read(noteDraftReviewProvider).errorMessage,
          isNotEmpty,
        );
      });
    });

    group('discard', () {
      test('transitions to discarded and clears the draft', () {
        final repo = _TrackingRepository();
        final container = _container(repo);
        final notifier = container.read(noteDraftReviewProvider.notifier);

        notifier.startReview(_draft());
        notifier.discard();

        final state = container.read(noteDraftReviewProvider);
        expect(state.status, NoteDraftReviewStatus.discarded);
        expect(state.noteDraft, isNull);
        expect(state.hasDraft, isFalse);
      });

      test('does not call the repository', () {
        final repo = _TrackingRepository();
        final container = _container(repo);
        final notifier = container.read(noteDraftReviewProvider.notifier);

        notifier.startReview(_draft());
        notifier.discard();

        expect(repo.insertCalls, 0);
        expect(repo.updateCalls, 0);
      });

      test('clears selected decision and target note id', () {
        final repo = _TrackingRepository();
        final container = _container(repo);
        final notifier = container.read(noteDraftReviewProvider.notifier);

        notifier.startReview(_draft(action: NoteDraftAction.appendToExistingNote));
        notifier.selectTargetNote('note-1');
        notifier.discard();

        final state = container.read(noteDraftReviewProvider);
        expect(state.targetNoteId, isNull);
        expect(state.selectedDecision, NoteDraftReviewDecision.discard);
      });

      test('is a no-op when there is no active draft', () {
        final repo = _TrackingRepository();
        final container = _container(repo);
        final notifier = container.read(noteDraftReviewProvider.notifier);

        notifier.discard();

        expect(
          container.read(noteDraftReviewProvider).status,
          NoteDraftReviewStatus.empty,
        );
        expect(repo.insertCalls, 0);
        expect(repo.updateCalls, 0);
      });
    });

    group('no auto-save contract', () {
      test('review state is empty before any action', () {
        final container = _container(_TrackingRepository());

        final state = container.read(noteDraftReviewProvider);
        expect(state.status, NoteDraftReviewStatus.empty);
        expect(state.noteDraft, isNull);
      });

      test('clear() resets to empty state regardless of current status', () async {
        final repo = _TrackingRepository();
        final container = _container(repo);
        final notifier = container.read(noteDraftReviewProvider.notifier);

        notifier.startReview(_draft());
        await notifier.saveAsNewNote();
        notifier.clear();

        final state = container.read(noteDraftReviewProvider);
        expect(state.status, NoteDraftReviewStatus.empty);
        expect(state.noteDraft, isNull);
      });

      test('selectDecision does not trigger any save', () async {
        final repo = _TrackingRepository();
        final container = _container(repo);
        final notifier = container.read(noteDraftReviewProvider.notifier);

        notifier.startReview(_draft());
        notifier.selectDecision(NoteDraftReviewDecision.appendToExistingNote);
        notifier.selectDecision(NoteDraftReviewDecision.saveAsNewNote);

        expect(repo.insertCalls, 0);
        expect(repo.updateCalls, 0);
      });
    });
  });
}
