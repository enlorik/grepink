import 'evidence_item.dart';

enum DeltaType { duplicate, relatedButNew, newClaim, contradiction, betterSource }

class KnowledgeDelta {
  final EvidenceItem evidence;
  final DeltaType deltaType;
  final String? existingNoteId;
  final String reason;

  const KnowledgeDelta({
    required this.evidence,
    required this.deltaType,
    this.existingNoteId,
    required this.reason,
  });
}
