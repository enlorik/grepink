import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/note.dart';
import '../models/railway_sync_state.dart';
import '../services/database_service.dart';
import '../services/railway_http_client.dart';
import '../services/railway_settings_service.dart';

const _uuid = Uuid();

// ---------------------------------------------------------------------------
// Injectable function types (for testability)
// ---------------------------------------------------------------------------

typedef RailwayNotesReloader = Future<void> Function();
typedef RailwayEmbeddingReindexer = Future<void> Function();

final railwayNotesReloaderProvider = Provider<RailwayNotesReloader>(
  (ref) => () async {},
);

final railwayEmbeddingReindexerProvider = Provider<RailwayEmbeddingReindexer>(
  (ref) => () async {},
);

// Overridable so tests can inject fake clients and settings services.
final railwayHttpClientProvider = Provider<RailwayHttpClient>(
  (ref) => LiveRailwayHttpClient(),
);

final railwaySettingsServiceProvider = Provider<RailwaySettingsService>(
  (ref) => RailwaySettingsService(),
);

// ---------------------------------------------------------------------------
// Coordinator state machine
// ---------------------------------------------------------------------------

enum _TriggerKind { mutation, startup, resume, manual }

class _Trigger {
  final _TriggerKind kind;
  final Completer<void>? completer;
  _Trigger(this.kind, [this.completer]);
}

class RailwaySyncNotifier extends StateNotifier<RailwaySyncState> {
  final Ref _ref;

  final List<_Trigger> _queue = [];
  bool _draining = false;
  int _generation = 0;
  DateTime? _lastSyncAt;
  static const _resumeThrottle = Duration(seconds: 60);

  RailwaySyncNotifier(this._ref) : super(const RailwaySyncState()) {
    _init();
  }

