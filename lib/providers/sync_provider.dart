import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/note.dart';
import '../models/sync_state.dart';
import '../services/database_service.dart';
import '../services/drive_sync_service.dart';
import '../services/note_export_service.dart';

typedef ConnectivityChecker = Future<List<ConnectivityResult>> Function();
typedef NotesGetter = Future<List<Note>> Function();
typedef NotesMerger = Future<void> Function(List<Note> existing, List<Note> incoming);
typedef NotesReloader = Future<void> Function();
typedef EmbeddingReindexer = Future<void> Function();

final connectivityCheckerProvider = Provider<ConnectivityChecker>(
  (ref) => () => Connectivity().checkConnectivity(),
);

final notesGetterProvider = Provider<NotesGetter>(
  (ref) => () => DatabaseService.instance.getAllNotes(),
);

final notesMergerProvider = Provider<NotesMerger>(
  (ref) => (existing, incoming) =>
      DatabaseService.instance.mergeNotes(existing, incoming).then((_) {}),
);

// Reloads the in-memory notes list after a remote merge. Overridden in main()
// to call notesProvider.notifier.loadNotes() without creating a circular import.
final notesReloaderProvider = Provider<NotesReloader>(
  (ref) => () async {},
);

// Triggers embedding generation for notes whose embeddingPending flag is set
// after a remote merge. Overridden in main() to call reindexPendingNotes().
final embeddingReindexerProvider = Provider<EmbeddingReindexer>(
  (ref) => () async {},
);

final syncServiceProvider = Provider<DriveSyncService>(
  (ref) => DriveSyncService(),
);

const _lastSyncKey = 'sync.lastSyncedAt';

class SyncNotifier extends StateNotifier<SyncState> {
  final Ref _ref;
  Timer? _debounce;
  bool _syncInProgress = false;
  bool _syncPending = false;

  SyncNotifier(this._ref) : super(const SyncState()) {
    _init();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    await _loadPersistedState();
    await _silentSignIn();
  }

  Future<void> _loadPersistedState() async {
    final prefs = await SharedPreferences.getInstance();
    final millis = prefs.getInt(_lastSyncKey);
    if (millis != null && mounted) {
      state = state.copyWith(
        lastSyncedAt: DateTime.fromMillisecondsSinceEpoch(millis),
      );
    }
  }

  Future<void> _silentSignIn() async {
    final service = _ref.read(syncServiceProvider);
    final ok = await service.signInSilently();
    if (!mounted) return;
    if (ok) {
      state = state.copyWith(
        isSignedIn: true,
        accountEmail: service.accountEmail,
        clearErrorMessage: true,
      );
      // Chain the first sync so notes are up to date immediately after startup.
      await sync();
    }
  }

  Future<void> signIn() async {
    final service = _ref.read(syncServiceProvider);
    final ok = await service.signIn();
    if (!mounted) return;
    state = state.copyWith(
      isSignedIn: ok,
      accountEmail: ok ? service.accountEmail : null,
      clearAccountEmail: !ok,
      clearErrorMessage: true,
    );
  }

  Future<void> signOut() async {
    final service = _ref.read(syncServiceProvider);
    await service.signOut();
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastSyncKey);
    state = state.copyWith(
      isSignedIn: false,
      clearAccountEmail: true,
      clearLastSyncedAt: true,
      clearErrorMessage: true,
    );
  }

  void scheduleSync() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 5), sync);
  }

  Future<void> sync() async {
    if (_syncInProgress) {
      _syncPending = true;
      return;
    }
    _syncInProgress = true;
    try {
      await _doSync();
      if (_syncPending) {
        _syncPending = false;
        await _doSync();
      }
    } finally {
      _syncInProgress = false;
      _syncPending = false;
    }
  }

  Future<void> _doSync() async {
    final service = _ref.read(syncServiceProvider);
    if (!service.isSignedIn) return;

    final checkConnectivity = _ref.read(connectivityCheckerProvider);
    final connectivity = await checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none) &&
        connectivity.length == 1) {
      return;
    }

    state = state.copyWith(status: SyncStatus.syncing, clearErrorMessage: true);
    try {
      final getNotes = _ref.read(notesGetterProvider);
      final mergeNotes = _ref.read(notesMergerProvider);
      final reloadNotes = _ref.read(notesReloaderProvider);
      final reindexEmbeddings = _ref.read(embeddingReindexerProvider);

      final remote = await service.download();
      if (remote != null) {
        final incoming = NoteExportService.instance.decode(remote);
        // Only merge notes whose updatedAt is strictly after our last sync.
        // Notes older than lastSyncedAt that are absent locally were deleted
        // locally and should not be resurrected from the remote backup.
        final lastSynced = state.lastSyncedAt;
        final toMerge = lastSynced == null
            ? incoming
            : incoming.where((n) => n.updatedAt.isAfter(lastSynced)).toList();
        if (toMerge.isNotEmpty) {
          final existing = await getNotes();
          await mergeNotes(existing, toMerge);
          await reloadNotes();
          await reindexEmbeddings();
        }
      }

      final allNotes = await getNotes();
      final encoded = NoteExportService.instance.encode(allNotes);
      await service.upload(encoded);

      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastSyncKey, now.millisecondsSinceEpoch);
      if (!mounted) return;
      state = state.copyWith(
        status: SyncStatus.idle,
        lastSyncedAt: now,
        clearErrorMessage: true,
      );
    } catch (_) {
      state = state.copyWith(
        status: SyncStatus.error,
        errorMessage: 'Sync failed. Check your connection and try again.',
      );
    }
  }
}

final syncProvider = StateNotifierProvider<SyncNotifier, SyncState>(
  (ref) => SyncNotifier(ref),
);
