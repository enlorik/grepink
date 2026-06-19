import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/claim_deduplication_result.dart';
import 'package:grepink/models/evidence_item.dart';
import 'package:grepink/models/extracted_claim.dart';
import 'package:grepink/services/claim_deduplication_service.dart';

import 'helpers/fake_text_similarity_provider.dart';

ExtractedClaim _claim({
  String id = 'claim-1',
  String text = 'The sky is blue.',
  List<String> citationUrls = const [],
  int order = 0,
}) =>
    ExtractedClaim(
      id: id,
      text: text,
      citationUrls: citationUrls,
      citationTitles: const [],
      sourceAnswerProvider: 'test',
      sourceQuestion: 'What color is the sky?',
      order: order,
    );

EvidenceItem _evidence({
  String id = 'ev-1',
  String content = 'The sky is blue.',
  String? sourceUrl,
}) =>
    EvidenceItem(
      id: id,
      type: EvidenceType.localNote,
      title: 'Note',
      content: content,
      sourceUrl: sourceUrl,
    );

void main() {
  group('TextSimilarityClaimDeduplicationService', () {
    test('exact/similar local content classifies as alreadyKnown', () async {
      final service =
          TextSimilarityClaimDeduplicationService(const FakeTextSimilarityProvider(0.9));

      final results = await service.classify(
        [_claim()],
        [_evidence()],
      );

      expect(results.length, 1);
      expect(results.first.classification, ClaimNoveltyClassification.alreadyKnown);
      expect(results.first.matchedLocalEvidence, isNotEmpty);
    });

    test('no local match classifies as newClaim', () async {
      final service =
          TextSimilarityClaimDeduplicationService(const FakeTextSimilarityProvider(0.1));

      final results = await service.classify(
        [_claim()],
        [_evidence(content: 'Completely unrelated text about biology.')],
      );

      expect(results.length, 1);
      expect(results.first.classification, ClaimNoveltyClassification.newClaim);
    });

    test('empty local evidence classifies claim as newClaim', () async {
      final service =
          TextSimilarityClaimDeduplicationService(const FakeTextSimilarityProvider(0.9));

      final results = await service.classify([_claim()], const []);

      expect(results.length, 1);
      expect(results.first.classification, ClaimNoveltyClassification.newClaim);
      expect(results.first.reason, isNotEmpty);
    });

    test('empty claims list returns empty result', () async {
      final service =
          TextSimilarityClaimDeduplicationService(const FakeTextSimilarityProvider(0.5));

      final results = await service.classify(const [], [_evidence()]);

      expect(results, isEmpty);
    });

    test('local match without source URL + external claim with citation => betterSource',
        () async {
      final service =
          TextSimilarityClaimDeduplicationService(const FakeTextSimilarityProvider(0.9));

      final results = await service.classify(
        [_claim(citationUrls: ['https://example.com/source'])],
        [_evidence(sourceUrl: null)],
      );

      expect(results.first.classification, ClaimNoveltyClassification.betterSource);
    });

    test('local match with source URL + external claim with citation => alreadyKnown',
        () async {
      final service =
          TextSimilarityClaimDeduplicationService(const FakeTextSimilarityProvider(0.9));

      final results = await service.classify(
        [_claim(citationUrls: ['https://example.com/source'])],
        [_evidence(sourceUrl: 'https://local-source.com')],
      );

      expect(results.first.classification, ClaimNoveltyClassification.alreadyKnown);
    });

    test('classification reason is non-empty', () async {
      final service =
          TextSimilarityClaimDeduplicationService(const FakeTextSimilarityProvider(0.8));

      final results = await service.classify([_claim()], [_evidence()]);

      expect(results.first.reason, isNotEmpty);
    });

    test('citation URLs from the claim survive into results', () async {
      final service =
          TextSimilarityClaimDeduplicationService(const FakeTextSimilarityProvider(0.1));
      const urls = ['https://example.com/a', 'https://example.com/b'];

      final results = await service.classify(
        [_claim(citationUrls: urls)],
        [_evidence()],
      );

      expect(results.first.citationUrls, containsAll(urls));
    });

    test('result order matches input claim order', () async {
      final service =
          TextSimilarityClaimDeduplicationService(const FakeTextSimilarityProvider(0.5));

      final claims = [
        _claim(id: 'a', order: 0),
        _claim(id: 'b', order: 1),
        _claim(id: 'c', order: 2),
      ];

      final results = await service.classify(claims, [_evidence()]);

      expect(results.map((r) => r.claim.id).toList(), ['a', 'b', 'c']);
    });

    test('result list is unmodifiable', () async {
      final service =
          TextSimilarityClaimDeduplicationService(const FakeTextSimilarityProvider(0.5));

      final results = await service.classify([_claim()], [_evidence()]);
      final extra = _claim(id: 'extra');

      expect(
        () => results.add(ClaimDeduplicationResult(
          claim: extra,
          classification: ClaimNoveltyClassification.newClaim,
          matchedLocalEvidence: const [],
          reason: 'test',
          citationUrls: const [],
        )),
        throwsUnsupportedError,
      );
    });

    test('classification reason does not contain API key patterns', () async {
      final service =
          TextSimilarityClaimDeduplicationService(const FakeTextSimilarityProvider(0.8));

      final results = await service.classify([_claim()], [_evidence()]);

      for (final result in results) {
        expect(result.reason, isNot(contains('sk-')));
        expect(result.reason, isNot(contains('Bearer ')));
        expect(result.reason, isNot(contains('api_key')));
      }
    });

    test('short claim found verbatim inside a long note classifies as alreadyKnown',
        () async {
      // Without chunking, comparing "The sky is blue." against the full
      // multi-sentence note body would return 0.0 from the exact-match fake
      // (the strings differ). With chunking, one chunk matches exactly → 1.0.
      final service = TextSimilarityClaimDeduplicationService(
          const ExactMatchFakeTextSimilarityProvider());

      const longNote =
          'The ocean is vast. The sky is blue. Clouds form from water vapor.';

      final results = await service.classify(
        [_claim(text: 'The sky is blue.')],
        [_evidence(content: longNote)],
      );

      expect(results.first.classification, ClaimNoveltyClassification.alreadyKnown);
    });

    test('claim not present in any chunk of a long note classifies as newClaim',
        () async {
      final service = TextSimilarityClaimDeduplicationService(
          const ExactMatchFakeTextSimilarityProvider());

      const longNote =
          'The ocean is vast. The sky is blue. Clouds form from water vapor.';

      final results = await service.classify(
        [_claim(text: 'Gravity pulls objects downward.')],
        [_evidence(content: longNote)],
      );

      expect(results.first.classification, ClaimNoveltyClassification.newClaim);
    });

    test(
        'claim URL already present in note content is not classified as betterSource',
        () async {
      // The EvidenceItem.sourceUrl field is null, so a naive check would say
      // "local has no URL — betterSource!" But the citation URL appears in the
      // note body text, meaning the user already has that source. Should be
      // alreadyKnown, not betterSource.
      final service =
          TextSimilarityClaimDeduplicationService(const FakeTextSimilarityProvider(0.9));

      const citationUrl = 'https://example.com/source';
      final results = await service.classify(
        [_claim(citationUrls: [citationUrl])],
        [_evidence(content: 'The sky is blue. See $citationUrl for details.')],
      );

      expect(results.first.classification, ClaimNoveltyClassification.alreadyKnown);
    });

    test('claim found in Markdown bullet list classifies as alreadyKnown', () async {
      // Lines in a bullet list do not end with sentence-ending punctuation, so
      // the sentence-boundary splitter alone leaves the whole list as one chunk.
      // The newline splitter handles this: each bullet becomes its own chunk and
      // the list marker is stripped before comparison.
      final service = TextSimilarityClaimDeduplicationService(
          const ExactMatchFakeTextSimilarityProvider());

      const bulletNote =
          '- The sky is blue\n- Clouds form from water vapor\n- The ocean is vast';

      final results = await service.classify(
        [_claim(text: 'The sky is blue')],
        [_evidence(content: bulletNote)],
      );

      expect(results.first.classification, ClaimNoveltyClassification.alreadyKnown);
    });

    test('claim absent from Markdown bullet list classifies as newClaim', () async {
      final service = TextSimilarityClaimDeduplicationService(
          const ExactMatchFakeTextSimilarityProvider());

      const bulletNote =
          '- The sky is blue\n- Clouds form from water vapor\n- The ocean is vast';

      final results = await service.classify(
        [_claim(text: 'Gravity pulls objects downward')],
        [_evidence(content: bulletNote)],
      );

      expect(results.first.classification, ClaimNoveltyClassification.newClaim);
    });
  });
}
