import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../services/source_page_loader.dart';
import '../services/source_image_loader.dart';
import '../theme/app_colors.dart';
import 'source_figure.dart';
import 'reading_markdown_style.dart';

/// A single article card: provenance, cited words, figures, optional context.
class SourcePageReader extends StatefulWidget {
  final String url;
  final String passage;
  final String? savedExcerpt;
  final String? sourceTitle;
  final SourcePageLoader? loader;
  final SourceImageLoader? imageLoader;
  final bool compact;
  const SourcePageReader({
    super.key,
    required this.url,
    required this.passage,
    this.savedExcerpt,
    this.sourceTitle,
    this.loader,
    this.imageLoader,
    this.compact = false,
  });
  @override
  State<SourcePageReader> createState() => _SourcePageReaderState();
}

class _SourcePageReaderState extends State<SourcePageReader> {
  SourcePage? _page;
  bool _loading = false;
  bool _failed = false;
  bool _expandedQuote = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(SourcePageReader old) {
    super.didUpdateWidget(old);
    if (old.savedExcerpt != widget.savedExcerpt || old.url != widget.url) {
      _expandedQuote = false;
    }
    if (old.url != widget.url || old.loader != widget.loader) {
      _page = null;
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    _loading = true;
    _failed = false;
    try {
      final page = await (widget.loader ?? HttpSourcePageLoader.shared).load(
        widget.url,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _page = page;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  Widget _markdown(String text) => MarkdownBody(
    data: text,
    selectable: true,
    sizedImageBuilder: (config) => Text(config.alt ?? 'Image'),
    styleSheet: readingMarkdownStyle(context, compact: true),
  );

  Widget _pageParagraph(SourcePageSection section) => Container(
    key: const Key('page-passage-highlight'),
    padding: const EdgeInsets.all(10),
    color: AppColors.primaryAccent.withValues(alpha: .08),
    child: _markdown(section.markdown),
  );

  @override
  Widget build(BuildContext context) {
    final page = _page;
    final excerpt = widget.savedExcerpt?.trim();
    final hasQuote = excerpt?.isNotEmpty == true;
    final exact = hasQuote ? page?.excerptIndex(excerpt!) : null;
    final index = exact ?? page?.candidateIndex(widget.passage);
    final host = Uri.tryParse(widget.url)?.host ?? widget.url;
    final supplied = widget.sourceTitle?.trim();
    final title =
        page?.title ??
        (supplied != null && supplied.isNotEmpty && !supplied.startsWith('http')
            ? supplied
            : host);
    final longQuote = (excerpt?.length ?? 0) > 500;
    final figures = page == null
        ? <SourcePageImage>[]
        : index == null
        ? page.images.take(1).toList()
        : page.imagesNear(index);
    final quote = hasQuote ? _markdown(excerpt!) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.compact)
          Tooltip(
            message: widget.url,
            child: Text(
              host.replaceFirst(RegExp(r'^www\.'), ''),
              key: const Key('source-domain'),
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: AppColors.primaryAccent),
            ),
          ),
        SizedBox(height: widget.compact ? 0 : 6),
        Text(
          title,
          key: const Key('source-article-title'),
          maxLines: widget.compact ? 1 : 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: widget.compact ? 14 : 19,
            fontWeight: FontWeight.w600,
            height: 1.3,
            letterSpacing: -.3,
          ),
        ),
        SizedBox(height: widget.compact ? 6 : 16),
        if (hasQuote) ...[
          Text(
            'Provider-cited excerpt',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 8),
          Container(
            key: const Key('provider-cited-excerpt'),
            padding: const EdgeInsets.fromLTRB(12, 4, 0, 4),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: AppColors.primaryAccent.withValues(alpha: .5),
                  width: 2,
                ),
              ),
            ),
            child: longQuote && !_expandedQuote
                ? LimitedBox(
                    maxHeight: widget.compact ? 90 : 160,
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: quote,
                    ),
                  )
                : quote,
          ),
          if (longQuote)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () =>
                    setState(() => _expandedQuote = !_expandedQuote),
                child: Text(_expandedQuote ? 'Less excerpt' : 'Full excerpt'),
              ),
            ),
          if (page != null && !widget.compact) ...[
            const SizedBox(height: 8),
            Text(
              exact != null
                  ? 'Cited text located in this page'
                  : 'Cited text was not located in the fetched page',
              key: const Key('excerpt-location-status'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ] else ...[
          const Text(
            'No exact excerpt was supplied for this passage.',
            key: Key('missing-cited-excerpt'),
          ),
        ],
        if (_loading)
          const LinearProgressIndicator(
            key: Key('source-page-loading'),
            minHeight: 1,
          ),
        if (_failed) ...[
          const SizedBox(height: 8),
          const Text(
            'The page could not be fetched; any cited excerpt above is retained.',
            key: Key('source-page-error'),
          ),
          TextButton(
            onPressed: () {
              _load();
              setState(() {});
            },
            child: const Text('Retry source page'),
          ),
        ],
        if (!widget.compact && page != null) ...[
          if (index == null)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'No matching passage found on this page.',
                key: Key('no-page-match'),
              ),
            ),
          // Figures remain accessible even when an exact cited quote cannot be found.
          for (final figure in figures) ...[
            const SizedBox(height: 16),
            SourceFigure(figure: figure, loader: widget.imageLoader),
          ],
          if (index != null && !hasQuote) ...[
            const SizedBox(height: 12),
            Text(
              'Related page text · not verified evidence',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            Container(
              key: const Key('source-page-quote'),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _markdown(page.sections[index].markdown),
            ),
          ],
          const SizedBox(height: 8),
          ExpansionTile(
            key: ValueKey('article-context-${widget.url}-${widget.passage}'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 12),
            title: const Text(
              'Read article context',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            subtitle: const Text(
              'Reader view · original site styling omitted',
              style: TextStyle(fontSize: 11),
            ),
            children: [
              if (index != null && hasQuote)
                Container(
                  key: const Key('source-page-quote'),
                  padding: const EdgeInsets.only(bottom: 12),
                  child: exact == null
                      ? _markdown(page.sections[index].markdown)
                      : _pageParagraph(page.sections[index]),
                ),
              _markdown(
                page.sections
                    .skip(index == null ? 0 : index + 1)
                    .take(10)
                    .map((s) => s.markdown)
                    .join('\n\n'),
              ),
            ],
          ),
        ],
        if (hasQuote && !widget.compact)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => Clipboard.setData(
                ClipboardData(
                  text:
                      '${Uri.parse(widget.url).removeFragment()}#:~:text=${Uri.encodeComponent(sourceTextKey(excerpt!))}',
                ),
              ),
              icon: const Icon(Icons.link, size: 14),
              label: const Text(
                'Copy link to cited text',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }
}
