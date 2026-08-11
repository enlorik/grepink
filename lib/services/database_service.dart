import 'dart:async';
import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/note.dart';
import '../models/tombstone.dart';

class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'grepink.db');
    return openDatabase(
      path,
      version: 2,
      onConfigure: (db) async {
        // WAL mode keeps the main DB file clean between checkpoints, so
        // Android Auto Backup always captures a consistent snapshot.
        await db.execute('PRAGMA journal_mode=WAL');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE notes (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        tags TEXT NOT NULL DEFAULT '[]',
        keywords TEXT NOT NULL DEFAULT '[]',
        is_pinned INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        embedding BLOB,
        embedding_pending INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE VIRTUAL TABLE notes_fts USING fts5(
        id UNINDEXED,
        title,
        content,
        tags,
        keywords,
        content='notes',
        content_rowid='rowid'
      )
    ''');

    // Triggers to keep FTS in sync
    await db.execute('''
      CREATE TRIGGER notes_ai AFTER INSERT ON notes BEGIN
        INSERT INTO notes_fts(rowid, id, title, content, tags, keywords)
        VALUES (new.rowid, new.id, new.title, new.content, new.tags, new.keywords);
      END
    ''');

    await db.execute('''
      CREATE TRIGGER notes_ad AFTER DELETE ON notes BEGIN
        INSERT INTO notes_fts(notes_fts, rowid, id, title, content, tags, keywords)
        VALUES ('delete', old.rowid, old.id, old.title, old.content, old.tags, old.keywords);
      END
    ''');

    await db.execute('''
      CREATE TRIGGER notes_au AFTER UPDATE ON notes BEGIN
        INSERT INTO notes_fts(notes_fts, rowid, id, title, content, tags, keywords)
        VALUES ('delete', old.rowid, old.id, old.title, old.content, old.tags, old.keywords);
        INSERT INTO notes_fts(rowid, id, title, content, tags, keywords)
        VALUES (new.rowid, new.id, new.title, new.content, new.tags, new.keywords);
      END
    ''');

    await _createTombstonesTable(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createTombstonesTable(db);
    }
  }

  Future<void> _createTombstonesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tombstones (
        id TEXT PRIMARY KEY,
        deleted_at INTEGER NOT NULL
      )
    ''');
  }

  Future<void> insertNote(Note note) async {
    final db = await database;
    await db.insert(
      'notes',
      note.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateNote(Note note) async {
    final db = await database;
    await db.update(
      'notes',
      note.toMap(),
      where: 'id = ?',
      whereArgs: [note.id],
    );
  }

  // Atomically deletes a note and records a tombstone in one transaction.
  Future<void> deleteNote(String id) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.delete('notes', where: 'id = ?', whereArgs: [id]);
      await txn.insert(
        'tombstones',
        {'id': id, 'deleted_at': now},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<Note?> getNoteById(String id) async {
    final db = await database;
    final maps = await db.query('notes', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Note.fromMap(maps.first);
  }

  Future<List<Note>> getAllNotes() async {
    final db = await database;
    final maps = await db.query(
      'notes',
      orderBy: 'is_pinned DESC, updated_at DESC',
    );
    return maps.map(Note.fromMap).toList();
  }

  Future<List<Tombstone>> getTombstones() async {
    final db = await database;
    final rows = await db.query('tombstones');
    return rows
        .map((r) => Tombstone(
              id: r['id'] as String,
              deletedAt: r['deleted_at'] as int,
            ))
        .toList();
  }

  // Inserts tombstones from an incoming sync payload without deleting notes.
  // Used when receiving tombstones that originated on another device.
  Future<void> insertTombstones(List<Tombstone> tombstones) async {
    if (tombstones.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      for (final t in tombstones) {
        await txn.insert(
          'tombstones',
          {'id': t.id, 'deleted_at': t.deletedAt},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  // Removes tombstones created before [cutoffMs] so they do not accumulate.
  Future<void> clearTombstonesOlderThan(int cutoffMs) async {
    final db = await database;
    await db
        .delete('tombstones', where: 'deleted_at < ?', whereArgs: [cutoffMs]);
  }

  Future<List<Map<String, dynamic>>> searchFts(String query) async {
    final db = await database;
    if (query.trim().isEmpty) return [];
    // Sanitize for FTS5 query
    final sanitized = query.trim().replaceAll('"', '""');
    try {
      final results = await db.rawQuery(
        '''
        SELECT n.*, bm25(notes_fts) as fts_rank
        FROM notes n
        JOIN notes_fts ON notes_fts.id = n.id
        WHERE notes_fts MATCH ?
        ORDER BY fts_rank
        LIMIT 20
        ''',
        ['"$sanitized"*'],
      );
      return results;
    } catch (_) {
      // Fallback: try phrase match without wildcard
      try {
        final results = await db.rawQuery(
          '''
          SELECT n.*, bm25(notes_fts) as fts_rank
          FROM notes n
          JOIN notes_fts ON notes_fts.id = n.id
          WHERE notes_fts MATCH ?
          ORDER BY fts_rank
          LIMIT 20
          ''',
          [sanitized],
        );
        return results;
      } catch (_) {
        return [];
      }
    }
  }

  Future<List<Note>> getAllNotesWithEmbeddings() async {
    final db = await database;
    final maps = await db.query(
      'notes',
      where: 'embedding IS NOT NULL AND embedding_pending = 0',
    );
    return maps.map(Note.fromMap).toList();
  }

  Future<List<Note>> getNotesWithPendingEmbeddings() async {
    final db = await database;
    final maps = await db.query(
      'notes',
      where: 'embedding_pending = 1',
    );
    return maps.map(Note.fromMap).toList();
  }

  Future<void> updateEmbedding(String noteId, List<double> embedding) async {
    final db = await database;
    final float32 = Float32List.fromList(embedding);
    final bytes = float32.buffer.asUint8List();
    await db.update(
      'notes',
      {'embedding': bytes, 'embedding_pending': 0},
      where: 'id = ?',
      whereArgs: [noteId],
    );
  }

  // Atomically deletes all notes and writes tombstones for each deleted note.
  Future<void> clearAll() async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      final rows = await txn.query('notes', columns: ['id']);
      await txn.delete('notes');
      await txn.execute('DELETE FROM notes_fts');
      for (final row in rows) {
        final id = row['id'] as String;
        await txn.insert(
          'tombstones',
          {'id': id, 'deleted_at': now},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  /// Atomically replaces all notes. Either every note from [notes] is written
  /// or the existing data is left completely intact (no partial import).
  /// Tombstones for replaced notes are NOT written here — the replacedAt
  /// timestamp in the sync payload serves as the authoritative-reset marker.
  Future<void> replaceAll(List<Note> notes) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('notes');
      await txn.execute('DELETE FROM notes_fts');
      for (final note in notes) {
        await txn.insert('notes', note.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  /// Atomically merges [incoming] notes into the database.
  /// Incoming wins only when its updatedAt is strictly newer than the row
  /// currently in the database (re-read inside the transaction to avoid TOCTOU).
  /// Returns the counts of added, updated, and skipped notes.
  Future<({int added, int updated, int skipped})> mergeNotes(
    List<Note> existing,
    List<Note> incoming,
  ) async {
    final db = await database;
    int added = 0, updated = 0, skipped = 0;
    await db.transaction((txn) async {
      for (final note in incoming) {
        final rows = await txn.query(
          'notes',
          columns: ['id', 'updated_at'],
          where: 'id = ?',
          whereArgs: [note.id],
          limit: 1,
        );
        final toWrite =
            note.copyWith(embeddingPending: true, clearEmbedding: true);
        if (rows.isEmpty) {
          // Guard against resurrection: if a local tombstone for this note
          // is at least as recent as the incoming note's updatedAt, the local
          // deletion wins and the note is not re-inserted.
          final tombRows = await txn.query(
            'tombstones',
            columns: ['deleted_at'],
            where: 'id = ?',
            whereArgs: [note.id],
            limit: 1,
          );
          if (tombRows.isNotEmpty) {
            final deletedAtMs = tombRows.first['deleted_at'] as int;
            if (deletedAtMs >= note.updatedAt.millisecondsSinceEpoch) {
              skipped++;
              continue;
            }
            // Incoming note is newer than the local deletion — override.
            await txn
                .delete('tombstones', where: 'id = ?', whereArgs: [note.id]);
          }
          await txn.insert('notes', toWrite.toMap(),
              conflictAlgorithm: ConflictAlgorithm.replace);
          added++;
        } else {
          final currentUpdatedAt =
              DateTime.parse(rows.first['updated_at'] as String);
          if (note.updatedAt.isAfter(currentUpdatedAt)) {
            await txn.update('notes', toWrite.toMap(),
                where: 'id = ?', whereArgs: [note.id]);
            updated++;
          } else {
            skipped++;
          }
        }
      }
    });
    return (added: added, updated: updated, skipped: skipped);
  }

  Future<void> reindexFts() async {
    final db = await database;
    await db.execute('INSERT INTO notes_fts(notes_fts) VALUES(\'rebuild\')');
  }
}
