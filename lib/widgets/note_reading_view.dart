import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:flutter/services.dart';

import '../models/grounded_answer.dart';
import '../services/note_document_blocks.dart';
import '../services/note_source_document.dart';
import '../theme/app_colors.dart';
import 'claim_source_preview.dart';

/// A document and its evidence occupy their own layout bounds, never an overlay.
/// Passage edits are drafts; the notebook's explicit Save remains authoritative.
class NoteReadingView extends StatefulWidget {
  final String content;
  final bool editable;
  final ValueChanged<String>? onChanged;
  const NoteReadingView(
      {super.key,
      required this.content,
      this.editable = false,
      this.onChanged});
  @override
  State<NoteReadingView> createState() => _NoteReadingViewState();
}

class _NoteReadingViewState extends State<NoteReadingView> {
  final _sourceScroll = ScrollController();
  final _editor = TextEditingController();
  List<GroundedAnswerCitation> _sources = [];
  int _sourceIndex = 0;
  NoteDocumentBlock? _editing;
  String _before = '', _after = '', _original = '';
  String? _lastEmission;

  @override
  void dispose() {
    _sourceScroll.dispose();
    _editor.dispose();
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

  void _inspect(List<String> urls, {String? selected}) {
    if (urls.isEmpty) return;
    final saved = {
      for (final c in NoteSourceDocument.sources(widget.content)) c.url: c
    };
    final index = selected == null ? 0 : urls.indexOf(selected);
    if (_sources.map((c) => c.url).join('\n') == urls.join('\n') &&
        selected == null) {
      return;
    }
    setState(() {
      _sources = urls
          .map((url) =>
              saved[url] ??
              GroundedAnswerCitation(
                  id: url, title: Uri.parse(url).host, url: url))
          .toList();
      _sourceIndex = index < 0 ? 0 : index;
    });
    if (_sourceScroll.hasClients) _sourceScroll.jumpTo(0);
  }

  void _wheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        !_sourceScroll.hasClients ||
        _sourceScroll.position.maxScrollExtent <= 0) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      _sourceScroll.jumpTo((_sourceScroll.offset + event.scrollDelta.dy)
          .clamp(0.0, _sourceScroll.position.maxScrollExtent)
          .toDouble());
    });
  }

  void _edit(NoteDocumentBlock block) {
    final source = NoteSourceDocument.withoutMetadata(widget.content);
    setState(() {
      _editing = block;
      _before = source.substring(0, block.start);
      _after = source.substring(block.end);
      _original = block.markdown;
      _editor.text = block.markdown;
    });
  }

  void _emit(String value) {
    final metadata =
        NoteSourceDocument.encode(NoteSourceDocument.sources(widget.content));
    _lastEmission =
        '$_before$value$_after${metadata.isEmpty ? '' : '\n\n$metadata'}';
    widget.onChanged?.call(_lastEmission!);
  }

  Widget _passage(NoteDocumentBlock block, int index) {
    final urls = _urls(block.markdown);
    final editing = _editing?.start == block.start;
    if (editing) {
      return Container(
        key: const Key('active-passage-editor'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: AppColors.backgroundStart,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primaryAccent)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
              controller: _editor,
              autofocus: true,
              minLines: 2,
              maxLines: null,
              decoration: const InputDecoration(
                  border: InputBorder.none, hintText: 'Write this passage…'),
              onChanged: _emit),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(
                onPressed: () {
                  _emit(_original);
                  setState(() => _editing = null);
                },
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => setState(() => _editing = null),
                child: const Text('Done')),
          ])
        ]),
      );
    }
    return MouseRegion(
      onEnter: (_) => _inspect(urls),
      cursor: widget.editable ? SystemMouseCursors.text : MouseCursor.defer,
      child: Listener(
        key: ValueKey('note-passage-$index'),
        behavior: HitTestBehavior.opaque,
        onPointerSignal: urls.isEmpty ? null : _wheel,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: widget.editable ? () => _edit(block) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: MarkdownBody(
              data: block.markdown.trim().isEmpty && widget.editable
                  ? 'Start writing…'
                  : NoteSourceDocument.visibleMarkdown(block.markdown),
              builders: {
                'a': _SourceLinkBuilder((url, _) =>
                    _inspect(urls.isEmpty ? [url] : urls, selected: url))
              },
              onTapLink: (label, href, title) {
                if (href != null) {
                  _inspect(urls.isEmpty ? [href] : urls, selected: href);
                }
              },
              sizedImageBuilder: (config) => Text(config.alt ?? 'Image'),
              styleSheet:
                  MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                p: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(height: 1.65),
                blockSpacing: 14,
                codeblockDecoration: BoxDecoration(
                    color: AppColors.codeBackground,
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
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
          border: Border(left: BorderSide(color: AppColors.dividerBorder))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
            child: Row(children: [
              Expanded(
                  child: Text(
                      'Sources · ${_sourceIndex + 1} of ${_sources.length}',
                      style: Theme.of(context).textTheme.labelLarge)),
              IconButton(
                  tooltip: 'Close source',
                  onPressed: () => setState(() => _sources = []),
                  icon: const Icon(Icons.close, size: 18)),
            ])),
        if (_sources.length > 1)
          SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                for (var i = 0; i < _sources.length; i++)
                  ChoiceChip(
                      label: Text('${i + 1}'),
                      selected: i == _sourceIndex,
                      onSelected: (_) {
                        setState(() => _sourceIndex = i);
                        if (_sourceScroll.hasClients) _sourceScroll.jumpTo(0);
                      }),
              ])),
        Expanded(
            child: SingleChildScrollView(
                key: const Key('saved-source-scroll'),
                controller: _sourceScroll,
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(source.title,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(Uri.parse(source.url).host,
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 20),
                      ClaimFormattedText(
                          data: source.snippet?.trim().isNotEmpty == true
                              ? source.snippet!
                              : 'No excerpt was saved with this source; open the page to read it.'),
                      const SizedBox(height: 16),
                      TextButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                                ClipboardData(text: source.url));
                          },
                          icon: const Icon(Icons.copy_outlined, size: 16),
                          label: const Text('Copy original page link')),
                      const Text('Saved excerpt · no live page is loaded.'),
                    ]))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final height =
          constraints.hasBoundedHeight ? constraints.maxHeight : 600.0;
      final source = NoteSourceDocument.withoutMetadata(widget.content);
      // Keep surrounding blocks stable while the active passage changes length.
      var blocks = _editing == null
          ? noteDocumentBlocks(source)
          : [
              ...noteDocumentBlocks(_before)
                  .where((b) => b.markdown.trim().isNotEmpty),
              NoteDocumentBlock(_editing!.start, _editing!.end, _editor.text),
              ...noteDocumentBlocks(_after)
                  .where((b) => b.markdown.trim().isNotEmpty)
                  .map((b) => NoteDocumentBlock(
                      _before.length + _editor.text.length + b.start,
                      _before.length + _editor.text.length + b.end,
                      b.markdown)),
            ];
      // Keep generated link directories in storage, with a compact reader entry.
      if (NoteSourceDocument.sources(widget.content).isNotEmpty &&
          _editing == null) {
        final directory =
            blocks.indexWhere((b) => b.markdown.trim() == '## Sources');
        if (directory >= 0 &&
            blocks.skip(directory + 1).every((b) => b.markdown
                .trim()
                .split('\n')
                .every((line) =>
                    RegExp(r'^- .+ — https?://\S+\s*$').hasMatch(line)))) {
          blocks = blocks.take(directory).toList();
        }
      }
      final article =
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.editable)
          Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Text(
                  'Click a passage to edit it. Save when you’re finished.',
                  style: Theme.of(context).textTheme.bodySmall)),
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
                              if (NoteSourceDocument.sources(widget.content)
                                  .isNotEmpty)
                                Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton.icon(
                                        icon: const Icon(Icons.link, size: 16),
                                        label: Text(
                                            'All note sources (${NoteSourceDocument.sources(widget.content).length})'),
                                        onPressed: () => _inspect(
                                            NoteSourceDocument.sources(
                                                    widget.content)
                                                .map((c) => c.url)
                                                .toList()))),
                            ]))))),
      ]);
      return SizedBox(
          height: height,
          child: _sources.isEmpty
              ? article
              : constraints.maxWidth >= 850
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                          Expanded(child: article),
                          SizedBox(width: 300, child: _inspector())
                        ])
                  : Column(children: [
                      if (height >= 420) Expanded(child: article),
                      SizedBox(
                          height: height < 420 ? height : height * .4,
                          child: _inspector())
                    ]));
    });
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
    return MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => inspect(href, label),
        child: InkWell(
            onTap: () => inspect(href, label),
            child: Text(label,
                style: (preferredStyle ?? const TextStyle()).copyWith(
                    color: AppColors.primaryAction,
                    decoration: TextDecoration.underline))));
  }
}
