import 'package:grepink/models/evidence_item.dart';
import 'package:grepink/services/local_evidence_retriever.dart';
import 'package:grepink/services/web_evidence_provider.dart';

class FakeLocalEvidenceRetriever implements LocalEvidenceRetriever {
  final List<EvidenceItem> items;

  FakeLocalEvidenceRetriever(this.items);

  @override
  Future<List<EvidenceItem>> retrieve(String question) async => items;
}

class FakeWebEvidenceProvider implements WebEvidenceProvider {
  final List<EvidenceItem> items;

  FakeWebEvidenceProvider(this.items);

  @override
  Future<List<EvidenceItem>> fetch(String question) async => items;
}
