import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/evidence_item.dart';
import 'package:grepink/models/knowledge_delta.dart';
import 'package:grepink/models/llm_provider_config.dart';
import 'package:grepink/services/configured_summary_writer_factory.dart';
import 'package:grepink/services/llm_provider.dart';
import 'package:grepink/services/llm_provider_factory.dart';
import 'package:grepink/services/llm_settings_service.dart';
import 'package:grepink/services/structured_summary_writer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'helpers/fake_secure_storage.dart';
import 'helpers/recording_llm_provider.dart';

class _RecordingLlmProviderFactory extends LlmProviderFactory {
  final LlmProvider provider;
  LlmProviderConfig? capturedConfig;
  String? capturedApiKey;

  _RecordingLlmProviderFactory(this.provider);

  @override
  LlmProvider create(LlmProviderConfig config, {String? apiKey}) {
    capturedConfig = config;
    capturedApiKey = apiKey;
    return provider;
  }
}

EvidenceItem _webItem(String id) => EvidenceItem(
      id: id,
      type: EvidenceType.webSearch,
      title: 'Web $id',
      content: 'Fresh evidence $id',
      sourceUrl: 'https://example.com/$id',
      relevanceScore: 0.9,
    );

KnowledgeDelta _newClaim(EvidenceItem item) => KnowledgeDelta(
      evidence: item,
      deltaType: DeltaType.newClaim,
      reason: 'new fact',
    );

void main() {
  group('ConfiguredSummaryWriterFactory', () {
    late SharedPreferences prefs;
    late FakeSecureStorage secureStorage;
    late LlmSettingsService settingsService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      secureStorage = FakeSecureStorage();
      settingsService = LlmSettingsService(
        prefs: prefs,
        secureStorage: secureStorage,
      );
    });

    test('constructs a structured writer from mock settings', () async {
      const config = LlmProviderConfig(
        providerKind: LlmProviderKind.mock,
        baseUrl: '',
        model: '',
        maxTokens: 640,
        temperature: 0.4,
      );
      await settingsService.saveConfig(config);

      final writer = await ConfiguredSummaryWriterFactory(
        settingsService: settingsService,
      ).create();

      expect(writer, isA<StructuredSummaryWriter>());
    });

    test('constructs a structured writer from openAI-compatible settings',
        () async {
      const config = LlmProviderConfig(
        providerKind: LlmProviderKind.openAICompatible,
        baseUrl: 'https://api.openai.com/v1',
        model: 'gpt-4o-mini',
        maxTokens: 1200,
        temperature: 0.3,
      );
      await settingsService.saveConfig(config);
      await settingsService.saveApiKey('sk-test-key');

      final writer = await ConfiguredSummaryWriterFactory(
        settingsService: settingsService,
      ).create();

      expect(writer, isA<StructuredSummaryWriter>());
    });

    test('loads config and secure api key into provider construction',
        () async {
      const config = LlmProviderConfig(
        providerKind: LlmProviderKind.openAICompatible,
        baseUrl: 'https://api.openai.com/v1',
        model: 'gpt-4.1-mini',
        maxTokens: 1500,
        temperature: 0.6,
      );
      await settingsService.saveConfig(config);
      await settingsService.saveApiKey('sk-secure-only');

      final recordingProvider = RecordingLlmProvider();
      final recordingFactory = _RecordingLlmProviderFactory(recordingProvider);
      final writer = await ConfiguredSummaryWriterFactory(
        settingsService: settingsService,
        providerFactory: recordingFactory,
      ).create();

      final webEvidence = [_webItem('w1')];
      await writer.write(
        question: 'What changed?',
        localEvidence: const [],
        webEvidence: webEvidence,
        deltas: [_newClaim(webEvidence.first)],
      );

      expect(
        recordingFactory.capturedConfig,
        config.copyWith(apiKeyConfigured: true),
      );
      expect(recordingFactory.capturedApiKey, 'sk-secure-only');
      expect(recordingProvider.requests, hasLength(1));
      expect(recordingProvider.requests.single.maxTokens, 1500);
      expect(recordingProvider.requests.single.temperature, 0.6);
    });

    test('invalid openAI-compatible config falls back to mock provider config',
        () async {
      const invalidConfig = LlmProviderConfig(
        providerKind: LlmProviderKind.openAICompatible,
        baseUrl: '',
        model: '',
        maxTokens: 1234,
        temperature: 0.7,
      );
      await settingsService.saveConfig(invalidConfig);
      await settingsService.saveApiKey('sk-should-not-be-used');

      final recordingProvider = RecordingLlmProvider();
      final recordingFactory = _RecordingLlmProviderFactory(recordingProvider);
      final writer = await ConfiguredSummaryWriterFactory(
        settingsService: settingsService,
        providerFactory: recordingFactory,
      ).create();

      final webEvidence = [_webItem('w1')];
      await writer.write(
        question: 'Fallback please',
        localEvidence: const [],
        webEvidence: webEvidence,
        deltas: [_newClaim(webEvidence.first)],
      );

      expect(
        recordingFactory.capturedConfig,
        LlmProviderConfig.defaults.copyWith(
          maxTokens: 1234,
          temperature: 0.7,
        ),
      );
      expect(recordingFactory.capturedApiKey, isNull);
      expect(recordingProvider.requests.single.maxTokens, 1234);
      expect(recordingProvider.requests.single.temperature, 0.7);
    });
  });
}
