import 'dart:convert';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const _backupFileName = 'grepink-notes-backup.json';
const _appDataFolder = 'appDataFolder';
const _versionPropKey = 'version';

class DriveSyncException implements Exception {
  final String message;
  const DriveSyncException(this.message);
  @override
  String toString() => 'DriveSyncException: $message';
}

// Thrown when another device updated the Drive file since our last download.
// The sync coordinator should re-download, merge, and retry.
class DriveSyncConflictException extends DriveSyncException {
  const DriveSyncConflictException(String message) : super(message);
}

abstract class DriveSyncService {
  bool get isSignedIn;
  String? get accountEmail;
  Future<bool> signIn();
  Future<bool> signInSilently();
  Future<void> signOut();
  Future<void> upload(String encodedJson);
  Future<String?> download();

  factory DriveSyncService() = _GoogleDriveSyncService;
}

// Fetches a fresh access token on every request so tokens never expire mid-session.
class _AuthenticatedClient extends http.BaseClient {
  final GoogleSignInAccount _account;
  final http.Client _inner;

  _AuthenticatedClient(this._account) : _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final auth = await _account.authentication;
    final token = auth.accessToken;
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

class _GoogleDriveSyncService implements DriveSyncService {
  final GoogleSignIn _googleSignIn;
  drive.DriveApi? _driveApi;
  _AuthenticatedClient? _httpClient;
  // Track our own sign-in flag so that a failed platform sign-out cannot leave
  // isSignedIn true and allow _getApi() to rebuild the Drive client.
  bool _signedIn = false;

  // Cached Drive file ID for this account (restored from prefs on sign-in).
  String? _cachedFileId;
  // Last known appProperties version — used for optimistic concurrency checks.
  int _localVersion = 0;

  _GoogleDriveSyncService()
      : _googleSignIn = GoogleSignIn(
          scopes: ['https://www.googleapis.com/auth/drive.appdata'],
        );

  @override
  bool get isSignedIn => _signedIn;

  @override
  String? get accountEmail => _googleSignIn.currentUser?.email;

  String? get _email => _googleSignIn.currentUser?.email;

