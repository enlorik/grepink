import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/note.dart';
import '../providers/notes_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/note_card.dart';
import '../widgets/grepink_fab.dart';
import '../widgets/grepink_bottom_nav.dart';

class NotesListScreen extends ConsumerStatefulWidget {
  const NotesListScreen({super.key});

  @override
  ConsumerState<NotesListScreen> createState() => _NotesListScreenState();
}

class _NotesListScreenState extends ConsumerState<NotesListScreen> {
  final Map<String, bool> _deletingIds = {};

  int _navIndex = 0;

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
      setState(() => _deletingIds.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(notesProvider);
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
                      child: Text('Grepink', style: AppTextStyles.displayMedium),
                    ),
                    IconButton(
                      icon: const Icon(Icons.search, color: AppColors.deepAction),
                      onPressed: () => context.push('/search'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: notesAsync.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: AppColors.primaryAction),
                  ),
                  error: (e, _) => Center(
                    child: Text('Error loading notes', style: AppTextStyles.bodyMedium),
                  ),
                  data: (_) {
                    if (pinnedNotes.isEmpty && unpinnedNotes.isEmpty) {
                      return _buildEmptyState();
                    }
                    return _buildNotesList(pinnedNotes, unpinnedNotes);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: GrepinkFab(
        onPressed: () => context.push('/note/new'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: GrepinkBottomNav(
        currentIndex: _navIndex,
        onTap: _onNavTap,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 80,
            height: 80,
            child: Icon(Icons.lightbulb_outline, size: 80, color: AppColors.primaryAccent),
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

  Widget _buildNotesList(List<Note> pinned, List<Note> unpinned) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      int cols;
      double margin;
      if (width < 450) {
        cols = 1;
        margin = 16;
      } else if (width < 1024) {
        cols = 2;
        margin = 24;
      } else {
        cols = width > 1400 ? 4 : 3;
        margin = 48;
      }

      return RefreshIndicator(
        onRefresh: () => ref.read(notesProvider.notifier).loadNotes(),
        color: AppColors.primaryAction,
        child: CustomScrollView(
          slivers: [
            if (pinned.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(margin, 20, margin, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.push_pin, size: 14, color: AppColors.pinHighlight),
                      const SizedBox(width: 6),
                      Text('PINNED', style: AppTextStyles.excerptSource),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: margin),
                sliver: cols == 1
                    ? SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (ctx, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _buildSwipeable(pinned[i], i),
                          ),
                          childCount: pinned.length,
                        ),
                      )
                    : SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1.2,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (ctx, i) => _buildSwipeable(pinned[i], i),
                          childCount: pinned.length,
                        ),
                      ),
              ),
            ],
            if (unpinned.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(margin, 20, margin, 8),
                  child: Text('NOTES', style: AppTextStyles.excerptSource),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(margin, 0, margin, 100),
                sliver: cols == 1
                    ? SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (ctx, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _buildSwipeable(unpinned[i], pinned.length + i),
                          ),
                          childCount: unpinned.length,
                        ),
                      )
                    : SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1.2,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (ctx, i) => _buildSwipeable(unpinned[i], pinned.length + i),
                          childCount: unpinned.length,
                        ),
                      ),
              ),
            ],
          ],
        ),
      );
    });
  }

  Widget _buildSwipeable(Note note, int index) {
    final isDeleting = _deletingIds[note.id] == true;
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      child: isDeleting
          ? const SizedBox.shrink()
          : Dismissible(
              key: Key(note.id),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                decoration: BoxDecoration(
                  color: AppColors.deleteHighlight,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              confirmDismiss: (_) async {
                return await _showDeleteConfirm(context);
              },
              onDismissed: (_) => _deleteNote(note.id),
              child: NoteCard(
                note: note,
                index: index,
                onDelete: () => _deleteNote(note.id),
                onPin: () => ref.read(notesProvider.notifier).togglePin(note.id),
              ),
            ),
    );
  }

  Future<bool> _showDeleteConfirm(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete note?', style: AppTextStyles.titleMedium),
        content: Text('This cannot be undone.', style: AppTextStyles.bodyMedium),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
