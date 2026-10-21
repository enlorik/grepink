import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/note.dart';
import '../models/grounded_answer.dart';
import '../services/note_source_document.dart';
import '../widgets/note_reading_view.dart';
import 'search_screen.dart';
import '../providers/notes_provider.dart';
import '../services/database_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/grepink_fab.dart';
import '../widgets/tag_chip.dart';

class NoteEditorScreen extends ConsumerStatefulWidget {
  final String? noteId;
  final bool embedded;

  const NoteEditorScreen({super.key, this.noteId, this.embedded = false});

  @override
  ConsumerState<NoteEditorScreen> createState() => NoteEditorScreenState();
}

class NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  late TextEditingController _tagController;
  List<String> _tags = [];
  List<String> _keywords = [];
  bool _isSaving = false;
  bool _showSuccess = false;
  Note? _originalNote;
  bool _initialized = false;
  bool _editing = false;
  bool _asking = false;
  int _insertOffset = -1;
  List<GroundedAnswerCitation> _sources = [];
  String get _documentContent {
    final metadata = NoteSourceDocument.encode(_sources);
    return [_contentController.text.trim(), metadata]
        .where((s) => s.isNotEmpty)
        .join('\n\n');
  }

  final FocusNode _contentFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _contentController = TextEditingController();
    _tagController = TextEditingController();
    _editing = widget.noteId == null;
    _contentController.addListener(_contentChanged);
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

  @override
  void didUpdateWidget(NoteEditorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.noteId != widget.noteId) {
      _originalNote = null;
      _sources = [];
      _titleController.clear();
      _contentController.clear();
      _tags = [];
      _keywords = [];
      _editing = false;
      _asking = false;
      _loadNote();
    }
  }

  Future<void> _loadNote() async {
    // Try provider first, fall back to database
    final candidates = (ref.read(notesProvider).valueOrNull ?? [])
        .where((n) => n.id == widget.noteId)
        .toList();
    Note? note = candidates.isEmpty ? null : candidates.first;

    note ??= await DatabaseService.instance.getNoteById(widget.noteId!);

    if (note == null || !mounted || note.id != widget.noteId) return;

    _originalNote = note;
    _titleController.text = note.title;
    _sources = NoteSourceDocument.sources(note.content);
    _contentController.text = NoteSourceDocument.withoutMetadata(note.content);
    setState(() {
      _tags = List.from(note!.tags);
      _keywords = List.from(note.keywords);
    });
  }

  void _contentChanged() {
    if (mounted)
      setState(() {
        _insertOffset = -1;
        _showSuccess = false;
      });
  }

  void _insertDraft(String markdown) {
    final byUrl = {for (final source in _sources) source.url: source};
    for (final source in NoteSourceDocument.sources(markdown)) {
      byUrl[source.url] = source;
    }
    _sources = byUrl.values.toList();
    final updated = insertNoteDraft(_contentController.text,
        NoteSourceDocument.withoutMetadata(markdown), _insertOffset);
    _contentController.text = updated;
    setState(() => _editing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Inserted into your draft; Save to keep it.')),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.removeListener(_contentChanged);
    _contentController.dispose();
    _tagController.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  Future<bool> confirmLeave() => _onWillPop();

  bool get _hasChanges {
    if (_originalNote == null) {
      return _titleController.text.isNotEmpty ||
          _contentController.text.isNotEmpty;
    }
    return _titleController.text != _originalNote!.title ||
        _documentContent != _originalNote!.content.trim() ||
        _tags.toString() != _originalNote!.tags.toString();
  }

  List<String> _extractKeywords(String title, String content) {
    final text = '$title $content'.toLowerCase();
    final words = text.split(RegExp(r'[\s\n\r\t,.!?;:]+'));
    final stopWords = {
      'the',
      'a',
      'an',
      'is',
      'in',
      'on',
      'at',
      'to',
      'for',
      'of',
      'and',
      'or',
      'but',
      'with',
      'it',
      'this',
      'that',
      'was',
      'are',
      'be',
      'i',
      'we',
      'you',
      'he',
      'she',
      'they',
      'my',
      'your',
      'his',
      'her',
      'its',
    };
    final freq = <String, int>{};
    for (final w in words) {
      if (w.length > 3 && !stopWords.contains(w)) {
        freq[w] = (freq[w] ?? 0) + 1;
      }
    }
    final sorted = freq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(10).map((e) => e.key).toList();
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final content = _documentContent;
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
        _originalNote = updated;
      }

      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _showSuccess = true;
      });

      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted && !widget.embedded) context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving note: $e')),
        );
      }
    }
  }

  Future<bool> _onWillPop() async {
    if (_isSaving) return false;
    if (!_hasChanges) return true;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Unsaved changes', style: AppTextStyles.titleMedium),
        content:
            Text('What would you like to do?', style: AppTextStyles.bodyMedium),
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
      return widget.embedded && !_hasChanges;
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
    final screen = Scaffold(
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
              if (_asking)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: DropdownButtonFormField<int>(
                    key: ValueKey(
                        'insert-$_insertOffset-${_contentController.text.length}'),
                    initialValue: _insertOffset,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Insert reviewed answer'),
                    items: noteInsertionTargets(_contentController.text)
                        .map((target) => DropdownMenuItem(
                              value: target.offset,
                              child: Text(
                                  target.offset < 0
                                      ? target.label
                                      : 'After: ${target.label}',
                                  overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _insertOffset = value ?? -1),
                  ),
                ),
              Expanded(child: LayoutBuilder(builder: (context, constraints) {
                final note = SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 100),
                  child: Center(
                      child: ConstrainedBox(
                    constraints:
                        BoxConstraints(maxWidth: _editing ? 1160 : 760),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTitleField(),
                          const Divider(color: AppColors.dividerBorder),
                          const SizedBox(height: 12),
                          LayoutBuilder(builder: (context, bodyConstraints) {
                            final preview =
                                NoteReadingView(content: _documentContent);
                            if (!_editing) return preview;
                            if (bodyConstraints.maxWidth >= 800) {
                              return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: _buildContentField()),
                                    const SizedBox(width: 24),
                                    Expanded(child: preview),
                                  ]);
                            }
                            return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildContentField(),
                                  const Divider(),
                                  const Text('Reading preview'),
                                  const SizedBox(height: 12),
                                  preview,
                                ]);
                          }),
                          if (_editing) ...[
                            const SizedBox(height: 20),
                            _buildTagsSection(),
                            if (_keywords.isNotEmpty) _buildKeywordsSection(),
                          ],
                        ]),
                  )),
                );
                if (!_asking) return note;
                final questions = Column(children: [
                  Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        const Expanded(
                            child: Text('Research beside your note')),
                        IconButton(
                            tooltip: 'Close questions',
                            onPressed: () => setState(() => _asking = false),
                            icon: const Icon(Icons.close)),
                      ])),
                  Expanded(child: SearchScreen(onInsertDraft: _insertDraft)),
                ]);
                return constraints.maxWidth >= 1050 &&
                        MediaQuery.textScalerOf(context).scale(1) <= 1.5
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                            Expanded(child: note),
                            const VerticalDivider(width: 1),
                            SizedBox(width: 440, child: questions),
                          ])
                    : Column(children: [
                        Expanded(child: note),
                        const Divider(height: 1),
                        Expanded(child: questions)
                      ]);
              })),
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
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop && await _onWillPop() && context.mounted) context.pop();
      },
      child: screen,
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 0),
      child: Row(
        children: [
          if (!widget.embedded)
            IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.deepAction),
              onPressed: () async {
                if (await _onWillPop() && mounted) {
                  context.pop();
                }
              },
            ),
          Expanded(
            child: Text(
              widget.noteId == null ? 'New Note' : 'Notebook',
              style: AppTextStyles.titleLarge,
            ),
          ),
          TextButton.icon(
            onPressed: () => setState(() => _editing = !_editing),
            icon: Icon(_editing
                ? Icons.chrome_reader_mode_outlined
                : Icons.edit_outlined),
            label: Text(_editing ? 'Read' : 'Edit'),
          ),
          TextButton.icon(
            onPressed: () => setState(() => _asking = !_asking),
            icon: const Icon(Icons.add_comment_outlined),
            label: const Text('Ask'),
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
        hintStyle: AppTextStyles.displayMedium
            .copyWith(color: AppColors.placeholderText),
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
        hintStyle:
            AppTextStyles.bodyLarge.copyWith(color: AppColors.placeholderText),
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
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.deepAction),
                decoration: InputDecoration(
                  hintText: 'Add tag...',
                  hintStyle: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.placeholderText),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide:
                        const BorderSide(color: AppColors.dividerBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide:
                        const BorderSide(color: AppColors.dividerBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide:
                        const BorderSide(color: AppColors.primaryAccent),
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
          children: _keywords
              .map((kw) => Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.keywordHighlight.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: AppColors.keywordHighlight
                              .withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      kw,
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.deepAction),
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }
}
