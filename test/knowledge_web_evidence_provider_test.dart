import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/brave_settings.dart';
import 'package:grepink/providers/brave_settings_provider.dart';
import 'package:grepink/providers/knowledge_ingestion_provider.dart';
import 'package:grepink/services/brave_evidence_provider.dart';
import 'package:grepink/services/brave_settings_service.dart';
import 'package:grepink/services/web_evidence_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_secure_storage.dart';

Future<(ProviderContainer, BraveSettingsService)> _makeContainer({
  required BraveSettings settings,
  String? apiKey,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final secureStorage = FakeSecureStorage();
  final service = BraveSettingsService(
    prefs: prefs,
    secureStorage: secureStorage,
  );

  await service.saveSettings(settings);
  if (apiKey != null) {
    await service.saveApiKey(apiKey);
  }

  final container = ProviderContainer(
    overrides: [
      braveSettingsServiceProvider.overrideWith((_) async => service),
    ],
  );

  return (container, service);
}

void main() {
  group('configuredKnowledgeWebEvidenceProvider', () {
    test('uses the empty provider when no Brave key is configured', () async {
      final (container, _) = await _makeContainer(
        settings: const BraveSettings(enabled: true),
      );
      addTearDown(container.dispose);

      final provider =
          await container.read(configuredKnowledgeWebEvidenceProvider.future);

      expect(provider, isA<EmptyWebEvidenceProvider>());
      expect(await provider.fetch('question'), isEmpty);
    });

    test('uses the empty provider when Brave is disabled', () async {
      final (container, _) = await _makeContainer(
        settings: const BraveSettings(enabled: false),
        apiKey: 'brave-key',
      );
      addTearDown(container.dispose);

      final provider =
          await container.read(configuredKnowledgeWebEvidenceProvider.future);

      expect(provider, isA<EmptyWebEvidenceProvider>());
      expect(await provider.fetch('question'), isEmpty);
    });

    test('uses BraveEvidenceProvider when Brave is enabled and configured',
        () async {
      final (container, _) = await _makeContainer(
        settings: const BraveSettings(
          enabled: true,
          resultCount: 7,
          safeSearch: BraveSafeSearch.strict,
        ),
        apiKey: 'brave-key',
      );
      addTearDown(container.dispose);

      final provider =
          await container.read(configuredKnowledgeWebEvidenceProvider.future);

      expect(provider, isA<BraveEvidenceProvider>());
    });
  });
}
