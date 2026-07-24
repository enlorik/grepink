import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:grepink/services/note_export_service.dart';

void main() {
  test('decoded backup notes are always queued for embedding reindex', () {
    final payload = jsonEncode({
      'version': 1,
      'exported_at': '2026-07-24T20:00:00Z',
      'notes': [
        {
          'id': 'restored-note',
          'title': 'Restored',
          'content': 'Knowledge that must remain searchable.',
          'tags': <String>[],
          'keywords': <String>[],
          'isPinned': false,
          'createdAt': '2026-07-24T18:00:00Z',
          'updatedAt': '2026-07-24T19:00:00Z',
          'embeddingPending': false,
        },
      ],
    });

    final decoded = NoteExportService.instance.decode(payload);

    expect(decoded, hasLength(1));
    expect(decoded.single.embedding, isNull);
    expect(decoded.single.embeddingPending, isTrue);
  });
}
