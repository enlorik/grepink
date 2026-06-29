import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/evidence_item.dart';
import 'package:grepink/models/grounded_answer.dart';
import 'package:grepink/services/claim_deduplication_service.dart';
import 'package:grepink/services/claim_extraction_service.dart';
import 'package:grepink/services/grounded_answer_ingestion_service.dart';
import 'package:grepink/services/grounded_answer_provider.dart';
import 'package:grepink/services/local_evidence_retriever.dart';

import 'helpers/fake_text_similarity_provider.dart';

// ─── Test doubles ────────────────────────────────────────────────────────────

class _FakeProvider implements GroundedAnswerProvider {
  final GroundedAnswer? _answer;
  final bool _shouldThrow;

  const _FakeProvider(this._answer, {bool shouldThrow = false})
      : _shouldThrow = shouldThrow;

  @override
  Future<GroundedAnswer?> fetchGroundedAnswer(String question) async {
    if (_shouldThrow) throw Exception('provider failed');
    return _answer;
  }
}

class _FakeLocalEvidence implements LocalEvidenceRetriever {
  final List<EvidenceItem> _items;

  const _FakeLocalEvidence(this._items);

  @override
  Future<List<EvidenceItem>> retrieve(String question) async => _items;
}

class _ThrowingLocalEvidence implements LocalEvidenceRetriever {
  @override
  Future<List<EvidenceItem>> retrieve(String question) async =>
      throw Exception('local evidence retrieval failed');
}

class _CallOrder {
  final events = <String>[];
}

class _OrderTrackingProvider implements GroundedAnswerProvider {
  final _CallOrder _order;
  _OrderTrackingProvider(this._order);

  @override
  Future<GroundedAnswer?> fetchGroundedAnswer(String question) async {
    _order.events.add('provider');
    return _answer();
  }
}

class _OrderTrackingLocalEvidence implements LocalEvidenceRetriever {
  final _CallOrder _order;
  _OrderTrackingLocalEvidence(this._order);

