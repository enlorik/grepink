import '../models/claim_deduplication_result.dart';
import '../models/evidence_item.dart';
import '../models/extracted_claim.dart';
import 'text_similarity_provider.dart';

abstract class ClaimDeduplicationService {
  /// Classifies each [claims] entry against [localEvidence].
  ///
  /// Returns one [ClaimDeduplicationResult] per input claim in the same order.
  /// Returns an empty list when [claims] is empty.
  Future<List<ClaimDeduplicationResult>> classify(
    List<ExtractedClaim> claims,
    List<EvidenceItem> localEvidence,
  );
}

/// Threshold above which a claim is considered to match local evidence.
const _highSimilarityThreshold = 0.65;

/// Splits note content into comparable chunks for claim similarity scoring.
///
/// Splits on sentence-ending punctuation AND on newlines so that Markdown
/// bullet lists (whose lines rarely end with `.!?`) are also broken apart.
/// Strips leading Markdown list markers (`- `, `* `, `1. `, etc.) so that
/// bare claim text can match bullet content without the formatting noise.
List<String> _chunks(String content) {
  final parts = content
      .split(RegExp(r'(?<=[.!?])\s+|\n+'))
      .map((s) => s.trim())
      .map((s) => s.replaceFirst(RegExp(r'^[-*•+]\s+|^\d+\.\s+'), '').trim())
      .where((s) => s.isNotEmpty)
      .toList();
  return parts.isEmpty ? [content] : parts;
}

class TextSimilarityClaimDeduplicationService
    implements ClaimDeduplicationService {
  final TextSimilarityProvider _similarity;

  // ignore: prefer_const_constructors_in_immutables - field type is abstract
  TextSimilarityClaimDeduplicationService(this._similarity);

  @override
  Future<List<ClaimDeduplicationResult>> classify(
    List<ExtractedClaim> claims,
    List<EvidenceItem> localEvidence,
  ) async {
    if (claims.isEmpty) return const [];

    final results = <ClaimDeduplicationResult>[];

    for (final claim in claims) {
      results.add(await _classifyClaim(claim, localEvidence));
    }

    return List.unmodifiable(results);
  }

  Future<ClaimDeduplicationResult> _classifyClaim(
    ExtractedClaim claim,
    List<EvidenceItem> localEvidence,
  ) async {
    if (localEvidence.isEmpty) {
      return ClaimDeduplicationResult(
        claim: claim,
        classification: ClaimNoveltyClassification.newClaim,
        matchedLocalEvidence: const [],
        reason: 'No local evidence to compare against.',
        citationUrls: List.unmodifiable(claim.citationUrls),
      );
    }

    double bestScore = 0.0;
    EvidenceItem? bestMatch;

    for (final evidence in localEvidence) {
      for (final chunk in _chunks(evidence.content)) {
        final score = await _similarity.similarity(claim.text, chunk);
        if (score > bestScore) {
          bestScore = score;
          bestMatch = evidence;
        }
      }
    }

    if (bestScore >= _highSimilarityThreshold && bestMatch != null) {
      final localHasUrl =
          bestMatch.sourceUrl != null && bestMatch.sourceUrl!.isNotEmpty;
      final claimHasUrl = claim.citationUrls.isNotEmpty;
      // Suppress betterSource only when EVERY claim URL is already present in
      // the matched note's text. If even one URL is missing the note is missing
      // a source, so betterSource still fires.
      final allClaimUrlsInNote =
          claim.citationUrls.every((url) => bestMatch!.content.contains(url));

      if (claimHasUrl && !localHasUrl && !allClaimUrlsInNote) {
        return ClaimDeduplicationResult(
          claim: claim,
          classification: ClaimNoveltyClassification.betterSource,
          matchedLocalEvidence: [bestMatch],
          reason:
              'Similar content found locally but the external claim has citation URLs not present in the local note.',
          similarityScore: bestScore,
          citationUrls: List.unmodifiable(claim.citationUrls),
        );
      }

      return ClaimDeduplicationResult(
        claim: claim,
        classification: ClaimNoveltyClassification.alreadyKnown,
        matchedLocalEvidence: [bestMatch],
        reason: 'High similarity match found in local notes.',
        similarityScore: bestScore,
        citationUrls: List.unmodifiable(claim.citationUrls),
      );
    }

    // Low similarity — claim is genuinely new.
    return ClaimDeduplicationResult(
      claim: claim,
      classification: ClaimNoveltyClassification.newClaim,
      matchedLocalEvidence: bestMatch != null ? [bestMatch] : const [],
      reason: 'No sufficiently similar content found in local notes.',
      similarityScore: bestScore > 0 ? bestScore : null,
      citationUrls: List.unmodifiable(claim.citationUrls),
    );
  }
}
