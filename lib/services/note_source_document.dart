import 'dart:convert';

import 'markdown_list_lines.dart';

import '../models/grounded_answer.dart';

/// Portable source excerpts travel with the note through sync and export.
/// Only citations used by the saved draft are embedded; no provider response
/// or credentials are retained. The comment stays invisible in Markdown.
class NoteSourceDocument {
  static final _metadata = RegExp(
    r'<!-- grepink-sources:([A-Za-z0-9+/=]+) -->',
  );

  static String encode(Iterable<GroundedAnswerCitation> citations) {
    final rows = citations
        .map(
          (c) => {
            'url': c.url,
            'title': c.title,
            if (c.snippet != null)
              'snippet': c.snippet!.length > 1600
                  ? c.snippet!.substring(0, 1600)
                  : c.snippet,
          },
        )
        .toList();
    if (rows.isEmpty) return '';
    return '<!-- grepink-sources:${base64Encode(utf8.encode(jsonEncode(rows)))} -->';
  }

  static List<GroundedAnswerCitation> sources(String content) {
    final result = <String, GroundedAnswerCitation>{};
    for (final match in _metadata.allMatches(content)) {
      try {
        final rows = jsonDecode(utf8.decode(base64Decode(match[1]!)));
        if (rows is! List) continue;
        for (final row in rows) {
          if (row is! Map || row['url'] is! String) continue;
          final url = row['url'] as String;
          final uri = Uri.tryParse(url);
          if (uri == null || !['http', 'https'].contains(uri.scheme)) continue;
          result[url] = GroundedAnswerCitation(
            id: url,
            title: row['title'] is String ? row['title'] as String : uri.host,
            url: url,
            snippet: row['snippet'] is String ? row['snippet'] as String : null,
          );
        }
      } catch (_) {
        // A manually edited or old metadata block must never prevent reading.
      }
    }
    return result.values.toList();
  }

  static String withoutMetadata(String content, {bool trim = true}) {
    if (trim) return content.replaceAll(_metadata, '').trim();
    // The writer adds exactly two separator newlines before each metadata block;
    // retain all actual draft whitespace so typing a space cannot close editing.
    return content.replaceAll(
      RegExp(r'(?:\n\n)?<!-- grepink-sources:[A-Za-z0-9+/=]+ -->'),
      '',
    );
  }

  static String visibleMarkdown(String content) {
    var fenced = false;
    final clean = normalizeMarkdownLists(content.replaceAll(_metadata, '').trim())
        .split('\n')
        .map((line) {
          if (RegExp(r'^\s{0,3}(`{3,}|~{3,})').hasMatch(line)) fenced = !fenced;
          if (fenced) return line;
          // Legacy drafts wrapped provider list markers in another bullet.
          // This is display-only and deliberately leaves thematic breaks intact.
          return line.replaceFirstMapped(
            RegExp(r'^(\s*)[-+*]\s+([-+*]\s+)(?=[^\s*+\-])'),
            (m) => '${m[1]}${m[2]}',
          );
        })
        .join('\n');
    // Older generated drafts split a bold phrase across two list items at a
    // sentence boundary. Join that narrowly identified display fragment while
    // retaining both source links and leaving stored/exported Markdown alone.
    final lines = clean.split('\n');
    final repairedLines = <String>[];
    String? codeFence;
    final fragments = RegExp(
      r'^(\s*[-+*]\s+\*\*[^\n*]*?\[Source(?: \d+)?\]\([^\n]+\))\n[-+*]\s+([^\n]*?\*\*[^\n]*)$',
    );
    for (var i = 0; i < lines.length; i++) {
      final marker = RegExp(r'^\s{0,3}(`{3,}|~{3,})').firstMatch(lines[i]);
      if (marker != null) {
        final type = marker[1]![0];
        if (codeFence == null) {
          codeFence = type;
        } else if (codeFence == type) {
          codeFence = null;
        }
      }
      final match = codeFence == null && i + 1 < lines.length
          ? fragments.firstMatch('${lines[i]}\n${lines[i + 1]}')
          : null;
      if (match != null) {
        repairedLines.add('${match[1]} ${match[2]}');
        i++;
      } else {
        repairedLines.add(lines[i]);
      }
    }
    final repaired = repairedLines.join('\n');
    // Existing drafts used a plain source directory; render compact links
    // without rewriting the saved note or losing its original URLs.
    return repaired.replaceAllMapped(
      RegExp(r'^- (.+) — (https?://\S+)\s*$', multiLine: true),
      (m) => '- [${m[1]!.replaceAll('[', '').replaceAll(']', '')}](<${m[2]}>)',
    );
  }
}

/// A target is an exact offset in a particular editor snapshot, never a global
/// replace of heading text (which can legitimately repeat).
class NoteInsertionTarget {
  final String label;
  final int offset;
  const NoteInsertionTarget(this.label, this.offset);
}

List<NoteInsertionTarget> noteInsertionTargets(String content) {
  final result = <NoteInsertionTarget>[];
  var offset = 0;
  var fenced = false;
  String? fence;
  for (final line in content.split('\n')) {
    final marker = RegExp(r'^\s{0,3}(`{3,}|~{3,})').firstMatch(line);
    if (marker != null) {
      final current = marker[1]![0];
      if (!fenced) {
        fenced = true;
        fence = current;
      } else if (fence == current) {
        fenced = false;
      }
    } else if (!fenced && RegExp(r'^#{1,6}\s+').hasMatch(line)) {
      if (result.isNotEmpty) {
        final previous = result.removeLast();
        result.add(NoteInsertionTarget(previous.label, offset));
      }
      result.add(
        NoteInsertionTarget(
          line.replaceFirst(RegExp(r'^#+\s+'), ''),
          content.length,
        ),
      );
    }
    offset += line.length + 1;
  }
  return [const NoteInsertionTarget('End of note', -1), ...result];
}

String insertNoteDraft(String content, String draft, int offset) {
  final at = offset < 0 ? content.length : offset.clamp(0, content.length);
  return [
    content.substring(0, at).trimRight(),
    draft.trim(),
    content.substring(at).trimLeft(),
  ].where((s) => s.isNotEmpty).join('\n\n');
}
