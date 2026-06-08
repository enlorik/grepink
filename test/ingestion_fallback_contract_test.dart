import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/evidence_item.dart';
import 'package:grepink/models/note_draft.dart';
import 'package:grepink/services/brave_evidence_provider.dart';
import 'package:grepink/services/delta_detector_impl.dart';
import 'package:grepink/services/knowledge_ingestion_service.dart';
import 'package:grepink/services/local_evidence_retriever.dart';
import 'package:grepink/services/structured_summary_writer.dart';
import 'package:grepink/services/web_evidence_provider.dart';
import 'package:http/http.dart' as http;

import 'helpers/fake_ingestion_sources.dart';
import 'helpers/fake_text_similarity_provider.dart';
import 'helpers/recording_llm_provider.dart';

// --- Spy helpers ---

class _RecordingRetriever implements LocalEvidenceRetriever {
  final List<String> _log;
  final List<EvidenceItem> items;

  _RecordingRetriever(this._log, this.items);

  @override
  Future<List<EvidenceItem>> retrieve(String question) async {
    _log.add('local');
    return items;
  }
}

class _RecordingWebProvider implements WebEvidenceProvider {
  final List<String> _log;
  final List<EvidenceItem> items;

  _RecordingWebProvider(this._log, this.items);

  @override
  Future<List<EvidenceItem>> fetch(String question) async {
    _log.add('web');
    return items;
  }
}

class _ErrorHttpClient extends http.BaseClient {
  final int statusCode;

  _ErrorHttpClient({this.statusCode = 500});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(Stream.value(const <int>[]), statusCode);
}

class _ThrowingHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Future.error(Exception('network error'));
}

// --- Evidence factories ---

EvidenceItem _localItem(String id, String content) => EvidenceItem(
      id: id,
      type: EvidenceType.localNote,
      title: 'Local $id',
      content: content,
      sourceNoteId: id,
    );

EvidenceItem _webItem(String id, String content, {String? sourceUrl}) =>
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
  double similarityScore = 0.2,
  RecordingLlmProvider? llmProvider,
}) {
  return KnowledgeIngestionServiceImpl(
    localRetriever: FakeLocalEvidenceRetriever(localItems),
    webProvider: FakeWebEvidenceProvider(webItems),
    deltaDetector:
        DeltaDetectorImpl(similarityProvider: FakeTextSimilarityProvider(similarityScore)),
    summaryWriter: StructuredSummaryWriter(
      llmProvider: llmProvider ?? RecordingLlmProvider(responseText: '# Draft'),
    ),
  );
}

// ---------------------------------------------------------------------------

