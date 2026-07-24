import 'dart:convert';
import '../models/note.dart';

const _exportVersion = 1;
const _exportKey = 'notes';
const _versionKey = 'version';
const _exportedAtKey = 'exported_at';

class ImportPreview {
  final int total;
  final int willAdd;
  final int willUpdate;
  final int willSkip;

  const ImportPreview({
    required this.total,
    required this.willAdd,
    required this.willUpdate,
    required this.willSkip,
  });
}

class ImportResult {
  final int added;
  final int updated;
  final int skipped;

  const ImportResult({
    required this.added,
    required this.updated,
    required this.skipped,
  });
}

class NoteExportService {
  NoteExportService._();
  static final NoteExportService instance = NoteExportService._();

  String encode(List<Note> notes) {
    final payload = {
      _versionKey: _exportVersion,
      _exportedAtKey: DateTime.now().toUtc().toIso8601String(),
      _exportKey: notes.map((n) => n.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  List<Note> decode(String json) {
    final Object? raw;
    try {
      raw = jsonDecode(json);
    } catch (e) {
      throw FormatException('Not valid JSON: $e');
    }
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Expected a JSON object at the top level');
    }
    final version = raw[_versionKey];
    if (version is! int || version != _exportVersion) {
      throw FormatException('Unsupported export version: $version');
    }
    final notesList = raw[_exportKey];
    if (notesList is! List) {
      throw const FormatException('Missing or invalid "notes" array');
    }
    final notes = <Note>[];
    for (int i = 0; i < notesList.length; i++) {
      final entry = notesList[i];
      if (entry is! Map<String, dynamic>) {
        throw FormatException('Note at index $i is not an object');
      }
      try {
        final imported = Note.fromJson(entry);
        // Export JSON intentionally omits the embedding vector, so every
        // imported note must be queued for reindexing regardless of the source
        // device's previous embeddingPending flag.
        notes.add(
          imported.copyWith(
            embeddingPending: true,
            clearEmbedding: true,
          ),
        );
      } catch (e) {
        throw FormatException('Note at index $i is malformed: $e');
      }
    }
    return notes;
  }

  ImportPreview preview(List<Note> existing, List<Note> incoming) {
    final existingById = {for (final n in existing) n.id: n};
    int willAdd = 0;
    int willUpdate = 0;
    int willSkip = 0;
    for (final note in incoming) {
      final current = existingById[note.id];
      if (current == null) {
        willAdd++;
      } else if (note.updatedAt.isAfter(current.updatedAt)) {
        willUpdate++;
      } else {
        willSkip++;
      }
    }
    return ImportPreview(
      total: incoming.length,
      willAdd: willAdd,
      willUpdate: willUpdate,
      willSkip: willSkip,
    );
  }

  /// Merge: incoming wins only when its updatedAt is strictly newer.
  MergeOutput merge(List<Note> existing, List<Note> incoming) {
    final existingById = {for (final n in existing) n.id: n};
    final merged = Map<String, Note>.from(existingById);
    int added = 0;
    int updated = 0;
    int skipped = 0;
    for (final note in incoming) {
      final current = merged[note.id];
      if (current == null) {
        merged[note.id] = note;
        added++;
      } else if (note.updatedAt.isAfter(current.updatedAt)) {
        merged[note.id] = note;
        updated++;
      } else {
        skipped++;
      }
    }
    return MergeOutput(
      notes: merged.values.toList(),
      result: ImportResult(added: added, updated: updated, skipped: skipped),
    );
  }
}

class MergeOutput {
  final List<Note> notes;
  final ImportResult result;

  const MergeOutput({required this.notes, required this.result});
}
