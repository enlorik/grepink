import 'markdown_list_lines.dart';

/// Exact source ranges. Each list item is editable separately; code and tables
/// remain intact, and no neighboring source text is reserialized.
class NoteDocumentBlock {
  final int start;
  final int end;
  final String markdown;
  const NoteDocumentBlock(this.start, this.end, this.markdown);
}

List<NoteDocumentBlock> noteDocumentBlocks(String source) {
  final blocks = <NoteDocumentBlock>[];
  var start = 0;
  var offset = 0;
  String? fence;
  void flush(int end) {
    if (end > start && source[end - 1] == '\n') end--;
    if (end > start && source.substring(start, end).trim().isNotEmpty) {
      blocks.add(NoteDocumentBlock(start, end, source.substring(start, end)));
    }
  }

  for (final line in source.split('\n')) {
    final marker = RegExp(r'^\s{0,3}(`{3,}|~{3,})').firstMatch(line);
    if (marker != null) {
      final kind = marker[1]![0];
      if (fence == null) {
        fence = kind;
      } else if (fence == kind) {
        fence = null;
      }
    }
    if (fence == null && marker == null) {
      if (line.trim().isEmpty) {
        flush(offset);
        start = (offset + line.length + 1).clamp(0, source.length);
      } else if (MarkdownListLine.parse(line) != null ||
          RegExp(r'^[ \t]*[-+*•●◦▪]\s*$').hasMatch(line)) {
        flush(offset);
        start = offset;
      }
    }
    offset += line.length + 1;
  }
  flush(source.length);
  if (blocks.isEmpty) blocks.add(const NoteDocumentBlock(0, 0, ''));
  return blocks;
}