  @override
  Future<bool> signIn() async {
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) return false;
      _driveApi = _buildDriveApi(account);
      _signedIn = true;
      await _restoreCachedFileId();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> signInSilently() async {
    try {
      final account = await _googleSignIn.signInSilently();
      if (account == null) return false;
      _driveApi = _buildDriveApi(account);
      _signedIn = true;
      await _restoreCachedFileId();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> signOut() async {
    // Clear local state first so no further Drive requests can be made,
    // even if the provider-level sign-out call throws.
    _signedIn = false;
    _cachedFileId = null;
    _localVersion = 0;
    _httpClient?.close();
    _httpClient = null;
    _driveApi = null;
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
  }

  Future<drive.DriveApi> _getApi() async {
    if (_driveApi != null) return _driveApi!;
    if (!_signedIn) throw const DriveSyncException('Not signed in');
    final account = _googleSignIn.currentUser;
    if (account == null) throw const DriveSyncException('Not signed in');
    _driveApi = _buildDriveApi(account);
    return _driveApi!;
  }

  drive.DriveApi _buildDriveApi(GoogleSignInAccount account) {
    _httpClient?.close();
    _httpClient = _AuthenticatedClient(account);
    return drive.DriveApi(_httpClient!);
  }

  Future<void> _restoreCachedFileId() async {
    final email = _email;
    if (email == null) return;
    final prefs = await SharedPreferences.getInstance();
    _cachedFileId = prefs.getString('sync.$email.fileId');
  }

  Future<void> _persistCachedFileId(String fileId) async {
    final email = _email;
    if (email == null) return;
    _cachedFileId = fileId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sync.$email.fileId', fileId);
  }

  Future<void> _clearCachedFileId() async {
    final email = _email;
    _cachedFileId = null;
    if (email == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('sync.$email.fileId');
  }

  @override
  Future<void> upload(String encodedJson) async {
    try {
      final api = await _getApi();
      final bytes = utf8.encode(encodedJson);
      final media = drive.Media(Stream.value(bytes), bytes.length);

      String? fileId = _cachedFileId;
      if (fileId != null) {
        // Verify the cached ID is still valid; on 404 fall through to search.
        try {
          await _uploadExisting(api, fileId, media);
          return;
        } on _FileNotFoundException {
          await _clearCachedFileId();
          fileId = null;
        }
      }

      // No cached ID — search for existing backup file.
      fileId = await _findFileId(api);
      if (fileId != null) {
        await _persistCachedFileId(fileId);
        await _uploadExisting(api, fileId, media);
      } else {
        // First upload: create a new file with version=1.
        final meta = drive.File()
          ..name = _backupFileName
          ..parents = [_appDataFolder]
          ..appProperties = {_versionPropKey: '1'};
        final created =
            await api.files.create(meta, uploadMedia: media, $fields: 'id');
        final newId = created.id;
        if (newId != null) await _persistCachedFileId(newId);
        _localVersion = 1;
      }
    } on DriveSyncException {
      rethrow;
    } catch (_) {
      throw const DriveSyncException('Upload failed');
    }
  }

  Future<void> _uploadExisting(
    drive.DriveApi api,
    String fileId,
    drive.Media media,
  ) async {
    // Optimistic concurrency: fetch current appProperties version.
    final drive.File currentMeta;
    try {
      currentMeta = await api.files.get(
        fileId,
        $fields: 'id,appProperties',
      ) as drive.File;
    } on drive.DetailedApiRequestError catch (e) {
      if (e.status == 404) throw const _FileNotFoundException();
      throw const DriveSyncException('Upload failed');
    }

    final currentVersion =
        int.tryParse(currentMeta.appProperties?[_versionPropKey] ?? '0') ?? 0;

    // If the Drive version doesn't match our last-known version, another device
    // has written since our last download — signal a conflict to the provider.
    if (currentVersion != _localVersion) {
      throw DriveSyncConflictException(
        'Conflict: expected version $_localVersion, found $currentVersion',
      );
    }

    final newVersion = currentVersion + 1;
    final newMeta = drive.File()
      ..appProperties = {_versionPropKey: newVersion.toString()};

    try {
      await api.files.update(newMeta, fileId, uploadMedia: media);
      _localVersion = newVersion;
    } on drive.DetailedApiRequestError catch (e) {
      if (e.status == 404) throw const _FileNotFoundException();
      throw const DriveSyncException('Upload failed');
    }
  }

  @override
  Future<String?> download() async {
    try {
      final api = await _getApi();

      String? fileId = _cachedFileId;
      if (fileId == null) {
        fileId = await _findFileId(api);
        if (fileId != null) await _persistCachedFileId(fileId);
      }
      if (fileId == null) return null;

      // Fetch current appProperties to update the local version before download.
      try {
        final meta = await api.files.get(
          fileId,
          $fields: 'id,appProperties',
        ) as drive.File;
        _localVersion =
            int.tryParse(meta.appProperties?[_versionPropKey] ?? '0') ?? 0;
      } catch (_) {
        // Non-fatal: proceed with content download; version check on next upload.
        _localVersion = 0;
      }

      final response = await api.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;
      final chunks = await response.stream.toList();
      final bytes = chunks.expand((c) => c).toList();
      return utf8.decode(bytes);
    } on DriveSyncException {
      rethrow;
    } catch (_) {
      throw const DriveSyncException('Download failed');
    }
  }

  // Finds the backup file ID. If duplicates exist, deletes all but the newest
  // (by createdTime) and returns the surviving ID.
  Future<String?> _findFileId(drive.DriveApi api) async {
    final list = await api.files.list(
      spaces: _appDataFolder,
      q: "name = '$_backupFileName'",
      orderBy: 'createdTime desc',
      $fields: 'files(id)',
    );
    final files = list.files;
    if (files == null || files.isEmpty) return null;
    if (files.length == 1) return files.first.id;

    // Multiple backup files found: keep the first (newest by createdTime desc)
    // and delete the rest.
    final keepId = files.first.id!;
    for (int i = 1; i < files.length; i++) {
      final staleId = files[i].id;
      if (staleId != null) {
        try {
          await api.files.delete(staleId);
        } catch (_) {
          // Best-effort cleanup; don't abort the operation.
        }
      }
    }
    return keepId;
  }
}

class _FileNotFoundException implements Exception {
  const _FileNotFoundException();
}
