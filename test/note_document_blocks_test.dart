import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/services/note_document_blocks.dart';
import 'package:grepink/services/note_source_document.dart';

void main() {
  test(
    'passage ranges preserve neighbors, list structure and fenced blank lines',
    () {
      const source =
          '# Title\n\n- One\n  - Nested\n\n```dart\none\n\ntwo\n```\n\nEnd.';
      final blocks = noteDocumentBlocks(source);
      expect(blocks.length, 5);
      expect(blocks[1].markdown, '- One');
      expect(blocks[2].markdown, '  - Nested');
      expect(blocks[3].markdown, contains('one\n\ntwo'));
      final target = blocks[1];
      final edited = source.replaceRange(target.start, target.end, 'Changed');
      expect(
        edited,
        '# Title\n\nChanged\n  - Nested\n\n```dart\none\n\ntwo\n```\n\nEnd.',
      );
    },
  );
  test(
    'legacy split emphasis remains one exact logical passage for display repair',
    () {
      const source =
          '- **First sentence. [Source](https://example.com/one)\n- Second sentence** ends here.\n- Separate item';
      final blocks = noteDocumentBlocks(source);
      expect(blocks.length, 2);
      expect(
        source.substring(blocks.first.start, blocks.first.end),
        blocks.first.markdown,
      );
      expect(
        NoteSourceDocument.visibleMarkdown(blocks.first.markdown),
        '- **First sentence. [Source](https://example.com/one) Second sentence** ends here.',
      );
      expect(blocks.last.markdown, '- Separate item');
      const ordinary = '- First\n- Second';
      expect(noteDocumentBlocks(ordinary).length, 2);
    },
  );
}
