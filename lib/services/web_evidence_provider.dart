import '../models/evidence_item.dart';

abstract class WebEvidenceProvider {
  Future<List<EvidenceItem>> fetch(String question);
}

class MockWebEvidenceProvider implements WebEvidenceProvider {
  @override
  Future<List<EvidenceItem>> fetch(String question) async {
    return [
      EvidenceItem(
        id: 'web_mock_1',
        type: EvidenceType.webSearch,
        title: 'Sample Web Result: $question',
        content:
            'This is a mock web search result related to "$question". '
            'It provides some background context that may or may not already exist in your notes.',
        sourceUrl: 'https://example.com/mock-result-1',
        relevanceScore: 0.75,
      ),
      EvidenceItem(
        id: 'web_mock_2',
        type: EvidenceType.webSearch,
        title: 'Another Mock Result',
        content:
            'A second mock result offering additional perspective on "$question". '
            'This content is intentionally distinct to exercise delta detection.',
        sourceUrl: 'https://example.com/mock-result-2',
        relevanceScore: 0.60,
      ),
    ];
  }
}
