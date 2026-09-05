import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/note.dart';
import 'package:grepink/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Note _note(String id, {String title = 'Note', String content = 'Content'}) =>
    Note(
      id: id,
      title: title,
      content: content,
      tags: const [],
      keywords: const [],
      isPinned: false,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      embeddingPending: false,
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    DatabaseService.testDatabasePath = inMemoryDatabasePath;
  });

  tearDown(() async {
    await DatabaseService.instance.closeForTesting();
    DatabaseService.testDatabasePath = null;
  });

  // -------------------------------------------------------------------------
  // Test A: edit during upload is not lost
  // -------------------------------------------------------------------------

  test('edit during upload is not lost', () async {
    final svc = DatabaseService.instance;
    const noteId = 'note-a';

    // Insert note — this enqueues an upsert in the outbox.
    await svc.insertNote(_note(noteId, title: 'Original'));

    // Capture the first outbox entry (as if it's in-flight).
    final before = await svc.getOutboxEntries();
    expect(before.length, 1);
    final inFlightSeq = before.first.seq;
    final inFlightMid = before.first.mutationId;

    // Simulate an edit while the upload is in flight.
    // The in-flight entry is still in the outbox (not yet removed).
    await svc.updateNote(_note(noteId, title: 'Edited'));

    // The edit coalesces into the existing entry (no later delete exists),
    // updating the payload and assigning a NEW mutation_id.
    final afterEdit = await svc.getOutboxEntries();
    expect(afterEdit.length, 1);
    expect(afterEdit.first.seq, inFlightSeq);
    expect(afterEdit.first.mutationId, isNot(inFlightMid),
        reason: 'coalesce replaces mutation_id with a new UUID');
    final editedPayload =
        jsonDecode(afterEdit.first.payload!) as Map<String, dynamic>;
    expect(editedPayload['title'], 'Edited');

    // Simulate a stale server ack for the ORIGINAL mutation_id.
    // Because the mutation_id was replaced during coalesce, removeOutboxEntry
    // matches zero rows — the entry survives the stale ack.
    await svc.removeOutboxEntry(inFlightSeq, inFlightMid);

    // Re-read the DB: the coalesced entry must still be there because the
    // stale ack did not match the new mutation_id.
    final afterStaleAck = await svc.getOutboxEntries();
    expect(afterStaleAck.length, 1,
        reason: 'edit must survive stale server ack');
    expect(afterStaleAck.first.seq, inFlightSeq);
    final survivingPayload =
        jsonDecode(afterStaleAck.first.payload!) as Map<String, dynamic>;
    expect(survivingPayload['title'], 'Edited',
        reason: 'edited payload must still be queued after stale ack');
  });

  // -------------------------------------------------------------------------
  // Test B: offline delete-then-restore
  // -------------------------------------------------------------------------

  test('offline delete-then-restore produces upsert after delete in outbox',
      () async {
    final svc = DatabaseService.instance;
    const noteId = 'note-b';

    // 1. Create note → outbox: [upsert(seq=1)]
    await svc.insertNote(_note(noteId, title: 'Hello'));
    final afterInsert = await svc.getOutboxEntries();
    expect(afterInsert.length, 1);
    expect(afterInsert.first.operation, 'upsert');
    final upsertSeq = afterInsert.first.seq;
    final upsertMid = afterInsert.first.mutationId;

    // 2. Delete note offline → outbox: [upsert(seq=1), delete(seq=2)]
    await svc.deleteNote(noteId);
    final afterDelete = await svc.getOutboxEntries();
    expect(afterDelete.length, 2);
    expect(afterDelete[0].operation, 'upsert');
    expect(afterDelete[0].seq, upsertSeq);
    expect(afterDelete[1].operation, 'delete');
    final deleteSeq = afterDelete[1].seq;
    expect(deleteSeq, greaterThan(upsertSeq));

    // 3. Restore note offline (insert again) →
    //    must NOT coalesce into upsert(seq=1) because delete(seq=2) comes after it.
    //    Must insert a NEW upsert(seq=3) after the delete.
    await svc.insertNote(_note(noteId, title: 'Restored'));
    final afterRestore = await svc.getOutboxEntries();
    expect(afterRestore.length, 3,
        reason: 'restore must not coalesce into the pre-delete upsert');

    // Order must be: upsert → delete → upsert
    expect(afterRestore[0].operation, 'upsert');
    expect(afterRestore[0].seq, upsertSeq);
    expect(afterRestore[1].operation, 'delete');
    expect(afterRestore[1].seq, deleteSeq);
    expect(afterRestore[2].operation, 'upsert');
    final restoreSeq = afterRestore[2].seq;
    expect(restoreSeq, greaterThan(deleteSeq));

    // The restore entry must carry the restored payload.
    final restorePayload =
        jsonDecode(afterRestore[2].payload!) as Map<String, dynamic>;
    expect(restorePayload['title'], 'Restored');

    // 4. Stale upload acknowledgment: the original upsert(seq=1) is acked by the
    //    server even though offline mutations have already queued after it.
    //    After the ack the outbox must still contain: [delete(seq=2), upsert(seq=3)].
    await svc.removeOutboxEntry(upsertSeq, upsertMid);

    final afterStaleAck = await svc.getOutboxEntries();
    expect(afterStaleAck.length, 2,
        reason: 'stale ack must only remove the acked entry');
    expect(afterStaleAck[0].operation, 'delete');
    expect(afterStaleAck[0].seq, deleteSeq);
    expect(afterStaleAck[1].operation, 'upsert');
    expect(afterStaleAck[1].seq, restoreSeq);

    // 5. Re-read the database: the restored note must still exist in the notes
    //    table and the newer queued upsert must carry the right payload.
    final restoredNote = await svc.getNoteById(noteId);
    expect(restoredNote, isNotNull,
        reason: 'restored note must still be in the notes table after stale ack');
    expect(restoredNote!.title, 'Restored');

    final restoreEntryPayload =
        jsonDecode(afterStaleAck[1].payload!) as Map<String, dynamic>;
    expect(restoreEntryPayload['title'], 'Restored',
        reason: 'queued upsert must still carry the restored title');

    // 6. Drain the remaining outbox in order and verify the server converges to
    //    the note being present.
    String? serverState; // null = deleted / never existed
    for (final entry in afterStaleAck) {
      if (entry.operation == 'upsert') {
        serverState = (jsonDecode(entry.payload!)
            as Map<String, dynamic>)['title'] as String?;
      } else {
        serverState = null;
      }
      await svc.removeOutboxEntry(entry.seq, entry.mutationId);
    }

    // Server should see the note as present with the restored title.
    expect(serverState, 'Restored');

    // Outbox is now empty.
    final finalOutbox = await svc.getOutboxEntries();
    expect(finalOutbox, isEmpty);
  });
}
