import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/models/evidence_item.dart';
import 'package:grepink/services/text_chunker.dart';

EvidenceItem _item(
  String content, {
  String id = 'note-1',
  String title = 'Test Note',
  String? sourceUrl,
  String? sourceNoteId,
}) =>
    EvidenceItem(
      id: id,
      type: EvidenceType.localNote,
      title: title,
      content: content,
      sourceNoteId: sourceNoteId,
      sourceUrl: sourceUrl,
    );

void main() {
  final chunker = TextChunker();

  // ---------------------------------------------------------------------------
  // Empty / whitespace-only content
  // ---------------------------------------------------------------------------

  group('TextChunker – empty / whitespace-only content', () {
    test('empty string returns []', () {
      expect(chunker.chunk(_item('')), isEmpty);
    });

    test('whitespace-only string returns []', () {
      expect(chunker.chunk(_item('   \n\t  ')), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Normal paragraph splitting
  // ---------------------------------------------------------------------------

  group('TextChunker – normal paragraph splitting', () {
    test('two short paragraphs become two chunks', () {
      const content = 'First paragraph text.\n\nSecond paragraph text.';
      final chunks = chunker.chunk(_item(content));

      expect(chunks.length, 2);
      expect(chunks[0].content, 'First paragraph text.');
      expect(chunks[1].content, 'Second paragraph text.');
    });

    test('single short paragraph becomes one chunk', () {
      const content = 'Just one paragraph.';
      final chunks = chunker.chunk(_item(content));

      expect(chunks.length, 1);
      expect(chunks.first.content, 'Just one paragraph.');
    });

    test('blank lines between paragraphs are consumed', () {
      const content = 'Para one.\n\n\n\nPara two.';
      final chunks = chunker.chunk(_item(content));

      expect(chunks.length, 2);
    });
  });

  // ---------------------------------------------------------------------------
  // Max-length guarantee
  // ---------------------------------------------------------------------------

  group('TextChunker – max-length guarantee (<=500 chars)', () {
    test('long paragraph with no punctuation produces chunks <=500 chars', () {
      // 600 words of "word" separated by spaces – no sentence-ending punctuation.
      final longContent = List.generate(600, (_) => 'word').join(' ');
      final chunks = chunker.chunk(_item(longContent));

      expect(chunks, isNotEmpty);
      for (final c in chunks) {
        expect(c.content.length, lessThanOrEqualTo(500),
            reason: 'chunk "${c.content.substring(0, 20)}…" exceeds 500 chars');
      }
    });

    test('one very long word sequence produces chunks <=500 chars', () {
      // A single run of 1 000 characters without any whitespace.
      final longWord = 'a' * 1000;
      final chunks = chunker.chunk(_item(longWord));

      expect(chunks, isNotEmpty);
      for (final c in chunks) {
        expect(c.content.length, lessThanOrEqualTo(500));
      }
    });

    test('long paragraph with some sentence-ending punctuation produces chunks <=500 chars',
        () {
      // Build a paragraph where each sentence is 200 chars – longer than half
      // the limit but shorter than the limit itself, forcing sentence-level splits.
      final sentence = '${'x' * 198}. ';
      final content = sentence * 5;
      final chunks = chunker.chunk(_item(content));

      expect(chunks, isNotEmpty);
      for (final c in chunks) {
        expect(c.content.length, lessThanOrEqualTo(500));
      }
    });
  });

  // ---------------------------------------------------------------------------
  // No text is lost
  // ---------------------------------------------------------------------------

  group('TextChunker – no text is lost', () {
    test('all characters are preserved when splitting long content', () {
      final longContent = List.generate(600, (i) => 'word$i').join(' ');
      final chunks = chunker.chunk(_item(longContent));

      final rejoined = chunks.map((c) => c.content).join(' ');
      // Every input word must appear in the output.
      for (var i = 0; i < 600; i++) {
        expect(rejoined, contains('word$i'),
            reason: 'word$i was lost during chunking');
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Metadata preservation
  // ---------------------------------------------------------------------------

  group('TextChunker – chunk metadata', () {
    test('sourceNoteId is taken from item.sourceNoteId when set', () {
      final chunks = chunker.chunk(_item(
        'Some content.',
        sourceNoteId: 'my-note-id',
      ));

      expect(chunks.first.sourceNoteId, 'my-note-id');
    });

    test('sourceNoteId falls back to item.id when sourceNoteId is null', () {
      final chunks = chunker.chunk(_item(
        'Some content.',
        id: 'fallback-id',
        sourceNoteId: null,
      ));

      expect(chunks.first.sourceNoteId, 'fallback-id');
    });

    test('sourceTitle matches item.title', () {
      final chunks = chunker.chunk(_item(
        'Some content.',
        title: 'My Note Title',
      ));

      expect(chunks.first.sourceTitle, 'My Note Title');
    });

    test('sourceUrl is propagated to all chunks', () {
      final longContent = List.generate(600, (_) => 'word').join(' ');
      const url = 'https://example.com/note';
      final chunks = chunker.chunk(_item(longContent, sourceUrl: url));

      expect(chunks, isNotEmpty);
      for (final c in chunks) {
        expect(c.sourceUrl, url);
      }
    });

    test('sourceUrl is null when not provided', () {
      final chunks = chunker.chunk(_item('Short content.'));

      expect(chunks.first.sourceUrl, isNull);
    });
  });
}
