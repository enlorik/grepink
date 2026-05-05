import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/evidence_item.dart';
import 'package:grepink/models/knowledge_delta.dart';
import 'package:grepink/services/delta_detector_impl.dart';

EvidenceItem _item(String id, String content) => EvidenceItem(
      id: id,
      type: EvidenceType.webSearch,
      title: 'Test item $id',
      content: content,
    );

EvidenceItem _localItem(String id, String content) => EvidenceItem(
      id: id,
      type: EvidenceType.localNote,
      title: 'Local note $id',
      content: content,
      sourceNoteId: id,
    );

void main() {
  final detector = DeltaDetectorImpl();

  group('DeltaDetectorImpl', () {
    test('exact duplicate is classified as duplicate', () async {
      const text = 'Flutter is a UI toolkit for building natively compiled applications.';
      final local = [_localItem('n1', text)];
      final incoming = [_item('w1', text)];

      final deltas = await detector.detect(local, incoming);

      expect(deltas.length, 1);
      expect(deltas.first.deltaType, DeltaType.duplicate);
    });

    test('high text similarity (>= 90%) is classified as duplicate', () async {
      // 20-word base; nearCopy replaces the last word → Jaccard = 19/21 ≈ 0.905 >= 0.9
      // Strings are NOT character-identical so the exact-duplicate path is bypassed.
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

    test('related content (30–89% overlap) is classified as relatedButNew', () async {
      // 5 shared words out of 15 total unique words → Jaccard = 5/15 ≈ 0.333 >= 0.3
      const localText =
          'apple banana cherry mango grape kiwi peach plum fig date';
      const incomingText =
          'apple banana cherry mango grape papaya lychee starfruit elderberry lime';
      final local = [_localItem('n1', localText)];
      final incoming = [_item('w1', incomingText)];

      final deltas = await detector.detect(local, incoming);

      expect(deltas.first.deltaType, DeltaType.relatedButNew);
    });

    test('unrelated content is classified as newClaim', () async {
      const localText = 'flutter dart mobile development widget tree rendering';
      const incomingText = 'quantum physics photon entanglement superposition collapse';
      final local = [_localItem('n1', localText)];
      final incoming = [_item('w1', incomingText)];

      final deltas = await detector.detect(local, incoming);

      expect(deltas.first.deltaType, DeltaType.newClaim);
    });

    test('new claim when no local evidence exists', () async {
      final deltas = await detector.detect([], [_item('w1', 'Some web fact.')]);

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
}
