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

    test('claim with two URLs, both in note content → alreadyKnown', () async {
      final service =
          TextSimilarityClaimDeduplicationService(const FakeTextSimilarityProvider(0.9));

      const urlA = 'https://example.com/a';
      const urlB = 'https://example.com/b';
      final results = await service.classify(
        [_claim(citationUrls: [urlA, urlB])],
        [_evidence(content: 'The sky is blue. See $urlA and $urlB for more.')],
      );

      expect(results.first.classification, ClaimNoveltyClassification.alreadyKnown);
    });

    test('claim with two URLs, only one in note content → betterSource', () async {
      // any() suppression would wrongly mark this alreadyKnown because urlA is
      // present. every() is required: urlB is missing, so betterSource fires.
      final service =
          TextSimilarityClaimDeduplicationService(const FakeTextSimilarityProvider(0.9));

      const urlA = 'https://example.com/a';
      const urlB = 'https://example.com/b';
      final results = await service.classify(
        [_claim(citationUrls: [urlA, urlB])],
        [_evidence(content: 'The sky is blue. See $urlA for more.')],
      );

      expect(results.first.classification, ClaimNoveltyClassification.betterSource);
    });

    test('claim with one URL present in note content → alreadyKnown', () async {
      final service =
          TextSimilarityClaimDeduplicationService(const FakeTextSimilarityProvider(0.9));

      const url = 'https://example.com/source';
      final results = await service.classify(
        [_claim(citationUrls: [url])],
        [_evidence(content: 'The sky is blue. See $url for more.')],
      );

      expect(results.first.classification, ClaimNoveltyClassification.alreadyKnown);
    });

    test('claim with one URL absent from note content → betterSource', () async {
      final service =
          TextSimilarityClaimDeduplicationService(const FakeTextSimilarityProvider(0.9));

      final results = await service.classify(
        [_claim(citationUrls: ['https://example.com/source'])],
        [_evidence(content: 'The sky is blue.')],
      );

      expect(results.first.classification, ClaimNoveltyClassification.betterSource);
    });

    test('identical positive claim and note → alreadyKnown, not contradiction', () async {
      final service =
          TextSimilarityClaimDeduplicationService(const FakeTextSimilarityProvider(0.9));

      final results = await service.classify(
        [_claim(text: 'The sky is blue.')],
        [_evidence(content: 'The sky is blue.')],
      );

      expect(results.first.classification, ClaimNoveltyClassification.alreadyKnown);
    });

    test('negated claim vs positive note → contradiction, not alreadyKnown', () async {
      // High token overlap (4/5 Jaccard) but opposite polarity — must not be
      // silently collapsed into alreadyKnown.
      final service =
          TextSimilarityClaimDeduplicationService(const FakeTextSimilarityProvider(0.9));

      final results = await service.classify(
        [_claim(text: 'The sky is not blue.')],
        [_evidence(content: 'The sky is blue.')],
      );

      expect(results.first.classification, ClaimNoveltyClassification.contradiction);
    });

    test('positive claim vs negated note → contradiction, not alreadyKnown', () async {
      final service =
          TextSimilarityClaimDeduplicationService(const FakeTextSimilarityProvider(0.9));

      final results = await service.classify(
        [_claim(text: 'The sky is blue.')],
        [_evidence(content: 'The sky is not blue.')],
      );

      expect(results.first.classification, ClaimNoveltyClassification.contradiction);
    });

    test('unrelated negated note with low similarity → newClaim, not contradiction',
        () async {
      // Threshold gate must prevent negation logic from running on low-scoring
      // matches — a negative sentence about a completely different topic should
      // never become contradiction just because it contains "not".
      final service =
          TextSimilarityClaimDeduplicationService(const FakeTextSimilarityProvider(0.1));

      final results = await service.classify(
        [_claim(text: 'The sky is blue.')],
        [_evidence(content: 'Bananas are not vegetables.')],
      );

      expect(results.first.classification, ClaimNoveltyClassification.newClaim);
    });

    test("contracted negation isn't vs positive note → contradiction", () async {
      // \b before n't breaks on contractions because the apostrophe is a
      // non-word char — \bn't\b never matches "isn't". The fix drops the
      // leading \b so n't matches inside any contraction.
      final service =
          TextSimilarityClaimDeduplicationService(const FakeTextSimilarityProvider(0.9));

      final results = await service.classify(
        [_claim(text: "The sky isn't blue.")],
        [_evidence(content: 'The sky is blue.')],
      );

      expect(results.first.classification, ClaimNoveltyClassification.contradiction);
    });

    test("contracted negation doesn't vs positive note → contradiction", () async {
      final service =
          TextSimilarityClaimDeduplicationService(const FakeTextSimilarityProvider(0.9));

      final results = await service.classify(
        [_claim(text: "The sky doesn't look blue.")],
        [_evidence(content: 'The sky looks blue.')],
      );

      expect(results.first.classification, ClaimNoveltyClassification.contradiction);
    });

    test('non-negated identical claim still classifies as alreadyKnown', () async {
      final service =
          TextSimilarityClaimDeduplicationService(const FakeTextSimilarityProvider(0.9));

      final results = await service.classify(
        [_claim(text: 'The sky is blue.')],
        [_evidence(content: 'The sky is blue.')],
      );

      expect(results.first.classification, ClaimNoveltyClassification.alreadyKnown);
    });

    test('differing numeric values → contradiction, not alreadyKnown', () async {
      // "$10 million" vs "$12 million" — high Jaccard overlap because most tokens
      // match, but the key fact differs. Must not be collapsed into alreadyKnown.
      final service =
          TextSimilarityClaimDeduplicationService(const FakeTextSimilarityProvider(0.9));

      final results = await service.classify(
        [_claim(text: 'Revenue was \$10 million in 2024.')],
        [_evidence(content: 'Revenue was \$12 million in 2024.')],
      );

      expect(results.first.classification, ClaimNoveltyClassification.contradiction);
    });

    test('identical numeric values → alreadyKnown, not contradiction', () async {
      final service =
          TextSimilarityClaimDeduplicationService(const FakeTextSimilarityProvider(0.9));

      final results = await service.classify(
        [_claim(text: 'Revenue was \$10 million in 2024.')],
        [_evidence(content: 'Revenue was \$10 million in 2024.')],
      );

      expect(results.first.classification, ClaimNoveltyClassification.alreadyKnown);
    });

    test('differing population numbers → contradiction', () async {
      final service =
          TextSimilarityClaimDeduplicationService(const FakeTextSimilarityProvider(0.9));

      final results = await service.classify(
        [_claim(text: 'Population was 5 million.')],
        [_evidence(content: 'Population was 6 million.')],
      );

      expect(results.first.classification, ClaimNoveltyClassification.contradiction);
    });

    test('numeric claim with low similarity → newClaim, not contradiction', () async {
      final service =
          TextSimilarityClaimDeduplicationService(const FakeTextSimilarityProvider(0.1));

      final results = await service.classify(
        [_claim(text: 'Revenue was \$10 million.')],
        [_evidence(content: 'Population was 6 million.')],
      );

      expect(results.first.classification, ClaimNoveltyClassification.newClaim);
    });

    test('numeric claim ending in period vs same without period → alreadyKnown',
        () async {
      // "2024." and "2024" must normalise to the same token so sentence-final
      // punctuation does not falsely trigger a numeric conflict.
      final service =
          TextSimilarityClaimDeduplicationService(const FakeTextSimilarityProvider(0.9));

      final results = await service.classify(
        [_claim(text: 'Revenue was \$10 million in 2024.')],
        [_evidence(content: 'Revenue was \$10 million in 2024')],
      );

      expect(results.first.classification, ClaimNoveltyClassification.alreadyKnown);
    });

    test('decimal percentage preserved across period-terminated and plain forms → alreadyKnown',
        () async {
      // "10.5%" must remain "10.5%" after normalisation — the dot is part of the
      // number, not sentence-ending punctuation.
      final service =
          TextSimilarityClaimDeduplicationService(const FakeTextSimilarityProvider(0.9));

      final results = await service.classify(
        [_claim(text: 'Growth rate was 10.5%.')],
        [_evidence(content: 'Growth rate was 10.5%.')],
      );

      expect(results.first.classification, ClaimNoveltyClassification.alreadyKnown);
    });

    test('differing dollar amounts with trailing periods → contradiction', () async {
      // Even after stripping trailing punctuation the amounts differ (\$10 vs
      // \$12), so this must still fire as contradiction.
      final service =
          TextSimilarityClaimDeduplicationService(const FakeTextSimilarityProvider(0.9));

      final results = await service.classify(
        [_claim(text: 'Revenue was \$10 million.')],
        [_evidence(content: 'Revenue was \$12 million.')],
      );

      expect(results.first.classification, ClaimNoveltyClassification.contradiction);
    });

    test('year with trailing period normalises correctly → alreadyKnown', () async {
      final service =
          TextSimilarityClaimDeduplicationService(const FakeTextSimilarityProvider(0.9));

      final results = await service.classify(
        [_claim(text: 'The policy was adopted in 2019.')],
        [_evidence(content: 'The policy was adopted in 2019')],
      );

      expect(results.first.classification, ClaimNoveltyClassification.alreadyKnown);
    });
  });
}
