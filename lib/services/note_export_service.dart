import 'dart:convert';
import '../models/note.dart';
import '../models/tombstone.dart';

// Current export version. Version 1 payloads (notes only) are still readable.
const _exportVersion = 2;
const _exportKey = 'notes';
const _tombstonesKey = 'tombstones';
const _replacedAtKey = 'replacedAt';
const _versionKey = 'version';
const _exportedAtKey = 'exported_at';

/// Result of decoding a sync payload — contains notes, tombstones, and an
/// optional authoritative-replacement timestamp.
class SyncPayload {
  final List<Note> notes;
  final List<Tombstone> tombstones;
  // Non-null when this payload is an authoritative "Replace all" reset.
  // All notes and tombstones on the receiving device that predate this
  // timestamp are superseded by the incoming data.
  final int? replacedAt; // milliseconds since epoch

  const SyncPayload({
    required this.notes,
    this.tombstones = const [],
    this.replacedAt,
  });
}

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

  /// Encodes [notes] as a version-2 sync payload with optional [tombstones]
  /// and [replacedAt] for authoritative-replacement semantics.
  String encode(
    List<Note> notes, {
    List<Tombstone> tombstones = const [],
    int? replacedAt,
  }) {
    final payload = <String, dynamic>{
      _versionKey: _exportVersion,
      _exportedAtKey: DateTime.now().toUtc().toIso8601String(),
      _exportKey: notes.map((n) => n.toJson()).toList(),
      _tombstonesKey: tombstones.map((t) => t.toJson()).toList(),
    };
    if (replacedAt != null) {
      payload[_replacedAtKey] = replacedAt;
    }
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Decodes a sync payload (version 1 or 2) and returns notes, tombstones,
  /// and an optional replacedAt timestamp.
  SyncPayload decodePayload(String json) {
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
    if (version is! int || (version != 1 && version != 2)) {
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
        notes.add(Note.fromJson(entry));
      } catch (e) {
        throw FormatException('Note at index $i is malformed: $e');
      }
    }

    // Version 2 extras
    List<Tombstone> tombstones = const [];
    int? replacedAt;
    if (version == 2) {
      final ts = raw[_tombstonesKey];
      if (ts is List) {
        tombstones = ts.map((t) {
          if (t is Map<String, dynamic>) return Tombstone.fromJson(t);
          throw const FormatException('Tombstone entry is not an object');
        }).toList();
      }
      final rat = raw[_replacedAtKey];
      if (rat is int) replacedAt = rat;
    }

    return SyncPayload(
        notes: notes, tombstones: tombstones, replacedAt: replacedAt);
  }

  /// Convenience wrapper that returns only the notes list (for import UI).
  List<Note> decode(String json) => decodePayload(json).notes;

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
        merged[note.id] =
            note.copyWith(embeddingPending: true, clearEmbedding: true);
        added++;
      } else if (note.updatedAt.isAfter(current.updatedAt)) {
        merged[note.id] =
            note.copyWith(embeddingPending: true, clearEmbedding: true);
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
