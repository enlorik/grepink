import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../models/note.dart';

const _uuid = Uuid();

class OutboxEntry {
  final int seq;
  final String mutationId;
  final String noteId;
  final String operation; // 'upsert' | 'delete'
  final String? payload; // JSON for upsert, null for delete
  final int? baseRevision; // remote revision to CAS against
  final String createdAt;

  const OutboxEntry({
    required this.seq,
    required this.mutationId,
    required this.noteId,
    required this.operation,
    this.payload,
    this.baseRevision,
    required this.createdAt,
  });

  factory OutboxEntry.fromMap(Map<String, dynamic> map) => OutboxEntry(
        seq: map['seq'] as int,
        mutationId: map['mutation_id'] as String,
        noteId: map['note_id'] as String,
        operation: map['operation'] as String,
        payload: map['payload'] as String?,
        baseRevision: map['base_revision'] as int?,
        createdAt: map['created_at'] as String,
      );

  Map<String, dynamic> toMutationJson() {
    final base = <String, dynamic>{
      'mutationId': mutationId,
      'noteId': noteId,
      'operation': operation,
      'baseRevision': baseRevision,
    };
    if (operation == 'upsert' && payload != null) {
      base['payload'] = jsonDecode(payload!);
    }
    return base;
  }
}

Map<String, dynamic> _noteToSyncPayload(Note note) => {
      'title': note.title,
      'content': note.content,
      'tags': note.tags,
      'keywords': note.keywords,
      'isPinned': note.isPinned,
      'createdAt': note.createdAt.toUtc().toIso8601String(),
      'updatedAt': note.updatedAt.toUtc().toIso8601String(),
    };

