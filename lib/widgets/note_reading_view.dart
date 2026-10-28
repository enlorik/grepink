import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:flutter/services.dart';

import '../models/grounded_answer.dart';
import '../services/note_document_blocks.dart';
import '../services/markdown_list_lines.dart';
import '../services/source_page_loader.dart';
import 'source_page_reader.dart';
import 'evidence_workspace.dart';
import '../services/note_source_document.dart';
import '../theme/app_colors.dart';
import 'claim_source_preview.dart';

/// A document and its evidence occupy their own layout bounds, never an overlay.
/// Passage edits are drafts; the notebook's explicit Save remains authoritative.
class NoteReadingView extends StatefulWidget {
  final String content;
  final bool editable;
  final ValueChanged<String>? onChanged;
  final SourcePageLoader? sourceLoader;
  final EvidenceController? evidence;
  final ValueChanged<int>? onAddBelow;
  const NoteReadingView({
    super.key,
    required this.content,
    this.editable = false,
    this.onChanged,
    this.sourceLoader,
    this.evidence,
    this.onAddBelow,
  });
  @override
  State<NoteReadingView> createState() => _NoteReadingViewState();
}

class _NoteReadingViewState extends State<NoteReadingView> {
  final _sourceScroll = ScrollController();
  final _editor = TextEditingController();
  final _editorFocus = FocusNode();
  String _editPrefix = '', _editLinks = '', _passageText = '';
  int _editGeneration = 0;

