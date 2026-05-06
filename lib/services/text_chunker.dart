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
  /// 1. Split on blank-line paragraph boundaries first.
  /// 2. If any resulting segment is still longer than [_maxChunkLength],
  ///    split further on sentence-ending punctuation (`. `, `? `, `! `).
  /// 3. Empty or whitespace-only chunks are ignored.
  List<TextChunk> chunk(EvidenceItem item) {
    final id = item.sourceNoteId ?? item.id;
    final segments = _splitIntoParagraphs(item.content)
        .expand((para) => _splitLongSegment(para))
        .where((s) => s.trim().isNotEmpty)
        .toList();

    if (segments.isEmpty) {
      // Fall back to the whole content as a single chunk when nothing is splittable.
      return [
        TextChunk(
          content: item.content.trim(),
          sourceNoteId: id,
          sourceTitle: item.title,
          sourceUrl: item.sourceUrl,
        ),
      ];
    }

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
}
