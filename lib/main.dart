import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'models/brave_settings.dart';
import 'providers/brave_settings_provider.dart';
import 'providers/claim_review_provider.dart';
import 'services/brave_search_grounded_answer_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ProviderScope(
      overrides: [
        groundedAnswerProviderProvider.overrideWith((ref) {
          final settings = ref.watch(braveSettingsProvider).valueOrNull ??
              BraveSettings.defaults;
          return BraveSearchGroundedAnswerProvider(
            settings: settings,
            apiKeyLoader: () async {
              final service =
                  await ref.read(braveSettingsServiceProvider.future);
              return service.loadApiKey();
            },
          );
        }),
      ],
      child: const GrepinkApp(),
    ),
  );
}
