import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/evidence_item.dart';
import 'package:grepink/models/knowledge_delta.dart';
import 'package:grepink/services/delta_detector_impl.dart';
import 'helpers/fake_text_similarity_provider.dart';

EvidenceItem _item(
  String id,
  String content, {
  String? sourceUrl,
}) =>
    EvidenceItem(
      id: id,
      type: EvidenceType.webSearch,
      title: 'Test item $id',
      content: content,
      sourceUrl: sourceUrl,
    );

EvidenceItem _localItem(
  String id,
  String content, {
  String? sourceUrl,
}) =>
    EvidenceItem(
      id: id,
      type: EvidenceType.localNote,
      title: 'Local note $id',
      content: content,
      sourceNoteId: id,
      sourceUrl: sourceUrl,
    );

void main() {
  group('DeltaDetectorImpl – Jaccard (default provider)', () {
    final detector = DeltaDetectorImpl();

    test('exact duplicate is classified as duplicate', () async {
      const text =
          'Flutter is a UI toolkit for building natively compiled applications.';
      final local = [_localItem('n1', text)];
      final incoming = [_item('w1', text)];

      final deltas = await detector.detect(local, incoming);

      expect(deltas.length, 1);
      expect(deltas.first.deltaType, DeltaType.duplicate);
    });

    test('near-identical text (Jaccard ≈ 0.905 ≥ 0.88) is classified as duplicate',
        () async {
      // 20-word base; nearCopy replaces the last word → Jaccard = 19/21 ≈ 0.905.
      const base =
          'one two three four five six seven eight nine ten '
          'eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty';
      const nearCopy =
          'one two three four five six seven eight nine ten '
          'eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twentyone';
      final local = [_localItem('n1', base)];
      final incoming = [_item('w1', nearCopy)];

      final deltas = await detector.detect(local, incoming);

      expect(deltas.first.deltaType, DeltaType.duplicate);
    });

    test('unrelated content is classified as newClaim', () async {
      const localText =
          'flutter dart mobile development widget tree rendering';
      const incomingText =
          'quantum physics photon entanglement superposition collapse';
      final local = [_localItem('n1', localText)];
      final incoming = [_item('w1', incomingText)];

      final deltas = await detector.detect(local, incoming);

      expect(deltas.first.deltaType, DeltaType.newClaim);
    });

    test('new claim when no local evidence exists', () async {
      final deltas =
          await detector.detect([], [_item('w1', 'Some web fact.')]);

      expect(deltas.first.deltaType, DeltaType.newClaim);
    });

    test('isExactDuplicate returns true for matching text', () {
      expect(
        detector.isExactDuplicate('Hello World', ['hello world', 'other']),
        isTrue,
      );
    });

    test('isExactDuplicate returns false when no match', () {
      expect(
        detector.isExactDuplicate('unique text', ['different', 'other']),
        isFalse,
      );
    });

    test('jaccardSimilarity returns 1.0 for identical texts', () {
      final score = detector.jaccardSimilarity('hello world', 'hello world');
      expect(score, closeTo(1.0, 0.001));
    });

    test('jaccardSimilarity returns 0.0 for completely different texts', () {
      final score = detector.jaccardSimilarity('alpha beta', 'gamma delta');
      expect(score, closeTo(0.0, 0.001));
    });
  });

  // ---------------------------------------------------------------------------
  // Fake-provider tests (meaning-aware scenarios)
  // ---------------------------------------------------------------------------

  group('DeltaDetectorImpl – FakeTextSimilarityProvider', () {
    EvidenceItem localNote(String id, String content, {String? sourceUrl}) =>
        _localItem(id, content, sourceUrl: sourceUrl);

    EvidenceItem webItem(String id, String content, {String? sourceUrl}) =>
        _item(id, content, sourceUrl: sourceUrl);

    test('same meaning with different words (score 0.91) becomes duplicate',
        () async {
      final detector =
          DeltaDetectorImpl(similarityProvider: const FakeTextSimilarityProvider(0.91));
      final local = [localNote('n1', 'Original phrasing of a concept.')];
      final incoming = [webItem('w1', 'Completely different words, same idea.')];

      final deltas = await detector.detect(local, incoming);

      expect(deltas.first.deltaType, DeltaType.duplicate);
      expect(deltas.first.bestSimilarityScore, closeTo(0.91, 0.001));
    });

    test('same topic but new detail (score 0.75) becomes relatedButNew',
        () async {
      final detector =
          DeltaDetectorImpl(similarityProvider: const FakeTextSimilarityProvider(0.75));
      final local = [localNote('n1', 'Topic overview.')];
      final incoming = [webItem('w1', 'Topic overview with one new detail.')];

      final deltas = await detector.detect(local, incoming);

      expect(deltas.first.deltaType, DeltaType.relatedButNew);
      expect(deltas.first.bestSimilarityScore, closeTo(0.75, 0.001));
    });

    test('unrelated item (score 0.20) becomes newClaim', () async {
      final detector =
          DeltaDetectorImpl(similarityProvider: const FakeTextSimilarityProvider(0.20));
      final local = [localNote('n1', 'Flutter widgets.')];
      final incoming = [webItem('w1', 'Quantum entanglement.')];

      final deltas = await detector.detect(local, incoming);

      expect(deltas.first.deltaType, DeltaType.newClaim);
      expect(deltas.first.bestSimilarityScore, closeTo(0.20, 0.001));
    });

    test(
        'betterSource: incoming has sourceUrl, matching local note has none, '
        'score 0.91 → betterSource', () async {
      final detector =
          DeltaDetectorImpl(similarityProvider: const FakeTextSimilarityProvider(0.91));
      final local = [localNote('n1', 'Some claim without a source.')];
      final incoming = [
        webItem('w1', 'Same claim with a source.',
            sourceUrl: 'https://example.com/source')
      ];

      final deltas = await detector.detect(local, incoming);

      expect(deltas.first.deltaType, DeltaType.betterSource);
      expect(deltas.first.existingNoteId, 'n1');
    });

    test(
        'duplicate (not betterSource) when both incoming and local have no sourceUrl',
        () async {
      final detector =
          DeltaDetectorImpl(similarityProvider: const FakeTextSimilarityProvider(0.92));
      final local = [localNote('n1', 'Claim without source.')];
      final incoming = [webItem('w1', 'Same claim, no source either.')];

      final deltas = await detector.detect(local, incoming);

      expect(deltas.first.deltaType, DeltaType.duplicate);
    });

    test(
        'betterSource on exact text match: incoming has url, local has none',
        () async {
      const sharedText = 'The speed of light is approximately 299,792 km/s.';
      final detector = DeltaDetectorImpl();
      final local = [localNote('n1', sharedText)];
      final incoming = [
        webItem('w1', sharedText, sourceUrl: 'https://physics.org/speed')
      ];

      final deltas = await detector.detect(local, incoming);

      expect(deltas.first.deltaType, DeltaType.betterSource);
      expect(deltas.first.existingNoteId, 'n1');
    });
  });

  // ---------------------------------------------------------------------------
  // Chunking tests
  // ---------------------------------------------------------------------------

  group('DeltaDetectorImpl – chunking finds relevant paragraph', () {
    test('relevant paragraph inside a long note is matched', () async {
      // The long note has an irrelevant intro + a paragraph matching the query.
      const intro = 'This note is about cooking. '
          'We will discuss baking bread, preparing soups, '
          'and various kitchen techniques that every cook should know. '
          'The art of cooking requires patience and practice.';
      const relevantParagraph =
          'Photosynthesis is the process by which plants convert sunlight '
          'into chemical energy. Chlorophyll absorbs light and drives the '
          'conversion of carbon dioxide and water into glucose and oxygen.';
      final longNoteContent = '$intro\n\n$relevantParagraph';

      // The fake score of 0.91 simulates embedding similarity finding the right paragraph.
      final detector =
          DeltaDetectorImpl(similarityProvider: const FakeTextSimilarityProvider(0.91));
      final local = [_localItem('n1', longNoteContent)];
      final incoming = [
        _item('w1', 'Plants use sunlight to make glucose through photosynthesis.')
      ];

      final deltas = await detector.detect(local, incoming);

      // The detector should find the relevant chunk and classify as duplicate.
      expect(deltas.first.deltaType, DeltaType.duplicate);
    });
  });
}
