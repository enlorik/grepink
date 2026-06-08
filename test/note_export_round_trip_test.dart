import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/evidence_item.dart';
import 'package:grepink/models/knowledge_delta.dart';
import 'package:grepink/models/note.dart';
import 'package:grepink/models/note_draft.dart';
import 'package:grepink/providers/note_draft_review_provider.dart';

// ---------------------------------------------------------------------------
// Fake repository – no database, no network
// ---------------------------------------------------------------------------

class _FakeRepo implements NoteDraftReviewRepository {
  Note? _stored;

  @override
  Future<Note> insertNote({required String title, required String content}) async {
    _stored = Note(
      id: 'rt-1',
      title: title,
      content: content,
      tags: const [],
      keywords: const [],
      isPinned: false,
      createdAt: DateTime.utc(2026, 6, 1),
      updatedAt: DateTime.utc(2026, 6, 1),
      embeddingPending: true,
    );
    return _stored!;
  }

  @override
  Future<void> updateNote(Note note) async {
    _stored = note;
  }

  @override
  Future<Note?> getNoteById(String id) async => _stored?.id == id ? _stored : null;

  Note? get stored => _stored;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _webEvidence = EvidenceItem(
  id: 'w1',
  type: EvidenceType.webSearch,
  title: 'Web result',
  content: 'Factual content from the web.',
  sourceUrl: 'https://example.com/article',
);

const _localEvidence = EvidenceItem(
  id: 'l1',
  type: EvidenceType.localNote,
  title: 'My prior note',
  content: 'Prior knowledge I already saved.',
  sourceNoteId: 'prior-note-id',
);

NoteDraft _makeDraft({
  required String question,
  required NoteDraftAction action,
  String markdown = '## Answer\n\nSome evidence-backed content.',
  List<EvidenceItem> web = const [_webEvidence],
  List<EvidenceItem> local = const [],
}) {
  return NoteDraft(
    question: question,
    markdownContent: markdown,
    action: action,
    deltas: [
      KnowledgeDelta(
        evidence: web.isNotEmpty ? web.first : local.first,
        deltaType: DeltaType.newClaim,
        reason: 'test',
      ),
    ],
    webEvidence: web,
    localEvidence: local,
  );
}

ProviderContainer _container(_FakeRepo repo) {
  final c = ProviderContainer(overrides: [
    noteDraftReviewRepositoryProvider.overrideWithValue(repo),
  ]);
  addTearDown(c.dispose);
  return c;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Note JSON round-trip', () {
    test('content with generated metadata comment is unchanged after toJson/fromJson', () {
      const content = '''<!-- grepink-generated-note
question: What is Dart?
generated_at: 2026-06-01T12:00:00.000000Z
action: createNewNote
source_count: 1
-->

## Answer

Dart is a client-optimised language.

[Source](https://example.com/article)''';

      final note = Note(
        id: 'n1',
        title: 'What is Dart?',
        content: content,
        tags: const [],
        keywords: const [],
        isPinned: false,
        createdAt: DateTime.utc(2026, 6, 1),
        updatedAt: DateTime.utc(2026, 6, 1),
        embeddingPending: false,
      );

      final restored = Note.fromJson(note.toJson());

      expect(restored.content, equals(content));
      expect(restored.content, contains('<!-- grepink-generated-note'));
      expect(restored.content, contains('question: What is Dart?'));
      expect(restored.content, contains('action: createNewNote'));
    });

    test('plain note content is unchanged after toJson/fromJson', () {
      const content = '# My research\n\nSome notes I wrote by hand.\n\n- point one\n- point two';

      final note = Note(
        id: 'n2',
        title: 'My research',
        content: content,
        tags: const ['dart', 'flutter'],
        keywords: const ['language', 'sdk'],
        isPinned: true,
        createdAt: DateTime.utc(2026, 5, 1),
        updatedAt: DateTime.utc(2026, 6, 1),
        embeddingPending: false,
      );

      final restored = Note.fromJson(note.toJson());

      expect(restored.content, equals(content));
      expect(restored.title, equals(note.title));
      expect(restored.tags, equals(note.tags));
      expect(restored.keywords, equals(note.keywords));
      expect(restored.isPinned, isTrue);
    });

    test('multi-section content with two metadata blocks is unchanged after round-trip', () {
      const content = '''<!-- grepink-generated-note
question: First question
generated_at: 2026-06-01T10:00:00.000000Z
action: createNewNote
source_count: 1
-->

## First Answer

Original content.

---

<!-- grepink-generated-note
question: Follow-up question
generated_at: 2026-06-01T11:00:00.000000Z
action: appendToExistingNote
source_count: 2
-->

## Update from question: Follow-up question

Additional content.''';

      final note = Note(
        id: 'n3',
        title: 'First question',
        content: content,
        tags: const [],
        keywords: const [],
        isPinned: false,
        createdAt: DateTime.utc(2026, 6, 1),
        updatedAt: DateTime.utc(2026, 6, 1),
        embeddingPending: false,
      );

      final json = jsonEncode(note.toJson());
      final restored = Note.fromJson(jsonDecode(json) as Map<String, dynamic>);

      expect(restored.content, equals(content));
      final metaOccurrences = '<!-- grepink-generated-note'.allMatches(restored.content).length;
      expect(metaOccurrences, 2);
    });
  });

  group('Sequential append round-trip', () {
    test('original metadata comment is present after first save', () async {
      final repo = _FakeRepo();
      final c = _container(repo);
      final notifier = c.read(noteDraftReviewProvider.notifier);

      notifier.startReview(_makeDraft(
        question: 'How does Dart work?',
        action: NoteDraftAction.createNewNote,
      ));
      await notifier.saveAsNewNote();

      expect(repo.stored, isNotNull);
      expect(repo.stored!.content, contains('<!-- grepink-generated-note'));
      expect(repo.stored!.content, contains('question: How does Dart work?'));
      expect(repo.stored!.content, contains('action: createNewNote'));
    });

    test('first metadata comment is preserved after appending a second draft', () async {
      final repo = _FakeRepo();
      final c = _container(repo);
      final notifier = c.read(noteDraftReviewProvider.notifier);

      // First save
      notifier.startReview(_makeDraft(
        question: 'How does Dart work?',
        action: NoteDraftAction.createNewNote,
      ));
      final firstNote = await notifier.saveAsNewNote();
      expect(firstNote, isNotNull);

      // Append a second draft to the same note
      notifier.startReview(_makeDraft(
        question: 'What is the Dart event loop?',
        action: NoteDraftAction.appendToExistingNote,
      ));
      notifier.selectTargetNote(firstNote!.id);
      final updatedNote = await notifier.appendToExistingNote();

      expect(updatedNote, isNotNull);
      final content = updatedNote!.content;

      // Both metadata comments must survive
      expect(content, contains('question: How does Dart work?'));
      expect(content, contains('question: What is the Dart event loop?'));
      expect(content, contains('action: createNewNote'));
      expect(content, contains('action: appendToExistingNote'));
      final metaCount = '<!-- grepink-generated-note'.allMatches(content).length;
      expect(metaCount, 2);
    });

    test('markdown content from both drafts is present after append', () async {
      final repo = _FakeRepo();
      final c = _container(repo);
      final notifier = c.read(noteDraftReviewProvider.notifier);

      notifier.startReview(_makeDraft(
        question: 'First question',
        action: NoteDraftAction.createNewNote,
        markdown: '## First\n\nOriginal answer content.',
      ));
      final firstNote = await notifier.saveAsNewNote();
      expect(firstNote, isNotNull);

      notifier.startReview(_makeDraft(
        question: 'Second question',
        action: NoteDraftAction.appendToExistingNote,
        markdown: '## Second\n\nAppended answer content.',
      ));
      notifier.selectTargetNote(firstNote!.id);
      final updatedNote = await notifier.appendToExistingNote();

      expect(updatedNote, isNotNull);
      final content = updatedNote!.content;
      expect(content, contains('Original answer content.'));
      expect(content, contains('Appended answer content.'));
      expect(content, contains('## Update from question: Second question'));
      expect(content, contains('---'));
    });

    test('source URL is preserved through saveAsNewNote and subsequent JSON round-trip', () async {
      final repo = _FakeRepo();
      final c = _container(repo);
      final notifier = c.read(noteDraftReviewProvider.notifier);

      notifier.startReview(_makeDraft(
        question: 'Source preservation test',
        action: NoteDraftAction.createNewNote,
        markdown: '## Answer\n\n[Source](https://example.com/article)',
      ));
      final note = await notifier.saveAsNewNote();
      expect(note, isNotNull);

      final restored = Note.fromJson(note!.toJson());

      expect(restored.content, contains('https://example.com/article'));
      expect(restored.content, contains('source_count: 1'));
    });
  });

  group('Metadata safety', () {
    test('no API keys or secret-like strings appear in exported content', () async {
      final repo = _FakeRepo();
      final c = _container(repo);
      final notifier = c.read(noteDraftReviewProvider.notifier);

      notifier.startReview(_makeDraft(
        question: 'Safety test',
        action: NoteDraftAction.createNewNote,
      ));
      final note = await notifier.saveAsNewNote();

      expect(note, isNotNull);
      final content = note!.content;
      expect(content, isNot(contains('apiKey')));
      expect(content, isNot(contains('api_key')));
      expect(content, isNot(contains('sk-')));
      expect(content, isNot(contains('Bearer ')));
    });

    test('question with double dashes is sanitized and metadata comment remains valid', () async {
      final repo = _FakeRepo();
      final c = _container(repo);
      final notifier = c.read(noteDraftReviewProvider.notifier);

      notifier.startReview(_makeDraft(
        question: 'What is -- the best approach?',
        action: NoteDraftAction.createNewNote,
      ));
      final note = await notifier.saveAsNewNote();

      expect(note, isNotNull);
      // The metadata comment block must open and close correctly
      final content = note!.content;
      expect(content, contains('<!-- grepink-generated-note'));
      expect(content, contains('-->'));
      // Double dashes in HTML comments would prematurely close them; verify escaped
      final commentStart = content.indexOf('<!-- grepink-generated-note');
      final commentEnd = content.indexOf('-->', commentStart);
      expect(commentEnd, greaterThan(commentStart));
      final commentBlock = content.substring(commentStart, commentEnd + 3);
      expect(commentBlock, isNot(contains('--\n')));
    });

    test('local-only evidence source count is accurate', () async {
      final repo = _FakeRepo();
      final c = _container(repo);
      final notifier = c.read(noteDraftReviewProvider.notifier);

      notifier.startReview(_makeDraft(
        question: 'Local sources only',
        action: NoteDraftAction.createNewNote,
        web: [],
        local: [_localEvidence],
      ));
      final note = await notifier.saveAsNewNote();

      expect(note, isNotNull);
      expect(note!.content, contains('source_count: 1'));
    });
  });
}
