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
  // Old generated drafts sometimes split one bold phrase across two bullets.
  // Keep that known fragment as one logical passage so display repair still sees
  // both halves; the original source range remains exact for editing/export.
  final fragments = RegExp(
    r'^(\s*[-+*]\s+\*\*[^\n*]*?\[Source(?: \d+)?\]\([^\n]+\))\n[-+*]\s+([^\n]*?\*\*[^\n]*)$',
  );
  final result = <NoteDocumentBlock>[];
  for (var i = 0; i < blocks.length; i++) {
    final block = blocks[i];
    if (i + 1 < blocks.length &&
        source.substring(block.end, blocks[i + 1].start) == '\n' &&
        fragments.hasMatch(source.substring(block.start, blocks[i + 1].end))) {
      final end = blocks[++i].end;
      result.add(
        NoteDocumentBlock(block.start, end, source.substring(block.start, end)),
      );
    } else {
      result.add(block);
    }
  }
  return result;
}
