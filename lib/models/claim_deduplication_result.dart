import 'evidence_item.dart';
import 'extracted_claim.dart';

enum ClaimNoveltyClassification {
  alreadyKnown,
  newClaim,
  betterSource,
  contradiction,
  uncertain,
}

class ClaimDeduplicationResult {
  final ExtractedClaim claim;
  final ClaimNoveltyClassification classification;
  final List<EvidenceItem> matchedLocalEvidence;
  final String reason;
  final double? similarityScore;
  final List<String> citationUrls;

  const ClaimDeduplicationResult({
    required this.claim,
    required this.classification,
    required this.matchedLocalEvidence,
    required this.reason,
    this.similarityScore,
    required this.citationUrls,
  });
}
