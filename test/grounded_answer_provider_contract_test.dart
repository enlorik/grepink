import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/grounded_answer.dart';
import 'package:grepink/services/grounded_answer_provider.dart';

class FakeGroundedAnswerProvider implements GroundedAnswerProvider {
  final GroundedAnswer? _result;
  FakeGroundedAnswerProvider(this._result);

  @override
  Future<GroundedAnswer?> fetchGroundedAnswer(String question) async {
    if (question.trim().isEmpty) return null;
    return _result;
  }
}

GroundedAnswerCitation _citation({
  String id = 'c1',
  String title = 'Some Title',
  String url = 'https://example.com/page',
  String? snippet,
  int? position,
}) =>
    GroundedAnswerCitation(
      id: id,
      title: title,
      url: url,
      snippet: snippet,
      position: position,
    );

GroundedAnswer _answer({
  String question = 'What is Grepink?',
  String answerText = 'Grepink is a notes-first memory app.',
  List<GroundedAnswerCitation>? citations,
  String providerName = 'fake',
  String? rawSourceLabel,
}) =>
    GroundedAnswer(
      question: question,
      answerText: answerText,
      citations: citations ?? [_citation()],
      providerName: providerName,
      generatedAt: DateTime.utc(2026, 6, 17),
      rawSourceLabel: rawSourceLabel,
    );

