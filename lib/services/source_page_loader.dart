import 'dart:convert';
import 'dart:typed_data';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

abstract class SourcePageLoader {
  Future<SourcePage> load(String url);
}

class SourcePageSection {
  final String text;
  final String markdown;
  final String? anchor;
  const SourcePageSection(this.text, this.markdown, [this.anchor]);
}

class SourcePage {
  final String title;
  final List<SourcePageSection> sections;
  const SourcePage(this.title, this.sections);

  /// Match locally; note text is never sent to the source website.
  int relevantIndex(String passage, {String? anchor}) {
    if (anchor != null && anchor.isNotEmpty) {
      final exact = sections.indexWhere((s) => s.anchor == anchor);
      if (exact >= 0) return exact;
    }
    final words = RegExp(r'[a-zA-Z]{3,}')
        .allMatches(passage.toLowerCase())
        .map((m) => m[0]!)
        .where(
          (w) => !const {
            'the',
            'and',
            'that',
            'this',
            'with',
            'from',
            'for',
            'are',
            'source',
            'https',
            'com',
            'www',
          }.contains(w),
        )
        .toSet();
    var best = sections.indexWhere(
      (s) => s.text.length > 25 && !RegExp(r'^#{1,6} ').hasMatch(s.markdown),
    );
    if (best < 0) best = 0;
    var score = 0.0;
    for (var i = 0; i < sections.length; i++) {
      final text = sections[i].text.toLowerCase();
      final found = words
          .where((w) => RegExp('\\b${RegExp.escape(w)}\\b').hasMatch(text))
          .length;
      final current =
          found /
          (1 + text.length / 1800) *
          (RegExp(r'^#{1,6} ').hasMatch(sections[i].markdown) ? .4 : 1);
      if (current > score) {
        score = current;
        best = i;
      }
    }
    return best;
  }

  String contextAt(int index) => sections
      .skip((index - 1).clamp(0, sections.length))
      .take(14)
      .map((s) => s.markdown)
      .join('\n\n');
}

class SourcePageException implements Exception {
  final String message;
  const SourcePageException(this.message);
  @override
  String toString() => message;
}

/// A bounded public-page reader, with no scripts, remote images or credentials.
/// Cache and in-flight deduplication avoid downloading a page for every line.
class HttpSourcePageLoader implements SourcePageLoader {
  static final shared = HttpSourcePageLoader();
  final http.Client Function() clientFactory;
  final Duration timeout;
  final _cache = <String, SourcePage>{};
  final _pending = <String, Future<SourcePage>>{};
  static const maxBytes = 1500000;
  HttpSourcePageLoader({
    http.Client Function()? clientFactory,
    this.timeout = const Duration(seconds: 8),
  }) : clientFactory = clientFactory ?? http.Client.new;

  static bool isPublicPage(Uri uri) {
    final host = uri.host.toLowerCase();
    if (!['https', 'http'].contains(uri.scheme) ||
        host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && ![80, 443].contains(uri.port))) {
      return false;
    }
    if (host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        host.endsWith('.internal') ||
        host == 'metadata.google.internal' ||
        host == '::' ||
        host == '::1' ||
        host.startsWith('fe80:') ||
        host.startsWith('fc') && host.contains(':') ||
        host.startsWith('fd') && host.contains(':') ||
        host.startsWith('::ffff:')) {
      return false;
    }
    final octets = host.split('.').map(int.tryParse).toList();
    if (RegExp(r'^[0-9.]+$').hasMatch(host) &&
        (octets.length != 4 ||
            octets.any((v) => v == null || v < 0 || v > 255))) {
      return false;
    }
    if (octets.length == 4 && octets.every((v) => v != null)) {
      final a = octets[0]!, b = octets[1]!;
      if (a == 0 ||
          a == 10 ||
          a == 127 ||
          a >= 224 ||
          a == 169 && b == 254 ||
          a == 172 && b >= 16 && b <= 31 ||
          a == 192 && b == 168 ||
          a == 100 && b >= 64 && b <= 127) {
        return false;
      }
    }
    return true;
  }

  @override
  Future<SourcePage> load(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !isPublicPage(uri)) {
      return Future.error(
        const SourcePageException(
          'Only public HTTP or HTTPS pages can be previewed.',
        ),
      );
    }
    final key = uri.removeFragment().toString();
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return Future.value(cached);
    }
    return _pending.putIfAbsent(
      key,
      () => _download(uri.removeFragment())
          .then((page) {
            _cache[key] = page;
            if (_cache.length > 12) _cache.remove(_cache.keys.first);
            return page;
          })
          .whenComplete(() {
            _pending.remove(key);
          }),
    );
  }

  Future<SourcePage> _download(Uri uri) async {
    final client = clientFactory();
    try {
      for (var redirects = 0; redirects <= 3; redirects++) {
        if (!isPublicPage(uri)) {
          throw const SourcePageException(
            'This redirect is not a public page.',
          );
        }
        final request = http.Request('GET', uri)..followRedirects = false;
        request.headers['Accept'] = 'text/html, text/plain;q=0.8';
        final response = await client.send(request).timeout(timeout);
        if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
          await response.stream.listen((_) {}).cancel();
          final next = response.headers['location'];
          if (next == null) break;
          uri = uri.resolve(next);
          continue;
        }
        if (response.statusCode != 200) {
          throw SourcePageException(
            'The website returned HTTP ${response.statusCode}.',
          );
        }
        final type = response.headers['content-type']?.split(';').first.trim();
        if (type != null &&
            ![
              'text/html',
              'application/xhtml+xml',
              'text/plain',
            ].contains(type)) {
          throw const SourcePageException(
            'This file is not a readable web page.',
          );
        }
        if ((response.contentLength ?? 0) > maxBytes) {
          throw const SourcePageException('This page is too large to preview.');
        }
        final bytes = await _read(response).timeout(timeout);
        final text = utf8.decode(bytes, allowMalformed: true);
        return type == 'text/plain'
            ? SourcePage(uri.host, [
                SourcePageSection(
                  text.substring(0, text.length.clamp(0, 24000)),
                  text.substring(0, text.length.clamp(0, 24000)),
                ),
              ])
            : parseSourcePage(text, fallbackTitle: uri.host);
      }
      throw const SourcePageException('The website redirected too many times.');
    } finally {
      client.close();
    }
  }

  Future<Uint8List> _read(http.StreamedResponse response) async {
    final result = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      if (result.length + chunk.length > maxBytes) {
        throw const SourcePageException('This page is too large to preview.');
      }
      result.add(chunk);
    }
    return result.takeBytes();
  }
}

