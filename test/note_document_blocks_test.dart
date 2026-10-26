import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/services/note_document_blocks.dart';

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
}
