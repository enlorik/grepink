import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/grounded_answer.dart';
import 'package:grepink/services/note_source_document.dart';

void main() {
  test('old sourced bold fragments join for display while keeping every URL',
      () {
    const stored =
        '- **Sized vs. [Source](https://one.example)\n- Unsized:** types. [Source](https://two.example)';
    final rendered = NoteSourceDocument.visibleMarkdown(stored);
    expect(rendered,
        '- **Sized vs. [Source](https://one.example) Unsized:** types. [Source](https://two.example)');
    expect(stored, contains('\n- Unsized:'));
    expect(NoteSourceDocument.visibleMarkdown('```\n$stored\n```'),
        '```\n$stored\n```');
    const valid =
        '- **One** [Source](https://one.example)\n- **Two** [Source](https://two.example)';
    expect(NoteSourceDocument.visibleMarkdown(valid), valid);
  });

  test('editable document text preserves spaces around metadata separators',
      () {
    const text = '  Draft ends with a space ';
    final metadata = NoteSourceDocument.encode([
      const GroundedAnswerCitation(
          id: '1', title: 'A', url: 'https://example.com')
    ]);
    expect(
        NoteSourceDocument.withoutMetadata('$text\n\n$metadata', trim: false),
        text);
    expect(
        NoteSourceDocument.withoutMetadata('$text\n\n$metadata'), text.trim());
  });

  test('legacy double bullets normalize only for display outside code', () {
    const document = '- * A fact\n\n```\n- * Code stays exact\n```\n\n* * *';
    expect(NoteSourceDocument.visibleMarkdown(document),
        '* A fact\n\n```\n- * Code stays exact\n```\n\n* * *');
    expect(document, startsWith('- *'));
  });

  test('saved excerpts survive note text round-trip without visible metadata',
      () {
    const citation = GroundedAnswerCitation(
        id: '1',
        title: 'Rust types',
        url: 'https://doc.rust-lang.org/reference/types.html',
        snippet: '**Scalar** types include integers.');
    final document =
        '# Types\n\n[Source](${citation.url})\n\n${NoteSourceDocument.encode([
          citation
        ])}';
    final reopened = NoteSourceDocument.sources(document).single;
    expect(reopened.snippet, citation.snippet);
    expect(reopened.url, citation.url);
    expect(NoteSourceDocument.visibleMarkdown(document),
        isNot(contains('grepink-sources')));
    expect(NoteSourceDocument.visibleMarkdown(document), contains('[Source]'));
  });
  test('malformed metadata and old notes remain readable', () {
    expect(NoteSourceDocument.sources('<!-- grepink-sources:invalid= -->'),
        isEmpty);
    expect(NoteSourceDocument.visibleMarkdown('- Rust — https://example.com'),
        '- [Rust](<https://example.com>)');
  });
  test('duplicate heading names have distinct insertion locations', () {
    const content = '# Types\n\nOld\n\n## More\n\nOne\n\n## More\n\nTwo';
    final targets = noteInsertionTargets(content);
    final additions = targets.where((t) => t.label == 'More').toList();
    expect(additions.length, 2);
    expect(insertNoteDraft(content, 'NEW', additions.first.offset),
        contains('One\n\nNEW\n\n## More'));
    expect(insertNoteDraft(content, 'NEW', -1), endsWith('Two\n\nNEW'));
  });
  test('headings inside code never become insertion targets', () {
    final targets = noteInsertionTargets('# Real\n```\n## code\n```\n## Next');
    expect(targets.map((t) => t.label), ['End of note', 'Real', 'Next']);
  });
}