SourcePage parseSourcePage(
  String source, {
  String fallbackTitle = 'Source page',
}) {
  final document = html.parse(source);
  final title = document.querySelector('title')?.text.trim();
  for (final element in document.querySelectorAll(
    'script,style,noscript,nav,header,footer,aside,form,button,svg,iframe',
  )) {
    element.remove();
  }
  final root =
      document.querySelector('main') ??
      document.querySelector('article') ??
      document.body;
  final sections = <SourcePageSection>[];
  var characters = 0;
  String inline(dom.Node node) {
    if (node is dom.Text) {
      return node.text
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAllMapped(RegExp(r'[\\*_\[\]]'), (m) => '\\${m[0]}');
    }
    if (node is! dom.Element) return '';
    final text = node.nodes.map(inline).join();
    if (node.localName == 'strong' || node.localName == 'b') return '**$text**';
    if (node.localName == 'em' || node.localName == 'i') return '*$text*';
    if (node.localName == 'code') {
      return '`${node.text.replaceAll('`', '')}`';
    }
    if (node.localName == 'br') return '\n';
    return text;
  }

  String block(dom.Element e, [int level = 0]) {
    if (e.localName == 'pre') {
      return '```\n${e.text.replaceAll('```', '` ` `')}\n```';
    }
    if (e.localName == 'ul' || e.localName == 'ol') {
      var count = 0;
      return e.children
          .where((n) => n.localName == 'li')
          .map((li) {
            count++;
            final own = li.nodes
                .where(
                  (n) =>
                      n is! dom.Element || !['ul', 'ol'].contains(n.localName),
                )
                .map(inline)
                .join()
                .trim();
            final children = li.children
                .where((n) => ['ul', 'ol'].contains(n.localName))
                .map((n) => block(n, level + 1))
                .join('\n');
            return '${'  ' * level}${e.localName == 'ol' ? '$count.' : '-'} $own${children.isEmpty ? '' : '\n$children'}';
          })
          .join('\n');
    }
    final value = inline(e).trim();
    if (RegExp(r'^h[1-6]$').hasMatch(e.localName ?? '')) {
      return '${'#' * int.parse(e.localName![1])} $value';
    }
    if (e.localName == 'blockquote') return '> $value';
    return value;
  }

  void visit(dom.Element element) {
    if (characters >= 24000 || sections.length >= 180) return;
    if (const {
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'p',
      'pre',
      'ul',
      'ol',
      'blockquote',
      'table',
    }.contains(element.localName)) {
      final text = element.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      final rendered = block(element);
      if (text.isNotEmpty) {
        sections.add(
          SourcePageSection(
            text,
            rendered.substring(0, rendered.length.clamp(0, 6000)),
            element.id.isEmpty ? null : element.id,
          ),
        );
        characters += rendered.length;
      }
    } else {
      for (final child in element.children) {
        visit(child);
      }
    }
  }

  if (root != null) visit(root);
  if (sections.isEmpty) {
    throw const SourcePageException('This page has no readable article text.');
  }
  return SourcePage(
    title?.isNotEmpty == true ? title! : fallbackTitle,
    List.unmodifiable(sections),
  );
}
