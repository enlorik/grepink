import '../models/evidence_item.dart';
import '../models/knowledge_delta.dart';

abstract class DeltaDetector {
  Future<List<KnowledgeDelta>> detect(
    List<EvidenceItem> localEvidence,
    List<EvidenceItem> incomingEvidence,
  );
}
