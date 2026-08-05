import '../models/claim_deduplication_result.dart';
import '../models/grounded_answer_provider_outcome.dart';
import '../models/grounded_claim_ingestion_result.dart';
import 'claim_deduplication_service.dart';
import 'claim_extraction_service.dart';
import 'grounded_answer_provider.dart';
import 'local_evidence_retriever.dart';

class GroundedAnswerIngestionService {
  final GroundedAnswerProvider _provider;
  final ClaimExtractionService _extractor;
  final ClaimDeduplicationService _deduplicator;
  final LocalEvidenceRetriever _localEvidence;

  GroundedAnswerIngestionService({
    required GroundedAnswerProvider provider,
    required ClaimExtractionService extractor,
    required ClaimDeduplicationService deduplicator,
    required LocalEvidenceRetriever localEvidence,
  })  : _provider = provider,
        _extractor = extractor,
        _deduplicator = deduplicator,
        _localEvidence = localEvidence;

  /// Fetches a grounded answer, extracts claims, and classifies them against
  /// local evidence.
  ///
  /// Returns [GroundedClaimIngestionResult.failure] for non-success outcomes.
  /// Returns [GroundedClaimIngestionResult.empty] for unexpected exceptions.
  /// Never throws. Never auto-saves.
  Future<GroundedClaimIngestionResult> ingest(String question) async {
    if (question.trim().isEmpty) {
      return GroundedClaimIngestionResult.empty(question);
    }

    GroundedAnswerProviderOutcome outcome;
    try {
      final localEvidence = await _localEvidence.retrieve(question);
      outcome = await _provider.fetchGroundedAnswer(question);

      if (outcome is! GroundedAnswerSuccess) {
        return GroundedClaimIngestionResult.failure(question, outcome);
      }

      final answer = outcome.answer;
      if (answer.isEmpty) {
        return GroundedClaimIngestionResult.failure(
            question, const GroundedAnswerEmpty());
      }

      final claims = _extractor.extract(answer);

      if (claims.isEmpty) {
        return GroundedClaimIngestionResult(
          question: question,
          answerText: answer.answerText,
          providerName: answer.providerName,
          knownClaims: const [],
          newClaims: const [],
          betterSourceClaims: const [],
          contradictionClaims: const [],
          uncertainClaims: const [],
          citations: List.unmodifiable(answer.citations),
          providerOutcome: outcome,
        );
      }

      final classified = await _deduplicator.classify(claims, localEvidence);

      final known = <ClaimDeduplicationResult>[];
      final newC = <ClaimDeduplicationResult>[];
      final better = <ClaimDeduplicationResult>[];
      final contradiction = <ClaimDeduplicationResult>[];
      final uncertain = <ClaimDeduplicationResult>[];

      for (final result in classified) {
        switch (result.classification) {
          case ClaimNoveltyClassification.alreadyKnown:
            known.add(result);
          case ClaimNoveltyClassification.newClaim:
            newC.add(result);
          case ClaimNoveltyClassification.betterSource:
            better.add(result);
          case ClaimNoveltyClassification.contradiction:
            contradiction.add(result);
          case ClaimNoveltyClassification.uncertain:
            uncertain.add(result);
        }
      }

      return GroundedClaimIngestionResult(
        question: question,
        answerText: answer.answerText,
        providerName: answer.providerName,
        knownClaims: List.unmodifiable(known),
        newClaims: List.unmodifiable(newC),
        betterSourceClaims: List.unmodifiable(better),
        contradictionClaims: List.unmodifiable(contradiction),
        uncertainClaims: List.unmodifiable(uncertain),
        citations: List.unmodifiable(answer.citations),
        providerOutcome: outcome,
      );
    } catch (_) {
      return GroundedClaimIngestionResult.empty(question);
    }
  }
}
