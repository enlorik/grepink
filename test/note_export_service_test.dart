import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/note.dart';
import 'package:grepink/services/note_export_service.dart';

Note _note({
  required String id,
  required String title,
  required String content,
  DateTime? createdAt,
  DateTime? updatedAt,
  List<String> tags = const [],
  bool isPinned = false,
}) {
  final now = DateTime.utc(2026, 1, 1);
  return Note(
    id: id,
    title: title,
    content: content,
    tags: tags,
    keywords: const [],
    isPinned: isPinned,
    createdAt: createdAt ?? now,
    updatedAt: updatedAt ?? now,
    embeddingPending: false,
  );
}

void main() {
  final svc = NoteExportService.instance;

  group('encode / decode round-trip', () {
    test('empty list survives round-trip', () {
      final json = svc.encode([]);
      final decoded = svc.decode(json);
      expect(decoded, isEmpty);
    });

    test('single note survives round-trip', () {
      final note = _note(id: 'n1', title: 'Hello', content: '# Hello\nWorld');
      final json = svc.encode([note]);
      final decoded = svc.decode(json);

      expect(decoded.length, 1);
      expect(decoded.first.id, note.id);
      expect(decoded.first.title, note.title);
      expect(decoded.first.content, note.content);
    });

    test('all note fields survive round-trip', () {
      final created = DateTime.utc(2025, 3, 15, 10, 0, 0);
      final updated = DateTime.utc(2026, 6, 1, 12, 30, 0);
      final note = _note(
        id: 'full-1',
        title: 'Full fields',
        content: '<!-- grepink-generated-note\nquestion: test\n-->\n\nContent',
        tags: ['dart', 'flutter'],
        isPinned: true,
        createdAt: created,
        updatedAt: updated,
      );
      final decoded = svc.decode(svc.encode([note]));
      final r = decoded.first;

      expect(r.tags, ['dart', 'flutter']);
      expect(r.isPinned, isTrue);
      expect(r.createdAt.toUtc(), created);
      expect(r.updatedAt.toUtc(), updated);
    });

    test('exported JSON contains version and exported_at', () {
      final json = svc.encode([_note(id: 'x', title: 'X', content: 'x')]);
      final map = jsonDecode(json) as Map<String, dynamic>;
      expect(map['version'], 1);
      expect(map['exported_at'], isA<String>());
    });

    test('multiple notes survive round-trip preserving order', () {
      final notes = List.generate(
        5,
        (i) => _note(id: 'n$i', title: 'Note $i', content: 'content $i'),
      );
      final decoded = svc.decode(svc.encode(notes));
      expect(decoded.length, 5);
      for (int i = 0; i < 5; i++) {
        expect(decoded[i].id, 'n$i');
      }
    });
  });

  group('decode rejects malformed input', () {
    test('throws on empty string', () {
      expect(() => svc.decode(''), throwsFormatException);
    });

    test('throws on plain text', () {
      expect(() => svc.decode('not json at all'), throwsFormatException);
    });

    test('throws on JSON array at top level', () {
      expect(() => svc.decode('[]'), throwsFormatException);
    });

    test('throws when version is missing', () {
      expect(
        () => svc.decode(jsonEncode({'notes': []})),
        throwsFormatException,
      );
    });

    test('throws when version is wrong', () {
      expect(
        () => svc.decode(jsonEncode({'version': 99, 'exported_at': '', 'notes': []})),
        throwsFormatException,
      );
    });

    test('throws when notes array is missing', () {
      expect(
        () => svc.decode(jsonEncode({'version': 1, 'exported_at': ''})),
        throwsFormatException,
      );
    });

    test('throws when notes is not a list', () {
      expect(
        () => svc.decode(jsonEncode({'version': 1, 'exported_at': '', 'notes': 'oops'})),
        throwsFormatException,
      );
    });

    test('throws when a note entry is not an object', () {
      expect(
        () => svc.decode(jsonEncode({'version': 1, 'exported_at': '', 'notes': [42]})),
        throwsFormatException,
      );
    });

    test('throws when a note entry is missing required fields', () {
      expect(
        () => svc.decode(jsonEncode({
          'version': 1,
          'exported_at': '',
          'notes': [
            {'id': 'x'} // missing title, content, etc.
          ],
        })),
        throwsFormatException,
      );
    });
  });

  group('merge behaviour', () {
    final older = DateTime.utc(2026, 1, 1);
    final newer = DateTime.utc(2026, 6, 1);

    test('new note in incoming is added', () {
      final existing = [_note(id: 'a', title: 'A', content: 'a')];
      final incoming = [_note(id: 'b', title: 'B', content: 'b')];
      final output = svc.merge(existing, incoming);

      expect(output.notes.map((n) => n.id), containsAll(['a', 'b']));
      expect(output.result.added, 1);
      expect(output.result.updated, 0);
      expect(output.result.skipped, 0);
    });

    test('incoming beats existing when newer', () {
      final existing = [_note(id: 'x', title: 'Old title', content: 'old', updatedAt: older)];
      final incoming = [_note(id: 'x', title: 'New title', content: 'new', updatedAt: newer)];
      final output = svc.merge(existing, incoming);

      final merged = output.notes.firstWhere((n) => n.id == 'x');
      expect(merged.title, 'New title');
      expect(output.result.updated, 1);
      expect(output.result.skipped, 0);
    });

    test('existing wins when incoming is older', () {
      final existing = [_note(id: 'x', title: 'Current', content: 'current', updatedAt: newer)];
      final incoming = [_note(id: 'x', title: 'Stale', content: 'stale', updatedAt: older)];
      final output = svc.merge(existing, incoming);

      final merged = output.notes.firstWhere((n) => n.id == 'x');
      expect(merged.title, 'Current');
      expect(output.result.skipped, 1);
      expect(output.result.updated, 0);
    });

    test('existing wins when timestamps are identical', () {
      final ts = DateTime.utc(2026, 3, 1);
      final existing = [_note(id: 'x', title: 'Existing', content: 'existing', updatedAt: ts)];
      final incoming = [_note(id: 'x', title: 'Incoming', content: 'incoming', updatedAt: ts)];
      final output = svc.merge(existing, incoming);

      final merged = output.notes.firstWhere((n) => n.id == 'x');
      expect(merged.title, 'Existing');
      expect(output.result.skipped, 1);
    });

    test('existing-only notes are preserved', () {
      final existing = [
        _note(id: 'keep', title: 'Keep me', content: 'keep'),
      ];
      final output = svc.merge(existing, []);

      expect(output.notes.any((n) => n.id == 'keep'), isTrue);
      expect(output.result.added, 0);
    });

    test('mixed merge — add, update, skip', () {
      final existing = [
        _note(id: 'keep', title: 'Keep', content: 'keep', updatedAt: newer),
        _note(id: 'update', title: 'Old', content: 'old', updatedAt: older),
      ];
      final incoming = [
        _note(id: 'new', title: 'New', content: 'new'),
        _note(id: 'update', title: 'Updated', content: 'updated', updatedAt: newer),
        _note(id: 'keep', title: 'Stale', content: 'stale', updatedAt: older),
      ];
      final output = svc.merge(existing, incoming);

      expect(output.result.added, 1);
      expect(output.result.updated, 1);
      expect(output.result.skipped, 1);

      final updated = output.notes.firstWhere((n) => n.id == 'update');
      expect(updated.title, 'Updated');

      final kept = output.notes.firstWhere((n) => n.id == 'keep');
      expect(kept.title, 'Keep');
    });
  });

  group('preview', () {
    final older = DateTime.utc(2026, 1, 1);
    final newer = DateTime.utc(2026, 6, 1);

    test('counts match merge behaviour', () {
      final existing = [
        _note(id: 'skip-me', title: 'A', content: 'a', updatedAt: newer),
        _note(id: 'update-me', title: 'B', content: 'b', updatedAt: older),
      ];
      final incoming = [
        _note(id: 'add-me', title: 'C', content: 'c'),
        _note(id: 'skip-me', title: 'Stale', content: 'stale', updatedAt: older),
        _note(id: 'update-me', title: 'Newer', content: 'newer', updatedAt: newer),
      ];
      final p = svc.preview(existing, incoming);

      expect(p.total, 3);
      expect(p.willAdd, 1);
      expect(p.willUpdate, 1);
      expect(p.willSkip, 1);
    });

    test('all-new import has add = total, update = 0, skip = 0', () {
      final incoming = [
        _note(id: 'a', title: 'A', content: 'a'),
        _note(id: 'b', title: 'B', content: 'b'),
      ];
      final p = svc.preview([], incoming);

      expect(p.total, 2);
      expect(p.willAdd, 2);
      expect(p.willUpdate, 0);
      expect(p.willSkip, 0);
    });
  });

  group('note content safety', () {
    test('exported JSON does not contain API key patterns', () {
      final note = _note(
        id: 'safe',
        title: 'Safe test',
        content: 'This note has no secrets.',
      );
      final json = svc.encode([note]);
      expect(json, isNot(contains('sk-')));
      expect(json, isNot(contains('Bearer ')));
      expect(json, isNot(contains('api_key')));
    });

    test('note with HTML comment metadata exports and imports cleanly', () {
      const content = '''<!-- grepink-generated-note
question: What is Flutter?
generated_at: 2026-01-01T00:00:00.000000Z
action: createNewNote
source_count: 1
-->

## Answer

Flutter is a UI toolkit.''';

      final note = _note(id: 'meta', title: 'Flutter', content: content);
      final decoded = svc.decode(svc.encode([note]));
      expect(decoded.first.content, content);
      expect(decoded.first.content, contains('<!-- grepink-generated-note'));
    });
  });
}
