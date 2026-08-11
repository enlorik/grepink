import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/note.dart';
import 'package:grepink/models/tombstone.dart';
import 'package:grepink/providers/sync_provider.dart';
import 'package:grepink/services/drive_sync_service.dart';
import 'package:grepink/services/note_export_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Fake service
// ---------------------------------------------------------------------------

class _FakeService implements DriveSyncService {
  String? _email;
  bool _signedIn;
  bool silentResult;
  String? remote;
  bool throwOnUpload;
  bool throwOnDownload = false;
  int uploadCalls = 0;
  int downloadCalls = 0;
  String? lastUploaded;
  Completer<void>? downloadBlock;
  Completer<void>? uploadBlock;
  Future<void> Function(String encoded)? onUpload;

  _FakeService({
    bool signedIn = true,
    String email = 'user@example.com',
    this.silentResult = false,
    this.remote,
    this.throwOnUpload = false,
    this.downloadBlock,
    this.onUpload,
  })  : _signedIn = signedIn,
        _email = signedIn ? email : null;

  @override
  bool get isSignedIn => _signedIn;
  @override
  String? get accountEmail => _email;

  @override
  Future<bool> signIn() async {
    _signedIn = true;
    _email = 'user@example.com';
    return true;
  }

  @override
  Future<bool> signInSilently() async {
    if (silentResult) {
      _signedIn = true;
      _email = 'user@example.com';
    }
    return silentResult;
  }

  @override
  Future<void> signOut() async {
    _signedIn = false;
    _email = null;
  }

  @override
  Future<void> upload(String encoded) async {
    if (uploadBlock != null) {
      await uploadBlock!.future;
      uploadBlock = null;
    }
    if (onUpload != null) await onUpload!(encoded);
    if (throwOnUpload) throw Exception('upload failed');
    uploadCalls++;
    lastUploaded = encoded;
  }

