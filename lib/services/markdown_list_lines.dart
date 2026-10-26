/// Repairs redundant marker glyphs while retaining indentation and code verbatim.
String normalizeMarkdownLists(String source) {
  String? fence;
  return source
      .split('\n')
      .map((line) {
        final marker = RegExp(r'^\s{0,3}(`{3,}|~{3,})').firstMatch(line);
        if (marker != null) {
          final kind = marker[1]![0];
          if (fence == null) {
            fence = kind;
          } else if (fence == kind) {
            fence = null;
          }
          return line;
        }
        if (fence != null) return line;
        final match = RegExp(
          r'^([ \t]*)([-+*•●◦▪](?:[ \t]+[-+*•●◦▪])*)[ \t]+(.+)$',
        ).firstMatch(line);
        if (match == null || RegExp(r'^[-+*\s]+$').hasMatch(line)) return line;
        final markers = match[2]!.replaceAll(RegExp(r'\s'), '');
        final bullet = '-+*'.contains(markers[0]) ? markers[0] : '-';
        return '${match[1]}$bullet ${match[3]}';
      })
      .join('\n');
}

class MarkdownListLine {
  final String prefix;
  final String body;
  final String marker;
  final int indent;
  const MarkdownListLine(this.prefix, this.body, this.marker, this.indent);

  static MarkdownListLine? parse(String source) {
    final normalized = normalizeMarkdownLists(source);
    final m = RegExp(
      r'^([ \t]*)([-+*]|\d{1,9}[.)])[ \t]+',
    ).firstMatch(normalized);
    if (m == null) return null;
    final original = RegExp(
      r'^([ \t]*)(?:[-+*•●◦▪]|\d{1,9}[.)])(?:[ \t]+[-+*•●◦▪])*[ \t]+',
    ).firstMatch(source);
    final prefix = original?.group(0) ?? m[0]!;
    return MarkdownListLine(
      prefix,
      source.substring(prefix.length),
      m[2]!,
      m[1]!.replaceAll('\t', '    ').length,
    );
  }
}

/// Parse an isolated review item as a list instead of mistaking its inherited
/// indentation for a code block; the review layout renders that indentation.
String standaloneListMarkdown(String source) {
  final normalized = normalizeMarkdownLists(source);
  if (MarkdownListLine.parse(normalized) == null) return normalized;
  final prefix = RegExp(r'^[ \t]*').firstMatch(normalized)![0]!;
  if (prefix.isEmpty) return normalized;
  return normalized
      .split('\n')
      .map(
        (line) =>
            line.startsWith(prefix) ? line.substring(prefix.length) : line,
      )
      .join('\n');
}
