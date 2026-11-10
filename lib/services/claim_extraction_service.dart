import '../models/extracted_claim.dart';
import '../models/grounded_answer.dart';

abstract class ClaimExtractionService {
  /// Splits [answer] into individual [ExtractedClaim] units.
  ///
  /// Returns an empty list when the answer is empty.
  /// Never mutates [answer].
  List<ExtractedClaim> extract(GroundedAnswer answer);
}

/// Sentence-based claim extractor that splits on sentence boundaries.
///
/// When citations have character offsets (startIndex/endIndex), only citations
/// overlapping the sentence's character range are attached to that claim and
/// [ExtractedClaim.citationUncertain] is false. When no overlapping citation is
/// found, inline citation placement is used; otherwise only unattributed answer
/// links are retained without excerpts and
/// [citationUncertain] is true.
///
/// Known limitation: the sentence splitter will incorrectly fragment
/// abbreviations like "Dr.", "U.S.", "e.g." that contain internal periods
/// followed by whitespace. This is a known trade-off of a rule-based approach.
class RuleBasedClaimExtractionService implements ClaimExtractionService {
  const RuleBasedClaimExtractionService();

  static final _sentenceEnd = RegExp(
    r'(?<=[.!?])(?:\*{1,2}|_{1,2})?(?:\[\d+\])*\s+',
  );