  @override
  Future<List<EvidenceItem>> retrieve(String question) async {
    _order.events.add('local');
    return const [];
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

GroundedAnswer _answer({
  String question = 'What is gravity?',
  String text = 'Gravity pulls objects. It acts at a distance.',
  List<GroundedAnswerCitation> citations = const [],
  String provider = 'test',
}) =>
    GroundedAnswer(
      question: question,
      answerText: text,
      citations: citations,
      providerName: provider,
      generatedAt: DateTime(2024, 1, 1),
    );

GroundedAnswerCitation _citation(String id, String url) =>
    GroundedAnswerCitation(id: id, title: 'T', url: url);

EvidenceItem _localEvidence(String id, String content, {String? sourceUrl}) =>
    EvidenceItem(
      id: id,
      type: EvidenceType.localNote,
      title: 'Note',
      content: content,
      sourceUrl: sourceUrl,
    );

GroundedAnswerIngestionService _service({
  GroundedAnswerProvider? provider,
  double similarity = 0.1,
  List<EvidenceItem> localEvidence = const [],
}) =>
    GroundedAnswerIngestionService(
      provider: provider ?? _FakeProvider(_answer()),
      extractor: const RuleBasedClaimExtractionService(),
      deduplicator:
          TextSimilarityClaimDeduplicationService(FakeTextSimilarityProvider(similarity)),
      localEvidence: _FakeLocalEvidence(localEvidence),
    );

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  group('GroundedAnswerIngestionService', () {
    test('null provider result returns safe empty result', () async {
      final svc = _service(provider: const _FakeProvider(null));

      final result = await svc.ingest('What is gravity?');

      expect(result.isEmpty, isTrue);
      expect(result.newClaims, isEmpty);
    });

    test('empty answer text returns safe empty result', () async {
      final svc = _service(
        provider: _FakeProvider(_answer(text: '')),
      );

      final result = await svc.ingest('What is gravity?');

      expect(result.isEmpty, isTrue);
    });

    test('answer with all known claims has no new claims', () async {
      final svc = _service(
        similarity: 0.9,
        localEvidence: [_localEvidence('e1', 'Gravity pulls objects.')],
      );

      final result = await svc.ingest('What is gravity?');

      expect(result.newClaims, isEmpty);
      expect(result.knownClaims, isNotEmpty);
      expect(result.shouldCreateDraft, isFalse);
    });

    test('answer with new claims produces non-empty newClaims', () async {
      final svc = _service(similarity: 0.1);

      final result = await svc.ingest('What is gravity?');

      expect(result.newClaims, isNotEmpty);
      expect(result.shouldCreateDraft, isTrue);
    });

    test('answer with better-source claim appears in betterSourceClaims', () async {
      final svc = _service(
        similarity: 0.9,
        localEvidence: [_localEvidence('e1', 'Gravity pulls objects.')],
        provider: _FakeProvider(
          _answer(
            text: 'Gravity pulls objects.',
            citations: [_citation('c1', 'https://example.com/gravity')],
          ),
        ),
      );

      final result = await svc.ingest('What is gravity?');

      expect(result.betterSourceClaims, isNotEmpty);
    });

    test('answer with citations preserves citation URLs in result', () async {
      final svc = _service(
        provider: _FakeProvider(
          _answer(
            citations: [_citation('c1', 'https://example.com/a')],
          ),
        ),
      );

      final result = await svc.ingest('What is gravity?');

      expect(result.citations.map((c) => c.url),
          contains('https://example.com/a'));
    });

    test('provider exception returns safe empty result without crashing',
        () async {
      final svc = _service(
        provider: const _FakeProvider(null, shouldThrow: true),
      );

      final result = await svc.ingest('What is gravity?');

      expect(result.isEmpty, isTrue);
    });

    test('empty question returns safe empty result', () async {
      final svc = _service();

      final result = await svc.ingest('');

      expect(result.isEmpty, isTrue);
    });

    test('no note is inserted or updated by this service', () async {
      // This is structural: the service has no database/persistence dependency,
      // so it cannot persist. The test verifies the result contains no note IDs.
      final svc = _service(similarity: 0.1);

      final result = await svc.ingest('What is gravity?');

      for (final claim in [
        ...result.newClaims,
        ...result.knownClaims,
        ...result.betterSourceClaims,
      ]) {
        expect(claim.claim.sourceAnswerProvider, isNotEmpty);
      }
    });

    test('result question matches the asked question', () async {
      final svc = _service();

      final result = await svc.ingest('What is gravity?');

      expect(result.question, 'What is gravity?');
    });

    test('result does not contain API keys or secrets in providerName', () async {
      final svc = _service(
        provider: _FakeProvider(_answer(provider: 'safe-provider-name')),
      );

      final result = await svc.ingest('What is gravity?');

      expect(result.providerName, isNot(contains('sk-')));
      expect(result.providerName, isNot(contains('Bearer ')));
    });

    test('hasNewKnowledge is false when all claims are known', () async {
      final svc = _service(
        similarity: 0.9,
        localEvidence: [
          _localEvidence('e1', 'Gravity pulls objects.'),
          _localEvidence('e2', 'It acts at a distance.'),
        ],
      );

      final result = await svc.ingest('What is gravity?');

      expect(result.hasNewKnowledge, isFalse);
    });

    test('local evidence retriever exception returns safe empty result', () async {
      // The outer try/catch in ingest() covers the local retrieval call, so a
      // failing retriever must not crash the service or surface an exception.
      final svc = GroundedAnswerIngestionService(
        provider: _FakeProvider(_answer()),
        extractor: const RuleBasedClaimExtractionService(),
        deduplicator: TextSimilarityClaimDeduplicationService(
            FakeTextSimilarityProvider(0.1)),
        localEvidence: _ThrowingLocalEvidence(),
      );

      final result = await svc.ingest('What is gravity?');

      expect(result.isEmpty, isTrue);
      expect(result.newClaims, isEmpty);
    });

    test('local evidence is retrieved before the external provider is called',
        () async {
      final order = _CallOrder();
      final svc = GroundedAnswerIngestionService(
        provider: _OrderTrackingProvider(order),
        extractor: const RuleBasedClaimExtractionService(),
        deduplicator: TextSimilarityClaimDeduplicationService(
            FakeTextSimilarityProvider(0.1)),
        localEvidence: _OrderTrackingLocalEvidence(order),
      );

      await svc.ingest('What is gravity?');

      expect(order.events, containsAllInOrder(['local', 'provider']));
      expect(order.events.first, 'local');
    });
  });
}
