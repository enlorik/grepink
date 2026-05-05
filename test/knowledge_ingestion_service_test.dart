import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/evidence_item.dart';
import 'package:grepink/models/knowledge_delta.dart';
import 'package:grepink/models/note_draft.dart';
import 'package:grepink/services/delta_detector.dart';
import 'package:grepink/services/knowledge_ingestion_service.dart';
import 'package:grepink/services/local_evidence_retriever.dart';
import 'package:grepink/services/summary_writer.dart';
import 'package:grepink/services/web_evidence_provider.dart';

// ---------------------------------------------------------------------------
// Minimal in-test fakes – no Mockito required
// ---------------------------------------------------------------------------

class _StubLocalRetriever implements LocalEvidenceRetriever {
  final List<EvidenceItem> items;
  _StubLocalRetriever(this.items);

  @override
  Future<List<EvidenceItem>> retrieve(String question) async => items;
}

class _StubWebProvider implements WebEvidenceProvider {
  final List<EvidenceItem> items;
  _StubWebProvider(this.items);

  @override
  Future<List<EvidenceItem>> fetch(String question) async => items;
}

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

// Uses MockSummaryWriter so it honours the doNotSave logic.
EvidenceItem _webItem(String id, String content) => EvidenceItem(
      id: id,
      type: EvidenceType.webSearch,
      title: 'Web $id',
      content: content,
    );

EvidenceItem _localItem(String id, String content) => EvidenceItem(
      id: id,
      type: EvidenceType.localNote,
      title: 'Local $id',
      content: content,
      sourceNoteId: id,
    );

KnowledgeDelta _delta(EvidenceItem item, DeltaType type) => KnowledgeDelta(
      evidence: item,
      deltaType: type,
      reason: 'test',
    );

KnowledgeIngestionServiceImpl _service({
  List<EvidenceItem> localItems = const [],
  List<EvidenceItem> webItems = const [],
  required List<KnowledgeDelta> deltas,
}) {
  return KnowledgeIngestionServiceImpl(
    localRetriever: _StubLocalRetriever(localItems),
    webProvider: _StubWebProvider(webItems),
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

    test('returns createNewNote when at least one delta is relatedButNew', () async {
      final w1 = _webItem('w1', 'related content');
      final deltas = [_delta(w1, DeltaType.relatedButNew)];

      final svc = _service(webItems: [w1], deltas: deltas);
      final draft = await svc.ingest('Tell me about Z');

      expect(draft.action, NoteDraftAction.createNewNote);
    });

    test('returns createNewNote when delta list is empty (no duplicates)', () async {
      final svc = _service(deltas: []);
      final draft = await svc.ingest('Anything?');

      // Empty deltas → not all duplicates → createNewNote
      expect(draft.action, NoteDraftAction.createNewNote);
    });

    test('draft contains the original question', () async {
      const question = 'How does photosynthesis work?';
      final svc = _service(deltas: []);
      final draft = await svc.ingest(question);

      expect(draft.question, question);
    });

    test('draft markdown is non-empty', () async {
      final svc = _service(deltas: []);
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
}
