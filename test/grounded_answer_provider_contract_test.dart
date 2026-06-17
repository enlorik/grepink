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
}) =>
    GroundedAnswerCitation(id: id, title: title, url: url, snippet: snippet);

GroundedAnswer _answer({
  String question = 'What is Grepink?',
  String answerText = 'Grepink is a notes-first memory app.',
  List<GroundedAnswerCitation>? citations,
  String providerName = 'fake',
}) =>
    GroundedAnswer(
      question: question,
      answerText: answerText,
      citations: citations ?? [_citation()],
      providerName: providerName,
      generatedAt: DateTime.utc(2026, 6, 17),
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

    test('snippet is optional', () {
      const c = GroundedAnswerCitation(id: 'z', title: 'T', url: 'https://x.com');
      expect(c.snippet, isNull);
    });

    test('equality by id and url', () {
      const a = GroundedAnswerCitation(id: 'c1', title: 'T', url: 'https://x.com');
      const b = GroundedAnswerCitation(id: 'c1', title: 'Other', url: 'https://x.com');
      expect(a, equals(b));
    });

    test('different id => not equal', () {
      const a = GroundedAnswerCitation(id: 'c1', title: 'T', url: 'https://x.com');
      const b = GroundedAnswerCitation(id: 'c2', title: 'T', url: 'https://x.com');
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

    test('rawSourceLabel is optional', () {
      final a = GroundedAnswer(
        question: 'q',
        answerText: 'text',
        citations: const [],
        providerName: 'test',
        generatedAt: DateTime.utc(2026),
      );
      expect(a.rawSourceLabel, isNull);
    });

    test('preserves providerName', () {
      final a = _answer(providerName: 'brave_ai_answers_v1');
      expect(a.providerName, 'brave_ai_answers_v1');
    });

    test('does not include secrets in debug fields', () {
      final a = _answer();
      expect(a.providerName, isNot(contains('key')));
      expect(a.providerName, isNot(contains('secret')));
      expect(a.answerText, isNot(contains('sk-')));
    });

    test('citations preserve url and title through answer', () {
      const c = GroundedAnswerCitation(
        id: 'ref1',
        title: 'Deep Dive Article',
        url: 'https://deep.example.org/article?id=42',
        snippet: 'First paragraph text.',
      );
      final a = _answer(citations: [c]);
      final stored = a.citations.first;
      expect(stored.url, 'https://deep.example.org/article?id=42');
      expect(stored.title, 'Deep Dive Article');
      expect(stored.snippet, 'First paragraph text.');
    });
  });

  group('GroundedAnswerProvider interface', () {
    test('fake provider returns null for empty question', () async {
      final provider = FakeGroundedAnswerProvider(_answer());
      final result = await provider.fetchGroundedAnswer('');
      expect(result, isNull);
    });

    test('fake provider returns null for whitespace-only question', () async {
      final provider = FakeGroundedAnswerProvider(_answer());
      final result = await provider.fetchGroundedAnswer('   ');
      expect(result, isNull);
    });

    test('fake provider returns result for valid question', () async {
      final expected = _answer(question: 'What is Dart?');
      final provider = FakeGroundedAnswerProvider(expected);
      final result = await provider.fetchGroundedAnswer('What is Dart?');
      expect(result, isNotNull);
      expect(result!.question, 'What is Dart?');
    });

    test('fake provider can return null result for valid question', () async {
      final provider = FakeGroundedAnswerProvider(null);
      final result = await provider.fetchGroundedAnswer('some question');
      expect(result, isNull);
    });

    test('NullGroundedAnswerProvider always returns null', () async {
      const provider = NullGroundedAnswerProvider();
      expect(await provider.fetchGroundedAnswer('anything'), isNull);
      expect(await provider.fetchGroundedAnswer(''), isNull);
    });
  });
}
