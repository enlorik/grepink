import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../services/source_page_loader.dart';
import '../services/source_image_loader.dart';
import '../theme/app_colors.dart';
import 'source_figure.dart';

/// Cited excerpts are kept distinct from locally matched page context.
class SourcePageReader extends StatefulWidget {
  final String url;
  final String passage;
  final String? savedExcerpt;
  final SourcePageLoader? loader;
  final SourceImageLoader? imageLoader;
  final bool compact;
  const SourcePageReader({
    super.key,
    required this.url,
    required this.passage,
    this.savedExcerpt,
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
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(SourcePageReader old) {
    super.didUpdateWidget(old);
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
    styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.6),
    ),
  );

  Widget _pageParagraph(String text, String? quote) {
    final clean = quote == null ? '' : sourceTextKey(quote);
    final at = clean.isEmpty ? -1 : text.toLowerCase().indexOf(clean);
    if (at < 0) {
      return SelectableText(
        text,
        key: const Key('page-passage'),
        style: const TextStyle(height: 1.6),
      );
    }
    return SelectableText.rich(
      TextSpan(
        children: [
          TextSpan(text: text.substring(0, at)),
          TextSpan(
            text: text.substring(at, at + clean.length),
            style: TextStyle(
              backgroundColor: AppColors.primaryAccent.withValues(alpha: .25),
            ),
          ),
          TextSpan(text: text.substring(at + clean.length)),
        ],
      ),
      key: const Key('page-passage-highlight'),
      style: const TextStyle(height: 1.6),
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    final excerpt = widget.savedExcerpt?.trim();
    final hasQuote = excerpt?.isNotEmpty == true;
    final exact = hasQuote ? page?.excerptIndex(excerpt!) : null;
    final index = exact ?? page?.candidateIndex(widget.passage);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasQuote) ...[
          Text(
            'Provider-cited excerpt',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          Container(
            key: const Key('provider-cited-excerpt'),
            padding: EdgeInsets.all(widget.compact ? 8 : 12),
            decoration: BoxDecoration(
              color: AppColors.primaryAccent.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: _markdown(excerpt!),
          ),
          const SizedBox(height: 8),
          if (page != null && !widget.compact)
            Text(
              exact != null
                  ? 'Cited text located in this page'
                  : 'Cited text was not located in the fetched page',
              key: const Key('excerpt-location-status'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (!widget.compact)
            TextButton.icon(
              onPressed: () => Clipboard.setData(
                ClipboardData(
                  text:
                      '${Uri.parse(widget.url).removeFragment()}#:~:text=${Uri.encodeComponent(sourceTextKey(excerpt))}',
                ),
              ),
              icon: const Icon(Icons.link, size: 16),
              label: const Text('Copy link to cited text'),
            ),
        ] else ...[
          const Text(
            'No exact excerpt was supplied for this passage.',
            key: Key('missing-cited-excerpt'),
          ),
          const SizedBox(height: 8),
        ],
        if (_loading)
          const Text('Loading source page…', key: Key('source-page-loading')),
        if (_failed) ...[
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
        if (page != null && index == null) ...[
          const Text(
            'No matching passage found on this page.',
            key: Key('no-page-match'),
          ),
          const SizedBox(height: 12),
        ],
        if (page != null && index != null && !widget.compact) ...[
          const SizedBox(height: 16),
          Text(page.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Text(
            exact != null
                ? 'Cited passage in context'
                : 'Related page text · not verified evidence',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          // Keep the quote's precise paragraph visible, not the first page section.
          Container(
            key: const Key('source-page-quote'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.dividerBorder),
              borderRadius: BorderRadius.circular(8),
            ),
            child: _pageParagraph(
              page.sections[index].text,
              exact == null ? null : excerpt,
            ),
          ),
          const SizedBox(height: 16),
          for (final figure in page.imagesNear(index))
            SourceFigure(figure: figure, loader: widget.imageLoader),
          _markdown(
            page.sections
                .skip(index + 1)
                .take(4)
                .map((s) => s.markdown)
                .join('\n\n'),
          ),
          const SizedBox(height: 12),
          Text(
            'Article text and figures · scripts and original styling omitted',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}
