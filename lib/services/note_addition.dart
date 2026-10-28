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
  var body = NoteSourceDocument.withoutMetadata(markdown);
  body = body.replaceFirst(RegExp(r'^#\s+[^\n]+\n*'), '');
  body = body.replaceAll(
    RegExp(r'^## (?:New knowledge|Better sources)\s*\n', multiLine: true),
    '',
  );
  final directory = RegExp(
    r'^## Sources\s*$',
    multiLine: true,
  ).firstMatch(body);
  if (directory != null) {
    final tail = body.substring(directory.end).trim();
    if (tail
        .split('\n')
        .every(
          (line) =>
              line.trim().isEmpty ||
              RegExp(r'^- .+ — https?://\S+\s*$').hasMatch(line),
        )) {
      body = body.substring(0, directory.start);
    }
  }
  return body.trim();
}
