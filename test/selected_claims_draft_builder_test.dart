import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/claim_deduplication_result.dart';
import 'package:grepink/models/claim_review_item.dart';
import 'package:grepink/models/grounded_answer.dart';
import 'package:grepink/services/selected_claims_draft_builder.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

ClaimReviewItem _item({
  String id = 'item-1',
  String text = 'A claim.',
  ClaimNoveltyClassification classification = ClaimNoveltyClassification.newClaim,
  List<String> citationUrls = const [],
  List<String> citationTitles = const [],
  bool canBeSaved = true,
  bool selectedByDefault = true,
}) =>
    ClaimReviewItem(
      id: id,
      text: text,
      classification: classification,
      citationUrls: citationUrls,
      citationTitles: citationTitles,
      selectedByDefault: selectedByDefault,
      reason: 'test',
      matchedLocalEvidenceIds: const [],
      canBeSaved: canBeSaved,
    );

GroundedAnswerCitation _citation(String id, String url, String title) =>
    GroundedAnswerCitation(id: id, title: title, url: url);

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  const builder = SelectedClaimsDraftBuilder();

  group('SelectedClaimsDraftBuilder', () {
    test('selected new claims appear in markdown', () {
      final result = builder.build(
        question: 'What is gravity?',
        selected: [_item(text: 'Gravity is a force.', citationUrls: [])],
        providerName: 'test',
        citations: const [],
      );

      expect(result.markdownContent, contains('Gravity is a force.'));
      expect(result.shouldSave, isTrue);
    });

    test('unselected/unsaveable known claims do not appear', () {
      final result = builder.build(
        question: 'What is gravity?',
        selected: [
          _item(
            id: 'known1',
            text: 'Already known fact.',
            classification: ClaimNoveltyClassification.alreadyKnown,
            canBeSaved: false,
          ),
        ],
        providerName: 'test',
        citations: const [],
      );

      expect(result.shouldSave, isFalse);
      expect(result.markdownContent, isEmpty);
    });

    test('selected better-source claims appear with URL', () {
      const url = 'https://better-source.com';
      final result = builder.build(
        question: 'What is gravity?',
        selected: [
          _item(
            text: 'Gravity is well studied.',
            classification: ClaimNoveltyClassification.betterSource,
            citationUrls: [url],
          ),
        ],
        providerName: 'test',
        citations: [_citation('c1', url, 'Better Source')],
      );

      expect(result.markdownContent, contains('Gravity is well studied.'));
      expect(result.markdownContent, contains(url));
    });

    test('source URLs survive into Sources section', () {
      const url = 'https://example.com/a';
      final result = builder.build(
        question: 'q',
        selected: [_item(citationUrls: [url])],
        providerName: 'test',
        citations: [_citation('c1', url, 'Example')],
      );

      expect(result.markdownContent, contains(url));
      expect(result.markdownContent, contains('## Sources'));
    });

    test('duplicate source URLs are deduplicated in Sources section', () {
      const url = 'https://same-source.com';
      final result = builder.build(
        question: 'q',
        selected: [
          _item(id: 'i1', text: 'Claim one.', citationUrls: [url]),
          _item(id: 'i2', text: 'Claim two.', citationUrls: [url]),
        ],
        providerName: 'test',
        citations: [_citation('c1', url, 'Same Source')],
      );

      // URL appears once in each claim inline link + once in Sources = multiple,
      // but the Sources section should list it only once.
      final sourcesSection = result.markdownContent
          .split('## Sources')
          .last;
      final sourcesOccurrences = url.allMatches(sourcesSection).length;
      expect(sourcesOccurrences, 1);
      expect(result.sourceCount, 1);
    });

    test('empty selection returns empty/doNotSave result', () {
      final result = builder.build(
        question: 'q',
        selected: const [],
        providerName: 'test',
        citations: const [],
      );

      expect(result.shouldSave, isFalse);
      expect(result.markdownContent, isEmpty);
    });

    test('markdown does not include raw full answer content beyond selected claims', () {
      final result = builder.build(
        question: 'What is gravity?',
        selected: [_item(text: 'Gravity pulls objects.')],
        providerName: 'test',
        citations: const [],
      );

      // Should only contain the selected claim, not any extra answer text.
      expect(result.markdownContent, contains('Gravity pulls objects.'));
      expect(result.markdownContent.split('Gravity pulls objects.').length, 2);
    });

    test('markdown does not include API keys or secrets', () {
      final result = builder.build(
        question: 'What is gravity?',
        selected: [_item(text: 'Normal claim text.')],
        providerName: 'safe-provider',
        citations: const [],
      );

      expect(result.markdownContent, isNot(contains('sk-')));
      expect(result.markdownContent, isNot(contains('Bearer ')));
      expect(result.markdownContent, isNot(contains('api_key')));
    });

    test('output is valid when citation title is missing (URL used as fallback)', () {
      const url = 'https://no-title.com';
      final result = builder.build(
        question: 'q',
        selected: [_item(citationUrls: [url])],
        providerName: 'test',
        citations: [_citation('c1', url, '')],
      );

      expect(result.markdownContent, contains(url));
      expect(result.markdownContent, isNotEmpty);
    });

    test('output is valid when URL is missing but claim was selected', () {
      final result = builder.build(
        question: 'q',
        selected: [_item(text: 'Claim without URL.', citationUrls: [])],
        providerName: 'test',
        citations: const [],
      );

      expect(result.shouldSave, isTrue);
      expect(result.markdownContent, contains('Claim without URL.'));
    });

    test('question is used as markdown title', () {
      final result = builder.build(
        question: 'What is photosynthesis?',
        selected: [_item(text: 'Plants use sunlight.')],
        providerName: 'test',
        citations: const [],
      );

      expect(result.markdownContent, contains('# What is photosynthesis?'));
    });

    test('sourceCount reflects deduplicated URL count', () {
      final result = builder.build(
        question: 'q',
        selected: [
          _item(id: 'a', citationUrls: ['https://a.com', 'https://b.com']),
          _item(id: 'b', citationUrls: ['https://a.com']),
        ],
        providerName: 'test',
        citations: [
          _citation('c1', 'https://a.com', 'A'),
          _citation('c2', 'https://b.com', 'B'),
        ],
      );

      expect(result.sourceCount, 2);
    });

    // ─── Claim-level citation title fallback ──────────────────────────────────

    test('claim-level title is used when URL is absent from provider citations', () {
      const url = 'https://claim-only.example.com';
      const claimTitle = 'Claim Only Source';
      final result = builder.build(
        question: 'q',
        selected: [
          _item(citationUrls: [url], citationTitles: [claimTitle]),
        ],
        providerName: 'test',
        citations: const [], // URL not present in provider citations
      );

      expect(result.markdownContent, contains('$claimTitle — $url'));
    });

    test('provider-level title wins over a conflicting claim-level title', () {
      const url = 'https://shared.example.com';
      const providerTitle = 'Provider Title';
      const claimTitle = 'Claim Title';
      final result = builder.build(
        question: 'q',
        selected: [
          _item(citationUrls: [url], citationTitles: [claimTitle]),
        ],
        providerName: 'test',
        citations: [_citation('c1', url, providerTitle)],
      );

      expect(result.markdownContent, contains('$providerTitle — $url'));
      expect(result.markdownContent, isNot(contains(claimTitle)));
    });

    test('missing or empty claim title falls back to the bare URL', () {
      const url = 'https://no-title.example.com';
      final result = builder.build(
        question: 'q',
        selected: [
          _item(citationUrls: [url], citationTitles: ['']),
        ],
        providerName: 'test',
        citations: [_citation('c1', url, '')], // empty provider title too
      );

      expect(result.markdownContent, contains('$url — $url'));
    });

    test('citationTitles shorter than citationUrls does not throw', () {
      const url1 = 'https://a.example.com';
      const url2 = 'https://b.example.com';
      final result = builder.build(
        question: 'q',
        selected: [
          _item(
            citationUrls: [url1, url2],
            citationTitles: ['Title A'], // only one title for two URLs
          ),
        ],
        providerName: 'test',
        citations: const [],
      );

      // Must not throw; the titled URL uses its title, the untitled URL falls back.
      expect(result.shouldSave, isTrue);
      expect(result.markdownContent, contains('Title A — $url1'));
      expect(result.markdownContent, contains('$url2 — $url2'));
    });

    test('duplicate URLs across claims remain listed once in Sources with claim title', () {
      const url = 'https://shared-claim.example.com';
      const claimTitle = 'Shared Claim Source';
      final result = builder.build(
        question: 'q',
        selected: [
          _item(id: 'i1', text: 'Claim one.', citationUrls: [url], citationTitles: [claimTitle]),
          _item(id: 'i2', text: 'Claim two.', citationUrls: [url], citationTitles: [claimTitle]),
        ],
        providerName: 'test',
        citations: const [],
      );

      final sourcesSection = result.markdownContent.split('## Sources').last;
      expect(url.allMatches(sourcesSection).length, 1);
      expect(result.sourceCount, 1);
    });

    test('sourceCount is deduplicated when claim-level titles are mixed', () {
      final result = builder.build(
        question: 'q',
        selected: [
          _item(
            id: 'a',
            citationUrls: ['https://x.com', 'https://y.com'],
            citationTitles: ['X', 'Y'],
          ),
          _item(
            id: 'b',
            citationUrls: ['https://x.com'],
            citationTitles: ['X Duplicate'],
          ),
        ],
        providerName: 'test',
        citations: const [],
      );

      expect(result.sourceCount, 2);
    });
  });
}
