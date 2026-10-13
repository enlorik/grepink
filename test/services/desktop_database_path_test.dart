import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:grepink/models/note.dart';
import 'package:grepink/services/database_service.dart';

void main() {
  final service = DatabaseService.instance;
  late Directory temporary;
  late String originalDatabaseDirectory;
  late String legacyPath;
  late String supportPath;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await service.closeForTesting();
    originalDatabaseDirectory = await databaseFactory.getDatabasesPath();
    temporary = await Directory.systemTemp.createTemp('grepink-desktop-');
    final legacyDirectory = p.join(temporary.path, 'old-working-directory');
    await databaseFactory.setDatabasesPath(legacyDirectory);
    legacyPath = p.join(legacyDirectory, 'grepink.db');
    supportPath = p.join(temporary.path, 'app-data', 'Grepink');
    DatabaseService.testDatabasePath = null;
    DatabaseService.testApplicationSupportPath = supportPath;
  });

  tearDown(() async {
    await service.closeForTesting();
    DatabaseService.testDatabasePath = null;
    DatabaseService.testApplicationSupportPath = null;
    await databaseFactory.setDatabasesPath(originalDatabaseDirectory);
    await temporary.delete(recursive: true);
  });

  Note note(String id) => Note(
    id: id,
    title: 'Local note',
    content: 'Must survive opening the app again',
    tags: const [],
    keywords: const [],
    isPinned: false,
    createdAt: DateTime.utc(2026, 10, 12),
    updatedAt: DateTime.utc(2026, 10, 12),
    embeddingPending: true,
  );

  test('fresh desktop database uses app data and survives reopening', () async {
    final openings = await Future.wait([service.database, service.database]);
    expect(identical(openings[0], openings[1]), isTrue);
    expect(openings[0].path, p.join(supportPath, 'grepink.db'));
    expect(await Directory(supportPath).exists(), isTrue);
    expect(await File(legacyPath).exists(), isFalse);

    await service.insertNote(note('new-note'));
    await service.closeForTesting();
    expect(
      (await service.getNoteById('new-note'))?.content,
      'Must survive opening the app again',
    );
    expect((await service.getOutboxEntries()).single.noteId, 'new-note');
    await service.resetSyncState();
    expect((await service.getOutboxEntries()).single.noteId, 'new-note');
  });

  test(
    'legacy migration preserves notes, WAL changes and sync metadata',
    () async {
      DatabaseService.testDatabasePath = legacyPath;
      await Directory(p.dirname(legacyPath)).create(recursive: true);
      await service.database;
      final keeper = await databaseFactoryFfi.openDatabase(
        legacyPath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      try {
      await keeper.execute('PRAGMA journal_mode=WAL');
        await keeper.execute('PRAGMA wal_autocheckpoint=0');
        await service.insertNote(note('legacy-note'));
        await service.setRemoteRevision('legacy-note', 17);
        final originalMutation = (await service.getOutboxEntries()).single;
      // Join the WAL with a real read so this connection keeps it alive after
      // DatabaseService closes its original connection for the migration.
      await keeper.rawQuery('SELECT COUNT(*) FROM notes');
        await service.closeForTesting();
        expect(await File('$legacyPath-wal').length(), greaterThan(0));
        DatabaseService.testDatabasePath = null;

        expect(
          (await service.getNoteById('legacy-note'))?.content,
          'Must survive opening the app again',
        );
        expect(await service.getRemoteRevision('legacy-note'), 17);
        expect(
          (await service.getOutboxEntries()).single.mutationId,
          originalMutation.mutationId,
        );
        expect(await File(legacyPath).exists(), isTrue);
        expect(
          await File(p.join(supportPath, 'grepink.db.migrating')).exists(),
          isFalse,
        );

        // Once migrated, the app must keep its newer database on subsequent opens.
        await service.insertNote(note('after-migration'));
        await service.closeForTesting();
        expect(await service.getNoteById('after-migration'), isNotNull);
      } finally {
        await keeper.close();
      }
    },
  );
}
