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

/// Returns true if [text] contains a common English negation marker.
///
/// Covers full-word negations (not, no, never, cannot) with word boundaries
/// and contracted negations (isn't, doesn't, can't, won't, etc.) via `n't`
/// without a leading \b — apostrophe breaks the word boundary so \bn't\b
/// never matches contractions.
/// Intentionally conservative — does not attempt full NLI.
bool _hasNegation(String text) {
  return RegExp(
    r"\b(not|no|never|cannot)\b|n't",
    caseSensitive: false,
  ).hasMatch(text);
}

/// Extracts numeric and date-like tokens from [text] as a set of strings.
///
/// Matches integers, decimals, currency amounts, percentages, and 4-digit
/// years, including optionally signed values (e.g. -5%, -$10).
///
/// Normalisation applied to each raw match:
/// 1. Trailing `.` or `,` are stripped ("2024." → "2024", "$10." → "$10")
///    so sentence-final punctuation does not produce false conflicts.
/// 2. A leading `+` is stripped ("+5%" → "5%") because an explicit plus
///    sign is equivalent to no sign; negative signs are preserved because
///    a negative value is materially different from a positive one.
Set<String> _numericTokens(String text) {
  return RegExp(r'[-+]?[\$£€]?\d[\d,\.]*%?')
      .allMatches(text)
      .map((m) => m.group(0)!)
      .map((t) => t.replaceFirst(RegExp(r'[.,]+$'), ''))
      .map((t) => t.replaceFirst(RegExp(r'^\+'), ''))
      .toSet();
}

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
    String bestChunk = '';

    for (final evidence in localEvidence) {
      for (final chunk in _chunks(evidence.content)) {
        final score = await _similarity.similarity(claim.text, chunk);
        if (score > bestScore) {
          bestScore = score;
          bestMatch = evidence;
          bestChunk = chunk;
        }
      }
    }

    if (bestScore >= _highSimilarityThreshold && bestMatch != null) {
      // Conservative negation check: compare polarity of the claim against the
      // specific chunk that scored highest (not the full note, which may contain
      // unrelated negations). If one has a negation marker and the other does
      // not, the texts likely assert opposite things — flag as contradiction
      // rather than silently collapsing them into alreadyKnown.
      if (_hasNegation(claim.text) != _hasNegation(bestChunk)) {
        return ClaimDeduplicationResult(
          claim: claim,
          classification: ClaimNoveltyClassification.contradiction,
          matchedLocalEvidence: [bestMatch],
          reason:
              'High token overlap but opposite polarity — possible negation conflict.',
          similarityScore: bestScore,
          citationUrls: List.unmodifiable(claim.citationUrls),
        );
      }

      // Numeric conflict check: only flag as contradiction when both sides have
      // numeric tokens and neither set is a subset of the other — meaning each
      // side has at least one number the other lacks (a true value conflict).
      // When one side is a strict superset (extra context like an added year),
      // return uncertain rather than wrongly calling it a contradiction.
      final claimNums = _numericTokens(claim.text);
      final chunkNums = _numericTokens(bestChunk);
      if (claimNums.isNotEmpty && chunkNums.isNotEmpty) {
        final claimContainsChunk = claimNums.containsAll(chunkNums);
        final chunkContainsClaim = chunkNums.containsAll(claimNums);
        if (!claimContainsChunk || !chunkContainsClaim) {
          if (claimContainsChunk || chunkContainsClaim) {
            // One side is a strict superset — additional numeric context, not
            // a conflicting value.
            return ClaimDeduplicationResult(
              claim: claim,
              classification: ClaimNoveltyClassification.uncertain,
              matchedLocalEvidence: [bestMatch],
              reason:
                  'High token overlap but one side contains additional numeric context — possibly more specific.',
              similarityScore: bestScore,
              citationUrls: List.unmodifiable(claim.citationUrls),
            );
          }
          // Neither contains the other — conflicting comparable numeric values.
          return ClaimDeduplicationResult(
            claim: claim,
            classification: ClaimNoveltyClassification.contradiction,
            matchedLocalEvidence: [bestMatch],
            reason:
                'High token overlap but differing numeric values — possible factual conflict.',
            similarityScore: bestScore,
            citationUrls: List.unmodifiable(claim.citationUrls),
          );
        }
      }

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
