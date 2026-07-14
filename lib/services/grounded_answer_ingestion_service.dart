import '../models/claim_deduplication_result.dart';
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

  bool get isConfigured => _provider.isConfigured;

  /// Fetches a grounded answer, extracts claims, and classifies them against
  /// local evidence.
  ///
  /// Returns [GroundedClaimIngestionResult.empty] if the provider returns null
  /// or if an exception occurs. Never throws. Never auto-saves.
  Future<GroundedClaimIngestionResult> ingest(String question) async {
    if (question.trim().isEmpty) {
      return GroundedClaimIngestionResult.empty(question);
    }

    try {
      final localEvidence = await _localEvidence.retrieve(question);
      final answer = await _provider.fetchGroundedAnswer(question);
      if (answer == null || answer.isEmpty) {
        return GroundedClaimIngestionResult.empty(question);
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
      );
    } catch (_) {
      return GroundedClaimIngestionResult.empty(question);
    }
  }
}
