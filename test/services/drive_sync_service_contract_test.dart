import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/services/drive_sync_service.dart';

// Fake that stores files in memory to verify contract behaviour.
class _FakeDriveSyncService implements DriveSyncService {
  bool _signedIn = false;
  String? _email;
  String? _storedContent;
  int _uploadCount = 0;

  @override
  bool get isSignedIn => _signedIn;

  @override
  String? get accountEmail => _email;

  @override
  Future<bool> signIn() async {
    _signedIn = true;
    _email = 'test@example.com';
    return true;
  }

  @override
  Future<bool> signInSilently() async {
    if (_signedIn) return true;
    return false;
  }

  @override
  Future<void> signOut() async {
    _signedIn = false;
    _email = null;
    _storedContent = null;
  }

  @override
  Future<void> upload(String encodedJson) async {
    _storedContent = encodedJson;
    _uploadCount++;
  }

  @override
  Future<String?> download() async => _storedContent;

  @override
  Future<DateTime?> getRemoteModifiedAt() async =>
      _storedContent == null ? null : DateTime.utc(2026, 1, 1);

  int get uploadCount => _uploadCount;
}

void main() {
  group('DriveSyncService contract', () {
    late _FakeDriveSyncService service;

    setUp(() {
      service = _FakeDriveSyncService();
    });

    test('upload() stores content with correct name and content', () async {
      const content = '{"version":1,"notes":[]}';
      await service.upload(content);
      expect(await service.download(), content);
    });

    test('upload() on second call replaces rather than duplicates', () async {
      await service.upload('{"version":1,"notes":[]}');
      await service.upload('{"version":1,"notes":["updated"]}');

      expect(service.uploadCount, 2);
      expect(await service.download(), contains('updated'));
    });

    test('download() returns null when no backup exists', () async {
      expect(await service.download(), isNull);
    });

    test('download() returns JSON string when backup exists', () async {
      const content = '{"version":1,"notes":[]}';
      await service.upload(content);
      expect(await service.download(), content);
    });

    test('getRemoteModifiedAt() returns null when no backup exists', () async {
      expect(await service.getRemoteModifiedAt(), isNull);
    });

    test('getRemoteModifiedAt() returns a date when backup exists', () async {
      await service.upload('{"version":1,"notes":[]}');
      expect(await service.getRemoteModifiedAt(), isNotNull);
    });

    test('signOut() clears internal state', () async {
      await service.signIn();
      expect(service.isSignedIn, isTrue);
      expect(service.accountEmail, isNotNull);

      await service.signOut();
      expect(service.isSignedIn, isFalse);
      expect(service.accountEmail, isNull);
    });

    test('isSignedIn is false before signIn', () {
      expect(service.isSignedIn, isFalse);
    });

    test('accountEmail is available after signIn', () async {
      await service.signIn();
      expect(service.accountEmail, isNotEmpty);
    });
  });
}
