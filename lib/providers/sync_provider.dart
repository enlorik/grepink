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
// Tracks note IDs present in the last successful upload so we can distinguish
// "deleted locally" (ID in knownIds, absent in local) from "new from another
// device" (ID not in knownIds) when processing the remote backup.
const _knownIdsKey = 'sync.knownIds';

class SyncNotifier extends StateNotifier<SyncState> {
  final Ref _ref;
  Timer? _debounce;
  bool _syncInProgress = false;
  bool _syncPending = false;
  // Incremented on sign-out so in-flight syncs can detect the cancellation and
  // avoid writing stale watermarks back to SharedPreferences.
  int _syncGeneration = 0;

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
    if (ok) {
      // Immediately download and merge so notes are available without waiting
      // for the next lifecycle resume or manual tap.
      await sync();
    }
  }

  Future<void> signOut() async {
    final service = _ref.read(syncServiceProvider);
    // Increment before awaiting sign-out so any in-flight sync that completes
    // its download while we await will see the changed generation and abort
    // before merging or uploading.
    _syncGeneration++;
    try {
      await service.signOut();
    } catch (_) {}
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastSyncKey);
    await prefs.remove(_knownIdsKey);
    if (!mounted) return;
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
      do {
        _syncPending = false;
        await _doSync();
      } while (_syncPending);
    } finally {
      _syncInProgress = false;
      _syncPending = false;
    }
  }

  Future<void> _doSync() async {
    final capturedGeneration = _syncGeneration;
    final service = _ref.read(syncServiceProvider);
    if (!service.isSignedIn) return;

    state = state.copyWith(status: SyncStatus.syncing, clearErrorMessage: true);
    try {
      // Connectivity check is inside try so a platform-channel failure is caught
      // and surfaces as a sync error rather than an unhandled future exception.
      final checkConnectivity = _ref.read(connectivityCheckerProvider);
      final connectivity = await checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none) &&
          connectivity.length == 1) {
        if (mounted) state = state.copyWith(status: SyncStatus.idle);
        return;
      }

      final getNotes = _ref.read(notesGetterProvider);
      final mergeNotes = _ref.read(notesMergerProvider);
      final reloadNotes = _ref.read(notesReloaderProvider);
      final reindexEmbeddings = _ref.read(embeddingReindexerProvider);

      final prefs = await SharedPreferences.getInstance();
      final knownIds = Set<String>.from(prefs.getStringList(_knownIdsKey) ?? []);

      final localNotes = await getNotes();
      final localIds = {for (final n in localNotes) n.id};

      final remote = await service.download();
      if (remote != null) {
        final incoming = NoteExportService.instance.decode(remote);
        // Merge rules using ID-based deletion tracking:
        // - ID not in knownIds: note from another device never seen here → merge
        // - ID in knownIds AND in localIds: present locally → updatedAt-wins in mergeNotes
        // - ID in knownIds but NOT in localIds: deleted locally → skip to prevent resurrection
        final toMerge = incoming.where((n) {
          if (!knownIds.contains(n.id)) return true;
          return localIds.contains(n.id);
        }).toList();
        if (toMerge.isNotEmpty) {
          // Guard against a sign-out that occurred while the download was in flight.
          if (_syncGeneration != capturedGeneration) {
            if (mounted) state = state.copyWith(status: SyncStatus.idle);
            return;
          }
          await mergeNotes(localNotes, toMerge);
          // Persist the newly merged IDs immediately so that if the subsequent
          // upload fails, a later sync still treats those notes as "known" and
          // respects any local deletion the user makes before the next upload.
          final updatedKnownIds =
              knownIds.union({for (final n in toMerge) n.id});
          await prefs.setStringList(_knownIdsKey, updatedKnownIds.toList());
          await reloadNotes();
          await reindexEmbeddings();
        }
      }

      // Guard before upload so we don't write through another account's DriveApi.
      if (_syncGeneration != capturedGeneration) {
        if (mounted) state = state.copyWith(status: SyncStatus.idle);
        return;
      }
      final allNotes = await getNotes();
      final encoded = NoteExportService.instance.encode(allNotes);
      await service.upload(encoded);

      // Skip persisting if a sign-out happened while the upload was in flight.
      // Reset status to idle so the UI doesn't stay stuck on "syncing".
      if (_syncGeneration != capturedGeneration) {
        if (mounted) state = state.copyWith(status: SyncStatus.idle);
        return;
      }
      final now = DateTime.now();
      await prefs.setInt(_lastSyncKey, now.millisecondsSinceEpoch);
      await prefs.setStringList(_knownIdsKey, allNotes.map((n) => n.id).toList());
      if (!mounted) return;
      state = state.copyWith(
        status: SyncStatus.idle,
        lastSyncedAt: now,
        clearErrorMessage: true,
      );
    } catch (_) {
      if (!mounted) return;
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
