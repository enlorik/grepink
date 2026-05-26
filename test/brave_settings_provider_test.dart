import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/brave_settings.dart';
import 'package:grepink/providers/brave_settings_provider.dart';
import 'package:grepink/services/brave_evidence_provider.dart';
import 'package:grepink/services/brave_settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_secure_storage.dart';

Future<(ProviderContainer, FakeSecureStorage, SharedPreferences)>
    _makeContainer() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final secureStorage = FakeSecureStorage();
  final service = BraveSettingsService(
    prefs: prefs,
    secureStorage: secureStorage,
  );

  final container = ProviderContainer(
    overrides: [
      braveSettingsServiceProvider.overrideWith((_) async => service),
    ],
  );

  return (container, secureStorage, prefs);
}

void main() {
  group('BraveSettingsNotifier', () {
    late ProviderContainer container;
    late FakeSecureStorage secureStorage;
    late SharedPreferences prefs;

    setUp(() async {
      (container, secureStorage, prefs) = await _makeContainer();
    });

    tearDown(() => container.dispose());

    test('loads defaults when nothing is persisted', () async {
      await container.read(braveSettingsProvider.future);

      final settings = container.read(braveSettingsProvider).valueOrNull!;
      expect(settings.enabled, isFalse);
      expect(settings.resultCount, 5);
      expect(settings.safeSearch, BraveSafeSearch.moderate);
      expect(settings.apiKeyConfigured, isFalse);
    });

    test('setEnabled persists config safely', () async {
      await container.read(braveSettingsProvider.future);
      await container.read(braveSettingsProvider.notifier).setEnabled(true);

      final settings = container.read(braveSettingsProvider).valueOrNull!;
      expect(settings.enabled, isTrue);
      expect(prefs.getString('brave_settings'), contains('"enabled":true'));
    });

    test('setResultCount clamps values into range', () async {
      await container.read(braveSettingsProvider.future);
      await container.read(braveSettingsProvider.notifier).setResultCount(99);

      final settings = container.read(braveSettingsProvider).valueOrNull!;
      expect(settings.resultCount, BraveSettings.kMaxResultCount);
    });

    test('setSafeSearch persists the selected level', () async {
      await container.read(braveSettingsProvider.future);
      await container
          .read(braveSettingsProvider.notifier)
          .setSafeSearch(BraveSafeSearch.strict);

      final settings = container.read(braveSettingsProvider).valueOrNull!;
      expect(settings.safeSearch, BraveSafeSearch.strict);
      expect(prefs.getString('brave_settings'), contains('strict'));
    });

    test('saveApiKey stores the key only in secure storage', () async {
      await container.read(braveSettingsProvider.future);
      await container.read(braveSettingsProvider.notifier).saveApiKey('brave-key');

      expect(secureStorage.data['brave_api_key'], 'brave-key');
      for (final key in prefs.getKeys()) {
        final value = prefs.get(key)?.toString() ?? '';
        expect(value.contains('brave-key'), isFalse);
      }
      expect(
        container.read(braveSettingsProvider).valueOrNull!.apiKeyConfigured,
        isTrue,
      );
    });

    test('clearApiKey removes the key and updates state', () async {
      await container.read(braveSettingsProvider.future);
      await container.read(braveSettingsProvider.notifier).saveApiKey('brave-key');

      await container.read(braveSettingsProvider.notifier).clearApiKey();

      expect(secureStorage.data.containsKey('brave_api_key'), isFalse);
      expect(
        container.read(braveSettingsProvider).valueOrNull!.apiKeyConfigured,
        isFalse,
      );
    });
  });
}
