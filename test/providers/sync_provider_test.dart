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
  int uploadCalls = 0;
  String? lastUploaded;

  _FakeDriveSyncService({
    bool signedIn = true,
    String? remote,
    this.throwOnUpload = false,
    this.throwOnDownload = false,
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

  @override
  Future<DateTime?> getRemoteModifiedAt() async => null;
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

      // Force syncing state
      final notifier = container.read(syncProvider.notifier);
      // Run two concurrent syncs; second should be a no-op
      final f1 = notifier.sync();
      final f2 = notifier.sync();
      await Future.wait([f1, f2]);

      expect(service.uploadCalls, 1);
    });

    test('sync() merges remote notes into local when remote exists', () async {
      final older = DateTime.utc(2025, 1, 1);
      final newer = DateTime.utc(2026, 6, 1);
      final remoteNote = _note(id: 'r1', title: 'Remote', updatedAt: newer);
      final localNote = _note(id: 'l1', title: 'Local', updatedAt: older);
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
  });
}
