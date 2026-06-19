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

      claims.add(ExtractedClaim(
        id: '${answer.providerName}_${answer.question.hashCode}_${claims.length}',
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
}
