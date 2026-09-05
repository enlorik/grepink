import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import '../desktop_file_writer_stub.dart'
    if (dart.library.io) '../desktop_file_writer_io.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../models/brave_settings.dart';
import '../models/note.dart';
import '../models/railway_sync_state.dart';
import '../providers/brave_settings_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/railway_sync_provider.dart';
import '../providers/settings_provider.dart';
import '../services/database_service.dart';
import '../services/brave_evidence_provider.dart';
import '../services/note_export_service.dart';
import '../services/railway_http_client.dart';
import '../services/railway_settings_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/grepink_bottom_nav.dart';
import '../widgets/llm_provider_settings_section.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _apiKeyController;
  late TextEditingController _braveSearchApiKeyController;
  late TextEditingController _braveAnswersApiKeyController;
  late TextEditingController _railwayUrlController;
  late TextEditingController _railwayTokenController;
  bool _apiKeyVisible = false;
  bool _braveSearchApiKeyVisible = false;
  bool _braveAnswersApiKeyVisible = false;
  bool _railwayTokenVisible = false;
  bool _railwayTestingConnection = false;

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController();
    _braveSearchApiKeyController = TextEditingController();
    _braveAnswersApiKeyController = TextEditingController();
    _railwayUrlController = TextEditingController();
    _railwayTokenController = TextEditingController();
    _loadRailwayConfig();
  }

  Future<void> _loadRailwayConfig() async {
    final svc = RailwaySettingsService();
    final url = await svc.getApiUrl();
    if (url != null && mounted) _railwayUrlController.text = url;
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _braveSearchApiKeyController.dispose();
    _braveAnswersApiKeyController.dispose();
    _railwayUrlController.dispose();
    _railwayTokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    final braveSettingsAsync = ref.watch(braveSettingsProvider);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.backgroundStart, AppColors.backgroundEnd],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back,
                          color: AppColors.deepAction),
                      onPressed: () => context.pop(),
                    ),
                    Text('Settings', style: AppTextStyles.displayMedium),
                  ],
                ),
              ),
              Expanded(
                child: settingsAsync.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.primaryAction),
                  ),
                  error: (e, _) => Center(child: Text('Error: $e')),
                  data: (settings) => braveSettingsAsync.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.primaryAction),
                    ),
                    error: (e, _) => Center(child: Text('Error: $e')),
                    data: (braveSettings) {
                      if (_apiKeyController.text.isEmpty &&
                          settings.apiKey.isNotEmpty) {
                        _apiKeyController.text = settings.apiKey;
                      }
                      return _buildContent(settings, braveSettings);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: GrepinkBottomNav(
        currentIndex: 2,
        onTap: (i) {
          if (i == 0) context.go('/');
          if (i == 1) context.push('/search');
        },
      ),
    );
  }

  Widget _buildContent(AppSettings settings, BraveSettings braveSettings) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      children: [
        // APPEARANCE
        _buildSection('APPEARANCE', [
          _buildSettingRow(
            title: 'Theme',
            subtitle: 'Coming in v1.1',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('v1.1',
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.deepAction)),
                ),
                const SizedBox(width: 8),
                const Switch(
                  value: false,
                  onChanged: null,
                  activeThumbColor: AppColors.primaryAction,
                ),
              ],
            ),
          ),
        ]),

        const SizedBox(height: 8),

        // AI SETTINGS
        _buildSection('AI SETTINGS', [
          _buildSettingRow(
            title: 'API Key',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _apiKeyController,
                  obscureText: !_apiKeyVisible,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.bodyText,
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    hintText: 'sk-...',
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _apiKeyVisible
                            ? Icons.visibility_off
                            : Icons.visibility,
                        size: 18,
                        color: AppColors.secondaryText,
                      ),
                      onPressed: () =>
                          setState(() => _apiKeyVisible = !_apiKeyVisible),
                    ),
                  ),
                  onChanged: (v) {
                    ref.read(settingsProvider.notifier).setApiKey(v.trim());
                  },
                ),
              ],
            ),
          ),
          _buildSettingRow(
            title: 'Max Tokens',
            subtitle: '${settings.maxTokens} tokens',
            child: Slider(
              value: settings.maxTokens.toDouble(),
              min: 50,
              max: 200,
              divisions: 15,
              activeColor: AppColors.primaryAction,
              inactiveColor: AppColors.dividerBorder,
              label: settings.maxTokens.toString(),
              onChanged: (v) {
                ref.read(settingsProvider.notifier).setMaxTokens(v.round());
              },
            ),
          ),
          _buildSettingRow(
            title: 'AI Responses',
            trailing: Switch(
              value: settings.aiEnabled,
              onChanged: (v) {
                ref.read(settingsProvider.notifier).setAiEnabled(v);
              },
              activeThumbColor: AppColors.primaryAction,
            ),
          ),
          _buildSettingRow(
            title: 'Embedding Model',
            subtitle: 'text-embedding-3-small',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.aiResponseBackground,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.dividerBorder),
              ),
              child: Text('read-only', style: AppTextStyles.bodySmall),
            ),
          ),
        ]),

        const SizedBox(height: 8),

        // AI PROVIDER
        const LlmProviderSettingsSection(),

        const SizedBox(height: 8),

        _buildSection('WEB EVIDENCE', [
          _buildSettingRow(
            title: 'Brave Search evidence',
            subtitle: braveSettings.searchKeyConfigured
                ? 'Search API key stored securely'
                : 'Add a Brave Search API key to enable this later',
            trailing: Switch(
              value: braveSettings.enabled,
              onChanged: (value) {
                ref.read(braveSettingsProvider.notifier).setEnabled(value);
              },
              activeThumbColor: AppColors.primaryAction,
            ),
          ),
          _buildSettingRow(
            title: 'Brave Search API Key',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _braveSearchApiKeyController,
                  obscureText: !_braveSearchApiKeyVisible,
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.bodyText,
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    hintText: braveSettings.searchKeyConfigured
                        ? 'Enter a new key to replace the saved one'
                        : 'BSA...',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _braveSearchApiKeyVisible
                            ? Icons.visibility_off
                            : Icons.visibility,
                        size: 18,
                        color: AppColors.secondaryText,
                      ),
                      onPressed: () {
                        setState(() {
                          _braveSearchApiKeyVisible =
                              !_braveSearchApiKeyVisible;
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: () async {
                        final apiKey = _braveSearchApiKeyController.text.trim();
                        if (apiKey.isEmpty) return;
                        await ref
                            .read(braveSettingsProvider.notifier)
                            .saveSearchApiKey(apiKey);
                        if (!mounted) return;
                        _braveSearchApiKeyController.clear();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content:
                                Text('Brave Search API key saved securely.'),
                          ),
                        );
                      },
                      child: const Text('Save key'),
                    ),
                    OutlinedButton(
                      onPressed: braveSettings.searchKeyConfigured
                          ? () async {
                              await ref
                                  .read(braveSettingsProvider.notifier)
                                  .clearSearchApiKey();
                              if (!mounted) return;
                              _braveSearchApiKeyController.clear();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content:
                                      Text('Brave Search API key cleared.'),
                                ),
                              );
                            }
                          : null,
                      child: const Text('Clear key'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _buildSettingRow(
            title: 'Brave Answers API Key',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _braveAnswersApiKeyController,
                  obscureText: !_braveAnswersApiKeyVisible,
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.bodyText,
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    hintText: braveSettings.answersKeyConfigured
                        ? 'Enter a new key to replace the saved one'
                        : 'BAA...',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _braveAnswersApiKeyVisible
                            ? Icons.visibility_off
                            : Icons.visibility,
                        size: 18,
                        color: AppColors.secondaryText,
                      ),
                      onPressed: () {
                        setState(() {
                          _braveAnswersApiKeyVisible =
                              !_braveAnswersApiKeyVisible;
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: () async {
                        final apiKey =
                            _braveAnswersApiKeyController.text.trim();
                        if (apiKey.isEmpty) return;
                        await ref
                            .read(braveSettingsProvider.notifier)
                            .saveAnswersApiKey(apiKey);
                        if (!mounted) return;
                        _braveAnswersApiKeyController.clear();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content:
                                Text('Brave Answers API key saved securely.'),
                          ),
                        );
                      },
                      child: const Text('Save key'),
                    ),
                    OutlinedButton(
                      onPressed: braveSettings.answersKeyConfigured
                          ? () async {
                              await ref
                                  .read(braveSettingsProvider.notifier)
                                  .clearAnswersApiKey();
                              if (!mounted) return;
                              _braveAnswersApiKeyController.clear();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content:
                                      Text('Brave Answers API key cleared.'),
                                ),
                              );
                            }
                          : null,
                      child: const Text('Clear key'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _buildSettingRow(
            title: 'Result count',
            subtitle: '${braveSettings.resultCount} results',
            child: Slider(
              value: braveSettings.resultCount.toDouble(),
              min: 1,
              max: 20,
              divisions: 19,
              activeColor: AppColors.primaryAction,
              inactiveColor: AppColors.dividerBorder,
              label: braveSettings.resultCount.toString(),
              onChanged: (value) {
                ref
                    .read(braveSettingsProvider.notifier)
                    .setResultCount(value.round());
              },
            ),
          ),
          _buildSettingRow(
            title: 'Safe Search',
            child: DropdownButtonFormField<BraveSafeSearch>(
              initialValue: braveSettings.safeSearch,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              items: BraveSafeSearch.values
                  .map(
                    (option) => DropdownMenuItem<BraveSafeSearch>(
                      value: option,
                      child: Text(option.name),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                ref.read(braveSettingsProvider.notifier).setSafeSearch(value);
              },
            ),
          ),
        ]),

        const SizedBox(height: 8),

        // RAILWAY SYNC
        _buildRailwaySyncSection(),

        const SizedBox(height: 8),

        // MEMORY ENGINE
        _buildSection('MEMORY ENGINE', [
          _buildSettingRow(
            title: 'Similarity Threshold',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Loose', style: AppTextStyles.bodySmall),
                    Text(settings.similarityThreshold.toStringAsFixed(2),
                        style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.deepAction,
                            fontWeight: FontWeight.w600)),
                    Text('Strict', style: AppTextStyles.bodySmall),
                  ],
                ),
                Slider(
                  value: settings.similarityThreshold,
                  min: 0.60,
                  max: 0.95,
                  divisions: 35,
                  activeColor: AppColors.primaryAction,
                  inactiveColor: AppColors.dividerBorder,
                  onChanged: (v) {
                    ref.read(settingsProvider.notifier).setSimilarityThreshold(
                          double.parse(v.toStringAsFixed(2)),
                        );
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Reindex My Notes'),
              onPressed: () async {
                final notifier = ref.read(notesProvider.notifier);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Reindexing notes...')),
                );
                await notifier.reindexEmbeddings();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Reindex complete!')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryAction,
                foregroundColor: AppColors.surface,
              ),
            ),
          ),
        ]),

        const SizedBox(height: 8),

        // DATA
        _buildSection('DATA', [
          _buildSettingRow(
            title: 'Export Notes',
            trailing: const Icon(Icons.upload_outlined,
                color: AppColors.primaryAction),
            onTap: _exportNotes,
          ),
          _buildSettingRow(
            title: 'Import Notes',
            trailing: const Icon(Icons.download_outlined,
                color: AppColors.primaryAction),
            onTap: _importNotes,
          ),
          _buildSettingRow(
            title: 'Clear All Notes',
            trailing: const Icon(Icons.delete_outline, color: AppColors.error),
            onTap: _confirmClearAll,
          ),
        ]),

        const SizedBox(height: 8),

        // ABOUT
        _buildSection('ABOUT', [
          _buildSettingRow(title: 'Version', subtitle: '2.1.0'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              'Built for me, by me. 🩷',
              style: AppTextStyles.aiResponse.copyWith(
                fontStyle: FontStyle.italic,
                color: AppColors.primaryAccent,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ]),
      ],
    );
  }

  String _formatLastSynced(DateTime? dt) {
    if (dt == null) return 'Never';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    final locale = Localizations.localeOf(context).toString();
    return DateFormat.yMd(locale).format(dt);
  }

  String _railwayStatusLabel(RailwaySyncStatus status) {
    switch (status) {
      case RailwaySyncStatus.notConfigured:
        return 'Not configured';
      case RailwaySyncStatus.idle:
        return 'Idle';
      case RailwaySyncStatus.syncing:
        return 'Syncing…';
      case RailwaySyncStatus.upToDate:
        return 'Up to date';
      case RailwaySyncStatus.pendingChanges:
        return 'Pending changes';
      case RailwaySyncStatus.offline:
        return 'Offline';
      case RailwaySyncStatus.authFailed:
        return 'Authentication failed';
      case RailwaySyncStatus.error:
        return 'Sync error';
    }
  }

  Widget _buildRailwaySyncSection() {
    final syncState = ref.watch(railwaySyncProvider);
    final isSyncing = syncState.status == RailwaySyncStatus.syncing;
    final isConfigured = syncState.status != RailwaySyncStatus.notConfigured;

    return _buildSection('RAILWAY SYNC', [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          'Notes travel over HTTPS but are readable inside your Railway '
          'PostgreSQL database. This version is not end-to-end encrypted.',
          style:
              AppTextStyles.bodySmall.copyWith(color: AppColors.secondaryText),
        ),
      ),
      _buildSettingRow(
        title: 'Railway API URL',
        child: TextField(
          controller: _railwayUrlController,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.url,
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.bodyText,
            fontFamily: 'monospace',
          ),
          decoration: const InputDecoration(
            hintText: 'https://your-app.railway.app',
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
          ),
        ),
      ),
      _buildSettingRow(
        title: 'Sync Token',
        child: TextField(
          controller: _railwayTokenController,
          obscureText: !_railwayTokenVisible,
          autocorrect: false,
          enableSuggestions: false,
          enableIMEPersonalizedLearning: false,
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.bodyText,
            fontFamily: 'monospace',
          ),
          decoration: InputDecoration(
            hintText: 'Paste token here',
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
            suffixIcon: IconButton(
              icon: Icon(
                _railwayTokenVisible ? Icons.visibility_off : Icons.visibility,
                size: 18,
                color: AppColors.secondaryText,
              ),
              onPressed: () =>
                  setState(() => _railwayTokenVisible = !_railwayTokenVisible),
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: _railwayTestingConnection
                  ? null
                  : () => _testRailwayConnection(),
              child: _railwayTestingConnection
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Test connection'),
            ),
            if (isConfigured)
              FilledButton(
                onPressed: isSyncing
                    ? null
                    : () => ref.read(railwaySyncProvider.notifier).syncNow(),
                child: isSyncing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Sync now'),
              ),
            if (isConfigured)
              OutlinedButton(
                onPressed: _disconnectRailway,
                style:
                    OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                child: const Text('Disconnect'),
              ),
          ],
        ),
      ),
      if (isConfigured)
        _buildSettingRow(
          title: 'Status',
          subtitle: _railwayStatusLabel(syncState.status),
          trailing: syncState.lastSyncedAt != null
              ? Text(
                  _formatLastSynced(syncState.lastSyncedAt),
                  style: AppTextStyles.bodySmall,
                )
              : null,
        ),
      if (syncState.conflictPreserved)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'Conflict copy preserved — a note conflict was resolved by creating a copy.',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.warning),
          ),
        ),
      if (syncState.errorMessage != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            syncState.errorMessage!,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
          ),
        ),
    ]);
  }

  Future<void> _testRailwayConnection() async {
    final url = _railwayUrlController.text.trim();
    final token = _railwayTokenController.text.trim();
    if (url.isEmpty || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter Railway URL and token first')),
      );
      return;
    }
    setState(() => _railwayTestingConnection = true);
    try {
      final bool ok;
      try {
        ok = await ref
            .read(railwaySyncProvider.notifier)
            .testConnection(url, token);
      } on RailwayInsecureEndpointException {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('URL must use HTTPS. Plain HTTP is not allowed.'),
          ),
        );
        return;
      }
      if (!mounted) return;
      if (ok) {
        // Save credentials only after a successful test.
        final svc = RailwaySettingsService();
        // Normalize by stripping trailing slashes so that spelling variants
        // of the same endpoint (with or without a trailing slash) are treated
        // as identical and do not trigger a needless sync state reset.
        final normalizedUrl = url.trimRight().replaceAll(RegExp(r'/+$'), '');
        // Fall back to the last saved endpoint so a reconnection to the same
        // server after a disconnect does not reset sync metadata and produce
        // conflict copies for every existing note.
        final rawPrevious =
            await svc.getApiUrl() ?? await svc.getLastEndpoint();
        final previousUrl =
            rawPrevious?.trimRight().replaceAll(RegExp(r'/+$'), '');
        // Always cancel the active drain — the running loop may have captured
        // the old token even when only the token changes without a URL change.
        ref.read(railwaySyncProvider.notifier).cancelDrain();
        if (previousUrl != normalizedUrl) {
          // Clear revision metadata and backfill the outbox BEFORE saving the
          // new URL so that a crash between the two writes leaves the old
          // endpoint active with a clean-base outbox rather than the new
          // endpoint carrying stale revision metadata and no outbox entries.
          await DatabaseService.instance.resetSyncState();
        }
        await svc.setApiUrl(normalizedUrl);
        await svc.setToken(token);
        // No mounted check here so reconfigure always runs after the saves;
        // reconfigure() guards internally with its own mounted check.
        await ref.read(railwaySyncProvider.notifier).reconfigure();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connection OK — configuration saved.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Connection failed. Check URL and try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _railwayTestingConnection = false);
    }
  }

  Future<void> _disconnectRailway() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:
            Text('Disconnect Railway sync?', style: AppTextStyles.titleMedium),
        content: Text(
          'This removes only the local configuration. Your notes on Railway '
          'and on this device are not deleted.',
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    // Cancel any in-flight sync before clearing credentials so the running
    // loop cannot apply its response after the configuration is gone.
    ref.read(railwaySyncProvider.notifier).cancelDrain();
    final svc = RailwaySettingsService();
    await svc.clearConfig();
    if (!mounted) return;
    _railwayUrlController.clear();
    _railwayTokenController.clear();
    await ref.read(railwaySyncProvider.notifier).reconfigure();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Railway sync disconnected.')),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
          child: Text(title, style: AppTextStyles.excerptSource),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.dividerBorder),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildSettingRow({
    required String title,
    String? subtitle,
    Widget? trailing,
    Widget? child,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppTextStyles.titleMedium),
                      if (subtitle != null)
                        Text(subtitle, style: AppTextStyles.bodySmall),
                    ],
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
            if (child != null) ...[
              const SizedBox(height: 8),
              child,
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _exportNotes() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final notes = await DatabaseService.instance.getAllNotes();
      final jsonText = NoteExportService.instance.encode(notes);
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .substring(0, 19);
      final fileName = 'grepink-notes-$timestamp.json';
      final bytes = Uint8List.fromList(utf8.encode(jsonText));
      // Web: passing bytes triggers a browser download.
      // Desktop: saveFile only returns the chosen path; write bytes ourselves.
      // Mobile: use share_plus (no desktop implementation for Windows/Linux).
      if (kIsWeb) {
        await FilePicker.platform.saveFile(
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['json'],
          bytes: bytes,
        );
      } else if (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        final savePath = await FilePicker.platform.saveFile(
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['json'],
        );
        if (savePath != null) {
          await writeToDesktopPath(savePath, bytes);
        }
      } else {
        await Share.shareXFiles(
          [XFile.fromData(bytes, name: fileName, mimeType: 'application/json')],
          subject: 'Grepink notes backup',
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<void> _importNotes() async {
    final messenger = ScaffoldMessenger.of(context);
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not open file picker: $e')),
      );
      return;
    }
    if (result == null || result.files.isEmpty) return;

    final bytes = result.files.first.bytes;
    if (bytes == null) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not read the selected file')),
      );
      return;
    }
    List<Note> incoming;
    try {
      final raw = utf8.decode(bytes);
      incoming = NoteExportService.instance.decode(raw);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Invalid backup file: $e')),
      );
      return;
    }

    List<Note> existing;
    ImportPreview preview;
    try {
      existing = await DatabaseService.instance.getAllNotes();
      preview = NoteExportService.instance.preview(existing, incoming);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not read notes: $e')),
      );
      return;
    }

    if (!mounted) return;
    final choice = await showDialog<_ImportChoice>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ImportConfirmDialog(preview: preview),
    );
    if (choice == null || !mounted) return;

    String? successMessage;
    try {
      if (choice == _ImportChoice.replaceAll) {
        final pendingNotes = incoming
            .map(
              (n) => n.copyWith(embeddingPending: true, clearEmbedding: true),
            )
            .toList();
        await DatabaseService.instance.replaceAll(pendingNotes);
        successMessage =
            'Replaced all notes with ${incoming.length} from backup';
      } else {
        // Atomic: either all changes land or none do.
        final result =
            await DatabaseService.instance.mergeNotes(existing, incoming);
        successMessage =
            'Import complete — added ${result.added}, updated ${result.updated}, skipped ${result.skipped}';
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
      return;
    }

    // UI refresh and re-embedding run after the write succeeds. loadNotes() is
    // outside the write try/catch so a transient read error does not incorrectly
    // report the import as failed when the data was already written.
    await ref.read(notesProvider.notifier).loadNotes();
    // Fire-and-forget: wraps its own exceptions so no unhandled futures escape.
    ref.read(notesProvider.notifier).reindexPendingNotes();
    ref.read(railwaySyncProvider.notifier).triggerAfterMutation();
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(successMessage)));
  }

  Future<void> _confirmClearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Clear all notes?', style: AppTextStyles.titleMedium),
        content: Text(
          'This will permanently delete all your notes and cannot be undone.',
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear All',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirm != true) {
      return;
    }

    await DatabaseService.instance.clearAll();
    await ref.read(notesProvider.notifier).loadNotes();
    ref.read(railwaySyncProvider.notifier).triggerAfterMutation();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All notes cleared')),
    );
  }
}

enum _ImportChoice { merge, replaceAll }

class _ImportConfirmDialog extends StatelessWidget {
  final ImportPreview preview;

  const _ImportConfirmDialog({required this.preview});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Import ${preview.total} notes?',
          style: AppTextStyles.titleMedium),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Merge (recommended): keeps your newer version when IDs collide.',
            style: AppTextStyles.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Will add ${preview.willAdd} new note(s), '
            'update ${preview.willUpdate} older note(s), '
            'skip ${preview.willSkip} already up-to-date note(s).',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: 16),
          Text(
            'Replace all: erases every existing note first. Cannot be undone.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        OutlinedButton(
          onPressed: () => _confirmReplace(context),
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
          child: const Text('Replace all'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ImportChoice.merge),
          child: const Text('Merge'),
        ),
      ],
    );
  }

  Future<void> _confirmReplace(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Replace all notes?', style: AppTextStyles.titleMedium),
        content: Text(
          'This will permanently delete all your current notes and replace them '
          'with the ${preview.total} note(s) from the backup. This cannot be undone.',
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Yes, replace all'),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (ok == true) {
      Navigator.pop(context, _ImportChoice.replaceAll);
    }
  }
}
