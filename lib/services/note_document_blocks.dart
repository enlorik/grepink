/// Exact source ranges for editing a passage without reserializing its neighbors.
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
  for (final line in source.split('\n')) {
    final marker = RegExp(r'^\s{0,3}(`{3,}|~{3,})').firstMatch(line);
    if (marker != null) {
      final current = marker[1]![0];
      if (fence == null) {
        fence = current;
      } else if (fence == current) {
        fence = null;
      }
    }
    if (fence == null && line.trim().isEmpty) {
      if (offset > start && source.substring(start, offset).trim().isNotEmpty) {
        final end =
            offset > start && source[offset - 1] == '\n' ? offset - 1 : offset;
        blocks.add(NoteDocumentBlock(start, end, source.substring(start, end)));
      }
      start = (offset + line.length + 1).clamp(0, source.length);
    }
    offset += line.length + 1;
  }
  if (start < source.length) {
    blocks
        .add(NoteDocumentBlock(start, source.length, source.substring(start)));
  }
  if (blocks.isEmpty) blocks.add(const NoteDocumentBlock(0, 0, ''));
  return blocks;
}
