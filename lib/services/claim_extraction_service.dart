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
/// found (or all offsets are null), the claim carries no citations and
/// [citationUncertain] is true.
///
/// Known limitation: the sentence splitter will incorrectly fragment
/// abbreviations like "Dr.", "U.S.", "e.g." that contain internal periods
/// followed by whitespace. This is a known trade-off of a rule-based approach.
class RuleBasedClaimExtractionService implements ClaimExtractionService {
  const RuleBasedClaimExtractionService();

  static final _sentenceEnd = RegExp(r'(?<=[.!?])\s+');

  @override
  List<ExtractedClaim> extract(GroundedAnswer answer) {
    // Use answerText without trimming so citation startIndex/endIndex offsets
    // remain aligned with sentence ranges. Individual claim texts are trimmed below.
    final text = answer.answerText;
    if (text.trim().isEmpty) return const [];

    final allCitations = answer.citations;
    final hasOffsets = allCitations.any(
        (c) => c.startIndex != null && c.endIndex != null);

    // Build sentence ranges using allMatches for position awareness.
    final sentences = <({int start, int end, String text})>[];
    int cursor = 0;
    for (final match in _sentenceEnd.allMatches(text)) {
      final segment = text.substring(cursor, match.start);
      if (segment.trim().isNotEmpty) {
        sentences.add((start: cursor, end: match.start, text: segment));
      }
      cursor = match.end;
    }
    if (cursor < text.length) {
      final tail = text.substring(cursor);
      if (tail.trim().isNotEmpty) {
        sentences.add((start: cursor, end: text.length, text: tail));
      }
    }

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

      if (!hasOffsets) {
        // No citation offset data — attach all citations and mark uncertain.
        // When citations are present, uncertainty prevents saving without a
        // verifiable source. When there are no citations at all, marking uncertain
        // ensures claims from unannotated answers are not saved as sourced facts.
        citationUrls =
            List.unmodifiable(allCitations.map((c) => c.url).toList());
        citationTitles =
            List.unmodifiable(allCitations.map((c) => c.title).toList());
        uncertain = true;
      } else {
        final overlapping = allCitations.where((c) {
          if (c.startIndex == null || c.endIndex == null) return false;
          return c.startIndex! < sentenceEnd && c.endIndex! > sentenceStart;
        }).toList();
        if (overlapping.isNotEmpty) {
          citationUrls =
              List.unmodifiable(overlapping.map((c) => c.url).toList());
          citationTitles =
              List.unmodifiable(overlapping.map((c) => c.title).toList());
          uncertain = false;
        } else {
          // No citation range covers this sentence; attach all citations
          // conservatively so saved claims still carry a source URL.
          citationUrls =
              List.unmodifiable(allCitations.map((c) => c.url).toList());
          citationTitles =
              List.unmodifiable(allCitations.map((c) => c.title).toList());
          uncertain = true;
        }
      }

      final id = _claimId(
          answer.providerName,
          answer.question,
          trimmed,
          claims.length,
          answer.generatedAt);

      claims.add(ExtractedClaim(
        id: id,
        text: trimmed,
        citationUrls: citationUrls,
        citationTitles: citationTitles,
        sourceAnswerProvider: answer.providerName,
        sourceQuestion: answer.question,
        order: claims.length,
        citationUncertain: uncertain,
      ));
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
      DateTime generatedAt) {
    final qKey = question.length > 40 ? question.substring(0, 40) : question;
    final tKey =
        claimText.length > 40 ? claimText.substring(0, 40) : claimText;
    final tsKey = generatedAt.millisecondsSinceEpoch.toRadixString(36);
    return '${provider}_ts:${tsKey}_q:${qKey}_i:${index}_t:$tKey'
        .replaceAll(RegExp(r'\s+'), '_');
  }
}
