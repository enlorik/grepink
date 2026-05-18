import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/note.dart';

Note _note({
  required String id,
  required String title,
  required String content,
}) {
  final now = DateTime.utc(2026, 5, 18, 3, 45);
  return Note(
    id: id,
    title: title,
    content: content,
    tags: const ['knowledge'],
    keywords: const ['grepink'],
    isPinned: false,
    createdAt: now,
    updatedAt: now,
    embeddingPending: false,
  );
}

Note _roundTrip(Note note) {
  final encoded = jsonEncode(note.toJson());
  final decoded = jsonDecode(encoded) as Map<String, dynamic>;
  return Note.fromJson(decoded);
}

void main() {
  group('Note export/import round trip', () {
    test('generated note source URLs survive export/import', () {
      final note = _note(
        id: 'generated-1',
        title: 'Generated note',
        content: '''<!-- grepink-generated-note
question: What changed?
generated_at: 2026-05-18T01:45:00.000Z
action: createNewNote
source_count: 2
-->

# Draft

- Claim with source https://example.com/source
- Another source https://example.com/extra''',
      );

      final restored = _roundTrip(note);

      expect(restored.content, contains('https://example.com/source'));
      expect(restored.content, contains('https://example.com/extra'));
    });

    test('generated note metadata survives export/import', () {
      final note = _note(
        id: 'generated-2',
        title: 'Generated note',
        content: '''<!-- grepink-generated-note
question: What changed?
generated_at: 2026-05-18T01:45:00.000Z
action: appendToExistingNote
source_count: 1
-->

## Update from question: What changed?

- Durable claim''',
      );

      final restored = _roundTrip(note);

      expect(restored.content, contains('<!-- grepink-generated-note'));
      expect(restored.content, contains('question: What changed?'));
      expect(restored.content, contains('action: appendToExistingNote'));
      expect(restored.content, contains('source_count: 1'));
    });

    test('regular notes still round-trip unchanged', () {
      final note = _note(
        id: 'regular-1',
        title: 'Regular note',
        content: '# Plain note\n\nJust a normal note body.',
      );

      final restored = _roundTrip(note);

      expect(restored.toJson(), note.toJson());
    });

    test('empty note content is handled safely', () {
      final note = _note(
        id: 'empty-1',
        title: 'Empty note',
        content: '',
      );

      final restored = _roundTrip(note);

      expect(restored.content, isEmpty);
      expect(restored.title, 'Empty note');
    });
  });
}
