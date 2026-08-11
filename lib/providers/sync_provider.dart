import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/note.dart';
import '../models/sync_state.dart';
import '../models/tombstone.dart';
import '../services/database_service.dart';
import '../services/drive_sync_service.dart';
import '../services/note_export_service.dart';

typedef ConnectivityChecker = Future<List<ConnectivityResult>> Function();
typedef NotesGetter = Future<List<Note>> Function();
typedef NotesMerger = Future<void> Function(
    List<Note> existing, List<Note> incoming);
typedef NotesReloader = Future<void> Function();
typedef EmbeddingReindexer = Future<void> Function();
typedef NotesDeleter = Future<void> Function(Set<String> ids);
typedef TombstonesGetter = Future<List<Tombstone>> Function();

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

// Returns all local tombstones for inclusion in the next upload payload.
// Overridden in tests to return an empty list by default.
final tombstonesGetterProvider = Provider<TombstonesGetter>(
  (ref) => () => DatabaseService.instance.getTombstones(),
);

// On non-Android platforms (and unonfigured iOS/web) google_sign_in must not
// be constructed. An unsupported-platform service signals not-signed-in so the
// UI can show an appropriate message.
final syncServiceProvider = Provider<DriveSyncService>((ref) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return const _UnsupportedDriveSyncService();
  }
  return DriveSyncService();
});

// ---------------------------------------------------------------------------
// Account-scoped SharedPreferences keys
// ---------------------------------------------------------------------------

String _lastSyncKey(String email) => 'sync.$email.lastSyncedAt';
String _knownIdsKey(String email) => 'sync.$email.knownIds';
String _forceUploadPendingKey(String email) => 'sync.$email.forceUploadPending';

// Legacy (unnamespaced) keys present before account-scoping was introduced.
const _legacyLastSyncKey = 'sync.lastSyncedAt';
const _legacyKnownIdsKey = 'sync.knownIds';
const _legacyForceUploadPendingKey = 'sync.forceUploadPending';

// ---------------------------------------------------------------------------
// Internal coordinator types
// ---------------------------------------------------------------------------

enum _SyncKind { forceUpload, regular }

class _WorkItem {
  final _SyncKind kind;
  // completer may be null for internally-injected recovery items.
  final Completer<void>? completer;
  _WorkItem(this.kind, [this.completer]);
}

// ---------------------------------------------------------------------------
// SyncNotifier
// ---------------------------------------------------------------------------

class SyncNotifier extends StateNotifier<SyncState> {
  final Ref _ref;
  Timer? _debounce;

  // Serialized coordinator state.
  final List<_WorkItem> _queue = [];
  bool _draining = false;

  // Incremented on sign-out so in-flight syncs can detect the cancellation and
  // avoid writing stale watermarks back to SharedPreferences.
  int _syncGeneration = 0;

  // Throttle for lifecycle-triggered syncs (app resume).
  DateTime? _lastCompletedSyncAt;
  static const _resumeThrottle = Duration(seconds: 60);