  @override
  void initState() {
    super.initState();
    _editorFocus.addListener(() {
      if (_editorFocus.hasFocus || _editing == null) return;
      final generation = _editGeneration;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            generation == _editGeneration &&
            !_editorFocus.hasFocus &&
            _editing != null) {
          _finish();
        }
      });
    });
  }

  List<GroundedAnswerCitation> _sources = [];
  int _sourceIndex = 0;
  NoteDocumentBlock? _editing;
  String _before = '', _after = '', _original = '';
  String? _lastEmission;

  @override
  void dispose() {
    _sourceScroll.dispose();
    _editor.dispose();
    _editorFocus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(NoteReadingView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content &&
        widget.content != _lastEmission) {
      _editing = null;
      _sources = [];
    }
    if (!widget.editable) _editing = null;
  }

  List<String> _urls(String markdown) {
    final result = <String>{};
    void visit(md.Node node) {
      if (node is! md.Element) return;
      final href = node.attributes['href'];
      if (href != null &&
          ['http', 'https'].contains(Uri.tryParse(href)?.scheme)) {
        result.add(href);
      }
      for (final child in node.children ?? <md.Node>[]) {
        visit(child);
      }
    }

    final doc = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored);
    for (final node in doc.parseLines(markdown.split('\n'))) {
      visit(node);
    }
    return result.toList();
  }

  List<GroundedAnswerCitation> _noteSources() {
    final result = {
      for (final c in NoteSourceDocument.sources(widget.content)) c.url: c,
    };
    for (final url in _urls(
      NoteSourceDocument.visibleMarkdown(widget.content),
    )) {
      result.putIfAbsent(
        url,
        () => GroundedAnswerCitation(
          id: url,
          title: Uri.parse(url).host,
          url: url,
        ),
      );
    }
    return result.values.toList();
  }

  void _inspect(List<String> urls, {String? selected, String? passage}) {
    if (urls.isEmpty) return;
    final saved = {for (final c in _noteSources()) c.url: c};
    if (widget.evidence != null) {
      widget.evidence!.inspect(
        passage ?? _passageText,
        urls
            .map(
              (url) =>
                  saved[url] ??
                  GroundedAnswerCitation(
                    id: url,
                    title: Uri.parse(url).host,
                    url: url,
                  ),
            )
            .toList(),
      );
      return;
    }
    final index = selected == null ? 0 : urls.indexOf(selected);
    if (_sources.map((c) => c.url).join('\n') == urls.join('\n') &&
        selected == null &&
        (passage == null || passage == _passageText)) {
      return;
    }
    setState(() {
      _sources = urls
          .map(
            (url) =>
                saved[url] ??
                GroundedAnswerCitation(
                  id: url,
                  title: Uri.parse(url).host,
                  url: url,
                ),
          )
          .toList();
      _sourceIndex = index < 0 ? 0 : index;
      if (passage != null) _passageText = passage;
    });
    if (_sourceScroll.hasClients) _sourceScroll.jumpTo(0);
  }

  void _wheel(PointerSignalEvent event) {
    if (widget.evidence != null) {
      widget.evidence!.wheel(event);
      return;
    }
    if (event is! PointerScrollEvent ||
        !_sourceScroll.hasClients ||
        _sourceScroll.position.maxScrollExtent <= 0) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      _sourceScroll.jumpTo(
        (_sourceScroll.offset + event.scrollDelta.dy)
            .clamp(0.0, _sourceScroll.position.maxScrollExtent)
            .toDouble(),
      );
    });
  }

  void _edit(NoteDocumentBlock block) {
    final source = NoteSourceDocument.withoutMetadata(
      widget.content,
      trim: false,
    );
    final list = MarkdownListLine.parse(block.markdown);
    final prefix = list?.prefix ?? '';
    var body = block.markdown.substring(prefix.length);
    final links = RegExp(
      r'(?:\s*\[Source(?: \d+)?\]\((?:<[^>]+>|[^)]+)\))+$',
    ).firstMatch(body);
    // Citation suffixes are protected from ordinary prose editing.
    final suffix = links?.group(0) ?? '';
    if (links != null) body = body.substring(0, links.start);
    _editGeneration++;
    setState(() {
      _editing = block;
      _before = source.substring(0, block.start);
      _after = source.substring(block.end);
      _original = block.markdown;
      _editPrefix = prefix;
      _editLinks = suffix;
      _editor.value = TextEditingValue(
        text: body,
        selection: TextSelection.collapsed(offset: body.length),
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editing != null) _editorFocus.requestFocus();
    });
  }

  void _emitRaw(String markdown) {
    final metadata = NoteSourceDocument.encode(
      NoteSourceDocument.sources(widget.content),
    );
    _lastEmission =
        '$_before$markdown$_after${metadata.isEmpty ? '' : '\n\n$metadata'}';
    widget.onChanged?.call(_lastEmission!);
  }

  void _emit(String value) => _emitRaw('$_editPrefix$value$_editLinks');
  void _finish({bool cancel = false}) {
    if (_editing == null) return;
    if (cancel) _emitRaw(_original);
    _editGeneration++;
    setState(() => _editing = null);
    _editorFocus.unfocus();
  }

  void _indent(bool outdent) {
    if (MarkdownListLine.parse('$_editPrefix${_editor.text}') != null) {
      setState(() {
        _editPrefix = outdent
            ? _editPrefix.replaceFirst(RegExp(r'^(?: {1,2}|\t)'), '')
            : '  $_editPrefix';
      });
      _emit(_editor.text);
    } else {
      if (outdent) return;
      final selection = _editor.selection;
      if (!selection.isValid) return;
      final text = _editor.text.replaceRange(
        selection.start,
        selection.end,
        outdent ? '' : '  ',
      );
      _editor.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(
          offset: selection.start + (outdent ? 0 : 2),
        ),
      );
      _emit(text);
    }
  }

  Widget _passage(NoteDocumentBlock block, int index) {
    final visible = NoteSourceDocument.visibleMarkdown(block.markdown);
    final originalList = MarkdownListLine.parse(block.markdown);
    final list = MarkdownListLine.parse(visible);
    final body = list?.body ?? visible;
    final urls = _urls(body);
    final editing = _editing?.start == block.start;
    final canEdit = widget.editable && widget.onChanged != null;
    final style = Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.65);
    final emptyMarker = RegExp(r'^\s*[-+*•●◦▪]\s*$').hasMatch(block.markdown);
    if (emptyMarker && !editing) return const SizedBox.shrink();
    Widget content;
    if (editing) {
      content = TextFieldTapRegion(
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                _finish(cancel: true),
            const SingleActivator(LogicalKeyboardKey.enter, control: true):
                _finish,
            const SingleActivator(LogicalKeyboardKey.tab): () => _indent(false),
            const SingleActivator(LogicalKeyboardKey.tab, shift: true): () =>
                _indent(true),
          },
          child: Semantics(
            label: 'Edit this line',
            child: TextField(
              key: const Key('active-passage-editor'),
              controller: _editor,
              focusNode: _editorFocus,
              autofocus: true,
              minLines: 1,
              maxLines: null,
              style: style,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                isCollapsed: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                hintText: 'Write…',
              ),
              onChanged: _emit,
              onSubmitted: (_) => _finish(),
              onTapOutside: (_) => _editorFocus.unfocus(),
            ),
          ),
        ),
      );
    } else {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: canEdit ? () => _edit(block) : null,
        child: MarkdownBody(
          data: body.trim().isEmpty && canEdit ? 'Start writing…' : body,
          builders: {
            'a': _SourceLinkBuilder(
              (url, _) => _inspect(
                urls.isEmpty ? [url] : urls,
                selected: url,
                passage: sourcePlainText(body),
              ),
            ),
          },
          onTapLink: (label, href, title) {
            if (href != null) {
              _inspect(
                urls.isEmpty ? [href] : urls,
                selected: href,
                passage: sourcePlainText(body),
              );
            }
          },
          sizedImageBuilder: (config) => Text(config.alt ?? 'Image'),
          styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
            p: style,
            blockSpacing: 14,
            blockquoteDecoration: const BoxDecoration(
              color: AppColors.codeBackground,
              border: Border(
                left: BorderSide(color: AppColors.dividerBorder, width: 3),
              ),
            ),
            codeblockDecoration: BoxDecoration(
              color: AppColors.codeBackground,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      );
    }
    final indent = originalList?.indent ?? 0;
    if (canEdit && widget.onAddBelow != null) {
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: content),
          IconButton(
            tooltip: 'Add information below this passage',
            visualDensity: VisualDensity.compact,
            onPressed: () => widget.onAddBelow!(block.end),
            icon: const Icon(Icons.add, size: 16),
          ),
        ],
      );
    }
    return MouseRegion(
      onEnter: (_) => _inspect(urls, passage: sourcePlainText(body)),
      onHover: (_) => _inspect(urls, passage: sourcePlainText(body)),
      cursor: canEdit ? SystemMouseCursors.text : MouseCursor.defer,
      child: Listener(
        key: ValueKey('note-passage-$index'),
        behavior: HitTestBehavior.opaque,
        onPointerSignal: urls.isEmpty ? null : _wheel,
        child: Padding(
          padding: EdgeInsets.fromLTRB(indent * 8.0, 6, 0, 6),
          child: list == null
              ? content
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 24,
                      child: Text(
                        RegExp(r'^\d').hasMatch(list.marker)
                            ? list.marker
                            : '•',
                        style: style,
                      ),
                    ),
                    Expanded(child: content),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _inspector() {
    final source = _sources[_sourceIndex];
    return Container(
      key: const Key('saved-note-source-preview'),
      decoration: const BoxDecoration(
        color: AppColors.backgroundStart,
        border: Border(left: BorderSide(color: AppColors.dividerBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Sources · ${_sourceIndex + 1} of ${_sources.length}',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close source',
                  onPressed: () => setState(() => _sources = []),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
          ),
          if (_sources.length > 1)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  for (var i = 0; i < _sources.length; i++)
                    ChoiceChip(
                      label: Text('${i + 1}'),
                      selected: i == _sourceIndex,
                      selectedColor: AppColors.primaryAccent.withValues(
                        alpha: .28,
                      ),
                      backgroundColor: AppColors.surface,
                      onSelected: (_) {
                        setState(() => _sourceIndex = i);
                        if (_sourceScroll.hasClients) _sourceScroll.jumpTo(0);
                      },
                    ),
                ],
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              key: const Key('saved-source-scroll'),
              controller: _sourceScroll,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    source.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    Uri.parse(source.url).host,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 20),
                  SourcePageReader(
                    url: source.url,
                    passage: _passageText,
                    savedExcerpt: source.snippet,
                    loader: widget.sourceLoader,
                  ),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: source.url));
                    },
                    icon: const Icon(Icons.copy_outlined, size: 16),
                    label: const Text('Copy original page link'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : 600.0;
        final source = NoteSourceDocument.withoutMetadata(
          widget.content,
          trim: false,
        );
        // Keep surrounding blocks stable while the active passage changes length.
        var blocks = _editing == null
            ? noteDocumentBlocks(source)
            : [
                ...noteDocumentBlocks(
                  _before,
                ).where((b) => b.markdown.trim().isNotEmpty),
                NoteDocumentBlock(
                  _editing!.start,
                  _editing!.end,
                  '$_editPrefix${_editor.text}$_editLinks',
                ),
                ...noteDocumentBlocks(_after)
                    .where((b) => b.markdown.trim().isNotEmpty)
                    .map(
                      (b) => NoteDocumentBlock(
                        _before.length +
                            _editPrefix.length +
                            _editor.text.length +
                            _editLinks.length +
                            b.start,
                        _before.length +
                            _editPrefix.length +
                            _editor.text.length +
                            _editLinks.length +
                            b.end,
                        b.markdown,
                      ),
                    ),
              ];
        // Keep generated link directories in storage, with a compact reader entry.
        if (_noteSources().isNotEmpty && _editing == null) {
          final directory = blocks.indexWhere(
            (b) => b.markdown.trim() == '## Sources',
          );
          if (directory >= 0 &&
              blocks
                  .skip(directory + 1)
                  .every(
                    (b) => b.markdown
                        .trim()
                        .split('\n')
                        .every(
                          (line) => RegExp(
                            r'^- (?:.+ — )?https?://\S+\s*$',
                          ).hasMatch(line),
                        ),
                  )) {
            blocks = blocks.take(directory).toList();
          }
        }
        final article = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 64),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < blocks.length; i++)
                          _passage(blocks[i], i),
                        if (widget.evidence == null &&
                            _noteSources().isNotEmpty)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              icon: const Icon(Icons.link, size: 16),
                              label: Text(
                                'All note sources (${_noteSources().length})',
                              ),
                              onPressed: () => _inspect(
                                _noteSources().map((c) => c.url).toList(),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
        return SizedBox(
          height: height,
          child: widget.evidence != null || _sources.isEmpty
              ? article
              : constraints.maxWidth >= 850
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: article),
                    SizedBox(width: 300, child: _inspector()),
                  ],
                )
              : Column(
                  children: [
                    if (height >= 420) Expanded(child: article),
                    SizedBox(
                      height: height < 420 ? height : height * .4,
                      child: _inspector(),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _SourceLinkBuilder extends MarkdownElementBuilder {
  final void Function(String, String) inspect;
  _SourceLinkBuilder(this.inspect);
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final href = element.attributes['href'];
    if (href == null) return null;
    final label = element.textContent;
    if (RegExp(
      r'^Source(?: \d+)?$',
      caseSensitive: false,
    ).hasMatch(label.trim())) {
      return const SizedBox.shrink();
    }
    return Text(label, style: preferredStyle);
  }
}
