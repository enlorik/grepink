import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/evidence_item.dart';
import 'package:grepink/services/evidence_source_quality.dart';

EvidenceItem _item({
  required String id,
  required EvidenceType type,
  String title = 'Title',
  String content = 'Content',
  String? sourceNoteId,
  String? sourceUrl,
  double relevanceScore = 0.0,
}) {
  return EvidenceItem(
    id: id,
    type: type,
    title: title,
    content: content,
    sourceNoteId: sourceNoteId,
    sourceUrl: sourceUrl,
    relevanceScore: relevanceScore,
  );
}

void main() {
  group('EvidenceSourceQuality', () {
    test('sourced items score above unsourced items', () {
      final sourced = _item(
        id: 'web-sourced',
        type: EvidenceType.webSearch,
        sourceUrl: 'https://example.com',
      );
      final unsourced = _item(
        id: 'web-unsourced',
        type: EvidenceType.webSearch,
        sourceUrl: null,
      );

      expect(
        EvidenceSourceQuality.score(sourced),
        greaterThan(EvidenceSourceQuality.score(unsourced)),
      );
    });

    test('local notes are not treated as web citations', () {
      final localNote = _item(
        id: 'local-1',
        type: EvidenceType.localNote,
        sourceNoteId: 'note-1',
        sourceUrl: 'https://example.com/local-note-source',
      );
      final webResult = _item(
        id: 'web-1',
        type: EvidenceType.webSearch,
        sourceUrl: 'https://example.com/result',
      );

      expect(EvidenceSourceQuality.isWebCitation(localNote), isFalse);
      expect(EvidenceSourceQuality.isWebCitation(webResult), isTrue);
    });

    test('relevanceScore affects ordering', () {
      final lowerRelevance = _item(
        id: 'b-item',
        type: EvidenceType.webSearch,
        sourceUrl: 'https://example.com/lower',
        relevanceScore: 0.2,
      );
      final higherRelevance = _item(
        id: 'a-item',
        type: EvidenceType.webSearch,
        sourceUrl: 'https://example.com/higher',
        relevanceScore: 0.9,
      );

      final items = [lowerRelevance, higherRelevance]..sort(EvidenceSourceQuality.compare);

      expect(items.first.id, 'a-item');
    });

    test('empty content is penalized safely', () {
      final blankContent = _item(
        id: 'blank',
        type: EvidenceType.webSearch,
        content: '   ',
        sourceUrl: 'https://example.com/blank',
      );
      final filledContent = _item(
        id: 'filled',
        type: EvidenceType.webSearch,
        content: 'Useful sourced content',
        sourceUrl: 'https://example.com/filled',
      );

      expect(
        EvidenceSourceQuality.score(blankContent),
        lessThan(EvidenceSourceQuality.score(filledContent)),
      );
    });
  });
}