  @override
  void dispose() {
    for (final t in [..._queue]) {
      t.completer?.complete();
    }
    _queue.clear();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  Future<void> _init() async {
    final settings = _ref.read(railwaySettingsServiceProvider);
    final configured = await settings.isConfigured();
    if (!configured) {
      if (mounted) state = const RailwaySyncState(status: RailwaySyncStatus.notConfigured);
      return;
    }
    final lastSync = await settings.getLastSyncedAt();
    if (mounted) {
      state = RailwaySyncState(
        status: RailwaySyncStatus.idle,
        lastSyncedAt: lastSync,
      );
    }
    _enqueue(_TriggerKind.startup);
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  void triggerAfterMutation() {
    if (state.status == RailwaySyncStatus.notConfigured) return;
    _enqueueNoWait(_TriggerKind.mutation);
  }

  Future<void> syncNow() {
    if (state.status == RailwaySyncStatus.notConfigured) {
      return Future.value();
    }
    return _enqueue(_TriggerKind.manual);
  }

  void syncOnResume() {
    if (state.status == RailwaySyncStatus.notConfigured) return;
    final now = DateTime.now();
    if (_lastSyncAt != null &&
        now.difference(_lastSyncAt!) < _resumeThrottle) {
      return;
    }
    _enqueueNoWait(_TriggerKind.resume);
  }

  /// Cancels any in-flight drain so that subsequent calls to resetSyncState
  /// and reconfigure start with a clean slate. The running loop exits at its
  /// next async boundary without applying stale server responses.
  void cancelDrain() => _generation++;

  Future<bool> testConnection(String baseUrl, String token) async {
    final client = _ref.read(railwayHttpClientProvider);
    try {
      return await client.checkStatus(baseUrl, token);
    } catch (_) {
      return false;
    }
  }

  Future<void> reconfigure() async {
    final settings = _ref.read(railwaySettingsServiceProvider);
    final configured = await settings.isConfigured();
    if (!mounted) return;
    if (configured) {
      final lastSync = await settings.getLastSyncedAt();
      state = RailwaySyncState(
        status: RailwaySyncStatus.idle,
        lastSyncedAt: lastSync,
      );
      _enqueueNoWait(_TriggerKind.startup);
    } else {
      state = const RailwaySyncState(status: RailwaySyncStatus.notConfigured);
    }
  }

  // ---------------------------------------------------------------------------
  // Coordinator
  // ---------------------------------------------------------------------------

  Future<void> _enqueue(_TriggerKind kind) {
    final t = _Trigger(kind, Completer<void>());
    _queue.add(t);
    _maybeStartDrain();
    return t.completer!.future;
  }

  void _enqueueNoWait(_TriggerKind kind) {
    _queue.add(_Trigger(kind));
    _maybeStartDrain();
  }

  void _maybeStartDrain() {
    if (_draining) return;
    _draining = true;
    _drain().whenComplete(() => _draining = false);
  }

  Future<void> _drain() async {
    final gen = _generation;
    while (_queue.isNotEmpty && mounted && _generation == gen) {
      // Take the first item, complete and discard any queued behind it.
      final item = _queue.removeAt(0);
      _flushQueue();

      final broke = await _runSyncLoop(gen);

      item.completer?.complete();

      if (broke || _generation != gen) {
        // Complete any triggers that arrived during the sync before stopping.
        _flushQueue();
        break;
      }
    }
  }

  void _flushQueue() {
    for (final t in [..._queue]) {
      t.completer?.complete();
    }
    _queue.clear();
  }

  /// Runs the outbox drain loop. Returns true if sync should stop (error).
  /// [gen] is the generation at which this loop was started; if _generation
  /// changes (cancelDrain was called), the loop exits without applying any
  /// further server responses to avoid applying stale data after a reset.
  Future<bool> _runSyncLoop(int gen) async {
    final settings = _ref.read(railwaySettingsServiceProvider);
    final client = _ref.read(railwayHttpClientProvider);

    final url = await settings.getApiUrl();
    final token = await settings.getToken();
    if (url == null || url.isEmpty || token == null || token.isEmpty) {
      if (mounted) {
        state = state.copyWith(status: RailwaySyncStatus.notConfigured);
      }
      return true;
    }

    if (mounted) {
      state = state.copyWith(
        status: RailwaySyncStatus.syncing,
        clearErrorMessage: true,
      );
    }

    try {
      // Drain until the outbox is empty or we hit a break condition.
      while (mounted && _generation == gen) {
        final entries = await DatabaseService.instance.getOutboxEntries();
        if (_generation != gen) break;

        // Collect the oldest pending entry per note.
        final perNote = <String, OutboxEntry>{};
        for (final e in entries) {
          perNote.putIfAbsent(e.noteId, () => e);
        }

        if (perNote.isEmpty) {
          // Outbox empty — do a read-only sync to pull in remote changes.
          final response = await client.sync(url, token, []);
          if (_generation != gen) break;
          if (mounted) await _applyResponse(response, [], settings);
          break;
        }

        // Cap each request to 500 mutations to stay within the server limit.
        const maxPerRequest = 500;
        final batch = perNote.values.take(maxPerRequest).toList();
        final mutations = batch.map((e) => e.toMutationJson()).toList();
        final response = await client.sync(url, token, mutations);

        if (!mounted || _generation != gen) break;
        await _applyResponse(response, batch, settings);

        // Recheck the outbox — mutations added during the request still need draining.
        final remaining = await DatabaseService.instance.getOutboxEntries();
        if (_generation != gen) break;
        if (remaining.isEmpty) {
          // Pull remote snapshot on final pass.
          final finalResp = await client.sync(url, token, []);
          if (_generation != gen) break;
          if (mounted) await _applyResponse(finalResp, [], settings);
          break;
        }
      }

      final now = DateTime.now();
      await settings.setLastSyncedAt(now);
      if (mounted) {
        _lastSyncAt = now;
        final pending =
            (await DatabaseService.instance.getOutboxEntries()).isNotEmpty;
        state = state.copyWith(
          status: pending
              ? RailwaySyncStatus.pendingChanges
              : RailwaySyncStatus.upToDate,
          lastSyncedAt: now,
          clearErrorMessage: true,
          conflictPreserved: state.conflictPreserved,
        );
      }
      return false;
    } on RailwayAuthException {
      if (mounted) {
        state = state.copyWith(
          status: RailwaySyncStatus.authFailed,
          errorMessage: 'Authentication failed. Check your sync token.',
        );
      }
      return true;
    } on SocketException catch (_) {
      if (mounted) {
        state = state.copyWith(
          status: RailwaySyncStatus.offline,
          errorMessage: 'Offline. Changes will sync when connected.',
        );
      }
      return true;
    } on TimeoutException catch (_) {
      // Timeout after the server may have committed — leave outbox intact for retry.
      if (mounted) {
        state = state.copyWith(
          status: RailwaySyncStatus.offline,
          errorMessage: 'Sync timed out. Will retry.',
        );
      }
      return true;
    } on RailwayInsecureEndpointException {
      if (mounted) {
        state = state.copyWith(
          status: RailwaySyncStatus.authFailed,
          errorMessage: 'Endpoint must use HTTPS.',
        );
      }
      return true;
    } catch (_) {
      if (mounted) {
        state = state.copyWith(
          status: RailwaySyncStatus.error,
          errorMessage: 'Sync failed. Will retry.',
        );
      }
      return true;
    }
  }

  Future<void> _applyResponse(
    RailwaySyncResponse response,
    List<OutboxEntry> sentEntries,
    RailwaySettingsService settings,
  ) async {
    final reloadNotes = _ref.read(railwayNotesReloaderProvider);
    final reindexEmbeddings = _ref.read(railwayEmbeddingReindexerProvider);
    final db = DatabaseService.instance;

    // Index sent entries by mutationId for quick lookup.
    final sentById = {for (final e in sentEntries) e.mutationId: e};

    // Also index by noteId so we can update the next queued mutation.
    final allEntries = await db.getOutboxEntries();
    final queuedByNote = <String, List<OutboxEntry>>{};
    for (final e in allEntries) {
      queuedByNote.putIfAbsent(e.noteId, () => []).add(e);
    }

    bool hadChanges = false;
    bool hadConflict = false;

    // Process acknowledged mutations.
    // Acknowledgements update outbox and revision metadata only — note content
    // is unchanged, so hadChanges is not set here. reloadNotes and
    // reindexEmbeddings are triggered only when actual note content changes.
    for (final ack in response.acknowledged) {
      await db.setRemoteRevision(ack.noteId, ack.revision);
      final sentEntry = sentById[ack.mutationId];
      if (sentEntry != null) {
        await db.removeOutboxEntry(sentEntry.seq, sentEntry.mutationId);
        // Update the next queued mutation for this note to use the new base.
        final queued = queuedByNote[ack.noteId] ?? [];
        for (final next in queued) {
          if (next.mutationId != sentEntry.mutationId) {
            await db.updateOutboxBaseRevision(next.seq, ack.revision);
            break;
          }
        }
      }
    }

    // Process conflicts.
    for (final conflict in response.conflicts) {
      hadChanges = true;
      hadConflict = true;

      final sentEntry = sentById[conflict.mutationId];

      if (conflict.operation == 'upsert') {
        if (conflict.serverState != null) {
          // Server has a newer active note.
          // 1. Preserve local payload as a conflict copy (new UUID, " Conflict copy" suffix).
          final localPayload = sentEntry?.payload;
          if (localPayload != null) {
            final localJson = Map<String, dynamic>.from(
              jsonDecodeSafe(localPayload) ?? {},
            );
            if (localJson.isNotEmpty) {
              final conflictNote = Note(
                id: _uuid.v4(),
                title: '${localJson['title'] ?? 'Untitled'} (Conflict copy)',
                content: (localJson['content'] as String?) ?? '',
                tags: List<String>.from(localJson['tags'] as List? ?? []),
                keywords:
                    List<String>.from(localJson['keywords'] as List? ?? []),
                isPinned: (localJson['isPinned'] as bool?) ?? false,
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
                embeddingPending: true,
              );
              await db.insertNote(conflictNote);
            }
          }
          // 2. Apply the remote version to the original note ID.
          final serverNote = _snapshotToNote(conflict.noteId, conflict.serverState!);
          if (serverNote != null) {
            await db.applyRemoteUpsert(serverNote, conflict.serverRevision);
          }
          await db.setRemoteRevision(conflict.noteId, conflict.serverRevision);
        } else {
          // Server has a tombstone for this note ID.
          // Preserve local payload as a new note with a new UUID.
          final localPayload = sentEntry?.payload;
          if (localPayload != null) {
            final localJson = Map<String, dynamic>.from(
              jsonDecodeSafe(localPayload) ?? {},
            );
            if (localJson.isNotEmpty) {
              final conflictNote = Note(
                id: _uuid.v4(),
                title: '${localJson['title'] ?? 'Untitled'} (Conflict copy)',
                content: (localJson['content'] as String?) ?? '',
                tags: List<String>.from(localJson['tags'] as List? ?? []),
                keywords:
                    List<String>.from(localJson['keywords'] as List? ?? []),
                isPinned: (localJson['isPinned'] as bool?) ?? false,
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
                embeddingPending: true,
              );
              await db.insertNote(conflictNote);
            }
          }
          // Keep the original ID deleted (tombstone wins).
          await db.applyRemoteTombstone(conflict.noteId, conflict.serverRevision);
          await db.setRemoteRevision(conflict.noteId, conflict.serverRevision);
        }
      } else {
        // delete conflict — server has a newer edit that beats our delete.
        // Keep the remote note, surface a warning (state.conflictPreserved).
        if (conflict.serverState != null) {
          final serverNote =
              _snapshotToNote(conflict.noteId, conflict.serverState!);
          if (serverNote != null) {
            await db.applyRemoteUpsert(serverNote, conflict.serverRevision);
          }
          await db.setRemoteRevision(conflict.noteId, conflict.serverRevision);
        }
      }

      // Remove the outbox entry for this conflict (resolution is complete).
      if (sentEntry != null) {
        await db.removeOutboxEntry(sentEntry.seq, sentEntry.mutationId);
      }
    }

    // Apply snapshot rows not currently in the outbox (safe read-only download).
    final activeOutboxNoteIds = {
      for (final e in await db.getOutboxEntries()) e.noteId
    };

    for (final row in response.snapshot) {
      // Skip notes we have a pending outbox entry for — the in-flight mutation
      // will resolve the state when it lands.
      if (activeOutboxNoteIds.contains(row.id)) continue;

      if (row.deleted) {
        final existing = await db.getNoteById(row.id);
        if (existing != null) {
          await db.applyRemoteTombstone(row.id, row.revision);
          hadChanges = true;
        } else {
          // Record the remote revision so future operations have the right base.
          await db.setRemoteRevision(row.id, row.revision);
        }
      } else if (row.title != null && row.content != null) {
        final existing = await db.getNoteById(row.id);
        final remoteNote = Note(
          id: row.id,
          title: row.title!,
          content: row.content!,
          tags: row.tags,
          keywords: row.keywords,
          isPinned: row.isPinned,
          createdAt: row.createdAt != null
              ? DateTime.parse(row.createdAt!)
              : DateTime.now(),
          updatedAt: row.updatedAt != null
              ? DateTime.parse(row.updatedAt!)
              : DateTime.now(),
          embeddingPending: true,
        );
        final currentRev = await db.getRemoteRevision(row.id);
        if (existing == null || currentRev == null || row.revision > currentRev) {
          await db.applyRemoteUpsert(remoteNote, row.revision);
          hadChanges = true;
        }
      }
    }

    if (hadChanges) {
      await reloadNotes();
      await reindexEmbeddings();
    }
    if (hadConflict && mounted) {
      state = state.copyWith(conflictPreserved: true);
    }
  }

  Note? _snapshotToNote(String id, Map<String, dynamic> payload) {
    try {
      return Note(
        id: id,
        title: payload['title'] as String? ?? 'Untitled',
        content: payload['content'] as String? ?? '',
        tags: List<String>.from(payload['tags'] as List? ?? []),
        keywords: List<String>.from(payload['keywords'] as List? ?? []),
        isPinned: payload['isPinned'] as bool? ?? false,
        createdAt: payload['createdAt'] != null
            ? DateTime.parse(payload['createdAt'] as String)
            : DateTime.now(),
        updatedAt: payload['updatedAt'] != null
            ? DateTime.parse(payload['updatedAt'] as String)
            : DateTime.now(),
        embeddingPending: true,
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? jsonDecodeSafe(String? s) {
    if (s == null) return null;
    try {
      final v = jsonDecode(s);
      if (v is Map<String, dynamic>) return v;
    } catch (_) {}
    return null;
  }
}

final railwaySyncProvider =
    StateNotifierProvider<RailwaySyncNotifier, RailwaySyncState>(
  (ref) => RailwaySyncNotifier(ref),
);
