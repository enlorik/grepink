import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/note.dart';
import '../providers/notes_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/grepink_fab.dart';
import '../widgets/tag_chip.dart';

class NoteEditorScreen extends ConsumerStatefulWidget {
  final String? noteId;

  const NoteEditorScreen({super.key, this.noteId});

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  late TextEditingController _tagController;
  List<String> _tags = [];
  List<String> _keywords = [];
  bool _isSaving = false;
  bool _showSuccess = false;
  Note? _originalNote;
  bool _initialized = false;
  final FocusNode _contentFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _contentController = TextEditingController();
    _tagController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized && widget.noteId != null) {
      _initialized = true;
      _loadNote();
    } else {
      _initialized = true;
    }
  }

  Future<void> _loadNote() async {
    final notes = ref.read(notesProvider).valueOrNull ?? [];
    final note = notes.firstWhere(
      (n) => n.id == widget.noteId,
      orElse: () => Note(
        id: widget.noteId!,
        title: '',
        content: '',
        tags: const [],
        keywords: const [],
        isPinned: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        embeddingPending: false,
      ),
    );
    _originalNote = note;
    _titleController.text = note.title;
    _contentController.text = note.content;
    setState(() {
      _tags = List.from(note.tags);
      _keywords = List.from(note.keywords);
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _tagController.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  bool get _hasChanges {
    if (_originalNote == null) {
      return _titleController.text.isNotEmpty || _contentController.text.isNotEmpty;
    }
    return _titleController.text != _originalNote!.title ||
        _contentController.text != _originalNote!.content ||
        _tags.toString() != _originalNote!.tags.toString();
  }

  List<String> _extractKeywords(String title, String content) {
    final text = '$title $content'.toLowerCase();
    final words = text.split(RegExp(r'[\s\n\r\t,\.!?;:]+'));
    final stopWords = {
      'the', 'a', 'an', 'is', 'in', 'on', 'at', 'to', 'for', 'of', 'and',
      'or', 'but', 'with', 'it', 'this', 'that', 'was', 'are', 'be', 'i',
      'we', 'you', 'he', 'she', 'they', 'my', 'your', 'his', 'her', 'its',
    };
    final freq = <String, int>{};
    for (final w in words) {
      if (w.length > 3 && !stopWords.contains(w)) {
        freq[w] = (freq[w] ?? 0) + 1;
      }
    }
    final sorted = freq.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(10).map((e) => e.key).toList();
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    if (title.isEmpty && content.isEmpty) return;

    setState(() {
      _isSaving = true;
      _keywords = _extractKeywords(title, content);
    });

    try {
      if (widget.noteId == null) {
        await ref.read(notesProvider.notifier).addNote(
          title: title,
          content: content,
          tags: _tags,
          keywords: _keywords,
        );
      } else if (_originalNote != null) {
        final updated = _originalNote!.copyWith(
          title: title.isEmpty ? 'Untitled' : title,
          content: content,
          tags: _tags,
          keywords: _keywords,
          updatedAt: DateTime.now(),
        );
        await ref.read(notesProvider.notifier).updateNote(updated);
      }

      setState(() {
        _isSaving = false;
        _showSuccess = true;
      });

      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) context.pop();
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving note: $e')),
        );
      }
    }
  }

  Future<bool> _onWillPop() async {
    if (!_hasChanges) return true;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Unsaved changes', style: AppTextStyles.titleMedium),
        content: Text('What would you like to do?', style: AppTextStyles.bodyMedium),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: const Text('Discard'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('Save'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (result == 'save') {
      await _save();
      return false;
    }
    return result == 'discard';
  }

  void _addTag() {
    final tag = _tagController.text.trim();
    if (tag.isNotEmpty && !_tags.contains(tag)) {
      setState(() {
        _tags.add(tag);
        _tagController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        if (await _onWillPop() && context.mounted) {
          context.pop();
        }
      },
      child: Scaffold(
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
                _buildAppBar(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTitleField(),
                        const SizedBox(height: 4),
                        const Divider(color: AppColors.dividerBorder),
                        const SizedBox(height: 12),
                        _buildContentField(),
                        const SizedBox(height: 20),
                        _buildTagsSection(),
                        if (_keywords.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _buildKeywordsSection(),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        floatingActionButton: GrepinkFab(
          onPressed: _isSaving ? null : _save,
          isSaving: _isSaving,
          showSuccess: _showSuccess,
          icon: Icons.check,
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.deepAction),
            onPressed: () async {
              if (await _onWillPop()) context.pop();
            },
          ),
          Expanded(
            child: Text(
              widget.noteId == null ? 'New Note' : 'Edit Note',
              style: AppTextStyles.titleLarge,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitleField() {
    return TextField(
      controller: _titleController,
      style: AppTextStyles.displayMedium,
      decoration: InputDecoration(
        hintText: 'Title',
        hintStyle: AppTextStyles.displayMedium.copyWith(color: AppColors.placeholderText),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        fillColor: Colors.transparent,
        filled: false,
      ),
      textInputAction: TextInputAction.next,
      onSubmitted: (_) => _contentFocus.requestFocus(),
    );
  }

  Widget _buildContentField() {
    return TextField(
      controller: _contentController,
      focusNode: _contentFocus,
      style: AppTextStyles.bodyLarge,
      decoration: InputDecoration(
        hintText: 'Write your thoughts...',
        hintStyle: AppTextStyles.bodyLarge.copyWith(color: AppColors.placeholderText),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: EdgeInsets.zero,
        fillColor: Colors.transparent,
        filled: false,
      ),
      maxLines: null,
      minLines: 8,
      keyboardType: TextInputType.multiline,
    );
  }

  Widget _buildTagsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('TAGS', style: AppTextStyles.excerptSource),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ..._tags.map((tag) => TagChip(
              label: tag,
              isEditable: true,
              onDelete: () => setState(() => _tags.remove(tag)),
            )),
            SizedBox(
              width: 120,
              height: 32,
              child: TextField(
                controller: _tagController,
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.deepAction),
                decoration: InputDecoration(
                  hintText: 'Add tag...',
                  hintStyle: AppTextStyles.bodySmall.copyWith(color: AppColors.placeholderText),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: AppColors.dividerBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: AppColors.dividerBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: AppColors.primaryAccent),
                  ),
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.surface,
                ),
                onSubmitted: (_) => _addTag(),
                textInputAction: TextInputAction.done,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKeywordsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('KEYWORDS', style: AppTextStyles.excerptSource),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _keywords.map((kw) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.keywordHighlight.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.keywordHighlight.withOpacity(0.5)),
            ),
            child: Text(
              kw,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.deepAction),
            ),
          )).toList(),
        ),
      ],
    );
  }
}
