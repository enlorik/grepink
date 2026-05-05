import 'dart:async';
import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/note.dart';

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
      version: 1,
      onCreate: _onCreate,
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

  Future<void> deleteNote(String id) async {
    final db = await database;
    await db.delete('notes', where: 'id = ?', whereArgs: [id]);
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

  Future<void> clearAll() async {
    final db = await database;
    await db.delete('notes');
    await db.execute("DELETE FROM notes_fts");
  }

  Future<void> reindexFts() async {
    final db = await database;
    await db.execute("INSERT INTO notes_fts(notes_fts) VALUES('rebuild')");
  }
}
