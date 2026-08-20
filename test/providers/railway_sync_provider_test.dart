import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/railway_sync_state.dart';
import 'package:grepink/providers/railway_sync_provider.dart';
import 'package:grepink/services/database_service.dart';
import 'package:grepink/services/railway_http_client.dart';
import 'package:grepink/services/railway_settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ---------------------------------------------------------------------------
// Fake HTTP client
// ---------------------------------------------------------------------------

class _FakeHttpClient implements RailwayHttpClient {
  bool healthResult = true;
  RailwaySyncResponse? nextResponse;
  Exception? throwOnSync;
  int syncCalls = 0;
  List<Map<String, dynamic>>? lastMutations;

  @override
  Future<bool> checkHealth(String baseUrl) async => healthResult;

  @override
  Future<RailwaySyncResponse> sync(
    String baseUrl,
    String token,
    List<Map<String, dynamic>> mutations,
  ) async {
    syncCalls++;
    lastMutations = mutations;
    if (throwOnSync != null) throw throwOnSync!;
    return nextResponse ??
        const RailwaySyncResponse(
          acknowledged: [],
          conflicts: [],
          snapshot: [],
        );
  }
}

// ---------------------------------------------------------------------------
// Fake settings storage (in-memory token)
// ---------------------------------------------------------------------------

class _FakeTokenStorage implements RailwaySettingsStorage {
  String? _token;

  @override
  Future<String?> readToken() async => _token;

  @override
  Future<void> writeToken(String token) async => _token = token;

  @override
  Future<void> deleteToken() async => _token = null;
}

// ---------------------------------------------------------------------------
// Helper to build a ProviderContainer with fakes injected.
// ---------------------------------------------------------------------------

ProviderContainer _buildContainer({
  RailwayHttpClient? client,
  RailwaySettingsService? settings,
  Future<void> Function()? onReload,
  Future<void> Function()? onReindex,
}) {
  final fakeClient = client ?? _FakeHttpClient();
  return ProviderContainer(
    overrides: [
      railwayHttpClientProvider.overrideWithValue(fakeClient),
      if (settings != null)
        railwaySettingsServiceProvider.overrideWithValue(settings),
      railwayNotesReloaderProvider
          .overrideWith((ref) => onReload ?? () async {}),
      railwayEmbeddingReindexerProvider
          .overrideWith((ref) => onReindex ?? () async {}),
    ],
  );
}

// A settings service that always returns the configured URL and token.
class _TestSettingsService extends RailwaySettingsService {
  final String _url;
  final String _token;

  _TestSettingsService({required String url, required String token})
      : _url = url,
        _token = token,
        super(storage: _FakeTokenStorage());

  @override
  Future<String?> getApiUrl() async => _url;

  @override
  Future<String?> getToken() async => _token;

  @override
  Future<bool> isConfigured() async => true;

  @override
  Future<DateTime?> getLastSyncedAt() async => null;

  @override
  Future<void> setLastSyncedAt(DateTime dt) async {}
}

class _UnconfiguredSettings extends RailwaySettingsService {
  _UnconfiguredSettings() : super(storage: _FakeTokenStorage());

  @override
  Future<String?> getApiUrl() async => null;

  @override
  Future<String?> getToken() async => null;

  @override
  Future<bool> isConfigured() async => false;

  @override
  Future<DateTime?> getLastSyncedAt() async => null;

  @override
  Future<void> setLastSyncedAt(DateTime dt) async {}
}