class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  Database? _db;

  // Override the database path in tests (e.g. inMemoryDatabasePath).
  @visibleForTesting
  static String? testDatabasePath;

  // Close the current database so the next [database] call reopens it fresh.
  // Use in test tearDown to achieve isolation between tests.
  @visibleForTesting
  Future<void> closeForTesting() async {
    await _db?.close();
    _db = null;
  }

  Future<Database> get database async {
    _db ??= await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final String path;
    if (testDatabasePath != null) {
      path = testDatabasePath!;
    } else {
      final dbPath = await getDatabasesPath();
      path = p.join(dbPath, 'grepink.db');
    }
    return openDatabase(
      path,
      version: 2,
      onConfigure: (db) async {
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

    await _createSyncTables(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createSyncTables(db);
      // Backfill existing notes so they reach an empty server.
      await _backfillOutbox(db);
    }
  }

  Future<void> _createSyncTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_outbox (
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        mutation_id TEXT NOT NULL UNIQUE,
        note_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        payload TEXT,
        base_revision INTEGER,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS note_remote_versions (
        note_id TEXT PRIMARY KEY,
        remote_revision INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _backfillOutbox(Database db) async {
    final notes = await db.query('notes', columns: [
      'id',
      'title',
      'content',
      'tags',
      'keywords',
      'is_pinned',
      'created_at',
      'updated_at',
    ]);
    final now = DateTime.now().toUtc().toIso8601String();
    for (final row in notes) {
      final note = Note.fromMap({
        ...row,
        'embedding': null,
        'embedding_pending': 0,
      });
      await db.insert(
        'sync_outbox',
        {
          'mutation_id': _uuid.v4(),
          'note_id': note.id,
          'operation': 'upsert',
          'payload': jsonEncode(_noteToSyncPayload(note)),
          'base_revision': null,
          'created_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Note mutations (also write outbox entries)
  // ---------------------------------------------------------------------------

  Future<void> insertNote(Note note, {String? mutationId}) async {
    final db = await database;
    final mid = mutationId ?? _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    final baseRev = await _remoteRevision(db, note.id);
    await db.transaction((txn) async {
      await txn.insert(
        'notes',
        note.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _writeOutbox(txn, mid, note.id, 'upsert',
          payload: jsonEncode(_noteToSyncPayload(note)),
          baseRevision: baseRev,
          createdAt: now);
    });
  }

  Future<void> updateNote(Note note, {String? mutationId}) async {
    final db = await database;
    final mid = mutationId ?? _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    final baseRev = await _remoteRevision(db, note.id);
    await db.transaction((txn) async {
      await txn.update(
        'notes',
        note.toMap(),
        where: 'id = ?',
        whereArgs: [note.id],
      );
      await _writeOutbox(txn, mid, note.id, 'upsert',
          payload: jsonEncode(_noteToSyncPayload(note)),
          baseRevision: baseRev,
          createdAt: now);
    });
  }

  Future<void> deleteNote(String id, {String? mutationId}) async {
    final db = await database;
    final mid = mutationId ?? _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    final baseRev = await _remoteRevision(db, id);
    await db.transaction((txn) async {
      await txn.delete('notes', where: 'id = ?', whereArgs: [id]);
      await _writeOutbox(txn, mid, id, 'delete',
          baseRevision: baseRev, createdAt: now);
    });
  }

  // ---------------------------------------------------------------------------
  // Remote-applied mutations — never generate outbox entries
  // ---------------------------------------------------------------------------

  Future<void> applyRemoteUpsert(
    Note note,
    int remoteRevision, {
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? (await database);
    final toWrite =
        note.copyWith(embeddingPending: true, clearEmbedding: true);
    await executor.insert(
      'notes',
      toWrite.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await executor.insert(
      'note_remote_versions',
      {'note_id': note.id, 'remote_revision': remoteRevision},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> applyRemoteTombstone(
    String noteId,
    int remoteRevision, {
    DatabaseExecutor? txn,
  }) async {
    final executor = txn ?? (await database);
    await executor.delete('notes', where: 'id = ?', whereArgs: [noteId]);
    await executor.insert(
      'note_remote_versions',
      {'note_id': noteId, 'remote_revision': remoteRevision},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---------------------------------------------------------------------------
  // Outbox management
  // ---------------------------------------------------------------------------

  Future<void> _writeOutbox(
    DatabaseExecutor txn,
    String mutationId,
    String noteId,
    String operation, {
    String? payload,
    int? baseRevision,
    required String createdAt,
  }) async {
    // If a pending outbox entry for this note already exists, update it in place
    // rather than stacking a second entry. This merges rapid local edits.
    final existing = await txn.query(
      'sync_outbox',
      where: 'note_id = ? AND operation = ?',
      whereArgs: [noteId, operation],
      orderBy: 'seq ASC',
      limit: 1,
    );
    if (existing.isNotEmpty && operation == 'upsert') {
      // Update the existing pending upsert with the latest payload.
      await txn.update(
        'sync_outbox',
        {
          'mutation_id': mutationId,
          'payload': payload,
          'created_at': createdAt,
        },
        where: 'seq = ?',
        whereArgs: [existing.first['seq']],
      );
    } else {
      await txn.insert(
        'sync_outbox',
        {
          'mutation_id': mutationId,
          'note_id': noteId,
          'operation': operation,
          'payload': payload,
          'base_revision': baseRevision,
          'created_at': createdAt,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> resetSyncState() async {
    final db = await database;
    await db.delete('note_remote_versions');
    await db.delete('sync_outbox');
    await _backfillOutbox(db);
  }

  Future<List<OutboxEntry>> getOutboxEntries() async {
    final db = await database;
    final rows = await db.query('sync_outbox', orderBy: 'seq ASC');
    return rows.map(OutboxEntry.fromMap).toList();
  }

  Future<void> removeOutboxEntry(int seq, String mutationId) async {
    final db = await database;
    await db.delete(
      'sync_outbox',
      where: 'seq = ? AND mutation_id = ?',
      whereArgs: [seq, mutationId],
    );
  }

  Future<void> updateOutboxBaseRevision(int seq, int newBaseRevision) async {
    final db = await database;
    await db.update(
      'sync_outbox',
      {'base_revision': newBaseRevision},
      where: 'seq = ?',
      whereArgs: [seq],
    );
  }

  Future<void> setRemoteRevision(String noteId, int revision) async {
    final db = await database;
    await db.insert(
      'note_remote_versions',
      {'note_id': noteId, 'remote_revision': revision},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int?> getRemoteRevision(String noteId) async {
    return _remoteRevision(await database, noteId);
  }

  Future<int?> _remoteRevision(DatabaseExecutor db, String noteId) async {
    final rows = await db.query(
      'note_remote_versions',
      where: 'note_id = ?',
      whereArgs: [noteId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['remote_revision'] as int?;
  }

  // ---------------------------------------------------------------------------
  // Bulk mutations (import / clear — also write outbox)
  // ---------------------------------------------------------------------------

  Future<void> clearAll() async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      final rows = await txn.query('notes', columns: ['id']);
      await txn.delete('notes');
      await txn.execute('DELETE FROM notes_fts');
      for (final row in rows) {
        final id = row['id'] as String;
        final baseRev = await txn.query(
          'note_remote_versions',
          where: 'note_id = ?',
          whereArgs: [id],
          limit: 1,
        );
        final base =
            baseRev.isEmpty ? null : baseRev.first['remote_revision'] as int?;
        await _writeOutbox(txn, _uuid.v4(), id, 'delete',
            baseRevision: base, createdAt: now);
      }
    });
  }

  Future<void> replaceAll(List<Note> notes) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      final existingRows = await txn.query('notes', columns: ['id']);
      final existingIds = {for (final r in existingRows) r['id'] as String};
      final incomingIds = {for (final n in notes) n.id};

      await txn.delete('notes');
      await txn.execute('DELETE FROM notes_fts');

      // Delete outbox for notes not in the new list.
      for (final id in existingIds.difference(incomingIds)) {
        final baseRev = await txn.query(
          'note_remote_versions',
          where: 'note_id = ?',
          whereArgs: [id],
          limit: 1,
        );
        final base =
            baseRev.isEmpty ? null : baseRev.first['remote_revision'] as int?;
        await _writeOutbox(txn, _uuid.v4(), id, 'delete',
            baseRevision: base, createdAt: now);
      }

      for (final note in notes) {
        await txn.insert('notes', note.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
        final baseRev = await txn.query(
          'note_remote_versions',
          where: 'note_id = ?',
          whereArgs: [note.id],
          limit: 1,
        );
        final base =
            baseRev.isEmpty ? null : baseRev.first['remote_revision'] as int?;
        await _writeOutbox(txn, _uuid.v4(), note.id, 'upsert',
            payload: jsonEncode(_noteToSyncPayload(note)),
            baseRevision: base,
            createdAt: now);
      }
    });
  }

  Future<({int added, int updated, int skipped})> mergeNotes(
    List<Note> existing,
    List<Note> incoming,
  ) async {
    final db = await database;
    final existingById = {for (final n in existing) n.id: n};
    int added = 0, updated = 0, skipped = 0;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      for (final note in incoming) {
        final current = existingById[note.id];
        final toWrite =
            note.copyWith(embeddingPending: true, clearEmbedding: true);
        if (current == null) {
          await txn.insert('notes', toWrite.toMap(),
              conflictAlgorithm: ConflictAlgorithm.replace);
          final baseRev = await txn.query(
            'note_remote_versions',
            where: 'note_id = ?',
            whereArgs: [note.id],
            limit: 1,
          );
          final base = baseRev.isEmpty
              ? null
              : baseRev.first['remote_revision'] as int?;
          await _writeOutbox(txn, _uuid.v4(), note.id, 'upsert',
              payload: jsonEncode(_noteToSyncPayload(note)),
              baseRevision: base,
              createdAt: now);
          added++;
        } else if (note.updatedAt.isAfter(current.updatedAt)) {
          await txn.update('notes', toWrite.toMap(),
              where: 'id = ?', whereArgs: [note.id]);
          final baseRev = await txn.query(
            'note_remote_versions',
            where: 'note_id = ?',
            whereArgs: [note.id],
            limit: 1,
          );
          final base = baseRev.isEmpty
              ? null
              : baseRev.first['remote_revision'] as int?;
          await _writeOutbox(txn, _uuid.v4(), note.id, 'upsert',
              payload: jsonEncode(_noteToSyncPayload(note)),
              baseRevision: base,
              createdAt: now);
          updated++;
        } else {
          skipped++;
        }
      }
    });
    return (added: added, updated: updated, skipped: skipped);
  }

  // ---------------------------------------------------------------------------
  // Standard read operations (unchanged)
  // ---------------------------------------------------------------------------

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

  Future<List<Map<String, dynamic>>> searchFts(String query) async {
    final db = await database;
    if (query.trim().isEmpty) return [];
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

  Future<void> reindexFts() async {
    final db = await database;
    await db.execute('INSERT INTO notes_fts(notes_fts) VALUES(\'rebuild\')');
  }
}
