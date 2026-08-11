import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../models/brave_settings.dart';
import '../models/note.dart';
import '../models/sync_state.dart';
import '../providers/brave_settings_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/sync_provider.dart';
import '../services/database_service.dart';
import '../services/brave_evidence_provider.dart';
import '../services/note_export_service.dart';
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
  bool _apiKeyVisible = false;
  bool _braveSearchApiKeyVisible = false;
  bool _braveAnswersApiKeyVisible = false;

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController();
    _braveSearchApiKeyController = TextEditingController();
    _braveAnswersApiKeyController = TextEditingController();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _braveSearchApiKeyController.dispose();
    _braveAnswersApiKeyController.dispose();
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

        // SYNC
        _buildSyncSection(),

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
    if (dt == null) return 'Never synced';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    final locale = Localizations.localeOf(context).toString();
    return DateFormat.yMd(locale).format(dt);
  }

  // Whether Drive sync is available on this platform.
  bool get _syncSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Widget _buildSyncSection() {
    if (!_syncSupported) {
      return _buildSection('SYNC', [
        _buildSettingRow(
          title: 'Google Drive sync',
          subtitle: 'Sync is only available on Android.',
        ),
      ]);
    }

    final syncState = ref.watch(syncProvider);
    final isSyncing = syncState.status == SyncStatus.syncing;

    return _buildSection('SYNC', [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          'Notes are uploaded as readable JSON to Google Drive App Data and are not end-to-end encrypted.',
          style:
              AppTextStyles.bodySmall.copyWith(color: AppColors.secondaryText),
        ),
      ),
      if (!syncState.isSignedIn)
        _buildSettingRow(
          title: 'Google account',
          subtitle: 'Not signed in',
          trailing: FilledButton(
            onPressed: () => ref.read(syncProvider.notifier).signIn(),
            child: const Text('Sign in with Google'),
          ),
        )
      else ...[
        _buildSettingRow(
          title: 'Google account',
          subtitle: syncState.accountEmail ?? '',
          trailing: OutlinedButton(
            onPressed: () => ref.read(syncProvider.notifier).signOut(),
            child: const Text('Sign out'),
          ),
        ),
        _buildSettingRow(
          title: 'Sync now',
          subtitle: _formatLastSynced(syncState.lastSyncedAt),
          trailing: FilledButton(
            onPressed:
                isSyncing ? null : () => ref.read(syncProvider.notifier).sync(),
            child: isSyncing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Sync now'),
          ),
        ),
      ],
      if (syncState.status == SyncStatus.error &&
          syncState.errorMessage != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            syncState.errorMessage!,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
          ),
        ),
    ]);
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
      final bytes = Uint8List.fromList(utf8.encode(jsonText));
      await Share.shareXFiles(
        [
          XFile.fromData(bytes,
              name: 'grepink-notes-$timestamp.json',
              mimeType: 'application/json')
        ],
        subject: 'Grepink notes backup',
      );
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
    if (choice == _ImportChoice.replaceAll) {
      // Await durable-marker persistence (syncUploadOnly sets the marker before
      // enqueuing), then show success. The upload itself runs in the background.
      await ref.read(syncProvider.notifier).syncUploadOnly();
    } else {
      ref.read(syncProvider.notifier).scheduleSync();
    }
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
    ref.read(syncProvider.notifier).scheduleSync();
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
