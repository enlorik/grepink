import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:flutter/services.dart';

import '../models/grounded_answer.dart';
import '../services/note_source_document.dart';
import '../theme/app_colors.dart';
import 'claim_source_preview.dart';

/// Rendering and source inspection are shared by the notebook and editor.
/// Hovering never fetches a remote page; copying its link is an explicit act.
class NoteReadingView extends StatefulWidget {
  final String content;
  const NoteReadingView({super.key, required this.content});
  @override
  State<NoteReadingView> createState() => _NoteReadingViewState();
}

class _NoteReadingViewState extends State<NoteReadingView> {
  GroundedAnswerCitation? _source;
  final _preview = OverlayPortalController();

  @override
  void didUpdateWidget(NoteReadingView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content) _source = null;
  }

  void _inspect(String url, String label) {
    final uri = Uri.tryParse(url);
    if (uri == null || !['https', 'http'].contains(uri.scheme)) return;
    final sources = NoteSourceDocument.sources(widget.content);
    final found = sources.where((c) => c.url == url);
    setState(() => _source = found.isEmpty
        ? GroundedAnswerCitation(id: url, title: label, url: url)
        : found.first);
    _preview.show();
  }

  @override
  Widget build(BuildContext context) {
    final source = _source;
    return OverlayPortal(
      controller: _preview,
      overlayChildBuilder: (context) => source == null
          ? const SizedBox.shrink()
          : Positioned(
              right: 20,
              bottom: 90,
              width: (MediaQuery.sizeOf(context).width - 40)
                  .clamp(0, 380)
                  .toDouble(),
              child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(12),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * 0.55),
                    child: SingleChildScrollView(
                        child: Container(
                      key: const Key('saved-note-source-preview'),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        border: Border.all(color: AppColors.dividerBorder),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(
                                  child: Text(source.title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium)),
                              IconButton(
                                  tooltip: 'Close source',
                                  onPressed: _preview.hide,
                                  icon: const Icon(Icons.close)),
                            ]),
                            Text(Uri.parse(source.url).host),
                            const SizedBox(height: 8),
                            ClaimFormattedText(
                                data: source.snippet?.trim().isNotEmpty == true
                                    ? source.snippet!
                                    : 'No excerpt was saved with this source; open the page to read it.'),
                            TextButton.icon(
                              onPressed: () async {
                                final messenger =
                                    ScaffoldMessenger.maybeOf(context);
                                await Clipboard.setData(
                                    ClipboardData(text: source.url));
                                if (!context.mounted) return;
                                messenger?.showSnackBar(const SnackBar(
                                    content: Text(
                                        'Source link copied; paste it into your browser.')));
                              },
                              icon: const Icon(Icons.open_in_new, size: 16),
                              label: const Text('Copy original page link'),
                            ),
                            const Text(
                                'Saved source excerpt; no live page is loaded.'),
                          ]),
                    )),
                  )),
            ),
      child: MarkdownBody(
        data: NoteSourceDocument.visibleMarkdown(widget.content),
        builders: {'a': _SourceLinkBuilder(_inspect)},
        onTapLink: (label, href, title) {
          if (href != null) _inspect(href, label);
        },
        sizedImageBuilder: (config) => Text(config.alt ?? 'Image'),
        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
          p: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.65),
          blockSpacing: 16,
        ),
      ),
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
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => inspect(href, label),
      child: InkWell(
        onTap: () => inspect(href, label),
        child: Text(label,
            style: (preferredStyle ?? const TextStyle()).copyWith(
                color: AppColors.deepAction,
                decoration: TextDecoration.underline)),
      ),
    );
  }
}