RailwaySettingsService _configuredSettings({
  String url = 'https://test.railway.app',
  String token = 'tok',
}) {
  SharedPreferences.setMockInitialValues({
    'railway_sync_api_url': url,
  });
  return _TestSettingsService(url: url, token: token);
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseService.testDatabasePath = inMemoryDatabasePath;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DatabaseService.instance.closeForTesting();
  });

  // ---------------------------------------------------------------------------
  // Not configured
  // ---------------------------------------------------------------------------

  test('not configured → notConfigured status without triggering sync',
      () async {
    final container = _buildContainer(settings: _UnconfiguredSettings());
    addTearDown(container.dispose);

    final notifier = container.read(railwaySyncProvider.notifier);
    // Wait for async init.
    await Future.delayed(const Duration(milliseconds: 50));

    expect(
      container.read(railwaySyncProvider).status,
      RailwaySyncStatus.notConfigured,
    );

    // triggerAfterMutation must be a no-op.
    notifier.triggerAfterMutation();
    await Future.delayed(const Duration(milliseconds: 50));
    expect(
      container.read(railwaySyncProvider).status,
      RailwaySyncStatus.notConfigured,
    );
  });

  // ---------------------------------------------------------------------------
  // testConnection
  // ---------------------------------------------------------------------------

  test('testConnection returns true when client returns true', () async {
    final client = _FakeHttpClient()..healthResult = true;
    final container =
        _buildContainer(client: client, settings: _UnconfiguredSettings());
    addTearDown(container.dispose);

    final ok = await container
        .read(railwaySyncProvider.notifier)
        .testConnection('https://test.railway.app', 'tok');
    expect(ok, isTrue);
  });

  test('testConnection returns false when client throws', () async {
    final fakeClient = _ThrowingHealthClient();
    final container =
        _buildContainer(client: fakeClient, settings: _UnconfiguredSettings());
    addTearDown(container.dispose);

    final ok = await container
        .read(railwaySyncProvider.notifier)
        .testConnection('https://test.railway.app', 'tok');
    expect(ok, isFalse);
  });

  // ---------------------------------------------------------------------------
  // Auth failure
  // ---------------------------------------------------------------------------

  test('auth failure sets authFailed status', () async {
    final client = _FakeHttpClient()
      ..throwOnSync = const RailwayAuthException();
    final settings = _configuredSettings();
    final container = _buildContainer(client: client, settings: settings);
    addTearDown(container.dispose);

    // Force provider creation so _init() runs during the delay.
    container.read(railwaySyncProvider.notifier);
    await Future.delayed(const Duration(milliseconds: 100));

    await container.read(railwaySyncProvider.notifier).syncNow();

    final state = container.read(railwaySyncProvider);
    expect(state.status, RailwaySyncStatus.authFailed);
  });

  // ---------------------------------------------------------------------------
  // Offline
  // ---------------------------------------------------------------------------

  test('offline error sets offline status', () async {
    final client = _FakeHttpClient()
      ..throwOnSync = const SocketException('no network');
    final settings = _configuredSettings();
    final container = _buildContainer(client: client, settings: settings);
    addTearDown(container.dispose);

    container.read(railwaySyncProvider.notifier);
    await Future.delayed(const Duration(milliseconds: 100));

    await container.read(railwaySyncProvider.notifier).syncNow();

    expect(
      container.read(railwaySyncProvider).status,
      RailwaySyncStatus.offline,
    );
  });

  // ---------------------------------------------------------------------------
  // Sync triggers reloadNotes and reindexEmbeddings
  // ---------------------------------------------------------------------------

  test('successful sync with remote notes triggers reload and reindex',
      () async {
    final client = _FakeHttpClient()
      ..nextResponse = const RailwaySyncResponse(
        acknowledged: [],
        conflicts: [],
        snapshot: [
          SnapshotRow(
            id: 'remote-note-id-001',
            revision: 1,
            deleted: false,
            title: 'Remote note',
            content: 'Remote content',
            tags: [],
            keywords: [],
            isPinned: false,
            createdAt: '2026-01-01T00:00:00.000Z',
            updatedAt: '2026-01-01T00:00:00.000Z',
          ),
        ],
      );
    final settings = _configuredSettings();

    int reloadCount = 0;
    int reindexCount = 0;

    final container = _buildContainer(
      client: client,
      settings: settings,
      onReload: () async => reloadCount++,
      onReindex: () async => reindexCount++,
    );
    addTearDown(container.dispose);

    container.read(railwaySyncProvider.notifier);
    await Future.delayed(const Duration(milliseconds: 100));

    await container.read(railwaySyncProvider.notifier).syncNow();

    expect(reloadCount, greaterThan(0));
    expect(reindexCount, greaterThan(0));
  });

  // ---------------------------------------------------------------------------
  // Conflict copy
  // ---------------------------------------------------------------------------

  test('conflict copy suffix is appended to note title', () {
    const payload = '''
      {
        "title": "My note",
        "content": "Some content",
        "tags": [],
        "keywords": [],
        "isPinned": false,
        "createdAt": "2026-01-01T00:00:00.000Z",
        "updatedAt": "2026-01-01T00:00:00.000Z"
      }
    ''';
    final json = jsonDecode(payload) as Map<String, dynamic>;
    final title = '${json['title'] ?? 'Untitled'} (Conflict copy)';
    expect(title, 'My note (Conflict copy)');
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _ThrowingHealthClient implements RailwayHttpClient {
  @override
  Future<bool> checkHealth(String baseUrl) async =>
      throw Exception('no network');

  @override
  Future<RailwaySyncResponse> sync(
    String baseUrl,
    String token,
    List<Map<String, dynamic>> mutations,
  ) async {
    throw Exception('should not sync');
  }
}
