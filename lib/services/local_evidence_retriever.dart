import '../models/evidence_item.dart';

abstract class LocalEvidenceRetriever {
  Future<List<EvidenceItem>> retrieve(String question);
}
