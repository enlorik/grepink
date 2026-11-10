import 'note_source_document.dart';

/// Deterministic topic labels avoid another provider call or an invented title.
String noteTopicTitle(String question, String markdown) {
  final heading = RegExp(
    r'^#{1,2}\s+(.+)$',
    multiLine: true,
  ).firstMatch(markdown);
  final headingText = heading?[1]?.trim();
  String topic =
      headingText != null &&
          !const {
            'draft',
            'notes',
            'research notes',
            'new knowledge',
            'generated note',
          }.contains(headingText.toLowerCase())
      ? headingText
      : question.trim();
  topic = topic.replaceFirst(
    RegExp(
      r'^(?:(?:what|who)\s+(?:is|are)|(?:please\s+)?(?:explain|describe|tell me about)|how\s+(?:does|do))\s+',
      caseSensitive: false,
    ),
    '',
  );
  topic = topic.replaceFirst(
    RegExp(r'^(?:what|who|why)\s+', caseSensitive: false),
    '',
  );
  topic = topic.replaceFirst(RegExp(r'\s+work\??$', caseSensitive: false), '');
  topic = topic
      .replaceAll(RegExp(r'[?*_`#]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (topic.isEmpty) return 'Research notes';
  topic = '${topic[0].toUpperCase()}${topic.substring(1)}';
  return topic.length > 72 ? '${topic.substring(0, 69)}…' : topic;
}

/// Insert prose into an existing story, not a nested Q&A/report envelope.
/// Explicit contradiction warnings and every inline citation stay intact.
String noteAdditionBody(String markdown) {
  final lines = NoteSourceDocument.withoutMetadata(markdown).split('\n');
  final kept = <String>[];
  String? fence;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final marker = RegExp(r'^\s{0,3}(`{3,}|~{3,})').firstMatch(line);
    if (marker != null) {
      final type = marker[1]![0];
      fence = fence == null
          ? type
          : fence == type
          ? null
          : fence;
      kept.add(line);
      continue;
    }
    if (fence == null) {
      if (i == 0 && RegExp(r'^#\s+').hasMatch(line)) continue;
      if (RegExp(r'^## (?:New knowledge|Better sources)\s*$').hasMatch(line)) {
        continue;
      }
      if (line.trim() == '## Sources' &&
          lines
              .skip(i + 1)
              .every(
                (tail) =>
                    tail.trim().isEmpty ||
                    RegExp(r'^- .+ — https?://\S+\s*$').hasMatch(tail),
              )) {
        break;
      }
    }
    kept.add(line);
  }
  return kept.join('\n').trim();
}