  SyncNotifier(this._ref) : super(const SyncState()) {
    _init();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    // Complete any pending queue items so callers are not left hanging.
    for (final item in [..._queue]) {
      item.completer?.complete();
    }
    _queue.clear();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  Future<void> _init() async {
    await _silentSignIn();
  }

  Future<void> _silentSignIn() async {
    final service = _ref.read(syncServiceProvider);
    final ok = await service.signInSilently();
    if (!mounted) return;
    if (ok) {
      final email = service.accountEmail!;
      state = state.copyWith(
        isSignedIn: true,
        accountEmail: email,
        clearErrorMessage: true,
      );
      await _migratePrefs(email);
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      await _loadPersistedLastSync(prefs, email);
      final forceUpload = prefs.getBool(_forceUploadPendingKey(email)) ?? false;
      if (forceUpload) {
        await syncUploadOnly();
      } else {
        await sync();
      }
    }
  }

  Future<void> _loadPersistedLastSync(
      SharedPreferences prefs, String email) async {
    final millis = prefs.getInt(_lastSyncKey(email));
    if (millis != null && mounted) {
      state = state.copyWith(
        lastSyncedAt: DateTime.fromMillisecondsSinceEpoch(millis),
      );
    }
  }

  // One-time migration: copy unnamespaced keys to account-scoped keys, then
  // remove the legacy keys so they are not re-read by a signed-out startup.
  Future<void> _migratePrefs(String email) async {
    final prefs = await SharedPreferences.getInstance();
    bool dirty = false;

    if (prefs.containsKey(_legacyLastSyncKey) &&
        !prefs.containsKey(_lastSyncKey(email))) {
      final v = prefs.getInt(_legacyLastSyncKey);
      if (v != null) await prefs.setInt(_lastSyncKey(email), v);
      dirty = true;
    }
    if (prefs.containsKey(_legacyKnownIdsKey) &&
        !prefs.containsKey(_knownIdsKey(email))) {
      final v = prefs.getStringList(_legacyKnownIdsKey);
      if (v != null) await prefs.setStringList(_knownIdsKey(email), v);
      dirty = true;
    }
    if (prefs.containsKey(_legacyForceUploadPendingKey) &&
        !prefs.containsKey(_forceUploadPendingKey(email))) {
      final v = prefs.getBool(_legacyForceUploadPendingKey);
      if (v != null) await prefs.setBool(_forceUploadPendingKey(email), v);
      dirty = true;
    }

    if (dirty) {
      await prefs.remove(_legacyLastSyncKey);
      await prefs.remove(_legacyKnownIdsKey);
      await prefs.remove(_legacyForceUploadPendingKey);
    }
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  Future<void> signIn() async {
    final service = _ref.read(syncServiceProvider);
    final ok = await service.signIn();
    if (!mounted) return;
    final email = ok ? service.accountEmail : null;
    state = state.copyWith(
      isSignedIn: ok,
      accountEmail: ok ? email : null,
      clearAccountEmail: !ok,
      clearErrorMessage: true,
    );
    if (ok && email != null) {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      await _loadPersistedLastSync(prefs, email);
      // Honor a durable force-upload flag that was set before sign-in.
      final forceUpload = prefs.getBool(_forceUploadPendingKey(email)) ?? false;
      if (forceUpload) {
        await syncUploadOnly();
      } else {
        await sync();
      }
    }
  }

  Future<void> signOut() async {
    final email = state.accountEmail;
    // Increment before awaiting so any in-flight sync that resumes after an
    // internal await sees the changed generation and aborts before writing state.
    _syncGeneration++;
    final service = _ref.read(syncServiceProvider);
    try {
      await service.signOut();
    } catch (_) {}
    if (!mounted) return;
    if (email != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastSyncKey(email));
      await prefs.remove(_knownIdsKey(email));
      await prefs.remove(_forceUploadPendingKey(email));
      await prefs.remove('sync.$email.fileId');
    }
    if (!mounted) return;
    // Drain the coordinator without running any more operations.
    for (final item in [..._queue]) {
      item.completer?.complete();
    }
    _queue.clear();
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

  // Enqueues a full download-merge-upload cycle with the lowest priority
  // (force uploads run first). If a durable force-upload flag is set from a
  // previous session, a recovery force-upload is inserted before this sync.
  Future<void> sync() async {
    final email = state.accountEmail;
    if (email != null) {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      if (prefs.getBool(_forceUploadPendingKey(email)) ?? false) {
        // Ensure a force upload drains first; do NOT await it so this sync
        // request is also queued and runs after.
        _enqueueNoWait(_SyncKind.forceUpload);
      }
    }
    return _enqueue(_SyncKind.regular);
  }

  // Immediately uploads all local notes to Drive without downloading first.
  // Sets a durable marker before queuing so a process kill before the upload
  // completes causes a retry on the next launch or sign-in.
  Future<void> syncUploadOnly() async {
    final email = state.accountEmail;
    if (email != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_forceUploadPendingKey(email), true);
    }
    return _enqueue(_SyncKind.forceUpload);
  }

  // Throttled resume-triggered sync (called from lifecycle observer).
  void syncOnResume() {
    if (!state.isSignedIn) return;
    final now = DateTime.now();
    if (_lastCompletedSyncAt != null &&
        now.difference(_lastCompletedSyncAt!) < _resumeThrottle) {
      return;
    }
    sync();
  }

  // ---------------------------------------------------------------------------
  // Coordinator
  // ---------------------------------------------------------------------------

  // Enqueues [kind] and starts the drain loop if not already running.
  // Returns a Future that completes when this specific work item finishes.
  Future<void> _enqueue(_SyncKind kind) {
    final item = _WorkItem(kind, Completer<void>());
    _queue.add(item);
    _maybeStartDrain();
    return item.completer!.future;
  }

  // Enqueues [kind] without returning a waitable future (fire-and-forget).
  void _enqueueNoWait(_SyncKind kind) {
    _queue.add(_WorkItem(kind));
    _maybeStartDrain();
  }

  void _maybeStartDrain() {
    if (_draining) return;
    _draining = true;
    _drainLoop().whenComplete(() => _draining = false);
  }

  Future<void> _drainLoop() async {
    final gen = _syncGeneration;

    while (_syncGeneration == gen) {
      // At the top of each iteration, inject a recovery force-upload if the
      // durable flag is set and no force-upload is already queued.
      await _injectDurableForceUploadIfNeeded(gen);

      if (!mounted) break;
      if (_syncGeneration != gen) break;

      if (_queue.isEmpty) break;

      // Force uploads always run before regular syncs.
      final fi = _queue.indexWhere((e) => e.kind == _SyncKind.forceUpload);
      final item = fi >= 0 ? _queue.removeAt(fi) : _queue.removeAt(0);

      bool success = false;
      if (item.kind == _SyncKind.forceUpload) {
        success = await _doUploadOnly(gen);
        // Clear the durable marker only when this was the last force-upload
        // in the queue and it succeeded.
        if (success && !_queue.any((e) => e.kind == _SyncKind.forceUpload)) {
          await _clearForceUploadMarker();
        }
      } else {
        await _doSync(gen);
      }

      item.completer?.complete();
    }

    // Sign-out cancelled this drain — complete remaining items.
    if (_syncGeneration != gen) {
      for (final item in [..._queue]) {
        item.completer?.complete();
      }
      _queue.clear();
    }
  }

  Future<void> _injectDurableForceUploadIfNeeded(int gen) async {
    if (_syncGeneration != gen) return;
    if (!mounted) return;
    final email = state.accountEmail;
    if (email == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (_syncGeneration != gen) return;
    if ((prefs.getBool(_forceUploadPendingKey(email)) ?? false) &&
        !_queue.any((e) => e.kind == _SyncKind.forceUpload)) {
      _queue.insert(0, _WorkItem(_SyncKind.forceUpload));
    }
  }

  Future<void> _clearForceUploadMarker() async {
    final service = _ref.read(syncServiceProvider);
    final email = state.accountEmail ??
        (service.isSignedIn ? service.accountEmail : null);
    if (email == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_forceUploadPendingKey(email));
  }

  // ---------------------------------------------------------------------------
  // Core sync operations
  // ---------------------------------------------------------------------------

  // Returns true on success, false on failure (state is updated internally).
  Future<bool> _doUploadOnly(int capturedGeneration) async {
    final service = _ref.read(syncServiceProvider);
    if (!service.isSignedIn) return true;

    // Resolve account email from state first, then fall back to the service so
    // the durable marker is always written even when state has not yet been
    // updated (e.g. first call before silent sign-in updates the notifier state).
    final email = state.accountEmail ??
        (service.isSignedIn ? service.accountEmail : null);

    // Ensure the durable marker is written before the upload attempt so that
    // a process kill between here and a successful upload triggers a retry.
    if (email != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_forceUploadPendingKey(email), true);
    }

    if (!mounted) return false;
    state = state.copyWith(status: SyncStatus.syncing, clearErrorMessage: true);
    try {
      final checkConnectivity = _ref.read(connectivityCheckerProvider);
      final connectivity = await checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none) &&
          connectivity.length == 1) {
        if (mounted) state = state.copyWith(status: SyncStatus.idle);
        return false;
      }
      if (_syncGeneration != capturedGeneration) {
        if (mounted) state = state.copyWith(status: SyncStatus.idle);
        return false;
      }
      final getNotes = _ref.read(notesGetterProvider);
      final getTombstones = _ref.read(tombstonesGetterProvider);
      final allNotes = await getNotes();
      final tombstones = await getTombstones();
      final encoded =
          NoteExportService.instance.encode(allNotes, tombstones: tombstones);
      await service.upload(encoded);
      if (_syncGeneration != capturedGeneration) {
        if (mounted) state = state.copyWith(status: SyncStatus.idle);
        return false;
      }
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      if (email != null) {
        await prefs.setInt(_lastSyncKey(email), now.millisecondsSinceEpoch);
        await prefs.setStringList(
            _knownIdsKey(email), allNotes.map((n) => n.id).toList());
      }
      if (!mounted) return true;
      _lastCompletedSyncAt = now;
      state = state.copyWith(
        status: SyncStatus.idle,
        lastSyncedAt: now,
        clearErrorMessage: true,
      );
      return true;
    } catch (_) {
      if (!mounted) return false;
      state = state.copyWith(
        status: SyncStatus.error,
        errorMessage: 'Sync failed. Check your connection and try again.',
      );
      return false;
    }
  }

  Future<void> _doSync(int capturedGeneration) async {
    final service = _ref.read(syncServiceProvider);
    if (!service.isSignedIn) return;

    final email = state.accountEmail;

    state = state.copyWith(status: SyncStatus.syncing, clearErrorMessage: true);
    try {
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
      final getTombstones = _ref.read(tombstonesGetterProvider);

      final prefs = await SharedPreferences.getInstance();
      final knownIds = Set<String>.from(email != null
          ? (prefs.getStringList(_knownIdsKey(email)) ?? [])
          : []);

      final remote = await service.download();
      if (remote != null) {
        final payload = NoteExportService.instance.decodePayload(remote);
        final incoming = payload.notes;
        final incomingTombstones = payload.tombstones;
        final replacedAt = payload.replacedAt;

        // Re-read local state after the download so any deletions that occurred
        // while the network call was in flight are reflected in the filter.
        var currentLocalNotes = await getNotes();
        var currentLocalIds = {for (final n in currentLocalNotes) n.id};
        final localNoteById = {for (final n in currentLocalNotes) n.id: n};
        final incomingIds = {for (final n in incoming) n.id};

        // --- Authoritative replacement ---
        // If the remote payload carries a replacedAt timestamp, any local note
        // (or tombstone) older than that timestamp is superseded by the remote.
        // Notes edited after replacedAt are preserved.
        if (replacedAt != null) {
          final replacedAtDt = DateTime.fromMillisecondsSinceEpoch(replacedAt);
          final authorityDeleteIds = currentLocalIds.where((id) {
            if (incomingIds.contains(id)) return false;
            final n = localNoteById[id];
            if (n == null) return false;
            return !n.updatedAt.isAfter(replacedAtDt);
          }).toSet();
          if (authorityDeleteIds.isNotEmpty) {
            if (_syncGeneration != capturedGeneration) {
              if (mounted) state = state.copyWith(status: SyncStatus.idle);
              return;
            }
            await deleteNotes(authorityDeleteIds);
            currentLocalNotes = currentLocalNotes
                .where((n) => !authorityDeleteIds.contains(n.id))
                .toList();
            currentLocalIds = currentLocalIds.difference(authorityDeleteIds);
            knownIds.removeAll(authorityDeleteIds);
            await reloadNotes();
          }
        }

        // --- Tombstone-based deletion ---
        // Notes deleted on another device are signalled by an explicit tombstone.
        // A local edit that postdates the tombstone's deletedAt survives.
        final incomingTombstoneIds = {for (final t in incomingTombstones) t.id};
        final tombstoneDeleteIds = <String>{};
        for (final tombstone in incomingTombstones) {
          final local = localNoteById[tombstone.id];
          if (local == null) continue;
          final deletedAt =
              DateTime.fromMillisecondsSinceEpoch(tombstone.deletedAt);
          if (!local.updatedAt.isAfter(deletedAt)) {
            tombstoneDeleteIds.add(tombstone.id);
          }
        }

        // --- Absence-based deletion (legacy guard) ---
        // Notes in knownIds, present locally, but absent from the remote backup
        // were deleted on another device. An empty backup is valid — it means
        // the remote cleared all notes intentionally.
        final sinceLastSync = state.lastSyncedAt;
        final remoteDeletedIds = knownIds.where((id) {
          if (!currentLocalIds.contains(id) || incomingIds.contains(id)) {
            return false;
          }
          // The remote carries a tombstone for this note — the tombstone-based
          // check already made the correct decision (delete or preserve).
          // Skip absence-based inference to avoid double-counting.
          if (incomingTombstoneIds.contains(id)) return false;
          // Preserve local edits made after the last sync.
          if (sinceLastSync != null) {
            final n = localNoteById[id];
            if (n != null && n.updatedAt.isAfter(sinceLastSync)) return false;
          }
          return true;
        }).toSet();

        final toDeleteIds = tombstoneDeleteIds.union(remoteDeletedIds);
        if (toDeleteIds.isNotEmpty) {
          if (_syncGeneration != capturedGeneration) {
            if (mounted) state = state.copyWith(status: SyncStatus.idle);
            return;
          }
          await deleteNotes(toDeleteIds);
          currentLocalNotes = currentLocalNotes
              .where((n) => !toDeleteIds.contains(n.id))
              .toList();
          currentLocalIds = currentLocalIds.difference(toDeleteIds);
          knownIds.removeAll(toDeleteIds);
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
          if (_syncGeneration != capturedGeneration) {
            if (mounted) state = state.copyWith(status: SyncStatus.idle);
            return;
          }
          await mergeNotes(currentLocalNotes, toMerge);
          // Persist the newly merged IDs so a later sync treats them as "known".
          final updatedKnownIds =
              knownIds.union({for (final n in toMerge) n.id});
          if (email != null) {
            await prefs.setStringList(
                _knownIdsKey(email), updatedKnownIds.toList());
          }
          await reloadNotes();
          await reindexEmbeddings();
        }
      }

      if (_syncGeneration != capturedGeneration) {
        if (mounted) state = state.copyWith(status: SyncStatus.idle);
        return;
      }

      // Upload with conflict retry (on DriveSyncConflictException, re-download
      // and retry once so the two-device {N}+X / {N}+Y scenario converges).
      final allNotes = await getNotes();
      final tombstones = await getTombstones();
      final encoded =
          NoteExportService.instance.encode(allNotes, tombstones: tombstones);
      try {
        await service.upload(encoded);
      } on DriveSyncConflictException {
        // Another device wrote while we were syncing — re-download, merge, retry.
        final remote2 = await service.download();
        if (remote2 != null) {
          final payload2 = NoteExportService.instance.decodePayload(remote2);
          if (_syncGeneration != capturedGeneration) {
            if (mounted) state = state.copyWith(status: SyncStatus.idle);
            return;
          }
          final freshLocal = await getNotes();
          await mergeNotes(freshLocal, payload2.notes);
          await reloadNotes();
        }
        final retryNotes = await getNotes();
        final retryTombstones = await getTombstones();
        await service.upload(NoteExportService.instance
            .encode(retryNotes, tombstones: retryTombstones));
        allNotes.clear();
        allNotes.addAll(retryNotes);
      }

      if (_syncGeneration != capturedGeneration) {
        if (mounted) state = state.copyWith(status: SyncStatus.idle);
        return;
      }
      final now = DateTime.now();
      if (email != null) {
        await prefs.setInt(_lastSyncKey(email), now.millisecondsSinceEpoch);
        await prefs.setStringList(
            _knownIdsKey(email), allNotes.map((n) => n.id).toList());
      }
      if (!mounted) return;
      _lastCompletedSyncAt = now;
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

// ---------------------------------------------------------------------------
// Unsupported-platform stub
// ---------------------------------------------------------------------------

class _UnsupportedDriveSyncService implements DriveSyncService {
  const _UnsupportedDriveSyncService();
  @override
  bool get isSignedIn => false;
  @override
  String? get accountEmail => null;
  @override
  Future<bool> signIn() async => false;
  @override
  Future<bool> signInSilently() async => false;
  @override
  Future<void> signOut() async {}
  @override
  Future<void> upload(String _) async {}
  @override
  Future<String?> download() async => null;
}
