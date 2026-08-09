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
typedef NotesDeleter = Future<void> Function(Set<String> ids);

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

// Deletes notes by ID from local storage. Overridden in tests to avoid real DB access.
final notesDeleterProvider = Provider<NotesDeleter>(
  (ref) => (ids) async {
    for (final id in ids) {
      await DatabaseService.instance.deleteNote(id);
    }
  },
);

final syncServiceProvider = Provider<DriveSyncService>(
  (ref) => DriveSyncService(),
);

const _lastSyncKey = 'sync.lastSyncedAt';
// Tracks note IDs present in the last successful upload so we can distinguish
// "deleted locally" (ID in knownIds, absent in local) from "new from another
// device" (ID not in knownIds) when processing the remote backup.
const _knownIdsKey = 'sync.knownIds';
// Survives process termination so that a failed force-upload (e.g. app killed
// mid-upload after replaceAll) is retried on the next launch rather than
// letting a download-merge overwrite the explicitly restored backup.
const _forceUploadPendingKey = 'sync.forceUploadPending';

class SyncNotifier extends StateNotifier<SyncState> {
  final Ref _ref;
  Timer? _debounce;
  bool _syncInProgress = false;
  bool _syncPending = false;
  // Set when syncUploadOnly() is called while a regular sync is in progress,
  // so the upload-only pass runs immediately after the active sync finishes.
  bool _forceUploadPending = false;
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
    final forceUpload = await _loadPersistedState();
    await _silentSignIn(forceUpload: forceUpload);
  }

  // Returns true when a durable force-upload flag is set (a replaceAll was
  // interrupted before the backup reached Drive).
  Future<bool> _loadPersistedState() async {
    final prefs = await SharedPreferences.getInstance();
    final millis = prefs.getInt(_lastSyncKey);
    if (millis != null && mounted) {
      state = state.copyWith(
        lastSyncedAt: DateTime.fromMillisecondsSinceEpoch(millis),
      );
    }
    return prefs.getBool(_forceUploadPendingKey) ?? false;
  }

  Future<void> _silentSignIn({bool forceUpload = false}) async {
    final service = _ref.read(syncServiceProvider);
    final ok = await service.signInSilently();
    if (!mounted) return;
    if (ok) {
      state = state.copyWith(
        isSignedIn: true,
        accountEmail: service.accountEmail,
        clearErrorMessage: true,
      );
      // If a replaceAll was interrupted by process termination before the
      // upload completed, upload-only so the restored snapshot reaches Drive
      // before any download-merge can overwrite it.
      if (forceUpload) {
        await syncUploadOnly();
      } else {
        await sync();
      }
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
      // If a replaceAll was interrupted while signed out, honor the durable
      // flag so newer Drive versions cannot overwrite the restored backup.
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final forceUpload = prefs.getBool(_forceUploadPendingKey) ?? false;
      if (forceUpload) {
        await syncUploadOnly();
      } else {
        await sync();
      }
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
    await prefs.remove(_forceUploadPendingKey);
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
      // If syncUploadOnly() was called while the drain loop was running
      // (e.g. replaceAll fired mid-sync), drain all queued upload-only passes
      // so Drive reflects every replacement, even if multiple fired mid-sync.
      while (_forceUploadPending) {
        _forceUploadPending = false;
        await _doUploadOnly();
      }
    } finally {
      _syncInProgress = false;
      _syncPending = false;
      _forceUploadPending = false;
    }
  }

  // Uploads current local notes to Drive without downloading or merging first.
  // Used after replaceAll to avoid a subsequent merge overwriting the restored notes.
  // If a sync is already in progress, queues a force-upload-only pass to run
  // immediately after the active sync finishes.
  Future<void> syncUploadOnly() async {
    // Record durably so a process kill before the upload completes triggers
    // a retry on the next launch instead of allowing a merge to overwrite
    // the explicitly restored backup.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_forceUploadPendingKey, true);

    if (_syncInProgress) {
      _forceUploadPending = true;
      return;
    }
    _syncInProgress = true;
    try {
      // Drain consecutive force uploads (e.g. a second replaceAll fired while
      // an earlier upload-only pass was still in flight).
      do {
        _forceUploadPending = false;
        await _doUploadOnly();
      } while (_forceUploadPending);
      // Then drain any regular sync requests queued during the upload(s).
      while (_syncPending) {
        _syncPending = false;
        await _doSync();
      }
    } finally {
      _syncInProgress = false;
      _syncPending = false;
      _forceUploadPending = false;
    }
  }

  Future<void> _doUploadOnly() async {
    final capturedGeneration = _syncGeneration;
    final service = _ref.read(syncServiceProvider);
    if (!service.isSignedIn) return;

    state = state.copyWith(status: SyncStatus.syncing, clearErrorMessage: true);
    try {
      final checkConnectivity = _ref.read(connectivityCheckerProvider);
      final connectivity = await checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none) &&
          connectivity.length == 1) {
        if (mounted) state = state.copyWith(status: SyncStatus.idle);
        return;
      }
      if (_syncGeneration != capturedGeneration) {
        if (mounted) state = state.copyWith(status: SyncStatus.idle);
        return;
      }
      final getNotes = _ref.read(notesGetterProvider);
      final allNotes = await getNotes();
      final encoded = NoteExportService.instance.encode(allNotes);
      await service.upload(encoded);
      if (_syncGeneration != capturedGeneration) {
        if (mounted) state = state.copyWith(status: SyncStatus.idle);
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      await prefs.setInt(_lastSyncKey, now.millisecondsSinceEpoch);
      await prefs.setStringList(_knownIdsKey, allNotes.map((n) => n.id).toList());
      // Only clear the durable flag when no further force-upload is queued.
      // If _forceUploadPending was set by a concurrent syncUploadOnly() while
      // this upload was in flight, the drain loop will call us again — keep
      // the flag so a crash before that second upload still triggers recovery.
      if (!_forceUploadPending) {
        await prefs.remove(_forceUploadPendingKey);
      }
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
      final deleteNotes = _ref.read(notesDeleterProvider);

      final prefs = await SharedPreferences.getInstance();
      final knownIds = Set<String>.from(prefs.getStringList(_knownIdsKey) ?? []);

      final remote = await service.download();
      if (remote != null) {
        final incoming = NoteExportService.instance.decode(remote);
        // Re-read local state after the download so any deletions that occurred
        // while the network call was in flight are reflected in the filter.
        // This minimises the staleness window to the time between this read and
        // mergeNotes (effectively zero compared to a network round-trip).
        var currentLocalNotes = await getNotes();
        var currentLocalIds = {for (final n in currentLocalNotes) n.id};

        // Cross-device deletions: notes in knownIds, present locally, but absent
        // from the remote backup were deleted on another device. An empty backup
        // is valid — it means the remote cleared all notes intentionally.
        final incomingIds = {for (final n in incoming) n.id};
        final localNoteById = {for (final n in currentLocalNotes) n.id: n};
        final sinceLastSync = state.lastSyncedAt;
        final remoteDeletedIds = knownIds.where((id) {
          if (!currentLocalIds.contains(id) || incomingIds.contains(id)) return false;
          // Preserve local edits made after the last sync: we cannot tell
          // whether the remote deletion or the local edit happened later, so
          // we keep the edit rather than risk data loss.
          if (sinceLastSync != null) {
            final localNote = localNoteById[id];
            if (localNote != null && localNote.updatedAt.isAfter(sinceLastSync)) {
              return false;
            }
          }
          return true;
        }).toSet();
        if (remoteDeletedIds.isNotEmpty) {
          if (_syncGeneration != capturedGeneration) {
            if (mounted) state = state.copyWith(status: SyncStatus.idle);
            return;
          }
          await deleteNotes(remoteDeletedIds);
          currentLocalNotes = currentLocalNotes
              .where((n) => !remoteDeletedIds.contains(n.id))
              .toList();
          currentLocalIds = currentLocalIds.difference(remoteDeletedIds);
          knownIds.removeAll(remoteDeletedIds);
          await reloadNotes();
        }

        // Merge rules using ID-based deletion tracking:
        // - ID not in knownIds: note from another device never seen here → merge
        // - ID in knownIds AND in currentLocalIds: present locally → updatedAt-wins
        // - ID in knownIds but NOT in currentLocalIds: deleted locally → skip
        final toMerge = incoming.where((n) {
          if (!knownIds.contains(n.id)) return true;
          return currentLocalIds.contains(n.id);
        }).toList();
        if (toMerge.isNotEmpty) {
          // Guard against a sign-out that occurred while the download was in flight.
          if (_syncGeneration != capturedGeneration) {
            if (mounted) state = state.copyWith(status: SyncStatus.idle);
            return;
          }
          await mergeNotes(currentLocalNotes, toMerge);
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
