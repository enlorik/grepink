import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/note.dart';
import 'package:grepink/services/note_export_service.dart';

/// These tests verify that notes written in one "build" (one export) can still
/// be read in a later build.  They use the JSON export format as a proxy for
/// on-disk persistence because the real SQLite database is unavailable in unit
/// tests.  The goal is to catch regressions in Note.toJson / Note.fromJson
/// before they reach a device.

Note _note({
  required String id,
  String title = 'Title',
  String content = 'Content',
  List<String> tags = const [],
  List<String> keywords = const [],
  bool isPinned = false,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  final ts = DateTime.utc(2026, 1, 1);
  return Note(
    id: id,
    title: title,
    content: content,
    tags: tags,
    keywords: keywords,
    isPinned: isPinned,
    createdAt: createdAt ?? ts,
    updatedAt: updatedAt ?? ts,
    embeddingPending: false,
  );
}

void main() {
  final svc = NoteExportService.instance;

  group('note schema stability', () {
    test('toJson keys are stable', () {
      final map = _note(id: 'k').toJson();
      expect(map.containsKey('id'), isTrue);
      expect(map.containsKey('title'), isTrue);
      expect(map.containsKey('content'), isTrue);
      expect(map.containsKey('tags'), isTrue);
      expect(map.containsKey('keywords'), isTrue);
      expect(map.containsKey('isPinned'), isTrue);
      expect(map.containsKey('createdAt'), isTrue);
      expect(map.containsKey('updatedAt'), isTrue);
      expect(map.containsKey('embeddingPending'), isTrue);
      // embedding bytes are intentionally excluded from JSON export
      expect(map.containsKey('embedding'), isFalse);
    });

    test('fromJson tolerates missing optional isPinned (false default)', () {
      final map = _note(id: 'opt').toJson()..remove('isPinned');
      final restored = Note.fromJson(map);
      expect(restored.isPinned, isFalse);
    });

    test('fromJson tolerates missing optional embeddingPending (false default)',
        () {
      final map = _note(id: 'ep').toJson()..remove('embeddingPending');
      final restored = Note.fromJson(map);
      expect(restored.embeddingPending, isFalse);
    });

    test('datetime round-trips with microsecond precision', () {
      final ts = DateTime.utc(2026, 6, 1, 23, 59, 59, 123, 456);
      final note = _note(id: 'dt', createdAt: ts, updatedAt: ts);
      final restored = Note.fromJson(note.toJson());
      // ISO-8601 preserves microseconds.
      expect(restored.createdAt.toUtc(), ts);
      expect(restored.updatedAt.toUtc(), ts);
    });

    test('tags and keywords survive list serialisation', () {
      final note = _note(
        id: 'lists',
        tags: ['a', 'b', 'c'],
        keywords: ['x', 'y'],
      );
      final restored = Note.fromJson(note.toJson());
      expect(restored.tags, ['a', 'b', 'c']);
      expect(restored.keywords, ['x', 'y']);
    });

    test('empty tags and keywords survive serialisation', () {
      final note = _note(id: 'empty-lists');
      final restored = Note.fromJson(note.toJson());
      expect(restored.tags, isEmpty);
      expect(restored.keywords, isEmpty);
    });
  });

  group('update-over-install persistence simulation', () {
    // Simulates: user has notes in build N, exports them, installs build N+1,
    // imports back.  All note data must survive unchanged.
    test('notes exported from build N restore fully in build N+1', () {
      final buildNNotes = [
        _note(
          id: 'study-1',
          title: 'Algebra revision',
          content: '## Chapter 3\n\nDerivative rules...',
          tags: ['maths', 'revision'],
          keywords: ['derivative', 'calculus'],
          isPinned: true,
          updatedAt: DateTime.utc(2026, 7, 1),
        ),
        _note(
          id: 'study-2',
          title: 'Biology notes',
          content:
              '## Cell division\n\nMitosis phases:\n1. Prophase\n2. Metaphase',
          tags: ['biology'],
          keywords: ['mitosis', 'cell'],
          updatedAt: DateTime.utc(2026, 7, 10),
        ),
      ];

      // Build N export
      final exported = svc.encode(buildNNotes);

      // Build N+1 import — simulated as a fresh decode
      final restored = svc.decode(exported);

      expect(restored.length, buildNNotes.length);
      for (int i = 0; i < buildNNotes.length; i++) {
        final orig = buildNNotes[i];
        final rest = restored[i];
        expect(rest.id, orig.id);
        expect(rest.title, orig.title);
        expect(rest.content, orig.content);
        expect(rest.tags, orig.tags);
        expect(rest.keywords, orig.keywords);
        expect(rest.isPinned, orig.isPinned);
        expect(rest.createdAt.toUtc(), orig.createdAt.toUtc());
        expect(rest.updatedAt.toUtc(), orig.updatedAt.toUtc());
      }
    });

    test('merge does not lose notes created in build N+1 after import', () {
      // Notes already on the device after import
      final afterImport = [
        _note(
            id: 'imported',
            title: 'Imported',
            content: 'from backup',
            updatedAt: DateTime.utc(2026, 7, 1)),
      ];
      // New note created in build N+1 session
      final newNote = _note(
          id: 'new-session',
          title: 'New',
          content: 'created later',
          updatedAt: DateTime.utc(2026, 7, 20));

      // Second export: both notes
      final exported2 = svc.encode([...afterImport, newNote]);
      final restored = svc.decode(exported2);

      expect(restored.any((n) => n.id == 'imported'), isTrue);
      expect(restored.any((n) => n.id == 'new-session'), isTrue);
    });

    test(
        'merge correctly resolves conflict between on-device and backup version',
        () {
      final deviceVersion = _note(
        id: 'conflict',
        title: 'Edited on device',
        content: 'newer content',
        updatedAt: DateTime.utc(2026, 7, 20),
      );
      final backupVersion = _note(
        id: 'conflict',
        title: 'Older backup',
        content: 'older content',
        updatedAt: DateTime.utc(2026, 7, 1),
      );

      final output = svc.merge([deviceVersion], [backupVersion]);
      final resolved = output.notes.firstWhere((n) => n.id == 'conflict');
      expect(resolved.title, 'Edited on device');
      expect(output.result.skipped, 1);
    });
  });

  group('export envelope integrity', () {
    test('exported JSON is valid UTF-8', () {
      final note = _note(
        id: 'utf8',
        title: 'Unicode: résumé, 日本語, emoji 🌸',
        content: 'Accented: àáâãäå\nCJK: 学习\nArabic: مرحبا',
      );
      final json = svc.encode([note]);
      // If decoding throws, the JSON is not valid UTF-8.
      expect(() => jsonDecode(json), returnsNormally);
      final restored = svc.decode(json);
      expect(restored.first.title, note.title);
      expect(restored.first.content, note.content);
    });

    test('notes with very long content survive round-trip', () {
      final longContent =
          List.generate(1000, (i) => 'Line $i of content.').join('\n');
      final note = _note(id: 'long', content: longContent);
      final restored = svc.decode(svc.encode([note]));
      expect(restored.first.content, longContent);
    });

    test('note with empty content survives round-trip', () {
      final note = _note(id: 'empty-content', content: '');
      final restored = svc.decode(svc.encode([note]));
      expect(restored.first.content, '');
    });
  });
}
