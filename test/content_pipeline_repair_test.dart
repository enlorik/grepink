import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:grepink/models/grounded_answer.dart';
import 'package:grepink/models/grounded_answer_provider_outcome.dart';
import 'package:grepink/services/brave_answers_grounded_answer_provider.dart';
import 'package:grepink/services/claim_extraction_service.dart';
import 'package:grepink/services/source_page_loader.dart';

GroundedAnswer answer(
  String text, [
  List<GroundedAnswerCitation> citations = const [],
]) => GroundedAnswer(
  question: 'Types?',
  answerText: text,
  citations: citations,
  providerName: 'fixture',
  generatedAt: DateTime(2026),
);

void main() {
  const extract = RuleBasedClaimExtractionService();
  test(
    'KaTeX exposes one formula rather than MathML plus raw TeX plus hidden HTML',
    () {
      final page = parseSourcePage(
        r'''<article><h1>Array types</h1><p>Arrays use <span class="katex"><span class="katex-mathml"><math><semantics><mrow><mi>kotlin.Array</mi><mo>⁡</mo><mo>(</mo><mi>T</mi><mo>)</mo></mrow><annotation encoding="application/x-tex">\operatorname{\texttt{kotlin.Array}}(T)</annotation></semantics></math></span><span class="katex-html" aria-hidden="true">kotlin.Array(T)</span></span> for their element type.</p></article>''',
      );
      expect(
        page.sections.last.text,
        'Arrays use kotlin.Array(T) for their element type.',
      );
      expect(page.sections.last.markdown, contains('`kotlin.Array(T)`'));
      expect(page.sections.last.markdown, isNot(contains('operatorname')));
      expect(
        page.excerptIndex('Arrays use kotlin.Array(T) for their element type.'),
        1,
      );
    },
  );
  test('native MathML preserves powers, indices and fractions', () {
    final page = parseSourcePage(
      '<main><p>Use <math><mfrac><msup><mi>x</mi><mn>2</mn></msup><msub><mi>y</mi><mi>i</mi></msub></mfrac></math>.</p></main>',
    );
    expect(page.sections.single.text, 'Use (x^(2))/(y_(i)).');
  });
  test(
    'numbered references recover passage association without borrowing a quote',
    () {
      const text =
          'Arrays store values. [1]\n\nStrings contain characters.[2] Next fact has no reference.';
      final claims = extract.extract(
        answer(text, [
          const GroundedAnswerCitation(
            id: '1',
            title: 'Arrays',
            url: 'https://example.com/arrays',
            snippet: 'An array excerpt.',
            position: text.length,
          ),
          const GroundedAnswerCitation(
            id: '2',
            title: 'Strings',
            url: 'https://example.com/strings',
            snippet: 'A string excerpt.',
            position: text.length,
          ),
        ]),
      );
      expect(claims.length, 3);
      expect(claims[0].citationUrls, ['https://example.com/arrays']);
      expect(claims[1].citationUrls, ['https://example.com/strings']);
      expect(claims[0].evidence.single.snippet, 'An array excerpt.');
      expect(claims[1].evidence.single.snippet, 'A string excerpt.');
      expect(claims[2].citationUncertain, isTrue);
      expect(claims[2].evidence.every((c) => c.snippet == null), isTrue);
    },
  );
  test('Markdown links survive absent structured provider citations', () {
    final claims = extract.extract(
      answer(
        'Arrays store values. [Array guide](https://example.com/arrays)\n\nStrings contain characters.',
      ),
    );
    expect(claims.length, 2);
    expect(claims.first.citationUrls, ['https://example.com/arrays']);
    expect(claims.first.citationUncertain, isFalse);
    expect(claims.first.evidence.single.snippet, isNull);
    expect(claims.last.citationUncertain, isTrue);
  });
  test(
    'recovering a Markdown link does not make an ambiguous end cluster trustworthy',
    () {
      const text = 'One fact. [Guide](https://example.com/a)\n\nAnother fact.';
      final claims = extract.extract(
        answer(text, [
          const GroundedAnswerCitation(
            id: '1',
            title: 'One',
            url: 'https://example.com/one',
            snippet: 'Unassigned one.',
            position: text.length,
          ),
          const GroundedAnswerCitation(
            id: '2',
            title: 'Two',
            url: 'https://example.com/two',
            snippet: 'Unassigned two.',
            position: text.length,
          ),
        ]),
      );
      expect(claims.last.citationUncertain, isTrue);
      expect(claims.last.evidence.every((c) => c.snippet == null), isTrue);
    },
  );
  test('code does not manufacture references and italics stay renderable', () {
    final claims = extract.extract(
      answer(
        '*First statement. Second statement.* Next statement.\n\n```md\n[Guide](https://example.com/not-a-citation) [1]\n```',
        [
          const GroundedAnswerCitation(
            id: '1',
            title: 'Answer source',
            url: 'https://example.com/answer',
          ),
        ],
      ),
    );
    expect(claims.first.text, '*First statement. Second statement.*');
    expect(claims.every((c) => c.citationUncertain), isTrue);
    expect(
      claims.expand((c) => c.citationUrls),
      isNot(contains('https://example.com/not-a-citation')),
    );
  });
  test(
    'provider cleanup keeps template syntax, prose and downstream citation positions',
    () async {
      const prose =
          'Use `Array<T>` and `</T>` literally. The next fact has a source.';
      final tag = jsonEncode({
        'number': 1,
        'url': 'https://example.com/types',
        'title': 'Type guide',
        'start_index': prose.indexOf('The next'),
        'end_index': prose.length,
        'snippet': 'A supplied excerpt.',
      });
      final content =
          '$prose<citation>$tag</citation><think>hidden text</think><usage>{}</usage>';
      final provider = BraveAnswersGroundedAnswerProvider(
        apiKey: 'placeholder',
        client: MockClient(
          (_) async => http.Response(
            'data: ${jsonEncode({
              'choices': [
                {
                  'delta': {'content': content},
                },
              ],
            })}\n\ndata: [DONE]\n\n',
            200,
          ),
        ),
      );
      final outcome =
          await provider.fetchGroundedAnswer('Types?') as GroundedAnswerSuccess;
      expect(outcome.answer.answerText, prose);
      expect(outcome.answer.citations.single.title, 'Type guide');
      final claims = extract.extract(outcome.answer);
      expect(claims.first.text, 'Use `Array<T>` and `</T>` literally.');
      expect(claims.last.evidence.single.snippet, 'A supplied excerpt.');
      expect(claims.last.citationUncertain, isFalse);
    },
  );
}