void main() {
  group('Ingestion fallback contract – call ordering', () {
    test('local evidence is gathered before web evidence', () async {
      final log = <String>[];
      final service = KnowledgeIngestionServiceImpl(
        localRetriever: _RecordingRetriever(log, [_localItem('n1', 'existing')]),
        webProvider: _RecordingWebProvider(log, [_webItem('w1', 'new fact')]),
        deltaDetector: DeltaDetectorImpl(
          similarityProvider: const FakeTextSimilarityProvider(0.2),
        ),
        summaryWriter:
            StructuredSummaryWriter(llmProvider: RecordingLlmProvider()),
      );

      await service.ingest('ordering test');

      expect(log, orderedEquals(['local', 'web']),
          reason: 'local retriever must be called before web provider');
    });
  });

  group('Ingestion fallback contract – empty web evidence', () {
    test('empty web evidence returns doNotSave without crashing', () async {
      final draft = await _service(
        localItems: [_localItem('n1', 'an existing note')],
        webItems: const [],
      ).ingest('no web available');

      expect(draft.action, NoteDraftAction.doNotSave);
      expect(draft.webEvidence, isEmpty);
    });

    test('no local and no web evidence returns doNotSave', () async {
      final draft =
          await _service().ingest('completely empty');

      expect(draft.action, NoteDraftAction.doNotSave);
    });

    test('EmptyWebEvidenceProvider resolves to doNotSave', () async {
      final service = KnowledgeIngestionServiceImpl(
        localRetriever:
            FakeLocalEvidenceRetriever([_localItem('n1', 'some note')]),
        webProvider: EmptyWebEvidenceProvider(),
        deltaDetector: DeltaDetectorImpl(
          similarityProvider: const FakeTextSimilarityProvider(0.2),
        ),
        summaryWriter:
            StructuredSummaryWriter(llmProvider: RecordingLlmProvider()),
      );

      final draft = await service.ingest('empty provider');

      expect(draft.action, NoteDraftAction.doNotSave);
    });
  });

  group('Ingestion fallback contract – web provider failure', () {
    test('BraveEvidenceProvider returns [] on network exception', () async {
      final provider = BraveEvidenceProvider(
        apiKey: 'test-key',
        httpClient: _ThrowingHttpClient(),
      );

      expect(await provider.fetch('network failure'), isEmpty);
    });

    test('BraveEvidenceProvider returns [] on HTTP 500', () async {
      final provider = BraveEvidenceProvider(
        apiKey: 'test-key',
        httpClient: _ErrorHttpClient(statusCode: 500),
      );

      expect(await provider.fetch('server error'), isEmpty);
    });

    test('BraveEvidenceProvider returns [] on HTTP 401', () async {
      final provider = BraveEvidenceProvider(
        apiKey: 'bad-key',
        httpClient: _ErrorHttpClient(statusCode: 401),
      );

      expect(await provider.fetch('auth failure'), isEmpty);
    });

    test('BraveEvidenceProvider with empty API key returns [] without network call',
        () async {
      // _ThrowingHttpClient would surface if a network call is made.
      final provider = BraveEvidenceProvider(
        apiKey: '',
        httpClient: _ThrowingHttpClient(),
      );

      expect(await provider.fetch('empty key'), isEmpty);
    });

    test('network failure wired into ingestion produces safe doNotSave draft',
        () async {
      final service = KnowledgeIngestionServiceImpl(
        localRetriever: FakeLocalEvidenceRetriever(const []),
        webProvider: BraveEvidenceProvider(
          apiKey: 'test-key',
          httpClient: _ThrowingHttpClient(),
        ),
        deltaDetector: DeltaDetectorImpl(
          similarityProvider: const FakeTextSimilarityProvider(0.2),
        ),
        summaryWriter:
            StructuredSummaryWriter(llmProvider: RecordingLlmProvider()),
      );

      final draft = await service.ingest('brave failure');

      expect(draft.action, NoteDraftAction.doNotSave);
      expect(draft.webEvidence, isEmpty);
    });
  });

  group('Ingestion fallback contract – summary writer sees actual evidence', () {
    test('LLM prompt contains actual local evidence content', () async {
      final llm = RecordingLlmProvider(responseText: '# Draft');
      final service = KnowledgeIngestionServiceImpl(
        localRetriever: FakeLocalEvidenceRetriever([
          _localItem('n1', 'Flutter uses reactive programming patterns.'),
        ]),
        webProvider: FakeWebEvidenceProvider([
          _webItem('w1', 'New claim about Dart isolates.'),
        ]),
        deltaDetector: DeltaDetectorImpl(
          similarityProvider: const FakeTextSimilarityProvider(0.2),
        ),
        summaryWriter: StructuredSummaryWriter(llmProvider: llm),
      );

      await service.ingest('Flutter concurrency?');

      final prompt = llm.requests.single.userPrompt;
      expect(prompt, contains('Flutter uses reactive programming patterns.'));
      expect(prompt, contains('New claim about Dart isolates.'));
    });

    test('LLM prompt includes web evidence source URL', () async {
      const url = 'https://dart.dev/guides/language/concurrency';
      final llm = RecordingLlmProvider(responseText: '# Draft');
      final service = KnowledgeIngestionServiceImpl(
        localRetriever: FakeLocalEvidenceRetriever(const []),
        webProvider: FakeWebEvidenceProvider([
          _webItem('w1', 'Sourced claim about isolates.', sourceUrl: url),
        ]),
        deltaDetector: DeltaDetectorImpl(
          similarityProvider: const FakeTextSimilarityProvider(0.2),
        ),
        summaryWriter: StructuredSummaryWriter(llmProvider: llm),
      );

      await service.ingest('Dart concurrency?');

      expect(llm.requests.single.userPrompt, contains(url));
    });

    test('LLM is not called when there is nothing to save', () async {
      final llm = RecordingLlmProvider();
      final service = KnowledgeIngestionServiceImpl(
        localRetriever: FakeLocalEvidenceRetriever(const []),
        webProvider: FakeWebEvidenceProvider(const []),
        deltaDetector: DeltaDetectorImpl(
          similarityProvider: const FakeTextSimilarityProvider(0.2),
        ),
        summaryWriter: StructuredSummaryWriter(llmProvider: llm),
      );

      await service.ingest('nothing to save');

      expect(llm.requests, isEmpty,
          reason: 'LLM must not be called when evidence is empty');
    });

    test('local evidence appearing in prompt proves notes-first ordering',
        () async {
      final llm = RecordingLlmProvider(responseText: '# Draft');
      final service = KnowledgeIngestionServiceImpl(
        localRetriever: FakeLocalEvidenceRetriever([
          _localItem('n1', 'unique-local-marker-content'),
        ]),
        webProvider: FakeWebEvidenceProvider([
          _webItem('w1', 'unique-web-marker-content'),
        ]),
        deltaDetector: DeltaDetectorImpl(
          similarityProvider: const FakeTextSimilarityProvider(0.2),
        ),
        summaryWriter: StructuredSummaryWriter(llmProvider: llm),
      );

      await service.ingest('ordering via prompt');

      final prompt = llm.requests.single.userPrompt;
      final localPos = prompt.indexOf('unique-local-marker-content');
      final webPos = prompt.indexOf('unique-web-marker-content');
      expect(localPos, lessThan(webPos),
          reason: 'local evidence must appear before web evidence in the prompt');
    });
  });
}
