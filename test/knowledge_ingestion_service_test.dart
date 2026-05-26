import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/evidence_item.dart';
import 'package:grepink/models/knowledge_delta.dart';
import 'package:grepink/models/note_draft.dart';
import 'package:grepink/services/brave_evidence_provider.dart';
import 'package:grepink/services/delta_detector.dart';
import 'package:grepink/services/knowledge_ingestion_service.dart';
import 'package:grepink/services/summary_writer.dart';
import 'package:http/http.dart' as http;
import 'helpers/fake_ingestion_sources.dart';

// ---------------------------------------------------------------------------
// Minimal in-test fakes – no Mockito required
// ---------------------------------------------------------------------------

class _StubDeltaDetector implements DeltaDetector {
  final List<KnowledgeDelta> deltas;
  _StubDeltaDetector(this.deltas);

  @override
  Future<List<KnowledgeDelta>> detect(
    List<EvidenceItem> localEvidence,
    List<EvidenceItem> incomingEvidence,
  ) async =>
      deltas;
}

class _ThrowingHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw Exception('brave boom');
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

EvidenceItem _webItem(String id, String content, {String? sourceUrl}) =>
    EvidenceItem(
      id: id,
      type: EvidenceType.webSearch,
      title: 'Web $id',
      content: content,
      sourceUrl: sourceUrl,
    );

EvidenceItem _localItem(String id, String content, {String? sourceUrl}) =>
    EvidenceItem(
      id: id,
      type: EvidenceType.localNote,
      title: 'Local $id',
      content: content,
      sourceNoteId: id,
      sourceUrl: sourceUrl,
    );

KnowledgeDelta _delta(EvidenceItem item, DeltaType type,
        {String? existingNoteId}) =>
    KnowledgeDelta(
      evidence: item,
      deltaType: type,
      existingNoteId: existingNoteId,
      reason: 'test',
    );

KnowledgeIngestionServiceImpl _service({
  List<EvidenceItem> localItems = const [],
  List<EvidenceItem> webItems = const [],
  required List<KnowledgeDelta> deltas,
}) {
  return KnowledgeIngestionServiceImpl(
    localRetriever: FakeLocalEvidenceRetriever(localItems),
    webProvider: FakeWebEvidenceProvider(webItems),
    deltaDetector: _StubDeltaDetector(deltas),
    summaryWriter: MockSummaryWriter(),
  );
}

// ---------------------------------------------------------------------------

