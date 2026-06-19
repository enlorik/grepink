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
      final score = await _similarity.similarity(claim.text, evidence.content);
      if (score > bestScore) {
        bestScore = score;
        bestMatch = evidence;
      }
    }

    if (bestScore >= _highSimilarityThreshold && bestMatch != null) {
      // Claim content is already known. Check if the external claim has a
      // citation URL while the local match does not — that would make it a
      // better source.
      final localHasUrl =
          bestMatch.sourceUrl != null && bestMatch.sourceUrl!.isNotEmpty;
      final claimHasUrl = claim.citationUrls.isNotEmpty;

      if (claimHasUrl && !localHasUrl) {
        return ClaimDeduplicationResult(
          claim: claim,
          classification: ClaimNoveltyClassification.betterSource,
          matchedLocalEvidence: [bestMatch],
          reason:
              'Similar content found locally but the external claim provides a citation URL the local note lacks.',
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
