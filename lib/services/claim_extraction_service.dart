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

      // ID is a deterministic content-based key derived from provider, question,
      // claim text, and insertion order. Avoids VM-restart-unstable hashCode.
      final id = _claimId(answer.providerName, answer.question, trimmed, claims.length);

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

  /// Builds a deterministic ID from stable string content.
  ///
  /// Uses a simple concatenation key rather than Dart's VM-unstable hashCode,
  /// so IDs remain consistent across app restarts if the same claim is re-extracted.
  static String _claimId(
      String provider, String question, String claimText, int index) {
    // Take the first 40 chars of each component to keep IDs human-readable
    // without unbounded length. Index disambiguates duplicates within a run.
    final qKey = question.length > 40 ? question.substring(0, 40) : question;
    final tKey = claimText.length > 40 ? claimText.substring(0, 40) : claimText;
    return '${provider}_q:${qKey}_i:${index}_t:$tKey'
        .replaceAll(RegExp(r'\s+'), '_');
  }
}
