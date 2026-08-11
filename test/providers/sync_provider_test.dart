import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/note.dart';
import 'package:grepink/models/sync_state.dart';
import 'package:grepink/providers/sync_provider.dart';
import 'package:grepink/services/drive_sync_service.dart';
import 'package:grepink/services/note_export_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------- fakes ----------

class _FakeDriveSyncService implements DriveSyncService {
  bool _signedIn;
  String? remote;
  bool throwOnUpload;
  bool throwOnDownload;
  bool silentSignInResult;
  int uploadCalls = 0;
  int downloadCalls = 0;
  String? lastUploaded;

  _FakeDriveSyncService({
    bool signedIn = true,
    this.remote,
    this.throwOnUpload = false,
    this.throwOnDownload = false,
    this.silentSignInResult = false,
  }) : _signedIn = signedIn;

  @override
  bool get isSignedIn => _signedIn;

  @override
  String? get accountEmail => _signedIn ? 'user@example.com' : null;

  @override
  Future<bool> signIn() async {
    _signedIn = true;
    return true;
  }

  @override
  Future<bool> signInSilently() async {
    if (silentSignInResult) _signedIn = true;
    return silentSignInResult;
  }

  @override
  Future<void> signOut() async => _signedIn = false;

  @override
  Future<void> upload(String encodedJson) async {
    if (throwOnUpload) throw Exception('upload error');
    uploadCalls++;
    lastUploaded = encodedJson;
  }

  @override
  Future<String?> download() async {
    if (throwOnDownload) throw Exception('download error');
    downloadCalls++;
    return remote;
  }
}

// ---------- helpers ----------

