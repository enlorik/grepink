import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/note.dart';
import '../providers/notes_provider.dart';
import '../providers/settings_provider.dart';
import '../services/database_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/grepink_bottom_nav.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _apiKeyController;
  bool _apiKeyVisible = false;

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);

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
                      icon: const Icon(Icons.arrow_back, color: AppColors.deepAction),
                      onPressed: () => context.pop(),
                    ),
                    Text('Settings', style: AppTextStyles.displayMedium),
                  ],
                ),
              ),
              Expanded(
                child: settingsAsync.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: AppColors.primaryAction),
                  ),
                  error: (e, _) => Center(child: Text('Error: $e')),
                  data: (settings) {
                    if (_apiKeyController.text.isEmpty && settings.apiKey.isNotEmpty) {
                      _apiKeyController.text = settings.apiKey;
                    }
                    return _buildContent(settings);
                  },
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

  Widget _buildContent(AppSettings settings) {
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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('v1.1', style: AppTextStyles.bodySmall.copyWith(color: AppColors.deepAction)),
                ),
                const SizedBox(width: 8),
                Switch(
                  value: false,
                  onChanged: null,
                  activeColor: AppColors.primaryAction,
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
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _apiKeyVisible ? Icons.visibility_off : Icons.visibility,
                        size: 18,
                        color: AppColors.secondaryText,
                      ),
                      onPressed: () => setState(() => _apiKeyVisible = !_apiKeyVisible),
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
              activeColor: AppColors.primaryAction,
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
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.deepAction, fontWeight: FontWeight.w600)),
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
            trailing: const Icon(Icons.upload_outlined, color: AppColors.primaryAction),
            onTap: () => _exportNotes(context),
          ),
          _buildSettingRow(
            title: 'Import Notes',
            trailing: const Icon(Icons.download_outlined, color: AppColors.primaryAction),
            onTap: () => _importNotes(context),
          ),
          _buildSettingRow(
            title: 'Clear All Notes',
            trailing: const Icon(Icons.delete_outline, color: AppColors.error),
            onTap: () => _confirmClearAll(context),
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

  Future<void> _exportNotes(BuildContext context) async {
    try {
      final notes = ref.read(notesProvider).valueOrNull ?? [];
      final json = jsonEncode(notes.map((n) => n.toJson()).toList());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported ${notes.length} notes (${json.length} chars)')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }

  Future<void> _importNotes(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Import: paste JSON data in a future update')),
    );
  }

  Future<void> _confirmClearAll(BuildContext context) async {
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
            child: const Text('Clear All', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await DatabaseService.instance.clearAll();
      await ref.read(notesProvider.notifier).loadNotes();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All notes cleared')),
        );
      }
    }
  }
}
