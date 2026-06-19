import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/extracted_claim.dart';
import 'package:grepink/models/grounded_answer.dart';
import 'package:grepink/services/claim_extraction_service.dart';

GroundedAnswer _answer({
  String question = 'What is photosynthesis?',
  String answerText = '',
  List<GroundedAnswerCitation> citations = const [],
  String provider = 'test-provider',
}) =>
    GroundedAnswer(
      question: question,
      answerText: answerText,
      citations: citations,
      providerName: provider,
      generatedAt: DateTime(2024, 1, 1),
    );

GroundedAnswerCitation _citation(String id, String url, String title) =>
    GroundedAnswerCitation(id: id, title: title, url: url);

void main() {
  const service = RuleBasedClaimExtractionService();

  group('RuleBasedClaimExtractionService', () {
    test('extracts multiple claims from a multi-sentence answer', () {
      final answer = _answer(
        answerText: 'Plants use sunlight to make food. '
            'This process is called photosynthesis. '
            'Chlorophyll captures light energy.',
      );

      final claims = service.extract(answer);

      expect(claims.length, 3);
      expect(claims[0].text, 'Plants use sunlight to make food.');
      expect(claims[1].text, 'This process is called photosynthesis.');
      expect(claims[2].text, 'Chlorophyll captures light energy.');
    });

    test('preserves claim order', () {
      final answer = _answer(
        answerText: 'First sentence. Second sentence. Third sentence.',
      );

      final claims = service.extract(answer);

      expect(claims.map((c) => c.order).toList(), [0, 1, 2]);
    });

    test('ignores empty sentences and whitespace-only segments', () {
      final answer = _answer(
        answerText: 'Valid claim.   ',
      );

      final claims = service.extract(answer);

      expect(claims.length, 1);
      expect(claims.first.text, 'Valid claim.');
    });

    test('deduplicates exact repeated claim text', () {
      final answer = _answer(
        answerText: 'Same claim. Same claim. Different claim.',
      );

      final claims = service.extract(answer);

      expect(claims.length, 2);
      expect(claims[0].text, 'Same claim.');
      expect(claims[1].text, 'Different claim.');
    });

    test('preserves citation URLs from the answer', () {
      final answer = _answer(
        answerText: 'Claim one. Claim two.',
        citations: [
          _citation('c1', 'https://example.com/a', 'Source A'),
          _citation('c2', 'https://example.com/b', 'Source B'),
        ],
      );

      final claims = service.extract(answer);

      for (final claim in claims) {
        expect(claim.citationUrls, containsAll(['https://example.com/a', 'https://example.com/b']));
        expect(claim.citationTitles, containsAll(['Source A', 'Source B']));
      }
    });

    test('handles answer with no citations', () {
      final answer = _answer(answerText: 'A claim without citations.');

      final claims = service.extract(answer);

      expect(claims.length, 1);
      expect(claims.first.citationUrls, isEmpty);
      expect(claims.first.citationTitles, isEmpty);
    });

    test('returns empty list for empty answer text', () {
      final answer = _answer(answerText: '');

      final claims = service.extract(answer);

      expect(claims, isEmpty);
    });

    test('returns empty list for whitespace-only answer text', () {
      final answer = _answer(answerText: '   \n  ');

      final claims = service.extract(answer);

      expect(claims, isEmpty);
    });

    test('does not mutate the original GroundedAnswer', () {
      final citations = [_citation('c1', 'https://example.com', 'Example')];
      final answer = _answer(
        answerText: 'A claim.',
        citations: citations,
      );

      final before = answer.answerText;
      final beforeCount = answer.citations.length;

      service.extract(answer);

      expect(answer.answerText, before);
      expect(answer.citations.length, beforeCount);
    });

    test('claim sourceAnswerProvider and sourceQuestion match the answer', () {
      final answer = _answer(
        question: 'What is gravity?',
        answerText: 'Gravity pulls objects together.',
        provider: 'my-provider',
      );

      final claims = service.extract(answer);

      expect(claims.first.sourceAnswerProvider, 'my-provider');
      expect(claims.first.sourceQuestion, 'What is gravity?');
    });

    test('claim ids are unique within the same answer', () {
      final answer = _answer(
        answerText: 'Alpha claim. Beta claim. Gamma claim.',
      );

      final claims = service.extract(answer);
      final ids = claims.map((c) => c.id).toSet();

      expect(ids.length, claims.length);
    });

    test('claim IDs are stable across multiple extract calls for the same input', () {
      final answer = _answer(
        question: 'What is gravity?',
        answerText: 'Gravity pulls objects. It acts at a distance.',
      );

      final first = service.extract(answer);
      final second = service.extract(answer);

      expect(first.map((c) => c.id).toList(),
          equals(second.map((c) => c.id).toList()));
    });

    test('citation lists on claims are unmodifiable', () {
      final answer = _answer(
        answerText: 'A claim.',
        citations: [_citation('c1', 'https://example.com', 'Ex')],
      );

      final claims = service.extract(answer);

      expect(
        () => claims.first.citationUrls.add('https://evil.com'),
        throwsUnsupportedError,
      );
    });

    test('ExtractedClaim equality is id-based', () {
      const a = ExtractedClaim(
        id: 'same',
        text: 'text one',
        citationUrls: [],
        citationTitles: [],
        sourceAnswerProvider: 'p',
        sourceQuestion: 'q',
        order: 0,
      );
      const b = ExtractedClaim(
        id: 'same',
        text: 'text two',
        citationUrls: [],
        citationTitles: [],
        sourceAnswerProvider: 'p2',
        sourceQuestion: 'q2',
        order: 1,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
