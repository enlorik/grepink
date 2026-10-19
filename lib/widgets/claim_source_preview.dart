import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/claim_review_item.dart';
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
    return '${uri.removeFragment()}#$anchor:~:text=${Uri.encodeComponent(excerpt!)}';
  }
}

String sourceExcerpt(String text) {
  final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final sentences = compact.split(RegExp(r'(?<=[.!?])\s+')).take(2).join(' ');
  return sentences.length <= 360
      ? sentences
      : '${sentences.substring(0, 357)}...';
}

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
    var title =
        i < item.citationTitles.length ? item.citationTitles[i].trim() : '';
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

/// A modeless reading companion; no remote page is loaded just by hovering.
class ClaimSourcePreviewPane extends StatelessWidget {
  final ClaimReviewItem? item;
  final List<GroundedAnswerCitation> citations;
  final VoidCallback onClose;

  const ClaimSourcePreviewPane({
    super.key,
    required this.item,
    required this.citations,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final sources = item == null
        ? <ClaimSourcePreview>[]
        : claimSourcePreviews(item!, citations);
    return Material(
      key: const Key('source-preview-pane'),
      elevation: 12,
      borderRadius: BorderRadius.circular(16),
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
              Text(item!.text, maxLines: 3, overflow: TextOverflow.ellipsis),
              const Divider(),
              if (sources.isEmpty)
                const Text('No source was supplied for this claim.'),
              for (var i = 0; i < sources.length; i++) ...[
                Text(
                  sources[i].title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(Uri.tryParse(sources[i].url)?.host ?? 'Source'),
                const SizedBox(height: 4),
                SelectableText(
                  sources[i].excerpt ??
                      'The provider did not supply a source excerpt.',
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
              'Source excerpts, not a live webpage; highlighting depends on your browser and matching page text.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
