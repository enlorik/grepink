import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/note.dart';
import '../models/grounded_answer.dart';
import '../services/note_source_document.dart';
import '../widgets/note_reading_view.dart';
import '../widgets/evidence_workspace.dart';
import '../services/note_addition.dart';
import 'search_screen.dart';
import '../providers/notes_provider.dart';
import '../services/database_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
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
  bool _showMetadata = false;
  bool _asking = false;
  int _insertOffset = -1;
  final _evidence = EvidenceController();
  List<GroundedAnswerCitation> _sources = [];
  String get _documentContent {
    final metadata = NoteSourceDocument.encode(_sources);
    return [
      _contentController.text,
      metadata,
    ].where((s) => s.isNotEmpty).join('\n\n');
  }

  final FocusNode _contentFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _contentController = TextEditingController();
    _tagController = TextEditingController();
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
      _evidence.clear();
      _originalNote = null;
      _sources = [];
      _titleController.clear();
      _contentController.clear();
      _tags = [];
      _keywords = [];
      _showMetadata = false;
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
    _contentController.text = NoteSourceDocument.withoutMetadata(
      note.content,
      trim: false,
    );
    setState(() {
      _tags = List.from(note!.tags);
      _keywords = List.from(note.keywords);
    });
  }

  void _contentChanged() {
    if (mounted) {
      setState(() {
        _insertOffset = -1;
        _showSuccess = false;
      });
    }
  }

  void _insertDraft(String markdown) {
    final byUrl = {for (final source in _sources) source.url: source};
    for (final source in NoteSourceDocument.sources(markdown)) {
      byUrl[source.url] = source;
    }
    _sources = byUrl.values.toList();
    final updated = insertNoteDraft(
      _contentController.text,
      noteAdditionBody(markdown),
      _insertOffset,
    );
    if (_titleController.text.trim().isEmpty) {
      _titleController.text = noteTopicTitle('', markdown);
    }
    _contentController.text = updated;
    setState(() => _showMetadata = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Inserted into your draft; Save to keep it.'),
      ),
    );
  }

  @override
  void dispose() {
    _evidence.dispose();
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
        _contentController.text !=
            NoteSourceDocument.withoutMetadata(
              _originalNote!.content,
              trim: false,
            ) ||
        NoteSourceDocument.encode(_sources) !=
            NoteSourceDocument.encode(
              NoteSourceDocument.sources(_originalNote!.content),
            ) ||
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
    if (title.isEmpty && NoteSourceDocument.withoutMetadata(content).isEmpty) {
      return;
    }

    setState(() {
      _isSaving = true;
      _keywords = _extractKeywords(title, content);
    });

    try {
      if (widget.noteId == null) {
        await ref
            .read(notesProvider.notifier)
            .addNote(
              title: title,
              content: content,
              tags: _tags,
              keywords: _keywords,
            );
      } else if (_originalNote != null) {
        final latest = (ref.read(notesProvider).valueOrNull ?? <Note>[]).where(
          (note) => note.id == widget.noteId,
        );
        final updated = (latest.isEmpty ? _originalNote! : latest.first)
            .copyWith(
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving note: $e')));
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
        content: Text(
          'What would you like to do?',
          style: AppTextStyles.bodyMedium,
        ),
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
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final note = ColoredBox(
                      color: AppColors.surface,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                            child: _buildTitleField(),
                          ),
                          const Divider(
                            height: 1,
                            color: AppColors.dividerBorder,
                          ),
                          Expanded(
                            child: NoteReadingView(
                              content: _documentContent,
                              editable: true,
                              evidence: _evidence,
                              onAddBelow: (offset) => setState(() {
                                _insertOffset = offset;
                                _asking = true;
                              }),
                              onChanged: (value) {
                                _contentController.text =
                                    NoteSourceDocument.withoutMetadata(
                                      value,
                                      trim: false,
                                    );
                                _contentChanged();
                              },
                            ),
                          ),
                          if (_showMetadata)
                            SizedBox(
                              height: 90,
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _buildTagsSection(),
                                    if (_keywords.isNotEmpty)
                                      _buildKeywordsSection(),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                    // One shared inspector serves both note and answer, and stays
                    // mounted while the question field receives focus.

                    final questions = Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              const Expanded(child: Text('Research')),
                              IconButton(
                                tooltip: 'Close questions',
                                onPressed: () =>
                                    setState(() => _asking = false),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 8,
                          ),
                          child: DropdownButtonFormField<int>(
                            key: ValueKey(
                              'insert-$_insertOffset-${_contentController.text.length}',
                            ),
                            initialValue: _insertOffset,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Insert reviewed answer',
                            ),
                            items: [
                              if (_insertOffset >= 0 &&
                                  !noteInsertionTargets(
                                    _contentController.text,
                                  ).any((t) => t.offset == _insertOffset))
                                DropdownMenuItem(
                                  value: _insertOffset,
                                  child: const Text('After selected passage'),
                                ),
                              ...noteInsertionTargets(
                                _contentController.text,
                              ).map(
                                (target) => DropdownMenuItem(
                                  value: target.offset,
                                  child: Text(
                                    target.offset < 0
                                        ? target.label
                                        : 'After: ${target.label}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (value) =>
                                setState(() => _insertOffset = value ?? -1),
                          ),
                        ),
                        Expanded(
                          child: SearchScreen(
                            onInsertDraft: _insertDraft,
                            evidence: _evidence,
                          ),
                        ),
                      ],
                    );
                    return ValueListenableBuilder<EvidenceSelection?>(
                      valueListenable: _evidence,
                      builder: (context, evidence, _) {
                        final showEvidence = _asking || evidence != null;
                        final sideBySide =
                            constraints.maxWidth >= 1180 &&
                            MediaQuery.textScalerOf(context).scale(1) <= 1.5;
                        Widget work = !_asking
                            ? note
                            : sideBySide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(child: note),
                                  const VerticalDivider(width: 1),
                                  SizedBox(width: 360, child: questions),
                                ],
                              )
                            : Column(
                                children: [
                                  Expanded(child: note),
                                  const Divider(height: 1),
                                  Expanded(child: questions),
                                ],
                              );
                        if (!showEvidence) return work;
                        final pane = EvidencePane(controller: _evidence);
                        return constraints.maxWidth >= 860
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(child: work),
                                  SizedBox(width: 300, child: pane),
                                ],
                              )
                            : Column(
                                children: [
                                  Expanded(child: work),
                                  SizedBox(
                                    height: constraints.maxHeight < 540
                                        ? 150
                                        : 220,
                                    child: pane,
                                  ),
                                ],
                              );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
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
              widget.noteId == null
                  ? 'New Note'
                  : (_hasChanges ? 'Unsaved changes' : 'Notebook'),
              style: AppTextStyles.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: 'Note details',
            icon: const Icon(Icons.info_outline, size: 20),
            onPressed: () => setState(() => _showMetadata = !_showMetadata),
          ),
          TextButton.icon(
            onPressed: () => setState(() => _asking = !_asking),
            icon: const Icon(Icons.add_comment_outlined),
            label: const Text('Ask'),
          ),
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: Text(
              _isSaving ? 'Saving…' : (_showSuccess ? 'Saved' : 'Save'),
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
        hintStyle: AppTextStyles.displayMedium.copyWith(
          color: AppColors.placeholderText,
        ),
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
            ..._tags.map(
              (tag) => TagChip(
                label: tag,
                isEditable: true,
                onDelete: () => setState(() => _tags.remove(tag)),
              ),
            ),
            SizedBox(
              width: 120,
              height: 32,
              child: TextField(
                controller: _tagController,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.deepAction,
                ),
                decoration: InputDecoration(
                  hintText: 'Add tag...',
                  hintStyle: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.placeholderText,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(
                      color: AppColors.dividerBorder,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(
                      color: AppColors.dividerBorder,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(
                      color: AppColors.primaryAccent,
                    ),
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
              .map(
                (kw) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.keywordHighlight.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.keywordHighlight.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    kw,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.deepAction,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}