void main() {
  group('GroundedAnswerCitation', () {
    test('preserves url exactly', () {
      const url = 'https://example.com/some/deep/path?q=1&r=2';
      const c = GroundedAnswerCitation(id: 'x', title: 'T', url: url);
      expect(c.url, url);
    });

    test('preserves title and snippet', () {
      const c = GroundedAnswerCitation(
        id: 'y',
        title: 'My Title',
        url: 'https://x.com',
        snippet: 'A short excerpt.',
      );
      expect(c.title, 'My Title');
      expect(c.snippet, 'A short excerpt.');
    });

    test('snippet is optional and null by default', () {
      const c = GroundedAnswerCitation(id: 'z', title: 'T', url: 'https://x.com');
      expect(c.snippet, isNull);
    });

    test('position is preserved when set', () {
      const c = GroundedAnswerCitation(id: 'p', title: 'T', url: 'https://x.com', position: 3);
      expect(c.position, 3);
    });

    test('position is null by default', () {
      const c = GroundedAnswerCitation(id: 'p', title: 'T', url: 'https://x.com');
      expect(c.position, isNull);
    });

    test('equality is keyed on id and url, not position', () {
      const a = GroundedAnswerCitation(id: 'c1', title: 'T', url: 'https://x.com', position: 1);
      const b = GroundedAnswerCitation(id: 'c1', title: 'T', url: 'https://x.com', position: 99);
      expect(a, equals(b));
    });

    test('equality by id and url ignores title differences', () {
      const a = GroundedAnswerCitation(id: 'c1', title: 'T', url: 'https://x.com');
      const b = GroundedAnswerCitation(id: 'c1', title: 'Other', url: 'https://x.com');
      expect(a, equals(b));
    });

    test('different id => not equal', () {
      const a = GroundedAnswerCitation(id: 'c1', title: 'T', url: 'https://x.com');
      const b = GroundedAnswerCitation(id: 'c2', title: 'T', url: 'https://x.com');
      expect(a, isNot(equals(b)));
    });

    test('different url => not equal', () {
      const a = GroundedAnswerCitation(id: 'c1', title: 'T', url: 'https://x.com/a');
      const b = GroundedAnswerCitation(id: 'c1', title: 'T', url: 'https://x.com/b');
      expect(a, isNot(equals(b)));
    });
  });

  group('GroundedAnswer', () {
    test('hasCitations is true when citations list is non-empty', () {
      final a = _answer(citations: [_citation()]);
      expect(a.hasCitations, isTrue);
    });

    test('hasCitations is false for empty citations list', () {
      final a = _answer(citations: []);
      expect(a.hasCitations, isFalse);
    });

    test('isEmpty false for normal answer text', () {
      final a = _answer(answerText: 'Something useful.');
      expect(a.isEmpty, isFalse);
    });

    test('isEmpty true for blank answer text', () {
      final a = _answer(answerText: '   ');
      expect(a.isEmpty, isTrue);
    });

    test('empty citation list is allowed', () {
      final a = _answer(citations: []);
      expect(a.citations, isEmpty);
      expect(a.hasCitations, isFalse);
    });

    test('rawSourceLabel is optional and null by default', () {
      final a = _answer();
      expect(a.rawSourceLabel, isNull);
    });

    test('rawSourceLabel is preserved when set', () {
      final a = _answer(rawSourceLabel: 'brave_ai_v1');
      expect(a.rawSourceLabel, 'brave_ai_v1');
    });

    test('preserves providerName', () {
      final a = _answer(providerName: 'brave_ai_answers_v1');
      expect(a.providerName, 'brave_ai_answers_v1');
    });

    test('citations list is unmodifiable after construction', () {
      final source = [_citation(id: 'c1')];
      final a = _answer(citations: source);
      source.add(_citation(id: 'c2'));
      expect(a.citations.length, 1,
          reason: 'mutating the source list must not affect the stored citations');
      expect(() => a.citations.add(_citation(id: 'c3')), throwsUnsupportedError,
          reason: 'citations returned by GroundedAnswer must not allow mutation');
    });

    test('equal when all fields match', () {
      final a = _answer();
      final b = _answer();
      expect(a, equals(b));
    });

    test('not equal when question differs', () {
      final a = _answer(question: 'What is X?');
      final b = _answer(question: 'What is Y?');
      expect(a, isNot(equals(b)));
    });

    test('not equal when answerText differs', () {
      final a = _answer(answerText: 'Text A.');
      final b = _answer(answerText: 'Text B.');
      expect(a, isNot(equals(b)));
    });

    test('not equal when providerName differs', () {
      final a = _answer(providerName: 'alpha');
      final b = _answer(providerName: 'beta');
      expect(a, isNot(equals(b)));
    });

    test('not equal when citation lists differ', () {
      final a = _answer(citations: [_citation(id: 'c1')]);
      final b = _answer(citations: [_citation(id: 'c2')]);
      expect(a, isNot(equals(b)));
    });

    test('not equal when generatedAt differs', () {
      final a = GroundedAnswer(
        question: 'q',
        answerText: 'text',
        citations: const [],
        providerName: 'p',
        generatedAt: DateTime.utc(2026, 6, 17, 10),
      );
      final b = GroundedAnswer(
        question: 'q',
        answerText: 'text',
        citations: const [],
        providerName: 'p',
        generatedAt: DateTime.utc(2026, 6, 17, 11),
      );
      expect(a, isNot(equals(b)));
    });

    test('not equal when rawSourceLabel differs', () {
      final a = _answer(rawSourceLabel: 'label_a');
      final b = _answer(rawSourceLabel: 'label_b');
      expect(a, isNot(equals(b)));
    });

    test('hashCode is consistent with equality', () {
      final a = _answer();
      final b = _answer();
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('citations preserve url and title through answer', () {
      const c = GroundedAnswerCitation(
        id: 'ref1',
        title: 'Deep Dive Article',
        url: 'https://deep.example.org/article?id=42',
        snippet: 'First paragraph text.',
        position: 1,
      );
      final a = _answer(citations: [c]);
      final stored = a.citations.first;
      expect(stored.url, 'https://deep.example.org/article?id=42');
      expect(stored.title, 'Deep Dive Article');
      expect(stored.snippet, 'First paragraph text.');
      expect(stored.position, 1);
    });
  });

  group('GroundedAnswerProvider interface', () {
    test('empty question returns null without calling into result', () async {
      final provider = FakeGroundedAnswerProvider(_answer());
      expect(await provider.fetchGroundedAnswer(''), isNull);
    });

    test('whitespace-only question returns null', () async {
      final provider = FakeGroundedAnswerProvider(_answer());
      expect(await provider.fetchGroundedAnswer('   '), isNull);
    });

    test('valid question returns the injected answer', () async {
      final injected = _answer(question: 'What is Dart?');
      final provider = FakeGroundedAnswerProvider(injected);
      final result = await provider.fetchGroundedAnswer('What is Dart?');
      expect(result, same(injected));
    });

    test('provider configured to return null does so for a non-empty question', () async {
      final provider = FakeGroundedAnswerProvider(null);
      expect(await provider.fetchGroundedAnswer('some question'), isNull);
    });

    test('NullGroundedAnswerProvider always returns null regardless of question', () async {
      const provider = NullGroundedAnswerProvider();
      expect(await provider.fetchGroundedAnswer('anything'), isNull);
      expect(await provider.fetchGroundedAnswer(''), isNull);
      expect(await provider.fetchGroundedAnswer('   '), isNull);
    });
  });
}
