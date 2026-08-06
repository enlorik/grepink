import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/note.dart';
import '../models/sync_state.dart';
import '../services/database_service.dart';
import '../services/drive_sync_service.dart';
import '../services/note_export_service.dart';

typedef ConnectivityChecker = Future<List<ConnectivityResult>> Function();
typedef NotesGetter = Future<List<Note>> Function();
typedef NotesMerger = Future<void> Function(List<Note> existing, List<Note> incoming);

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

final syncServiceProvider = Provider<DriveSyncService>(
  (ref) => DriveSyncService(),
);

class SyncNotifier extends StateNotifier<SyncState> {
  final Ref _ref;
  Timer? _debounce;
  bool _syncInProgress = false;

  SyncNotifier(this._ref) : super(const SyncState());

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> signIn() async {
    final service = _ref.read(syncServiceProvider);
    final ok = await service.signIn();
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
    state = state.copyWith(
      isSignedIn: false,
      clearAccountEmail: true,
      clearErrorMessage: true,
    );
  }

  void scheduleSync() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 5), sync);
  }

  Future<void> sync() async {
    if (_syncInProgress) return;
    _syncInProgress = true;
    try {
      await _doSync();
    } finally {
      _syncInProgress = false;
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

      final remote = await service.download();
      if (remote != null) {
        final incoming = NoteExportService.instance.decode(remote);
        final existing = await getNotes();
        await mergeNotes(existing, incoming);
      }

      final allNotes = await getNotes();
      final encoded = NoteExportService.instance.encode(allNotes);
      await service.upload(encoded);

      state = state.copyWith(
        status: SyncStatus.idle,
        lastSyncedAt: DateTime.now(),
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