  @override
  Future<String?> download() async {
    downloadCalls++;
    if (downloadBlock != null) {
      await downloadBlock!.future;
      downloadBlock = null;
    }
    if (throwOnDownload) throw Exception('download failed');
    return remote;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Note _note({
  required String id,
  String title = 'T',
  String content = 'c',
  DateTime? updatedAt,
}) {
  final ts = updatedAt ?? DateTime.utc(2026, 1, 1);
  return Note(
    id: id,
    title: title,
    content: content,
    tags: const [],
    keywords: const [],
    isPinned: false,
    createdAt: ts,
    updatedAt: ts,
    embeddingPending: false,
  );
}

List<Note> _localNotes = [];
final List<String> _mergedNoteIds = [];
final Set<String> _deletedIds = {};

ProviderContainer _makeContainer({
  required _FakeService service,
  List<ConnectivityResult> connectivity = const [ConnectivityResult.wifi],
  List<Note>? local,
  List<Tombstone> tombstones = const [],
}) {
  _localNotes = List.of(local ?? []);
  _mergedNoteIds.clear();
  _deletedIds.clear();

  return ProviderContainer(
    overrides: [
      syncServiceProvider.overrideWithValue(service),
      connectivityCheckerProvider.overrideWithValue(() async => connectivity),
      notesGetterProvider.overrideWithValue(() async => List.of(_localNotes)),
      notesMergerProvider.overrideWithValue((existing, incoming) async {
        _mergedNoteIds.addAll(incoming.map((n) => n.id));
      }),
      notesDeleterProvider.overrideWithValue((ids) async {
        _deletedIds.addAll(ids);
        _localNotes.removeWhere((n) => ids.contains(n.id));
      }),
      notesReloaderProvider.overrideWithValue(() async {}),
      embeddingReindexerProvider.overrideWithValue(() async {}),
      tombstonesGetterProvider.overrideWithValue(() async => tombstones),
    ],
  );
}

const _userEmail = 'user@example.com';
const _markerKey = 'sync.$_userEmail.forceUploadPending';
const _knownIdsPrefsKey = 'sync.$_userEmail.knownIds';
const _lastSyncPrefsKey = 'sync.$_userEmail.lastSyncedAt';

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SyncNotifier coordinator', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    tearDown(() {
      _localNotes = [];
      _mergedNoteIds.clear();
      _deletedIds.clear();
    });

    // -----------------------------------------------------------------------
    // Queuing and ordering
    // -----------------------------------------------------------------------

    test('force→force: two rapid syncUploadOnly calls both complete', () async {
      final service = _FakeService();
      final container = _makeContainer(service: service);
      addTearDown(container.dispose);
      final notifier = container.read(syncProvider.notifier);

      final f1 = notifier.syncUploadOnly();
      final f2 = notifier.syncUploadOnly();
      await Future.wait([f1, f2]);

      expect(service.uploadCalls, 2,
          reason: 'both force-upload requests must upload independently');
      expect(service.downloadCalls, 0,
          reason: 'force-upload must never download');
    });

    test('force→normal: force upload runs; regular sync downloads exactly once',
        () async {
      final service = _FakeService();
      final container = _makeContainer(service: service);
      addTearDown(container.dispose);
      final notifier = container.read(syncProvider.notifier);

      final f1 = notifier.syncUploadOnly();
      final f2 = notifier.sync();
      await Future.wait([f1, f2]);

      expect(service.downloadCalls, 1,
          reason: 'only the regular sync should download');
      expect(service.uploadCalls, greaterThanOrEqualTo(2),
          reason: 'at least one force-upload plus the regular-sync upload');
    });

    test(
        'normal→force: force upload queues and completes after sync-in-progress',
        () async {
      final downloadBlock = Completer<void>();
      final service = _FakeService(downloadBlock: downloadBlock);
      final container = _makeContainer(service: service);
      addTearDown(container.dispose);
      final notifier = container.read(syncProvider.notifier);

      final fSync = notifier.sync();
      await pumpEventQueue(times: 20);

      final fForce = notifier.syncUploadOnly();
      downloadBlock.complete();
      await Future.wait([fSync, fForce]);

      expect(service.downloadCalls, 1);
      expect(service.uploadCalls, 2,
          reason: 'regular-sync upload + subsequent force-upload');
    });

    test('force→normal→force: all three items complete', () async {
      final service = _FakeService();
      final container = _makeContainer(service: service);
      addTearDown(container.dispose);
      final notifier = container.read(syncProvider.notifier);

      final f1 = notifier.syncUploadOnly();
      final f2 = notifier.sync();
      final f3 = notifier.syncUploadOnly();
      await Future.wait([f1, f2, f3]);

      expect(service.downloadCalls, 1);
      expect(service.uploadCalls, greaterThanOrEqualTo(3));
    });

    // -----------------------------------------------------------------------
    // Durable-marker persistence
    // -----------------------------------------------------------------------

    test('offline recovery: failed syncUploadOnly leaves durable marker',
        () async {
      final service = _FakeService();
      final container = _makeContainer(service: service);
      addTearDown(container.dispose);
      final notifier = container.read(syncProvider.notifier);

      // signIn sets state.accountEmail so the scoped prefs key is known.
      await notifier.signIn();
      service.throwOnUpload = true;

      await notifier.syncUploadOnly();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(_markerKey), isTrue,
          reason: 'marker must persist after a failed upload');
    });

    test('upload failure: marker persists and triggers retry on next startup',
        () async {
      final service1 = _FakeService(throwOnUpload: true);
      final c1 = _makeContainer(service: service1);
      addTearDown(c1.dispose);
      await c1.read(syncProvider.notifier).syncUploadOnly();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(_markerKey), isTrue);

      // Simulate process restart with silent sign-in success.
      final service2 = _FakeService(signedIn: false, silentResult: true);
      final c2 = _makeContainer(service: service2);
      addTearDown(c2.dispose);

      c2.read(syncProvider.notifier); // triggers _init()
      await pumpEventQueue(times: 40);

      expect(service2.uploadCalls, greaterThan(0),
          reason:
              'startup must retry the upload when the durable marker is set');
      expect(service2.downloadCalls, 0,
          reason: 'retry must be a force-upload, not a download-first sync');
    });

    test(
        'process-restart recovery: marker in prefs triggers syncUploadOnly on startup',
        () async {
      SharedPreferences.setMockInitialValues({_markerKey: true});

      final service = _FakeService(signedIn: false, silentResult: true);
      final container = _makeContainer(service: service);
      addTearDown(container.dispose);

      container.read(syncProvider.notifier); // triggers _init()
      await pumpEventQueue(times: 40);

      expect(service.uploadCalls, greaterThan(0));
      expect(service.downloadCalls, 0);
    });

    test(
        'marker-clear timing: marker persists while second force upload is pending',
        () async {
      var callCount = 0;
      final secondUploadGate = Completer<void>();
      final service = _FakeService(
        onUpload: (enc) async {
          callCount++;
          if (callCount == 2) await secondUploadGate.future;
        },
      );
      final container = _makeContainer(service: service);
      addTearDown(container.dispose);
      final notifier = container.read(syncProvider.notifier);

      final f1 = notifier.syncUploadOnly();
      final f2 = notifier.syncUploadOnly();

      await f1;
      await pumpEventQueue(times: 30);

      final prefsA = await SharedPreferences.getInstance();
      expect(prefsA.getBool(_markerKey), isTrue,
          reason:
              'marker must not be cleared while the second force upload is pending');

      secondUploadGate.complete();
      await f2;

      final prefsB = await SharedPreferences.getInstance();
      expect(prefsB.containsKey(_markerKey), isFalse,
          reason:
              'marker must be cleared only after all queued force uploads succeed');
    });

    // -----------------------------------------------------------------------
    // Remote-deletion semantics
    // -----------------------------------------------------------------------

    test(
        'empty remote clear-all: all knownIds notes deleted when backup is empty',
        () async {
      SharedPreferences.setMockInitialValues({
        _knownIdsPrefsKey: ['x', 'y']
      });

      final remoteJson = NoteExportService.instance.encode([]);
      final service = _FakeService(remote: remoteJson);
      final container = _makeContainer(
        service: service,
        local: [_note(id: 'x'), _note(id: 'y')],
      );
      addTearDown(container.dispose);

      await container.read(syncProvider.notifier).signIn();

      expect(_deletedIds.contains('x'), isTrue,
          reason: 'empty remote propagates as clear-all for knownIds notes');
      expect(_deletedIds.contains('y'), isTrue);
    });

    test('tombstone propagation: remote tombstone deletes matching local note',
        () async {
      SharedPreferences.setMockInitialValues({
        _knownIdsPrefsKey: ['x']
      });

      final deletedAt = DateTime.utc(2026, 6, 1).millisecondsSinceEpoch;
      final remoteJson = NoteExportService.instance.encode(
        [],
        tombstones: [Tombstone(id: 'x', deletedAt: deletedAt)],
      );
      final service = _FakeService(remote: remoteJson);
      final container = _makeContainer(
        service: service,
        local: [_note(id: 'x', updatedAt: DateTime.utc(2026, 1, 1))],
      );
      addTearDown(container.dispose);

      await container.read(syncProvider.notifier).signIn();

      expect(_deletedIds.contains('x'), isTrue,
          reason: 'remote tombstone must delete the matching local note');
    });

    test('locally edited note survives a remote tombstone', () async {
      SharedPreferences.setMockInitialValues({
        _knownIdsPrefsKey: ['x']
      });

      final tombstoneAt = DateTime.utc(2026, 6, 1).millisecondsSinceEpoch;
      // Note edited AFTER the tombstone — local edit wins.
      final remoteJson = NoteExportService.instance.encode(
        [],
        tombstones: [Tombstone(id: 'x', deletedAt: tombstoneAt)],
      );
      final service = _FakeService(remote: remoteJson);
      final container = _makeContainer(
        service: service,
        local: [_note(id: 'x', updatedAt: DateTime.utc(2026, 7, 1))],
      );
      addTearDown(container.dispose);

      await container.read(syncProvider.notifier).signIn();

      expect(_deletedIds.contains('x'), isFalse,
          reason:
              'updatedAt guard: locally edited note must not be deleted by a stale tombstone');
    });

    test('locally deleted known note is not re-merged from remote', () async {
      final note = _note(id: 'x');
      final remoteJson = NoteExportService.instance.encode([note]);
      final service = _FakeService(remote: remoteJson);

      final container = _makeContainer(service: service, local: [note]);
      addTearDown(container.dispose);
      // First sign-in records 'x' in knownIds.
      await container.read(syncProvider.notifier).signIn();

      _localNotes = [];
      _mergedNoteIds.clear();

      // Second sync must not re-merge 'x' even though remote still has it.
      await container.read(syncProvider.notifier).sync();

      expect(_mergedNoteIds.contains('x'), isFalse,
          reason:
              'a locally deleted known note must not be resurrected from remote');
    });

    test(
        'edit during deletion: note edited after tombstone timestamp is preserved',
        () async {
      SharedPreferences.setMockInitialValues({
        _knownIdsPrefsKey: ['x']
      });

      final tombstoneAt = DateTime.utc(2026, 6, 1).millisecondsSinceEpoch;
      // Note updated AFTER tombstone — the updatedAt guard must keep it.
      final remoteJson = NoteExportService.instance.encode(
        [],
        tombstones: [Tombstone(id: 'x', deletedAt: tombstoneAt)],
      );
      final service = _FakeService(remote: remoteJson);
      final container = _makeContainer(
        service: service,
        local: [_note(id: 'x', updatedAt: DateTime.utc(2026, 8, 1))],
      );
      addTearDown(container.dispose);

      await container.read(syncProvider.notifier).signIn();

      expect(_deletedIds.contains('x'), isFalse,
          reason:
              'updatedAt guard must protect a locally edited note from remote deletion');
    });

    // -----------------------------------------------------------------------
    // Account switching
    // -----------------------------------------------------------------------

    test('account A knownIds do not contaminate account B sync', () async {
      // A's scoped prefs are present but B uses a different email prefix.
      SharedPreferences.setMockInitialValues({
        'sync.a@example.com.knownIds': ['note-a'],
        'sync.a@example.com.lastSyncedAt': 1000,
      });

      final remoteNote = _note(id: 'note-from-remote');
      final remoteJson = NoteExportService.instance.encode([remoteNote]);

      // B's service email is 'user@example.com' — different from A's.
      final service = _FakeService(remote: remoteJson);
      final container = _makeContainer(service: service, local: []);
      addTearDown(container.dispose);

      await container.read(syncProvider.notifier).signIn();

      expect(_mergedNoteIds.contains('note-from-remote'), isTrue,
          reason:
              'B must see the remote note as new (not contaminated by A\'s knownIds)');
      expect(_deletedIds, isEmpty,
          reason: 'B must not delete notes based on A\'s stale state');
    });

    // -----------------------------------------------------------------------
    // Generation guard (sign-out during sync)
    // -----------------------------------------------------------------------

    test('sign-out during sync prevents stale lastSyncedAt prefs write',
        () async {
      final service = _FakeService();
      final container = _makeContainer(service: service);
      addTearDown(container.dispose);
      final notifier = container.read(syncProvider.notifier);

      // Establish accountEmail via signIn.
      await notifier.signIn();
      (await SharedPreferences.getInstance()).remove(_lastSyncPrefsKey);

      // Arm a new download block for the next sync.
      service.downloadBlock = Completer<void>();

      final fSync = notifier.sync();
      await pumpEventQueue(times: 20);

      await notifier.signOut();

      service.downloadBlock!.complete();
      await fSync;

      final finalState = container.read(syncProvider);
      expect(finalState.isSignedIn, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(_lastSyncPrefsKey), isFalse,
          reason:
              'generation guard must prevent stale lastSyncedAt write after sign-out');
    });

    // -----------------------------------------------------------------------
    // Versioned payload
    // -----------------------------------------------------------------------

    test('version-1 payload decodes correctly (backward compatibility)', () {
      const v1 =
          '{"version":1,"exported_at":"2026-01-01T00:00:00Z","notes":[]}';
      final payload = NoteExportService.instance.decodePayload(v1);

      expect(payload.notes, isEmpty);
      expect(payload.tombstones, isEmpty);
      expect(payload.replacedAt, isNull);
    });

    test('version-1 payload with a note decodes all fields', () {
      final note = _note(id: 'v1-note', title: 'V1', content: 'Hello');
      final noteJson = jsonEncode(note.toJson());
      final v1 =
          '{"version":1,"exported_at":"2026-01-01T00:00:00Z","notes":[$noteJson]}';
      final payload = NoteExportService.instance.decodePayload(v1);

      expect(payload.notes.length, 1);
      expect(payload.notes.first.id, 'v1-note');
      expect(payload.tombstones, isEmpty);
    });

    // -----------------------------------------------------------------------
    // Authoritative replacement (replacedAt)
    // -----------------------------------------------------------------------

    test('authoritative replacement: notes older than replacedAt are deleted',
        () async {
      final replacedAt = DateTime.utc(2026, 6, 1);
      final oldNote = _note(id: 'old', updatedAt: DateTime.utc(2026, 1, 1));
      final newNote = _note(id: 'new', updatedAt: DateTime.utc(2026, 7, 1));
      final keptNote = _note(id: 'kept', updatedAt: DateTime.utc(2026, 5, 1));

      final remoteJson = NoteExportService.instance.encode(
        [keptNote],
        replacedAt: replacedAt.millisecondsSinceEpoch,
      );
      final service = _FakeService(remote: remoteJson);
      final container = _makeContainer(
        service: service,
        local: [oldNote, newNote],
      );
      addTearDown(container.dispose);

      await container.read(syncProvider.notifier).signIn();

      expect(_deletedIds.contains('old'), isTrue,
          reason:
              'note older than replacedAt absent from remote must be deleted');
      expect(_deletedIds.contains('new'), isFalse,
          reason:
              'note newer than replacedAt must survive the authoritative reset');
    });

    // -----------------------------------------------------------------------
    // Disposal
    // -----------------------------------------------------------------------

    test('disposal mid-sync does not throw', () async {
      final downloadBlock = Completer<void>();
      final service = _FakeService(downloadBlock: downloadBlock);
      final container = _makeContainer(service: service);
      final notifier = container.read(syncProvider.notifier);

      final fSync = notifier.sync();
      await pumpEventQueue(times: 20);

      container.dispose();
      downloadBlock.complete();

      await expectLater(fSync, completes);
    });
  });
}
