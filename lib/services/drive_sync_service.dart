import 'dart:convert';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

const _backupFileName = 'grepink-notes-backup.json';
const _appDataFolder = 'appDataFolder';

class DriveSyncException implements Exception {
  final String message;
  const DriveSyncException(this.message);
  @override
  String toString() => 'DriveSyncException: $message';
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

  _GoogleDriveSyncService()
      : _googleSignIn = GoogleSignIn(
          scopes: ['https://www.googleapis.com/auth/drive.appdata'],
        );

  @override
  bool get isSignedIn => _googleSignIn.currentUser != null;

  @override
  String? get accountEmail => _googleSignIn.currentUser?.email;

  @override
  Future<bool> signIn() async {
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) return false;
      _driveApi = _buildDriveApi(account);
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
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    _httpClient?.close();
    _httpClient = null;
    _driveApi = null;
  }

  Future<drive.DriveApi> _getApi() async {
    if (_driveApi != null) return _driveApi!;
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

  @override
  Future<void> upload(String encodedJson) async {
    try {
      final api = await _getApi();
      final existingId = await _findFileId(api);
      final bytes = utf8.encode(encodedJson);
      final media = drive.Media(Stream.value(bytes), bytes.length);

      if (existingId == null) {
        final meta = drive.File()
          ..name = _backupFileName
          ..parents = [_appDataFolder];
        await api.files.create(meta, uploadMedia: media);
      } else {
        await api.files.update(drive.File(), existingId, uploadMedia: media);
      }
    } on DriveSyncException {
      rethrow;
    } catch (_) {
      throw const DriveSyncException('Upload failed');
    }
  }

  @override
  Future<String?> download() async {
    try {
      final api = await _getApi();
      final id = await _findFileId(api);
      if (id == null) return null;
      final response = await api.files.get(
        id,
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

  Future<String?> _findFileId(drive.DriveApi api) async {
    final list = await api.files.list(
      spaces: _appDataFolder,
      q: "name = '$_backupFileName'",
      $fields: 'files(id)',
    );
    final files = list.files;
    if (files == null || files.isEmpty) return null;
    return files.first.id;
  }
}
