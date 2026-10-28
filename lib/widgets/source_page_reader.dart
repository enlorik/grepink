import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../services/source_page_loader.dart';
import '../theme/app_colors.dart';

/// Shared by saved notes and generated answers. Source context is matched locally.
class SourcePageReader extends StatefulWidget {
  final String url;
  final String passage;
  final String? savedExcerpt;
  final SourcePageLoader? loader;
  const SourcePageReader({
    super.key,
    required this.url,
    required this.passage,
    this.savedExcerpt,
    this.loader,
  });
  @override
  State<SourcePageReader> createState() => _SourcePageReaderState();
}

class _SourcePageReaderState extends State<SourcePageReader> {
  SourcePage? _page;
  bool _loading = false;
  String? _error;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    if (widget.savedExcerpt?.trim().isNotEmpty != true) _load();
  }

  @override
  void didUpdateWidget(SourcePageReader old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _generation++;
      _page = null;
      _error = null;
      _loading = false;
      if (widget.savedExcerpt?.trim().isNotEmpty != true) _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    // initState and didUpdateWidget are already followed by a build.
    _loading = true;
    _error = null;
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
        _loading = false;
        _error =
            'This website could not be loaded; retry or copy its page link.';
      });
    }
  }

  Widget _markdown(String text) => MarkdownBody(
    data: text,
    selectable: true,
    sizedImageBuilder: (config) => Text(config.alt ?? 'Image'),
    styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.6),
      blockquoteDecoration: const BoxDecoration(
        color: AppColors.codeBackground,
        border: Border(
          left: BorderSide(color: AppColors.primaryAccent, width: 3),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final page = _page;
    final index = page?.relevantIndex(
      widget.passage,
      anchor: Uri.tryParse(widget.url)?.fragment,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.savedExcerpt?.trim().isNotEmpty == true) ...[
          _markdown(widget.savedExcerpt!),
          const SizedBox(height: 12),
        ],
        if (_loading)
          const Text('Loading source page…', key: Key('source-page-loading')),
        if (_error != null) ...[
          Text(_error!, key: const Key('source-page-error')),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () {
                setState(() {});
                _load();
              },
              child: const Text('Retry source page'),
            ),
          ),
        ],
        if (page != null && index != null) ...[
          Text(page.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Text(
            'Relevant passage from the page',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 6),
          Container(
            key: const Key('source-page-quote'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryAccent.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              page.sections[index].text.substring(
                0,
                page.sections[index].text.length.clamp(0, 1200),
              ),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.6),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.link, size: 16),
              label: const Text('Copy link to this passage'),
              onPressed: () async {
                final uri = Uri.parse(widget.url);
                final anchor = uri.fragment.split(':~:').first;
                final text = page.sections[index].text;
                final quote = text.substring(0, text.length.clamp(0, 240));
                await Clipboard.setData(
                  ClipboardData(
                    text:
                        '${uri.removeFragment()}#$anchor:~:text=${Uri.encodeComponent(quote)}',
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          _markdown(page.contextAt(index)),
          const SizedBox(height: 12),
          Text(
            'Website reader · scripts and images are omitted',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (page == null &&
            !_loading &&
            _error == null &&
            widget.savedExcerpt?.trim().isNotEmpty == true)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () {
                _load();
                setState(() {});
              },
              child: const Text('Read original page'),
            ),
          ),
      ],
    );
  }
}
