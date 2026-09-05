import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepink/models/brave_settings.dart';
import 'package:grepink/providers/brave_settings_provider.dart';

export 'package:grepink/models/brave_settings.dart';

class _FixedBraveSettingsNotifier extends BraveSettingsNotifier {
  final BraveSettings _settings;
  _FixedBraveSettingsNotifier(this._settings);

  @override
  Future<BraveSettings> build() async => _settings;
}

Override braveSettingsOverride(BraveSettings settings) => braveSettingsProvider
    .overrideWith(() => _FixedBraveSettingsNotifier(settings));
