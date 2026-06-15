import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/evidence_item.dart';
import 'package:grepink/models/knowledge_delta.dart';
import 'package:grepink/models/note.dart';
import 'package:grepink/models/note_draft.dart';
import 'package:grepink/providers/note_draft_review_provider.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeRepository implements NoteDraftReviewRepository {
  final Map<String, Note> notesById = {};
  int insertedNotes = 0;
  int updatedNotes = 0;

  @override
  Future<Note?> getNoteById(String id) async => notesById[id];

  @override
  Future<Note> insertNote({required String title, required String content}) async {
    insertedNotes++;
    final now = DateTime(2026, 6, 1);
    final note = Note(
      id: 'fake-$insertedNotes',
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
    updatedNotes++;
    notesById[note.id] = note;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _sourceUrl = 'https://example.com/source-page';
const _evidenceContent = 'Detailed evidence content that should stay private.';

const _evidence = EvidenceItem(
  id: 'e1',
  type: EvidenceType.webSearch,
  title: 'Evidence title',
  content: _evidenceContent,
  sourceUrl: _sourceUrl,
);

NoteDraft _draft({
  String question = 'What is the answer?',
  NoteDraftAction action = NoteDraftAction.createNewNote,
  String? markdownBody,
}) {
  return NoteDraft(
    question: question,
    markdownContent: markdownBody ?? '# Draft\n\nSome synthesised content.',
    action: action,
    deltas: const [
      KnowledgeDelta(evidence: _evidence, deltaType: DeltaType.newClaim, reason: 'test'),
    ],
    localEvidence: const [],
    webEvidence: const [_evidence],
  );
}

Note _existingNote({
  String id = 'note-1',
  String content = 'Existing note content.',
}) {
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

ProviderContainer _container(_FakeRepository repo) {
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
  group('Generated note metadata — content contract', () {
    test('metadata comment contains question, generated_at, action, source_count',
        () async {
      final repo = _FakeRepository();
      final container = _container(repo);
      final notifier = container.read(noteDraftReviewProvider.notifier);

      notifier.startReview(_draft(question: 'Metadata completeness check'));
      final note = await notifier.saveAsNewNote();

      expect(note, isNotNull);
      final content = note!.content;
      expect(content, contains('<!-- grepink-generated-note'));
      expect(content, contains('question: Metadata completeness check'));
      expect(content, contains('generated_at:'));
      expect(content, contains('action: createNewNote'));
      expect(content, contains('source_count: 1'));
      expect(content, contains('-->'));
    });

    test('generated_at value is a valid ISO 8601 UTC timestamp', () async {
      final repo = _FakeRepository();
      final container = _container(repo);
      final notifier = container.read(noteDraftReviewProvider.notifier);

      notifier.startReview(_draft());
      final note = await notifier.saveAsNewNote();

      expect(note, isNotNull);
      final content = note!.content;
      final match = RegExp(r'generated_at: (.+)').firstMatch(content);
      expect(match, isNotNull, reason: 'generated_at field must be present');
      final timestampStr = match!.group(1)!.trim();
      expect(
        () => DateTime.parse(timestampStr),
        returnsNormally,
        reason: 'generated_at value must be a parseable ISO 8601 datetime',
      );
      expect(timestampStr, endsWith('Z'), reason: 'timestamp must be UTC (ending in Z)');
    });

    test('metadata comment does not contain source URLs', () async {
      final repo = _FakeRepository();
      final container = _container(repo);
      final notifier = container.read(noteDraftReviewProvider.notifier);

      notifier.startReview(_draft());
      final note = await notifier.saveAsNewNote();

      expect(note, isNotNull);
      final content = note!.content;

      // Extract just the metadata comment block
      final commentMatch =
          RegExp(r'<!--.*?-->', dotAll: true).firstMatch(content);
      expect(commentMatch, isNotNull);
      final commentText = commentMatch!.group(0)!;

      expect(commentText, isNot(contains(_sourceUrl)),
          reason: 'Source URL must not appear in the metadata comment');
    });

    test('metadata comment does not contain full evidence content', () async {
      final repo = _FakeRepository();
      final container = _container(repo);
      final notifier = container.read(noteDraftReviewProvider.notifier);

      notifier.startReview(_draft());
      final note = await notifier.saveAsNewNote();

      expect(note, isNotNull);
      final content = note!.content;

      final commentMatch =
          RegExp(r'<!--.*?-->', dotAll: true).firstMatch(content);
      expect(commentMatch, isNotNull);
      final commentText = commentMatch!.group(0)!;

      expect(commentText, isNot(contains(_evidenceContent)),
          reason: 'Evidence content must not appear in the metadata comment');
    });

    test('metadata does not include API key patterns', () async {
      final repo = _FakeRepository();
      final container = _container(repo);
      final notifier = container.read(noteDraftReviewProvider.notifier);

      notifier.startReview(_draft());
      final note = await notifier.saveAsNewNote();

      expect(note, isNotNull);
      final content = note!.content;
      final commentMatch =
          RegExp(r'<!--.*?-->', dotAll: true).firstMatch(content);
      expect(commentMatch, isNotNull);
      final commentText = commentMatch!.group(0)!;

      expect(commentText.toLowerCase(), isNot(contains('apikey')));
      expect(commentText.toLowerCase(), isNot(contains('api_key')));
      expect(commentText, isNot(contains('sk-')));
    });
  });

  group('Generated note metadata — sanitisation', () {
    test('double-dash in question is replaced with single-dash-space-dash', () async {
      final repo = _FakeRepository();
      final container = _container(repo);
      final notifier = container.read(noteDraftReviewProvider.notifier);

      notifier.startReview(_draft(question: 'A--B question'));
      final note = await notifier.saveAsNewNote();

      expect(note, isNotNull);
      final content = note!.content;
      expect(content, contains('question: A- -B question'),
          reason: '-- in the question must be sanitised to - - to keep the comment valid');
    });

    test('sanitised question does not prematurely close the HTML comment', () async {
      final repo = _FakeRepository();
      final container = _container(repo);
      final notifier = container.read(noteDraftReviewProvider.notifier);

      notifier.startReview(
        _draft(question: 'Close comment attempt -->', action: NoteDraftAction.createNewNote),
      );
      final note = await notifier.saveAsNewNote();

      expect(note, isNotNull);
      final content = note!.content;
      // The comment must remain a single valid block that ends with -->
      final commentMatches = RegExp(r'<!--.*?-->', dotAll: true).allMatches(content).toList();
      expect(commentMatches.length, 1,
          reason: 'There must be exactly one closed metadata comment block');
    });

    test('multiple whitespace in question is collapsed to single space', () async {
      final repo = _FakeRepository();
      final container = _container(repo);
      final notifier = container.read(noteDraftReviewProvider.notifier);

      notifier.startReview(_draft(question: 'What   is\n\nthis?'));
      final note = await notifier.saveAsNewNote();

      expect(note, isNotNull);
      expect(note!.content, contains('question: What is this?'));
    });
  });

  group('Generated note metadata — append behaviour', () {
    test('appended draft has its own metadata block with appendToExistingNote action',
        () async {
      final repo = _FakeRepository();
      repo.notesById['note-1'] = _existingNote();
      final container = _container(repo);
      final notifier = container.read(noteDraftReviewProvider.notifier);

      notifier.startReview(
        _draft(question: 'Append question', action: NoteDraftAction.appendToExistingNote),
      );
      notifier.selectTargetNote('note-1');
      final updated = await notifier.appendToExistingNote();

      expect(updated, isNotNull);
      expect(updated!.content, contains('action: appendToExistingNote'));
      expect(updated.content, contains('question: Append question'));
      expect(updated.content, contains('<!-- grepink-generated-note'));
    });

    test('appended draft preserves existing note content before the separator', () async {
      final repo = _FakeRepository();
      const existingText = 'Original note text that must be preserved.';
      repo.notesById['note-1'] = _existingNote(content: existingText);
      final container = _container(repo);
      final notifier = container.read(noteDraftReviewProvider.notifier);

      notifier.startReview(
        _draft(action: NoteDraftAction.appendToExistingNote),
      );
      notifier.selectTargetNote('note-1');
      final updated = await notifier.appendToExistingNote();

      expect(updated, isNotNull);
      expect(updated!.content, contains(existingText),
          reason: 'Existing content must be preserved before the appended block');
      expect(updated.content, contains('---'),
          reason: 'A separator must appear between existing and appended content');
    });

    test('two sequential appends each get their own metadata block', () async {
      final repo = _FakeRepository();
      repo.notesById['note-1'] = _existingNote(content: 'Original content.');
      final container = _container(repo);

      // First append
      final notifier1 = container.read(noteDraftReviewProvider.notifier);
      notifier1.startReview(
        _draft(question: 'First append', action: NoteDraftAction.appendToExistingNote),
      );
      notifier1.selectTargetNote('note-1');
      await notifier1.appendToExistingNote();

      // Second append uses the already-updated note from the repo
      notifier1.clear();
      notifier1.startReview(
        _draft(question: 'Second append', action: NoteDraftAction.appendToExistingNote),
      );
      notifier1.selectTargetNote('note-1');
      await notifier1.appendToExistingNote();

      final finalNote = repo.notesById['note-1']!;
      final commentMatches =
          RegExp(r'<!--.*?-->', dotAll: true).allMatches(finalNote.content).toList();
      expect(commentMatches.length, 2,
          reason: 'Each append should add exactly one metadata block');
      expect(finalNote.content, contains('question: First append'));
      expect(finalNote.content, contains('question: Second append'));
      expect(finalNote.content, contains('Original content.'),
          reason: 'Original content must survive both appends');
    });
  });
}
