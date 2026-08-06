import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/note.dart';
import 'package:grepink/models/sync_state.dart';
import 'package:grepink/providers/sync_provider.dart';
import 'package:grepink/services/drive_sync_service.dart';
import 'package:grepink/services/note_export_service.dart';

// ---------- fakes ----------

class _FakeDriveSyncService implements DriveSyncService {
  bool _signedIn;
  final String? _remote;
  bool throwOnUpload;
  bool throwOnDownload;
  bool silentSignInResult;
  int uploadCalls = 0;
  String? lastUploaded;

  _FakeDriveSyncService({
    bool signedIn = true,
    String? remote,
    this.throwOnUpload = false,
    this.throwOnDownload = false,
    this.silentSignInResult = false,
  })  : _signedIn = signedIn,
        _remote = remote;

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
    return _remote;
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
    ],
  );
}

// ---------- tests ----------

void main() {
  group('SyncNotifier', () {
    tearDown(() {
      _localNotes = [];
      _mergeCalls.clear();
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

    test('sync() skips when already syncing', () async {
      final service = _FakeDriveSyncService();
      final container = _makeContainer(service: service);
      addTearDown(container.dispose);

      final notifier = container.read(syncProvider.notifier);
      final f1 = notifier.sync();
      final f2 = notifier.sync();
      await Future.wait([f1, f2]);

      expect(service.uploadCalls, 1);
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
        syncState.lastSyncedAt!.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(
        syncState.lastSyncedAt!.isBefore(after.add(const Duration(seconds: 1))),
        isTrue,
      );
    });

    test('sync() sets status=error and errorMessage on DriveApi failure', () async {
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

    test('sync() does not resurrect notes deleted before lastSyncedAt', () async {
      // A note that existed in a prior backup but was deleted locally should
      // not come back just because the remote still has it, as long as the
      // remote copy predates our last successful sync.
      final beforeLastSync = DateTime.utc(2026, 1, 1);
      final deletedNote =
          _note(id: 'deleted', title: 'Deleted note', updatedAt: beforeLastSync);
      final remoteJson = NoteExportService.instance.encode([deletedNote]);

      final service = _FakeDriveSyncService(remote: remoteJson);
      final container = _makeContainer(service: service, localNotes: []);
      addTearDown(container.dispose);

      // Simulate a prior sync by patching lastSyncedAt into the notifier state.
      // We do this by running a sync first (so lastSyncedAt = now), then faking
      // the remote to have the old note.
      //
      // Simpler: directly drive the notifier after an initial successful sync
      // that sets lastSyncedAt to a time after deletedNote.updatedAt.
      container.read(syncProvider.notifier);
      // Manually set the lastSyncedAt by running a clean sync first.
      await container.read(syncProvider.notifier).sync();
      // Now lastSyncedAt is around DateTime.now(). deletedNote.updatedAt =
      // 2026-01-01, which is before lastSyncedAt, so it must NOT be merged.
      final uploadsBefore = service.uploadCalls;
      _mergeCalls.clear();
      await container.read(syncProvider.notifier).sync();

      // mergeNotes must NOT have been called with the deleted note.
      final resurrected = _mergeCalls.any(
        (c) => c.incoming.any((n) => n.id == 'deleted'),
      );
      expect(resurrected, isFalse,
          reason: 'Deleted note should not be resurrected from stale remote backup');
      expect(service.uploadCalls, greaterThan(uploadsBefore));
    });

    test('silent sign-in on startup restores session state', () async {
      final service = _FakeDriveSyncService(
        signedIn: false,
        silentSignInResult: true,
      );
      final container = _makeContainer(service: service);
      addTearDown(container.dispose);

      // Reading the notifier triggers its creation, which fires _silentSignIn().
      container.read(syncProvider.notifier);
      // Allow the async signInSilently() call to complete before checking state.
      await Future<void>.delayed(Duration.zero);

      final syncState = container.read(syncProvider);
      expect(syncState.isSignedIn, isTrue);
      expect(syncState.accountEmail, isNotNull);
    });
  });
}
