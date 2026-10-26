import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../models/claim_review_item.dart';
import '../theme/app_colors.dart';
import '../services/source_page_loader.dart';
import 'source_page_reader.dart';
import '../models/grounded_answer.dart';

/// Presentation metadata only: the original citation lists remain untouched.
class ClaimSourcePreview {
  final String url;
  final String title;
  final String? excerpt;

  const ClaimSourcePreview(this.url, this.title, this.excerpt);

  String get pageLink {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        excerpt == null) {
      return url;
    }
    // Only provider-supplied source text is used for browser highlighting.
    final anchor = uri.fragment.split(':~:').first;
    return '${uri.removeFragment()}#$anchor:~:text=${Uri.encodeComponent(sourcePlainText(excerpt!))}';
  }
}

/// Render provider Markdown without fetching images or opening embedded links.
/// Claims remain non-selectable so the enclosing checkbox owns its tap target.
class ClaimFormattedText extends StatelessWidget {
  final String data;
  final bool selectable;
  final TextStyle? style;

  const ClaimFormattedText({
    super.key,
    required this.data,
    this.selectable = false,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    if (!RegExp(
      r'[*_`#>~\[\]\n|]|^\s*(?:[-+]\s|\d+[.)]\s|---+\s*$)',
    ).hasMatch(data)) {
      return selectable
          ? SelectableText(data, style: style)
          : Text(data, style: style);
    }
    final body = MarkdownBody(
      data: data,
      selectable: selectable,
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: (style ?? Theme.of(context).textTheme.bodyMedium)?.copyWith(
          height: 1.5,
        ),
        blockSpacing: 8,
        blockquoteDecoration: const BoxDecoration(
          color: AppColors.codeBackground,
          border: Border(
            left: BorderSide(color: AppColors.dividerBorder, width: 3),
          ),
        ),
      ),
      sizedImageBuilder: (config) => Text(config.alt ?? 'Image'),
    );
    if (selectable) return body;
    // Markdown links create recognizers even without an onTapLink callback.
    // Keep one accessible checkbox label and let its tile own every claim tap.
    return Semantics(
      label: sourcePlainText(data),
      excludeSemantics: true,
      child: AbsorbPointer(child: body),
    );
  }
}

/// Plain prose keeps its short preview; structured excerpts retain line breaks.
String sourceExcerpt(String text) {
  final normalized = text.replaceAll('\r\n', '\n').trim();
  if (normalized.contains('\n')) {
    if (normalized.length <= 1600) return normalized;
    final boundary = normalized.lastIndexOf('\n', 1600);
    var clipped = normalized.substring(0, boundary > 0 ? boundary : 1600);
    // Keep a truncated fenced code block from swallowing the ellipsis.
    if (RegExp(r'^```', multiLine: true).allMatches(clipped).length.isOdd) {
      clipped += '\n```';
    }
    if (RegExp(r'^~~~', multiLine: true).allMatches(clipped).length.isOdd) {
      clipped += '\n~~~';
    }
    return '$clipped\n\n…';
  }
  final compact = normalized.replaceAll(RegExp(r'\s+'), ' ');
  final sentences = compact.split(RegExp(r'(?<=[.!?])\s+')).take(2).join(' ');
  return sentences.length <= 360
      ? sentences
      : '${sentences.substring(0, 357)}...';
}

/// Browser text fragments match visible page words, not Markdown delimiters.
String sourcePlainText(String text) => text
    .replaceAllMapped(RegExp(r'!?\[([^\]]+)\]\([^)]*\)'), (m) => m[1]!)
    .replaceAll(
      RegExp(
        r'^\s{0,3}(?:#{1,6}\s+|>\s*|[-+*]\s+|\d+[.)]\s+)',
        multiLine: true,
      ),
      '',
    )
    .replaceAll(RegExp(r'^\s*(?:```|~~~).*$', multiLine: true), '')
    .replaceAll(RegExp(r'[*_`~]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

List<ClaimSourcePreview> claimSourcePreviews(
  ClaimReviewItem item,
  List<GroundedAnswerCitation> citations,
) {
  final seen = <String>{};
  final result = <ClaimSourcePreview>[];
  for (var i = 0; i < item.citationUrls.length; i++) {
    final url = item.citationUrls[i].trim();
    if (url.isEmpty || !seen.add(url)) continue;
    final matching = citations.where((c) => c.url.trim() == url);
    var title = i < item.citationTitles.length
        ? item.citationTitles[i].trim()
        : '';
    String? excerpt;
    for (final citation in matching) {
      if ((title.isEmpty || title == url) && citation.title.trim().isNotEmpty) {
        title = citation.title.trim();
      }
      if (excerpt == null && (citation.snippet?.trim().isNotEmpty ?? false)) {
        excerpt = sourceExcerpt(citation.snippet!);
      }
    }
    if (title.isEmpty || title == url) {
      title = Uri.tryParse(url)?.host ?? '';
      if (title.isEmpty) title = 'Source ${result.length + 1}';
    }
    result.add(ClaimSourcePreview(url, title, excerpt));
  }
  return result;
}

/// A modeless reading companion that loads missing source excerpts on hover.
class ClaimSourcePreviewPane extends StatelessWidget {
  final ClaimReviewItem? item;
  final List<GroundedAnswerCitation> citations;
  final VoidCallback onClose;
  final bool docked;
  final SourcePageLoader? sourceLoader;

  const ClaimSourcePreviewPane({
    super.key,
    required this.item,
    required this.citations,
    required this.onClose,
    this.docked = false,
    this.sourceLoader,
  });

  @override
  Widget build(BuildContext context) {
    final sources = item == null
        ? <ClaimSourcePreview>[]
        : claimSourcePreviews(item!, citations);
    return Material(
      key: const Key('source-preview-pane'),
      elevation: docked ? 0 : 8,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Source preview',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: 'Close source preview',
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Text('Follows the claim you hover, focus, or tap.'),
            const SizedBox(height: 12),
            if (item == null)
              const Text('Hover a claim or tap its Sources button.'),
            if (item != null) ...[
              ClaimFormattedText(data: item!.text, selectable: true),
              const Divider(),
              if (sources.isEmpty)
                const Text('No source was supplied for this claim.'),
              for (var i = 0; i < sources.length; i++) ...[
                Text(
                  sources[i].title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (sources[i].title != Uri.tryParse(sources[i].url)?.host)
                  Text(Uri.tryParse(sources[i].url)?.host ?? 'Source'),
                const SizedBox(height: 4),
                SourcePageReader(
                  url: sources[i].url,
                  passage: item!.text,
                  savedExcerpt: sources[i].excerpt,
                  loader: sourceLoader,
                ),
                TextButton.icon(
                  key: Key('copy-source-link-$i'),
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: sources[i].pageLink),
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Page link copied. Paste it into your browser; matching text may be highlighted.',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: Text(
                    sources[i].excerpt == null
                        ? 'Copy page link'
                        : 'Copy highlighted page link',
                  ),
                ),
                const Divider(),
              ],
            ],
            const Text(
              'Website reader; scripts and images are omitted. Saved excerpts remain available offline.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