  @override
  List<ExtractedClaim> extract(GroundedAnswer answer) {
    // Use answerText without trimming so citation startIndex/endIndex offsets
    // remain aligned with sentence ranges. Individual claim texts are trimmed below.
    final text = answer.answerText;
    if (text.trim().isEmpty) return const [];

    bool validRange(GroundedAnswerCitation c) =>
        c.startIndex != null &&
        c.endIndex != null &&
        c.startIndex! >= 0 &&
        c.endIndex! > c.startIndex! &&
        c.endIndex! <= text.length;
    final codeRanges = RegExp(
      r'```[\s\S]*?(?:```|$)|~~~[\s\S]*?(?:~~~|$)|`[^`\n]*`',
    ).allMatches(text).toList();
    bool inCode(int at) => codeRanges.any((r) => at >= r.start && at < r.end);
    final allCitations = <GroundedAnswerCitation>[];
    final explicit = Set<GroundedAnswerCitation>.identity();
    // Recover references explicitly written by the provider, without searching
    // for new sources or treating answer-level references as sentence proof.
    for (final c in answer.citations) {
      final markers = RegExp(r'^\d+$').hasMatch(c.id)
          ? RegExp(
              '\\[${RegExp.escape(c.id)}\\](?![(:])',
            ).allMatches(text).where((m) => !inCode(m.start)).toList()
          : <RegExpMatch>[];
      if (markers.isEmpty || validRange(c)) {
        allCitations.add(c);
      } else {
        for (final marker in markers) {
          final anchored = c.copyWith(position: marker.end);
          allCitations.add(anchored);
          explicit.add(anchored);
        }
      }
    }
    final links = RegExp(
      r'\[([^\]\n]+)\]\((?:<(https?://[^>\s]+)>|(https?://[^\s)]+))\)',
    ).allMatches(text).toList();
    for (final link in links) {
      if (inCode(link.start) ||
          link.start > 0 && text[link.start - 1] == r'\') {
        continue;
      }
      final url = link[2] ?? link[3]!;
      if (allCitations.any((c) => c.url == url && c.position == link.end)) {
        continue;
      }
      final anchored = GroundedAnswerCitation(
        id: 'inline-${link.start}',
        title: link[1]!,
        url: url,
        position: link.end,
      );
      allCitations.add(anchored);
      explicit.add(anchored);
    }
    final formatting = [
      ...RegExp(
        r'(?<![\w\\*])\*(?![\s*])[\s\S]*?(?<!\s)\*(?!\*)',
      ).allMatches(text),
      ...RegExp(
        r'(?<![\w\\])_(?![\s_])[\s\S]*?(?<!\s)_(?![\w_])',
      ).allMatches(text),
      ...links,
    ];
    final sentences = <({int start, int end, String text})>[];
    var cursor = 0;
    for (final match in _sentenceEnd.allMatches(text)) {
      if (match.start < cursor) continue;
      final boundary = match.start + match[0]!.trimRight().length;
      if (formatting.any((r) => boundary > r.start && boundary < r.end)) {
        continue;
      }
      final prefix = text.substring(0, boundary);
      if (inCode(match.start) ||
          RegExp(r'(?<!\\)\*\*').allMatches(prefix).length.isOdd ||
          RegExp(r'(?<!\\)__').allMatches(prefix).length.isOdd) {
        continue;
      }
      // A trailing citation belongs to this sentence, not the next sentence.
      var end = boundary;
      var next = match.end;
      var whitespace = match[0]!;
      final reference = RegExp(
        r'^(?:\[\d+\](?![(:])|\[[^\]\n]+\]\((?:<https?://[^>\s]+>|https?://[^\s)]+)\))',
      );
      while (!RegExp(r'\n[ \t]*\n').hasMatch(whitespace)) {
        final suffix = reference.firstMatch(text.substring(next));
        if (suffix == null) break;
        end = next + suffix.end;
        next = end;
        final gap = RegExp(r'^\s*').firstMatch(text.substring(next))!;
        whitespace = gap[0]!;
        next += gap.end;
      }
      final segment = text.substring(cursor, end);
      if (segment.trim().isNotEmpty) {
        sentences.add((start: cursor, end: end, text: segment));
      }
      cursor = next;
    }
    if (cursor < text.length && text.substring(cursor).trim().isNotEmpty) {
      sentences.add((
        start: cursor,
        end: text.length,
        text: text.substring(cursor),
      ));
    }
    final positions = answer.citations.map((c) => c.position).toSet();
    final endCluster =
        sentences.length > 1 &&
        answer.citations.length > 1 &&
        positions.length == 1 &&
        positions.single == text.trimRight().length;

    final seen = <String>{};
    final claims = <ExtractedClaim>[];

    for (final sentence in sentences) {
      final trimmed = sentence.text.trim();
      if (trimmed.isEmpty) continue;
      if (seen.contains(trimmed)) continue;
      seen.add(trimmed);

      final sentenceStart = sentence.start;
      final sentenceEnd = sentence.end;

      final List<String> citationUrls;
      final List<String> citationTitles;
      final bool uncertain;

      // A source consulted for the answer is not automatically evidence for
      // every sentence. Keep only provider ranges overlapping this claim.
      final overlapping = allCitations.where((c) {
        if (validRange(c)) {
          return c.startIndex! < sentenceEnd && c.endIndex! > sentenceStart;
        }
        final position = c.position;
        if (endCluster && !explicit.contains(c) ||
            position == null ||
            position <= 0 ||
            position > text.length) {
          return false;
        }
        final anchor = text.substring(0, position).trimRight().length;
        return anchor > sentenceStart && anchor <= sentenceEnd;
      }).toList();
      uncertain = overlapping.isEmpty;
      // Keep answer source links reachable even when their sentence attribution
      // is unknown, but never recycle a different claim's quote as evidence.
      final evidence = uncertain
          ? allCitations
                .map(
                  (c) => GroundedAnswerCitation(
                    id: c.id,
                    title: c.title,
                    url: c.url,
                  ),
                )
                .toList()
          : overlapping;
      citationUrls = List.unmodifiable(evidence.map((c) => c.url).toSet());
      citationTitles = List.unmodifiable(
        citationUrls.map(
          (url) => evidence.firstWhere((c) => c.url == url).title,
        ),
      );

      final id = _claimId(
        answer.providerName,
        answer.question,
        trimmed,
        claims.length,
        answer.generatedAt,
      );

      final contentStart = sentence.start + sentence.text.indexOf(trimmed);
      final lineStart =
          text.lastIndexOf('\n', contentStart == 0 ? 0 : contentStart - 1) + 1;
      final indentation = text.substring(lineStart, contentStart);
      final formatted =
          RegExp(r'^[ \t]*$').hasMatch(indentation) &&
              RegExp(r'^(?:[-+*•●◦▪]|\d+[.)])\s').hasMatch(trimmed)
          ? '$indentation$trimmed'
          : trimmed;
      claims.add(
        ExtractedClaim(
          id: id,
          text: formatted,
          citationUrls: citationUrls,
          citationTitles: citationTitles,
          evidence: List.unmodifiable(evidence),
          evidenceMapped: true,
          sourceAnswerProvider: answer.providerName,
          sourceQuestion: answer.question,
          order: claims.length,
          citationUncertain: uncertain,
        ),
      );
    }

    return List.unmodifiable(claims);
  }

  /// Builds a deterministic, instance-scoped ID.
  ///
  /// [generatedAt] scopes the ID to the specific answer instance so that two
  /// answers to the same question at different times never share claim IDs,
  /// even when provider/question/text are identical.
  static String _claimId(
    String provider,
    String question,
    String claimText,
    int index,
    DateTime generatedAt,
  ) {
    final qKey = question.length > 40 ? question.substring(0, 40) : question;
    final tKey = claimText.length > 40 ? claimText.substring(0, 40) : claimText;
    final tsKey = generatedAt.millisecondsSinceEpoch.toRadixString(36);
    return '${provider}_ts:${tsKey}_q:${qKey}_i:${index}_t:$tKey'.replaceAll(
      RegExp(r'\s+'),
      '_',
    );
  }
}
