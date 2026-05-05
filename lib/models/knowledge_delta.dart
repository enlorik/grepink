import 'evidence_item.dart';

enum DeltaType { duplicate, relatedButNew, newClaim, contradiction, betterSource }

class KnowledgeDelta {
  final EvidenceItem evidence;
  final DeltaType deltaType;
  final String? existingNoteId;
  final String reason;

  /// Best similarity score computed during delta detection (0.0–1.0).
  /// Null when no local evidence was available to compare against.
  final double? bestSimilarityScore;

  const KnowledgeDelta({
    required this.evidence,
    required this.deltaType,
    this.existingNoteId,
    required this.reason,
    this.bestSimilarityScore,
  });
}
