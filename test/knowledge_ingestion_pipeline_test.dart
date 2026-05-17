import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/evidence_item.dart';
import 'package:grepink/models/note_draft.dart';
import 'package:grepink/services/delta_detector_impl.dart';
import 'package:grepink/services/knowledge_ingestion_service.dart';
import 'package:grepink/services/llm_provider.dart';
import 'package:grepink/services/local_evidence_retriever.dart';
import 'package:grepink/services/structured_summary_writer.dart';
import 'package:grepink/services/web_evidence_provider.dart';

import 'helpers/fake_text_similarity_provider.dart';

class _FakeLocalEvidenceRetriever implements LocalEvidenceRetriever {
  final List<EvidenceItem> items;

  _FakeLocalEvidenceRetriever(this.items);

  @override
  Future<List<EvidenceItem>> retrieve(String question) async => items;
}

class _FakeWebEvidenceProvider implements WebEvidenceProvider {
  final List<EvidenceItem> items;

  _FakeWebEvidenceProvider(this.items);

  @override
  Future<List<EvidenceItem>> fetch(String question) async => items;
}

class _RecordingLlmProvider implements LlmProvider {
  final String responseText;
  final List<LlmRequest> requests = <LlmRequest>[];

  _RecordingLlmProvider({this.responseText = '# Draft'});

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    requests.add(request);
    return LlmResponse(
      text: responseText,
      providerName: 'recording',
      model: 'recording-model',
    );
  }
}

EvidenceItem _localItem(
  String id,
  String content, {
  String? sourceUrl,
}) =>
    EvidenceItem(
      id: id,
      type: EvidenceType.localNote,
      title: 'Local $id',
      content: content,
      sourceNoteId: id,
      sourceUrl: sourceUrl,
    );

EvidenceItem _webItem(
  String id,
  String content, {
  String? sourceUrl,
}) =>
    EvidenceItem(
      id: id,
      type: EvidenceType.webSearch,
      title: 'Web $id',
      content: content,
      sourceUrl: sourceUrl,
      relevanceScore: 0.9,
    );

KnowledgeIngestionServiceImpl _service({
  List<EvidenceItem> localItems = const [],
  List<EvidenceItem> webItems = const [],
  required LlmProvider llmProvider,
  double similarityScore = 0.2,
}) {
  return KnowledgeIngestionServiceImpl(
    localRetriever: _FakeLocalEvidenceRetriever(localItems),
    webProvider: _FakeWebEvidenceProvider(webItems),
    deltaDetector: DeltaDetectorImpl(
      similarityProvider: FakeTextSimilarityProvider(similarityScore),
    ),
    summaryWriter: StructuredSummaryWriter(llmProvider: llmProvider),
  );
}

void main() {
  group('Knowledge ingestion pipeline', () {
    test('no web evidence returns doNotSave without calling the LLM', () async {
      final llmProvider = _RecordingLlmProvider();
      final service = _service(
        localItems: [_localItem('n1', 'Existing note')],
        webItems: const [],
        llmProvider: llmProvider,
      );

      final draft = await service.ingest('Nothing new?');

      expect(draft.action, NoteDraftAction.doNotSave);
      expect(llmProvider.requests, isEmpty);
    });

    test('all duplicate deltas return doNotSave without calling the LLM',
        () async {
      const sharedText = 'Flutter uses widgets to compose UI.';
      final llmProvider = _RecordingLlmProvider();
      final service = _service(
        localItems: [_localItem('n1', sharedText)],
        webItems: [_webItem('w1', sharedText)],
        llmProvider: llmProvider,
      );

      final draft = await service.ingest('Tell me about widgets');

      expect(draft.action, NoteDraftAction.doNotSave);
      expect(llmProvider.requests, isEmpty);
    });

    test('new claim creates a new note draft', () async {
      final llmProvider = _RecordingLlmProvider(responseText: '# New draft');
      final service = _service(
        localItems: [_localItem('n1', 'Existing local topic')],
        webItems: [_webItem('w1', 'Completely new durable fact')],
        llmProvider: llmProvider,
        similarityScore: 0.2,
      );

      final draft = await service.ingest('What is new?');

      expect(draft.action, NoteDraftAction.createNewNote);
      expect(draft.markdownContent, '# New draft');
    });

    test('related but new evidence creates a new note draft', () async {
      final llmProvider = _RecordingLlmProvider(responseText: '# Related draft');
      final service = _service(
        localItems: [_localItem('n1', 'Topic overview')],
        webItems: [_webItem('w1', 'Topic overview plus a new detail')],
        llmProvider: llmProvider,
        similarityScore: 0.75,
      );

      final draft = await service.ingest('Topic update?');

      expect(draft.action, NoteDraftAction.createNewNote);
    });

    test('better source only appends to an existing note', () async {
      const sharedText = 'The speed of light is approximately 299,792 km/s.';
      final llmProvider =
          _RecordingLlmProvider(responseText: '# Better source draft');
      final service = _service(
        localItems: [_localItem('n1', sharedText)],
        webItems: [
          _webItem(
            'w1',
            sharedText,
            sourceUrl: 'https://physics.example/speed-of-light',
          ),
        ],
        llmProvider: llmProvider,
      );

      final draft = await service.ingest('Need a citation');

      expect(draft.action, NoteDraftAction.appendToExistingNote);
    });

    test('source URLs survive into the prompt and fallback markdown', () async {
      final llmProvider = _RecordingLlmProvider(responseText: '');
      final service = _service(
        localItems: const [],
        webItems: [
          _webItem(
            'w1',
            'Durable sourced claim',
            sourceUrl: 'https://example.com/source',
          ),
        ],
        llmProvider: llmProvider,
      );

      final draft = await service.ingest('Preserve the citation');

      expect(llmProvider.requests.single.userPrompt,
          contains('https://example.com/source'));
      expect(draft.markdownContent, contains('https://example.com/source'));
    });

    test('local evidence is included in the summary prompt', () async {
      final llmProvider = _RecordingLlmProvider();
      final service = _service(
        localItems: [
          _localItem('n1', 'Existing local note that should appear in the prompt'),
        ],
        webItems: [_webItem('w1', 'Related web evidence')],
        llmProvider: llmProvider,
        similarityScore: 0.75,
      );

      await service.ingest('Use prior knowledge');

      expect(
        llmProvider.requests.single.userPrompt,
        contains('Existing local note that should appear in the prompt'),
      );
    });

    test('empty LLM output falls back to safe markdown without crashing',
        () async {
      final llmProvider = _RecordingLlmProvider(responseText: '');
      final service = _service(
        localItems: const [],
        webItems: [_webItem('w1', 'Brand new claim')],
        llmProvider: llmProvider,
      );

      final draft = await service.ingest('Fallback please');

      expect(draft.action, NoteDraftAction.createNewNote);
      expect(draft.markdownContent, contains('Suggested markdown to save'));
    });
  });
}
