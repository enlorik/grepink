import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/note.dart';
import 'note_editor_screen.dart';
import '../providers/notes_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/grepink_fab.dart';
import '../widgets/grepink_bottom_nav.dart';

class NotesListScreen extends ConsumerStatefulWidget {
  const NotesListScreen({super.key});

  @override
  ConsumerState<NotesListScreen> createState() => _NotesListScreenState();
}

class _NotesListScreenState extends ConsumerState<NotesListScreen> {
  final Map<String, bool> _deletingIds = {};
  final _editorKey = GlobalKey<NoteEditorScreenState>();
  List<Note> _visibleNotes = [];
  String? _selectedId;

  Future<void> _selectNote(String id) async {
    if (_selectedId == id) return;
    if (_editorKey.currentState != null &&
        !await _editorKey.currentState!.confirmLeave()) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _selectedId = id;
    });
  }

  final int _navIndex = 0;

  void _onNavTap(int index) {
    if (index == 0) return;
    if (index == 1) context.push('/search');
    if (index == 2) context.push('/settings');
  }

  Future<void> _deleteNote(String id) async {
    setState(() => _deletingIds[id] = true);
    await Future.delayed(const Duration(milliseconds: 200));
    if (mounted) {
      await ref.read(notesProvider.notifier).deleteNote(id);
      if (mounted) setState(() => _deletingIds.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(notesProvider);
    if (notesAsync.valueOrNull != null) _visibleNotes = notesAsync.valueOrNull!;
    final pinnedNotes = ref.watch(pinnedNotesProvider);
    final unpinnedNotes = ref.watch(unpinnedNotesProvider);

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
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child:
                          Text('Grepink', style: AppTextStyles.displayMedium),
                    ),
                    IconButton(
                      tooltip: 'New note',
                      onPressed: () => context.push('/note/new'),
                      icon: const Icon(Icons.add, color: AppColors.deepAction),
                    ),
                    IconButton(
                      icon:
                          const Icon(Icons.search, color: AppColors.deepAction),
                      onPressed: () => context.push('/search'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _visibleNotes.isNotEmpty
                    ? _buildNotebook(_visibleNotes)
                    : notesAsync.when(
                        loading: () => const Center(
                          child: CircularProgressIndicator(
                              color: AppColors.primaryAction),
                        ),
                        error: (e, _) => Center(
                          child: Text('Error loading notes',
                              style: AppTextStyles.bodyMedium),
                        ),
                        data: (_) {
                          if (pinnedNotes.isEmpty && unpinnedNotes.isEmpty) {
                            return _buildEmptyState();
                          }
                          return _buildNotebook(
                              [...pinnedNotes, ...unpinnedNotes]);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: _visibleNotes.isNotEmpty
          ? null
          : GrepinkFab(
              onPressed: () => context.push('/note/new'),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: GrepinkBottomNav(
        currentIndex: _navIndex,
        onTap: _onNavTap,
      ),
    );
  }

  Widget _buildNotebook(List<Note> notes) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 900;
      if (wide) _selectedId ??= notes.first.id;
      final active = notes.where((n) => n.id == _selectedId);
      final selected = active.isEmpty ? notes.first : active.first;
      final editor = NoteEditorScreen(
          key: _editorKey, noteId: selected.id, embedded: true);
      final list = ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final note in notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                selected:
                    (wide || _selectedId != null) && note.id == selected.id,
                selectedTileColor: AppColors.surface,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                title: Text(note.title,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                    note.content
                        .replaceAll(RegExp(r'[#*`\[\]]'), '')
                        .split('\n')
                        .where((l) => l.trim().isNotEmpty)
                        .take(2)
                        .join(' '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                onTap: () => _selectNote(note.id),
                trailing: PopupMenuButton<String>(
                  tooltip: 'Note actions',
                  onSelected: (action) async {
                    if (action == 'pin') {
                      await ref.read(notesProvider.notifier).togglePin(note.id);
                    }
                    if (action == 'delete' &&
                        context.mounted &&
                        await _showDeleteConfirm(context)) {
                      if (note.id == selected.id &&
                          _editorKey.currentState != null &&
                          !await _editorKey.currentState!.confirmLeave()) {
                        return;
                      }
                      await _deleteNote(note.id);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                        value: 'pin',
                        child: Text(note.isPinned ? 'Unpin' : 'Pin')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ),
            ),
        ],
      );
      if (wide) {
        return Row(children: [
          SizedBox(width: 260, child: list),
          const VerticalDivider(width: 1),
          Expanded(child: editor)
        ]);
      }
      if (_selectedId == null) return list;
      return Column(children: [
        Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
                onPressed: () async {
                  if (_editorKey.currentState != null &&
                      !await _editorKey.currentState!.confirmLeave()) {
                    return;
                  }
                  if (mounted) setState(() => _selectedId = null);
                },
                icon: const Icon(Icons.arrow_back),
                label: const Text('All notes'))),
        Expanded(child: editor),
      ]);
    });
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 80,
            height: 80,
            child: Icon(Icons.lightbulb_outline,
                size: 80, color: AppColors.primaryAccent),
          ),
          const SizedBox(height: 24),
          Text('Your mind is blank...', style: AppTextStyles.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Tap + to add your first note',
            style: AppTextStyles.bodyMedium,
          ),
        ],
      ),
    );
  }

  Future<bool> _showDeleteConfirm(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete note?', style: AppTextStyles.titleMedium),
        content:
            Text('This cannot be undone.', style: AppTextStyles.bodyMedium),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