Note _note({
  required String id,
  String title = 'Title',
  String content = 'Content',
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
final List<_MergeCall> _mergeCalls = [];
final Set<String> _deletedIds = {};

class _MergeCall {
  final List<Note> existing;
  final List<Note> incoming;
  _MergeCall(this.existing, this.incoming);
}

ProviderContainer _makeContainer({
  required _FakeDriveSyncService service,
  List<ConnectivityResult> connectivity = const [ConnectivityResult.wifi],
  List<Note>? localNotes,
}) {
  _localNotes = localNotes ?? [];
  _mergeCalls.clear();
  _deletedIds.clear();

  return ProviderContainer(
    overrides: [
      syncServiceProvider.overrideWithValue(service),
      connectivityCheckerProvider.overrideWithValue(
        () async => connectivity,
      ),
      notesGetterProvider.overrideWithValue(() async => List.of(_localNotes)),
      notesMergerProvider.overrideWithValue((existing, incoming) async {
        _mergeCalls.add(_MergeCall(existing, incoming));
      }),
      notesDeleterProvider.overrideWithValue((ids) async {
        _deletedIds.addAll(ids);
        _localNotes.removeWhere((n) => ids.contains(n.id));
      }),
      notesReloaderProvider.overrideWithValue(() async {}),
      embeddingReindexerProvider.overrideWithValue(() async {}),
      tombstonesGetterProvider.overrideWithValue(() async => []),
    ],
  );
}

// ---------- tests ----------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SyncNotifier', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() {
      _localNotes = [];
      _mergeCalls.clear();
      _deletedIds.clear();
    });

    test('sync() skips when not signed in', () async {
      final service = _FakeDriveSyncService(signedIn: false);
      final container = _makeContainer(service: service);
      addTearDown(container.dispose);

      await container.read(syncProvider.notifier).sync();

      expect(container.read(syncProvider).status, SyncStatus.idle);
      expect(service.uploadCalls, 0);
    });

    test('sync() skips when offline', () async {
      final service = _FakeDriveSyncService();
      final container = _makeContainer(
        service: service,
        connectivity: [ConnectivityResult.none],
      );
      addTearDown(container.dispose);

      await container.read(syncProvider.notifier).sync();

      expect(container.read(syncProvider).status, SyncStatus.idle);
      expect(service.uploadCalls, 0);
    });

    test('sync() queues one follow-up when already syncing', () async {
      // When a second sync() call arrives while one is in-flight, it should
      // mark a pending flag so a single follow-up run happens after the first
      // finishes — not unlimited queuing, but no silent discard either.
      final service = _FakeDriveSyncService();
      final container = _makeContainer(service: service);
      addTearDown(container.dispose);

      final notifier = container.read(syncProvider.notifier);
      final f1 = notifier.sync();
      final f2 = notifier.sync();
      await Future.wait([f1, f2]);

      // First sync uploads once; the queued sync uploads once more.
      expect(service.uploadCalls, 2);
    });

    test('sync() merges remote notes into local when remote exists', () async {
      final newer = DateTime.utc(2026, 6, 1);
      final remoteNote = _note(id: 'r1', title: 'Remote', updatedAt: newer);
      final localNote = _note(id: 'l1', title: 'Local');
      final remoteJson = NoteExportService.instance.encode([remoteNote]);

      final service = _FakeDriveSyncService(remote: remoteJson);
      final container = _makeContainer(
        service: service,
        localNotes: [localNote],
      );
      addTearDown(container.dispose);

      await container.read(syncProvider.notifier).sync();

      expect(_mergeCalls.length, 1);
      expect(_mergeCalls.first.incoming.first.id, 'r1');
    });

    test('sync() uploads after merging', () async {
      final service = _FakeDriveSyncService();
      final container = _makeContainer(service: service);
      addTearDown(container.dispose);

      await container.read(syncProvider.notifier).sync();

      expect(service.uploadCalls, 1);
      expect(service.lastUploaded, isNotNull);
    });

    test('sync() sets lastSyncedAt on success', () async {
      final service = _FakeDriveSyncService();
      final container = _makeContainer(service: service);
      addTearDown(container.dispose);

      final before = DateTime.now();
      await container.read(syncProvider.notifier).sync();
      final after = DateTime.now();

      final syncState = container.read(syncProvider);
      expect(syncState.status, SyncStatus.idle);
      expect(syncState.lastSyncedAt, isNotNull);
      expect(
        syncState.lastSyncedAt!
            .isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(
        syncState.lastSyncedAt!.isBefore(after.add(const Duration(seconds: 1))),
        isTrue,
      );
    });

    test('sync() sets status=error and errorMessage on DriveApi failure',
        () async {
      final service = _FakeDriveSyncService(throwOnDownload: true);
      final container = _makeContainer(service: service);
      addTearDown(container.dispose);

      await container.read(syncProvider.notifier).sync();

      final syncState = container.read(syncProvider);
      expect(syncState.status, SyncStatus.error);
      expect(syncState.errorMessage, isNotNull);
      expect(syncState.errorMessage, isNotEmpty);
    });

    test('sync() does not expose note content in errorMessage', () async {
      final sensitiveNote = _note(
        id: 'secret',
        title: 'My secret plan',
        content: 'Step 1: rule the world',
      );
      final service = _FakeDriveSyncService(throwOnUpload: true);
      final container = _makeContainer(
        service: service,
        localNotes: [sensitiveNote],
      );
      addTearDown(container.dispose);

      await container.read(syncProvider.notifier).sync();

      final msg = container.read(syncProvider).errorMessage ?? '';
      expect(msg.contains('secret'), isFalse);
      expect(msg.contains('rule the world'), isFalse);
      expect(msg.contains('Step 1'), isFalse);
    });

    test(
        'sync() does not resurrect a note that was deleted after the last sync',
        () async {
      // Scenario: note 'deleted' existed locally and was successfully synced
      // (so its ID is recorded in knownIds). The user then deleted it locally.
      // The remote backup still has it. A subsequent sync must NOT re-insert it.
      final deletedNote = _note(id: 'deleted', title: 'Deleted note');
      final remoteJson = NoteExportService.instance.encode([deletedNote]);
      final service = _FakeDriveSyncService(remote: remoteJson);

      // Step 1: sign in (sets accountEmail so scoped prefs keys work) — first sync
      // records 'deleted' in knownIds.
      final container =
          _makeContainer(service: service, localNotes: [deletedNote]);
      addTearDown(container.dispose);
      await container.read(syncProvider.notifier).signIn();

      // Step 2: user deletes the note locally.
      _localNotes = [];
      _mergeCalls.clear();
      final uploadsBeforeSecondSync = service.uploadCalls;

      // Step 3: second sync must skip the remote copy.
      await container.read(syncProvider.notifier).sync();

      final resurrected = _mergeCalls.any(
        (c) => c.incoming.any((n) => n.id == 'deleted'),
      );
      expect(resurrected, isFalse,
          reason:
              'Deleted note should not be resurrected from stale remote backup');
      expect(service.uploadCalls, greaterThan(uploadsBeforeSecondSync));
    });

    test('sync() deletes a note that was removed on another device', () async {
      // Scenario: note 'x' is known (synced before, so its ID is in knownIds)
      // and present locally, but the latest remote backup no longer contains it
      // — another device deleted it. This sync must delete 'x' locally.
      final noteX = _note(id: 'x', title: 'Note X');
      final noteY = _note(id: 'y', title: 'Note Y');
      // Remote backup has 'y' but NOT 'x'.
      final remoteJson = NoteExportService.instance.encode([noteY]);

      // Pre-populate knownIds so 'x' is considered a previously synced note.
      SharedPreferences.setMockInitialValues({
        'sync.user@example.com.knownIds': ['x']
      });

      final service = _FakeDriveSyncService(remote: remoteJson);
      final container = _makeContainer(service: service, localNotes: [noteX]);
      addTearDown(container.dispose);

      // signIn() sets accountEmail so the scoped knownIds key is read correctly,
      // then immediately runs a sync that sees 'x' in knownIds but absent from remote.
      await container.read(syncProvider.notifier).signIn();

      expect(_deletedIds.contains('x'), isTrue,
          reason: 'Note deleted on another device should be removed locally');
      expect(
          _mergeCalls.any((c) => c.incoming.any((n) => n.id == 'x')), isFalse,
          reason: 'Remotely deleted note must not be re-merged');
    });

    test('syncUploadOnly() uploads without downloading', () async {
      final localNote = _note(id: 'l1');
      final service = _FakeDriveSyncService();
      final container =
          _makeContainer(service: service, localNotes: [localNote]);
      addTearDown(container.dispose);

      await container.read(syncProvider.notifier).syncUploadOnly();

      expect(service.uploadCalls, 1,
          reason: 'syncUploadOnly should upload current notes');
      expect(service.downloadCalls, 0,
          reason:
              'syncUploadOnly must not download to avoid overwriting restored notes');
      expect(_mergeCalls, isEmpty,
          reason: 'syncUploadOnly must not merge remote notes');
    });

    test('signIn() triggers an immediate sync', () async {
      final service = _FakeDriveSyncService(signedIn: false);
      final container = _makeContainer(service: service);
      addTearDown(container.dispose);

      await container.read(syncProvider.notifier).signIn();

      expect(service.uploadCalls, 1,
          reason:
              'signIn should immediately sync so Drive notes are downloaded');
    });

    test('sync() sets status=error when connectivity check throws', () async {
      final service = _FakeDriveSyncService();
      final container = ProviderContainer(
        overrides: [
          syncServiceProvider.overrideWithValue(service),
          connectivityCheckerProvider
              .overrideWithValue(() async => throw Exception('platform error')),
          notesGetterProvider.overrideWithValue(() async => []),
          notesMergerProvider.overrideWithValue((e, i) async {}),
          notesDeleterProvider.overrideWithValue((ids) async {}),
        ],
      );
      addTearDown(container.dispose);
      SharedPreferences.setMockInitialValues({});

      await container.read(syncProvider.notifier).sync();

      expect(container.read(syncProvider).status, SyncStatus.error);
      expect(service.uploadCalls, 0);
    });

    test('silent sign-in on startup restores session state', () async {
      final service = _FakeDriveSyncService(
        signedIn: false,
        silentSignInResult: true,
      );
      final container = _makeContainer(service: service);
      addTearDown(container.dispose);

      // Reading the notifier triggers _init() → _silentSignIn() → sync().
      container.read(syncProvider.notifier);
      // Drain the full async chain (sign-in + sync + prefs write).
      await pumpEventQueue(times: 20);

      final syncState = container.read(syncProvider);
      expect(syncState.isSignedIn, isTrue);
      expect(syncState.accountEmail, isNotNull);
    });
  });
}
