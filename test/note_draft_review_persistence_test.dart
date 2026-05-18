import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/evidence_item.dart';
import 'package:grepink/models/knowledge_delta.dart';
import 'package:grepink/models/note.dart';
import 'package:grepink/models/note_draft.dart';
import 'package:grepink/models/note_draft_review_state.dart';
import 'package:grepink/providers/note_draft_review_provider.dart';

class _FakeNoteDraftReviewRepository implements NoteDraftReviewRepository {
  final Map<String, Note> notesById = <String, Note>{};
  int insertedNotes = 0;
  int updatedNotes = 0;

  @override
  Future<Note?> getNoteById(String id) async => notesById[id];

  @override
  Future<void> insertNote(Note note) async {
    insertedNotes++;
    notesById[note.id] = note;
  }

  @override
  Future<void> updateNote(Note note) async {
    updatedNotes++;
    notesById[note.id] = note;
  }
}

NoteDraft _draft({
  required String question,
  required NoteDraftAction action,
  String markdownContent =
      '# Draft\n\nSource: https://example.com/source\n\nFresh claim',
}) {
  const evidence = EvidenceItem(
    id: 'e1',
    type: EvidenceType.webSearch,
    title: 'Evidence',
    content: 'Durable evidence',
    sourceUrl: 'https://example.com/source',
  );

  return NoteDraft(
    question: question,
    markdownContent: markdownContent,
    action: action,
    deltas: const [
      KnowledgeDelta(
        evidence: evidence,
        deltaType: DeltaType.newClaim,
        reason: 'test',
      ),
    ],
    localEvidence: const [],
    webEvidence: const [evidence],
  );
}

Note _note({
  required String id,
  required String title,
  required String content,
}) {
  final now = DateTime(2026, 5, 18);
  return Note(
    id: id,
    title: title,
    content: content,
    tags: const [],
    keywords: const [],
    isPinned: false,
    createdAt: now,
    updatedAt: now,
    embeddingPending: false,
  );
}

void main() {
  group('NoteDraftReviewNotifier persistence', () {
    test('saveAsNewNote creates a new note with source URLs preserved',
        () async {
      final repository = _FakeNoteDraftReviewRepository();
      final container = ProviderContainer(
        overrides: [
          noteDraftReviewRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(noteDraftReviewProvider.notifier);
      notifier.startReview(
        _draft(
          question: 'What changed?',
          action: NoteDraftAction.createNewNote,
        ),
      );

      final createdNote = await notifier.saveAsNewNote();

      expect(createdNote, isNotNull);
      expect(repository.insertedNotes, 1);
      expect(createdNote!.title, 'What changed?');
      expect(createdNote.content, contains('<!-- grepink-generated-note'));
      expect(createdNote.content, contains('question: What changed?'));
      expect(createdNote.content, contains('action: createNewNote'));
      expect(createdNote.content, contains('source_count: 1'));
      expect(createdNote.content, contains('https://example.com/source'));
      expect(
        container.read(noteDraftReviewProvider).status,
        NoteDraftReviewStatus.saved,
      );
    });

    test('appendToExistingNote updates an existing note and preserves URLs',
        () async {
      final repository = _FakeNoteDraftReviewRepository();
      repository.notesById['note-1'] = _note(
        id: 'note-1',
        title: 'Existing note',
        content: 'Existing content',
      );
      final container = ProviderContainer(
        overrides: [
          noteDraftReviewRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(noteDraftReviewProvider.notifier);
      notifier.startReview(
        _draft(
          question: 'Append this',
          action: NoteDraftAction.appendToExistingNote,
        ),
      );
      notifier.selectTargetNote('note-1');

      final updatedNote = await notifier.appendToExistingNote();

      expect(updatedNote, isNotNull);
      expect(repository.updatedNotes, 1);
      expect(updatedNote!.content, contains('<!-- grepink-generated-note'));
      expect(updatedNote.content, contains('question: Append this'));
      expect(updatedNote.content, contains('action: appendToExistingNote'));
      expect(updatedNote.content, contains('source_count: 1'));
      expect(updatedNote.content, contains('## Update from question: Append this'));
      expect(updatedNote.content, contains('https://example.com/source'));
      expect(
        container.read(noteDraftReviewProvider).status,
        NoteDraftReviewStatus.saved,
      );
    });

    test('generated note metadata does not include secret-like fields', () async {
      final repository = _FakeNoteDraftReviewRepository();
      final container = ProviderContainer(
        overrides: [
          noteDraftReviewRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(noteDraftReviewProvider.notifier);
      notifier.startReview(
        _draft(
          question: 'Keep this traceable',
          action: NoteDraftAction.createNewNote,
        ),
      );

      final createdNote = await notifier.saveAsNewNote();

      expect(createdNote, isNotNull);
      expect(createdNote!.content, isNot(contains('apiKey')));
      expect(createdNote.content, isNot(contains('api_key')));
      expect(createdNote.content, isNot(contains('prompt')));
      expect(createdNote.content, isNot(contains('sk-')));
    });

    test('appendToExistingNote fails safely when no target is selected',
        () async {
      final repository = _FakeNoteDraftReviewRepository();
      final container = ProviderContainer(
        overrides: [
          noteDraftReviewRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(noteDraftReviewProvider.notifier);
      notifier.startReview(
        _draft(
          question: 'Append safely',
          action: NoteDraftAction.appendToExistingNote,
        ),
      );

      final result = await notifier.appendToExistingNote();

      expect(result, isNull);
      expect(repository.updatedNotes, 0);
      expect(
        container.read(noteDraftReviewProvider).status,
        NoteDraftReviewStatus.error,
      );
      expect(
        container.read(noteDraftReviewProvider).errorMessage,
        contains('Select a target note'),
      );
    });

    test('appendToExistingNote fails safely when target note does not exist',
        () async {
      final repository = _FakeNoteDraftReviewRepository();
      final container = ProviderContainer(
        overrides: [
          noteDraftReviewRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(noteDraftReviewProvider.notifier);
      notifier.startReview(
        _draft(
          question: 'Missing target',
          action: NoteDraftAction.appendToExistingNote,
        ),
      );
      notifier.selectTargetNote('missing-note');

      final result = await notifier.appendToExistingNote();

      expect(result, isNull);
      expect(repository.updatedNotes, 0);
      expect(repository.insertedNotes, 0);
      expect(
        container.read(noteDraftReviewProvider).errorMessage,
        contains('no longer exists'),
      );
    });

    test('discard clears review state and does not modify notes', () {
      final repository = _FakeNoteDraftReviewRepository();
      final container = ProviderContainer(
        overrides: [
          noteDraftReviewRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(noteDraftReviewProvider.notifier);
      notifier.startReview(
        _draft(
          question: 'Discard this',
          action: NoteDraftAction.createNewNote,
        ),
      );

      notifier.discard();

      final state = container.read(noteDraftReviewProvider);
      expect(state.status, NoteDraftReviewStatus.discarded);
      expect(state.noteDraft, isNull);
      expect(repository.insertedNotes, 0);
      expect(repository.updatedNotes, 0);
    });
  });
}
