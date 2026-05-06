import '../models/evidence_item.dart';

/// A single chunk derived from a longer [EvidenceItem].
class TextChunk {
  final String content;
  final String sourceNoteId;
  final String sourceTitle;
  final String? sourceUrl;

  const TextChunk({
    required this.content,
    required this.sourceNoteId,
    required this.sourceTitle,
    this.sourceUrl,
  });
}

/// Splits long note content into paragraph/sentence-sized chunks so that
/// delta detection can find a relevant passage inside a long note instead of
/// comparing against the full, diluted text body.
class TextChunker {
  static const int _maxChunkLength = 500;

  /// Returns a list of non-empty [TextChunk]s derived from [item].
  ///
  /// Strategy:
  /// 1. Return [] immediately if [item.content] is empty or whitespace-only.
  /// 2. Split on blank-line paragraph boundaries first.
  /// 3. If any resulting segment is still longer than [_maxChunkLength],
  ///    split further on sentence-ending punctuation (`. `, `? `, `! `).
  /// 4. If any segment is still longer than [_maxChunkLength], hard-wrap on
  ///    whitespace near the boundary (or at exactly [_maxChunkLength] when no
  ///    whitespace is nearby).
  /// 5. Empty or whitespace-only chunks are ignored.
  List<TextChunk> chunk(EvidenceItem item) {
    if (item.content.trim().isEmpty) return [];

    final id = item.sourceNoteId ?? item.id;
    final segments = _splitIntoParagraphs(item.content)
        .expand((para) => _splitLongSegment(para))
        .expand((seg) => _hardWrap(seg))
        .where((s) => s.trim().isNotEmpty)
        .toList();

    if (segments.isEmpty) return [];

    return segments
        .map((s) => TextChunk(
              content: s.trim(),
              sourceNoteId: id,
              sourceTitle: item.title,
              sourceUrl: item.sourceUrl,
            ))
        .toList();
  }

  List<String> _splitIntoParagraphs(String text) {
    return text.split(RegExp(r'\n\s*\n')).where((p) => p.trim().isNotEmpty).toList();
  }

  List<String> _splitLongSegment(String segment) {
    if (segment.length <= _maxChunkLength) return [segment];

    // Split on sentence boundaries.
    final sentences = segment.split(RegExp(r'(?<=[.?!])\s+'));
    final chunks = <String>[];
    final buffer = StringBuffer();

    for (final sentence in sentences) {
      if (buffer.length + sentence.length > _maxChunkLength && buffer.isNotEmpty) {
        chunks.add(buffer.toString().trim());
        buffer.clear();
      }
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(sentence);
    }

    if (buffer.isNotEmpty) chunks.add(buffer.toString().trim());
    return chunks.isEmpty ? [segment] : chunks;
  }

  List<String> _hardWrap(String segment) {
    if (segment.length <= _maxChunkLength) return [segment];

    final chunks = <String>[];
    var remaining = segment;
    while (remaining.length > _maxChunkLength) {
      // Try to break on the last whitespace at or before the limit.
      var breakAt = remaining.lastIndexOf(RegExp(r'\s'), _maxChunkLength);
      if (breakAt <= 0) {
        // No whitespace found; hard-cut at the limit.
        breakAt = _maxChunkLength;
      }
      chunks.add(remaining.substring(0, breakAt).trimRight());
      remaining = remaining.substring(breakAt).trimLeft();
    }
    if (remaining.isNotEmpty) chunks.add(remaining);
    return chunks;
  }
}
