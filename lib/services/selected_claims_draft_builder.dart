import '../models/claim_deduplication_result.dart';
import '../models/claim_review_item.dart';
import '../models/grounded_answer.dart';

class ClaimDraftResult {
  final String markdownContent;
  final int sourceCount;
  final bool shouldSave;

  const ClaimDraftResult({
    required this.markdownContent,
    required this.sourceCount,
    required this.shouldSave,
  });

  static const empty = ClaimDraftResult(
    markdownContent: '',
    sourceCount: 0,
    shouldSave: false,
  );
}

class SelectedClaimsDraftBuilder {
  const SelectedClaimsDraftBuilder();

  /// Builds a markdown draft from [selected] ClaimReviewItems.
  ///
  /// Only items where [ClaimReviewItem.canBeSaved] is true are included.
  /// AlreadyKnown items are never included even if selected.
  /// Returns [ClaimDraftResult.empty] when no saveable items are selected.
  /// Never includes API keys, raw provider credentials, or full answer text.
  ClaimDraftResult build({
    required String question,
    required List<ClaimReviewItem> selected,
    required String providerName,
    required List<GroundedAnswerCitation> citations,
  }) {
    final saveable = selected
        .where((item) =>
            item.canBeSaved &&
            item.classification != ClaimNoveltyClassification.alreadyKnown)
        .toList();

    if (saveable.isEmpty) return ClaimDraftResult.empty;

    final newItems = saveable
        .where((i) => i.classification == ClaimNoveltyClassification.newClaim)
        .toList();
    final betterItems = saveable
        .where((i) => i.classification == ClaimNoveltyClassification.betterSource)
        .toList();
    final contradictionItems = saveable
        .where((i) => i.classification == ClaimNoveltyClassification.contradiction)
        .toList();

    // Titles are resolved primarily from the provider-level citations list,
    // falling back to each claim's own citationTitles for URLs the provider
    // list doesn't cover (e.g. a claim-level source not echoed back in the
    // top-level answer citations).
    final titleByUrl = <String, String>{
      for (final c in citations)
        if (c.title.isNotEmpty) c.url: c.title,
    };
    // Collect all URL references used in saveable items for deduplication.
    final usedUrls = <String>{};
    for (final item in saveable) {
      usedUrls.addAll(item.citationUrls);
      for (var i = 0; i < item.citationUrls.length; i++) {
        final url = item.citationUrls[i];
        final itemTitle = i < item.citationTitles.length ? item.citationTitles[i] : '';
        if (itemTitle.isNotEmpty) {
          titleByUrl.putIfAbsent(url, () => itemTitle);
        }
      }
    }

    final buf = StringBuffer();

    // Title
    final title = question.trim().isEmpty ? 'Research notes' : question;
    buf.writeln('# $title');
    buf.writeln();

    if (newItems.isNotEmpty) {
      buf.writeln('## New knowledge');
      buf.writeln();
      for (final item in newItems) {
        buf.write('- ${item.text}');
        if (item.citationUrls.isNotEmpty) {
          buf.write(' [Source](${item.citationUrls.first})');
        }
        buf.writeln();
      }
      buf.writeln();
    }

    if (betterItems.isNotEmpty) {
      buf.writeln('## Better sources');
      buf.writeln();
      for (final item in betterItems) {
        buf.write('- ${item.text}');
        if (item.citationUrls.isNotEmpty) {
          buf.write(' [Source](${item.citationUrls.first})');
        }
        buf.writeln();
      }
      buf.writeln();
    }

    if (contradictionItems.isNotEmpty) {
      buf.writeln('## Possible contradictions to review');
      buf.writeln();
      for (final item in contradictionItems) {
        buf.write('- ${item.text}');
        if (item.citationUrls.isNotEmpty) {
          buf.write(' [Source](${item.citationUrls.first})');
        }
        buf.writeln();
      }
      buf.writeln();
    }

    // Sources section — deduplicated
    if (usedUrls.isNotEmpty) {
      buf.writeln('## Sources');
      buf.writeln();
      for (final url in usedUrls) {
        final label = titleByUrl[url] ?? url;
        buf.writeln('- $label — $url');
      }
    }

    return ClaimDraftResult(
      markdownContent: buf.toString().trimRight(),
      sourceCount: usedUrls.length,
      shouldSave: true,
    );
  }
}
