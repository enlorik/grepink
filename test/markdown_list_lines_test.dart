import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/services/markdown_list_lines.dart';

void main() {
  test(
    'double ASCII and Unicode bullets become one marker while indentation survives',
    () {
      expect(
        normalizeMarkdownLists(
          '- • Function\n  - • Trait\n\t• Pointer\n- - Other',
        ),
        '- Function\n  - Trait\n\t- Pointer\n- Other',
      );
      expect(MarkdownListLine.parse('  - • Trait')!.body, 'Trait');
      expect(MarkdownListLine.parse('  - • Trait')!.indent, 2);
    },
  );
  test(
    'code, thematic breaks, ordered markers and ordinary arithmetic remain intact',
    () {
      const source = '```rust\n- • code\n```\n\n* * *\n\n2. Second\n\nx * y';
      expect(normalizeMarkdownLists(source), source);
      expect(MarkdownListLine.parse('    2. Second')!.marker, '2.');
    },
  );
}
