import 'claim_deduplication_result.dart';
import 'grounded_answer.dart';

class GroundedClaimIngestionResult {
  final String question;
  final String answerText;
  final String providerName;
  final List<ClaimDeduplicationResult> knownClaims;
  final List<ClaimDeduplicationResult> newClaims;
  final List<ClaimDeduplicationResult> betterSourceClaims;
  final List<ClaimDeduplicationResult> contradictionClaims;
  final List<ClaimDeduplicationResult> uncertainClaims;
  final List<GroundedAnswerCitation> citations;

  const GroundedClaimIngestionResult({
    required this.question,
    required this.answerText,
    required this.providerName,
    required this.knownClaims,
    required this.newClaims,
    required this.betterSourceClaims,
    required this.contradictionClaims,
    required this.uncertainClaims,
    required this.citations,
  });

  bool get hasNewKnowledge =>
      newClaims.isNotEmpty ||
      betterSourceClaims.isNotEmpty ||
      contradictionClaims.isNotEmpty;

  bool get shouldCreateDraft => hasNewKnowledge;

  bool get isEmpty =>
      knownClaims.isEmpty &&
      newClaims.isEmpty &&
      betterSourceClaims.isEmpty &&
      contradictionClaims.isEmpty &&
      uncertainClaims.isEmpty;

  static GroundedClaimIngestionResult empty(String question) =>
      GroundedClaimIngestionResult(
        question: question,
        answerText: '',
        providerName: '',
        knownClaims: const [],
        newClaims: const [],
        betterSourceClaims: const [],
        contradictionClaims: const [],
        uncertainClaims: const [],
        citations: const [],
      );
}
