import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/llm_provider_config.dart';
import 'package:grepink/providers/llm_settings_provider.dart';
import 'package:grepink/services/llm_settings_service.dart';
import 'package:grepink/widgets/llm_provider_settings_section.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'helpers/fake_secure_storage.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

Future<(LlmSettingsService, FakeSecureStorage)> _makeService({
  Map<String, Object> prefsValues = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefsValues);
  final prefs = await SharedPreferences.getInstance();
  final secureStorage = FakeSecureStorage();
  final service = LlmSettingsService(
    prefs: prefs,
    secureStorage: secureStorage,
  );
  return (service, secureStorage);
}

/// Wraps [child] in a minimal app + Riverpod scope with a fake service.
Widget _buildApp(
  LlmSettingsService service, {
  Widget child = const LlmProviderSettingsSection(),
}) {
  return ProviderScope(
    overrides: [
      llmSettingsServiceProvider.overrideWith((_) async => service),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: child),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('LlmProviderSettingsSection', () {
    // -----------------------------------------------------------------------
    // Initial render
    // -----------------------------------------------------------------------
    group('initial render', () {
      testWidgets('shows the AI PROVIDER section title', (tester) async {
        final (service, _) = await _makeService();
        await tester.pumpWidget(_buildApp(service));
        await tester.pumpAndSettle();

        expect(find.text('AI PROVIDER'), findsOneWidget);
      });

      testWidgets('shows Provider selector', (tester) async {
        final (service, _) = await _makeService();
        await tester.pumpWidget(_buildApp(service));
        await tester.pumpAndSettle();

        expect(find.text('Provider'), findsOneWidget);
      });
    });

    // -----------------------------------------------------------------------
    // Mock provider
    // -----------------------------------------------------------------------
    group('mock provider (default)', () {
      testWidgets('shows mock provider note', (tester) async {
        final (service, _) = await _makeService();
        await tester.pumpWidget(_buildApp(service));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Mock provider is used for testing'),
          findsOneWidget,
        );
      });

      testWidgets('does not show Base URL field for mock provider',
          (tester) async {
        final (service, _) = await _makeService();
        await tester.pumpWidget(_buildApp(service));
        await tester.pumpAndSettle();

        expect(find.text('Base URL'), findsNothing);
      });

      testWidgets('does not show Model field for mock provider',
          (tester) async {
        final (service, _) = await _makeService();
        await tester.pumpWidget(_buildApp(service));
        await tester.pumpAndSettle();

        expect(find.text('Model'), findsNothing);
      });

      testWidgets('does not show API Key field for mock provider',
          (tester) async {
        final (service, _) = await _makeService();
        await tester.pumpWidget(_buildApp(service));
        await tester.pumpAndSettle();

        expect(find.text('API Key'), findsNothing);
      });
    });

    // -----------------------------------------------------------------------
    // OpenAI-compatible provider
    // -----------------------------------------------------------------------
    group('openAICompatible provider', () {
      Future<LlmSettingsService> makeOpenAiService() async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final service = LlmSettingsService(
          prefs: prefs,
          secureStorage: FakeSecureStorage(),
        );
        const config = LlmProviderConfig(
          providerKind: LlmProviderKind.openAICompatible,
          baseUrl: 'https://api.openai.com/v1',
          model: 'gpt-4o-mini',
          maxTokens: 900,
          temperature: 0.2,
        );
        await service.saveConfig(config);
        return service;
      }

      testWidgets('shows Base URL field', (tester) async {
        final service = await makeOpenAiService();
        await tester.pumpWidget(_buildApp(service));
        await tester.pumpAndSettle();

        expect(find.text('Base URL'), findsOneWidget);
      });

      testWidgets('shows Model field', (tester) async {
        final service = await makeOpenAiService();
        await tester.pumpWidget(_buildApp(service));
        await tester.pumpAndSettle();

        expect(find.text('Model'), findsOneWidget);
      });

      testWidgets('shows API Key field', (tester) async {
        final service = await makeOpenAiService();
        await tester.pumpWidget(_buildApp(service));
        await tester.pumpAndSettle();

        expect(find.text('API Key'), findsOneWidget);
      });

      testWidgets('shows Max Tokens slider', (tester) async {
        final service = await makeOpenAiService();
        await tester.pumpWidget(_buildApp(service));
        await tester.pumpAndSettle();

        expect(find.text('Max Tokens'), findsOneWidget);
      });

      testWidgets('shows Temperature slider', (tester) async {
        final service = await makeOpenAiService();
        await tester.pumpWidget(_buildApp(service));
        await tester.pumpAndSettle();

        expect(find.text('Temperature'), findsOneWidget);
      });

      testWidgets('shows Save and Clear buttons for API key', (tester) async {
        final service = await makeOpenAiService();
        await tester.pumpWidget(_buildApp(service));
        await tester.pumpAndSettle();

        expect(find.text('Save'), findsOneWidget);
        expect(find.text('Clear'), findsOneWidget);
      });

      testWidgets('shows "No API key saved" when no key is stored',
          (tester) async {
        final service = await makeOpenAiService();
        await tester.pumpWidget(_buildApp(service));
        await tester.pumpAndSettle();

        expect(find.text('No API key saved'), findsOneWidget);
      });

      testWidgets('shows "API key saved" after saving a key', (tester) async {
        final service = await makeOpenAiService();
        await service.saveApiKey('sk-test');

        await tester.pumpWidget(_buildApp(service));
        await tester.pumpAndSettle();

        expect(find.text('API key saved'), findsOneWidget);
      });

      testWidgets('does not show mock provider note', (tester) async {
        final service = await makeOpenAiService();
        await tester.pumpWidget(_buildApp(service));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Mock provider is used for testing'),
          findsNothing,
        );
      });
    });

    // -----------------------------------------------------------------------
    // Provider switching
    // -----------------------------------------------------------------------
    group('switching provider kind', () {
      testWidgets('switching to openAICompatible shows openAI fields',
          (tester) async {
        final (service, _) = await _makeService();

        await tester.pumpWidget(_buildApp(service));
        await tester.pumpAndSettle();

        // Initially mock — no Base URL
        expect(find.text('Base URL'), findsNothing);

        // Tap the dropdown to open it
        await tester.tap(find.byType(DropdownButtonFormField<LlmProviderKind>));
        await tester.pumpAndSettle();

        // Select OpenAI-compatible
        await tester.tap(
          find.text('OpenAI-compatible / Local AI').last,
        );
        await tester.pumpAndSettle();

        expect(find.text('Base URL'), findsOneWidget);
      });
    });

    // -----------------------------------------------------------------------
    // Validation
    // -----------------------------------------------------------------------
    group('validation', () {
      testWidgets('invalid config (empty baseUrl) shows validation message',
          (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final service = LlmSettingsService(
          prefs: prefs,
          secureStorage: FakeSecureStorage(),
        );
        // Save a config that is openAICompatible but has empty baseUrl
        const config = LlmProviderConfig(
          providerKind: LlmProviderKind.openAICompatible,
          baseUrl: '',
          model: 'gpt-4o-mini',
          maxTokens: 900,
          temperature: 0.2,
        );
        await service.saveConfig(config);

        await tester.pumpWidget(_buildApp(service));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('baseUrl must not be empty'),
          findsOneWidget,
        );
      });
    });

    // -----------------------------------------------------------------------
    // API key security
    // -----------------------------------------------------------------------
    group('API key save/clear calls service', () {
      testWidgets('Save button calls saveApiKey on notifier', (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final secureStorage = FakeSecureStorage();
        final service = LlmSettingsService(
          prefs: prefs,
          secureStorage: secureStorage,
        );
        const config = LlmProviderConfig(
          providerKind: LlmProviderKind.openAICompatible,
          baseUrl: 'https://api.openai.com/v1',
          model: 'gpt-4o-mini',
          maxTokens: 900,
          temperature: 0.2,
        );
        await service.saveConfig(config);

        await tester.pumpWidget(_buildApp(service));
        await tester.pumpAndSettle();

        // Type an API key
        await tester.enterText(
          find.byWidgetPredicate(
            (w) =>
                w is TextField &&
                (w.decoration?.hintText?.contains('sk-') ?? false),
          ),
          'sk-abc123',
        );

        // Tap Save
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(secureStorage.data.containsKey('llm_api_key'), isTrue);
        expect(secureStorage.data['llm_api_key'], 'sk-abc123');
      });

      testWidgets('Clear button calls clearApiKey on notifier', (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final secureStorage = FakeSecureStorage();
        final service = LlmSettingsService(
          prefs: prefs,
          secureStorage: secureStorage,
        );
        const config = LlmProviderConfig(
          providerKind: LlmProviderKind.openAICompatible,
          baseUrl: 'https://api.openai.com/v1',
          model: 'gpt-4o-mini',
          maxTokens: 900,
          temperature: 0.2,
        );
        await service.saveConfig(config);
        await service.saveApiKey('sk-existing');

        await tester.pumpWidget(_buildApp(service));
        await tester.pumpAndSettle();

        // Tap Clear
        await tester.tap(find.text('Clear'));
        await tester.pumpAndSettle();

        expect(secureStorage.data.containsKey('llm_api_key'), isFalse);
      });
    });
  });
}
