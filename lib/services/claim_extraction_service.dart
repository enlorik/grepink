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
/// This is a conservative rule-based extractor. It does not claim to perfectly
/// understand citations yet. Citation URLs from the parent answer are attached
/// to every extracted claim conservatively until per-sentence attribution is
/// available.
///
/// Known limitation: the sentence splitter will incorrectly fragment
/// abbreviations like "Dr.", "U.S.", "e.g." that contain internal periods
/// followed by whitespace. This is a known trade-off of a rule-based approach.
class RuleBasedClaimExtractionService implements ClaimExtractionService {
  const RuleBasedClaimExtractionService();

  static final _sentenceEnd = RegExp(r'(?<=[.!?])\s+');

  @override
  List<ExtractedClaim> extract(GroundedAnswer answer) {
    final text = answer.answerText.trim();
    if (text.isEmpty) return const [];

    final citationUrls = answer.citations.map((c) => c.url).toList();
    final citationTitles = answer.citations.map((c) => c.title).toList();

    final rawSentences = text.split(_sentenceEnd);

    final seen = <String>{};
    final claims = <ExtractedClaim>[];

    for (final sentence in rawSentences) {
      final trimmed = sentence.trim();
      if (trimmed.isEmpty) continue;
      if (seen.contains(trimmed)) continue;
      seen.add(trimmed);

      // ID is deterministic: same GroundedAnswer + same claim text + same
      // position always yields the same ID, but distinct answer instances
      // (different generatedAt) never collide even for identical question/text.
      final id = _claimId(
          answer.providerName, answer.question, trimmed, claims.length, answer.generatedAt);

      claims.add(ExtractedClaim(
        id: id,
        text: trimmed,
        citationUrls: List.unmodifiable(citationUrls),
        citationTitles: List.unmodifiable(citationTitles),
        sourceAnswerProvider: answer.providerName,
        sourceQuestion: answer.question,
        order: claims.length,
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
      String provider, String question, String claimText, int index, DateTime generatedAt) {
    final qKey = question.length > 40 ? question.substring(0, 40) : question;
    final tKey = claimText.length > 40 ? claimText.substring(0, 40) : claimText;
    final tsKey = generatedAt.millisecondsSinceEpoch.toRadixString(36);
    return '${provider}_ts:${tsKey}_q:${qKey}_i:${index}_t:$tKey'
        .replaceAll(RegExp(r'\s+'), '_');
  }
}