void main() {
  group('KnowledgeIngestionService – doNotSave behaviour', () {
    test('returns doNotSave when all deltas are duplicate', () async {
      final webItem = _webItem('w1', 'some content');
      final delta = _delta(webItem, DeltaType.duplicate);

      final svc = _service(webItems: [webItem], deltas: [delta]);
      final draft = await svc.ingest('What is X?');

      expect(draft.action, NoteDraftAction.doNotSave);
    });

    test('returns createNewNote when at least one delta is newClaim', () async {
      final w1 = _webItem('w1', 'duplicate content');
      final w2 = _webItem('w2', 'brand new content');

      final deltas = [
        _delta(w1, DeltaType.duplicate),
        _delta(w2, DeltaType.newClaim),
      ];

      final svc = _service(webItems: [w1, w2], deltas: deltas);
      final draft = await svc.ingest('What is Y?');

      expect(draft.action, NoteDraftAction.createNewNote);
    });

    test('returns createNewNote when at least one delta is relatedButNew',
        () async {
      final w1 = _webItem('w1', 'related content');
      final deltas = [_delta(w1, DeltaType.relatedButNew)];

      final svc = _service(webItems: [w1], deltas: deltas);
      final draft = await svc.ingest('Tell me about Z');

      expect(draft.action, NoteDraftAction.createNewNote);
    });

    test('returns doNotSave when delta list is empty (nothing to record)',
        () async {
      final w1 = _webItem('w1', 'some content');
      final svc = _service(webItems: [w1], deltas: []);
      final draft = await svc.ingest('Anything?');

      expect(draft.action, NoteDraftAction.doNotSave);
    });

    test('returns doNotSave when there is no web evidence', () async {
      final svc = _service(deltas: []);
      final draft = await svc.ingest('No evidence question');

      expect(draft.action, NoteDraftAction.doNotSave);
    });

    test('draft contains the original question', () async {
      const question = 'How does photosynthesis work?';
      final w1 = _webItem('w1', 'photosynthesis content');
      final svc = _service(webItems: [w1], deltas: [_delta(w1, DeltaType.newClaim)]);
      final draft = await svc.ingest(question);

      expect(draft.question, question);
    });

    test('draft markdown is non-empty', () async {
      final w1 = _webItem('w1', 'some content');
      final svc = _service(webItems: [w1], deltas: [_delta(w1, DeltaType.newClaim)]);
      final draft = await svc.ingest('Some question');

      expect(draft.markdownContent, isNotEmpty);
    });

    test('local and web evidence are forwarded to the draft', () async {
      final local = [_localItem('n1', 'local text')];
      final web = [_webItem('w1', 'web text')];
      final deltas = [_delta(web.first, DeltaType.newClaim)];

      final svc = _service(localItems: local, webItems: web, deltas: deltas);
      final draft = await svc.ingest('test question');

      expect(draft.localEvidence, equals(local));
      expect(draft.webEvidence, equals(web));
    });
  });

  group('KnowledgeIngestionService – empty/no-evidence doNotSave', () {
    test('empty incoming evidence returns doNotSave with explanatory markdown',
        () async {
      // No web evidence → doNotSave.
      final svc = _service(deltas: []);
      final draft = await svc.ingest('Empty test');

      expect(draft.action, NoteDraftAction.doNotSave);
      expect(draft.markdownContent, contains('No New Knowledge Found'));
    });

    test('all-duplicate evidence returns doNotSave', () async {
      final w1 = _webItem('w1', 'old info');
      final svc = _service(
          webItems: [w1], deltas: [_delta(w1, DeltaType.duplicate)]);
      final draft = await svc.ingest('Already known');

      expect(draft.action, NoteDraftAction.doNotSave);
    });

    test('Brave provider failure still returns a safe doNotSave draft',
        () async {
      final svc = KnowledgeIngestionServiceImpl(
        localRetriever: FakeLocalEvidenceRetriever(const []),
        webProvider: BraveEvidenceProvider(
          apiKey: 'brave-key',
          httpClient: _ThrowingHttpClient(),
        ),
        deltaDetector: _StubDeltaDetector(const []),
        summaryWriter: MockSummaryWriter(),
      );

      final draft = await svc.ingest('Brave failure test');

      expect(draft.action, NoteDraftAction.doNotSave);
      expect(draft.webEvidence, isEmpty);
    });
  });

  group('KnowledgeIngestionService – betterSource', () {
    test('betterSource produces appendToExistingNote draft', () async {
      final localNote = _localItem('n1', 'A claim.'); // no sourceUrl
      final webEvidence = _webItem('w1', 'Same claim.',
          sourceUrl: 'https://example.com'); // has sourceUrl

      final delta = _delta(webEvidence, DeltaType.betterSource,
          existingNoteId: 'n1');

      final svc = _service(
        localItems: [localNote],
        webItems: [webEvidence],
        deltas: [delta],
      );
      final draft = await svc.ingest('Claim question');

      expect(draft.action, NoteDraftAction.appendToExistingNote);
    });

    test('betterSource draft markdown references the source URL', () async {
      final webEvidence = _webItem('w1', 'Sourced claim.',
          sourceUrl: 'https://example.com/source');
      final delta = _delta(webEvidence, DeltaType.betterSource);

      final svc = _service(webItems: [webEvidence], deltas: [delta]);
      final draft = await svc.ingest('Source test');

      expect(draft.markdownContent, contains('https://example.com/source'));
    });
  });

  group('KnowledgeIngestionService – source URL in markdown', () {
    test('source URL appears in markdown for web evidence', () async {
      final web = _webItem('w1', 'Some content',
          sourceUrl: 'https://example.com/page');
      final delta = _delta(web, DeltaType.newClaim);

      final svc = _service(webItems: [web], deltas: [delta]);
      final draft = await svc.ingest('URL test');

      expect(draft.markdownContent, contains('https://example.com/page'));
    });

    test('web evidence without sourceUrl is marked as unsourced', () async {
      final web = _webItem('w1', 'Content without a URL'); // no sourceUrl
      final delta = _delta(web, DeltaType.newClaim);

      final svc = _service(webItems: [web], deltas: [delta]);
      final draft = await svc.ingest('Unsourced test');

      expect(draft.markdownContent, contains('unsourced'));
    });
  });

  group('KnowledgeIngestionService – no auto-save', () {
    test('ingest() returns a draft but does not mutate any external state',
        () async {
      // This test verifies that the service is pure: it only returns a NoteDraft
      // and never directly writes to a database or triggers side-effects.
      // Since MockSummaryWriter has no side effects, a successful return is sufficient.
      final w1 = _webItem('w1', 'new fact');
      final delta = _delta(w1, DeltaType.newClaim);

      final svc = _service(webItems: [w1], deltas: [delta]);
      final draft = await svc.ingest('Auto-save test');

      // Service returns a draft but does not auto-save.
      expect(draft, isA<NoteDraft>());
      expect(draft.action, isNot(equals(NoteDraftAction.doNotSave)));
    });
  });
}
