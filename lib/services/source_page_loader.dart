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

class SourcePageImage {
  final String url;
  final String caption;
  final int section;
  const SourcePageImage(this.url, this.caption, this.section);
}

String sourceTextKey(String text) => text
    .replaceAll(RegExp(r'^[ \t]{0,3}#{1,6}[ \t]+', multiLine: true), '')
    .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m[1]!)
    .replaceAllMapped(
      RegExp(r'\*\*(.*?)\*\*|__(.*?)__|`([^`]+)`'),
      (m) => m[1] ?? m[2] ?? m[3]!,
    )
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim()
    .toLowerCase();

class SourcePage {
  final String title;
  final List<SourcePageSection> sections;
  final List<SourcePageImage> images;
  const SourcePage(this.title, this.sections, [this.images = const []]);

  int? excerptIndex(String excerpt) {
    final quote = sourceTextKey(excerpt);
    if (quote.length < 12) return null;
    for (var i = 0; i < sections.length; i++) {
      if (sourceTextKey(sections[i].text).contains(quote)) return i;
    }
    final parts = sections.map((s) => sourceTextKey(s.text)).toList();
    final at = parts.join(' ').indexOf(quote);
    if (at >= 0) {
      var cursor = 0;
      for (var i = 0; i < parts.length; i++) {
        if (cursor + parts[i].length >= at) return i;
        cursor += parts[i].length + 1;
      }
    }
    return null;
  }

  int? candidateIndex(String passage) {
    final words = RegExp(
      r'[a-zA-Z]{4,}',
    ).allMatches(passage.toLowerCase()).map((m) => m[0]!).toSet();
    final index = relevantIndex(passage);
    final found = words
        .where(
          (w) => RegExp(
            '\\b${RegExp.escape(w)}\\b',
          ).hasMatch(sections[index].text.toLowerCase()),
        )
        .length;
    return found >= 2 ? index : null;
  }

  List<SourcePageImage> imagesNear(int index) =>
      (images.toList()..sort(
            (a, b) =>
                (a.section - index).abs().compareTo((b.section - index).abs()),
          ))
          .take(2)
          .toList();

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
            : parseSourcePage(text, fallbackTitle: uri.host, baseUrl: uri);
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

// A static reader must choose one representation, rather than concatenating
// MathML, raw TeX annotations and KaTeX's hidden visual duplicate.
String _mathText(dom.Node node) {
  if (node is dom.Text) return node.text.replaceAll('⁡', '');
  if (node is! dom.Element) return '';
  String part(int i) =>
      i < node.children.length ? _mathText(node.children[i]) : '';
  return switch (node.localName) {
    'annotation' || 'annotation-xml' => '',
    'semantics' => part(0),
    'msup' => '${part(0)}^(${part(1)})',
    'msub' => '${part(0)}_(${part(1)})',
    'msubsup' => '${part(0)}_(${part(1)})^(${part(2)})',
    'mfrac' => '(${part(0)})/(${part(1)})',
    'msqrt' => 'sqrt(${node.nodes.map(_mathText).join()})',
    'mspace' => ' ',
    'mfenced' =>
      '${node.attributes['open'] ?? '('}${node.children.map(_mathText).join(node.attributes['separators'] ?? ',')}${node.attributes['close'] ?? ')'}',
    _ => node.nodes.map(_mathText).join(),
  };
}

void _normalizeSourceMath(dom.Document document) {
  for (final wrapper in document.querySelectorAll('.katex')) {
    final math = wrapper.querySelector('math');
    final value = math == null
        ? wrapper.querySelector('.katex-html')?.text
        : _mathText(math);
    if (value != null && value.trim().isNotEmpty) {
      wrapper.replaceWith(dom.Element.tag('code')..text = value.trim());
    }
  }
  for (final math in document.querySelectorAll('math')) {
    final value = _mathText(math).trim();
    if (value.isNotEmpty) {
      math.replaceWith(dom.Element.tag('code')..text = value);
    }
  }
}

SourcePage parseSourcePage(
  String source, {
  String fallbackTitle = 'Source page',
  Uri? baseUrl,
}) {
  final document = html.parse(source);
  _normalizeSourceMath(document);
  final articleRoot =
      document.querySelector('article') ?? document.querySelector('main');
  final title =
      articleRoot?.querySelector('h1')?.text.trim() ??
      document
          .querySelector('meta[property="og:title"]')
          ?.attributes['content']
          ?.trim() ??
      document.querySelector('title')?.text.trim();
  for (final element in document.querySelectorAll(
    'script,style,noscript,nav,footer,aside,form,button,svg,iframe,annotation,annotation-xml,[aria-hidden="true"]',
  )) {
    element.remove();
  }
  final root = articleRoot ?? document.body;
  final sections = <SourcePageSection>[];
  final images = <SourcePageImage>[];
  final seenImages = <String>{};
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
    if (e.localName == 'table') {
      final rows = e
          .querySelectorAll('tr')
          .map(
            (row) => row.children
                .where((cell) => ['th', 'td'].contains(cell.localName))
                .map((cell) => inline(cell).trim().replaceAll('|', r'\|'))
                .toList(),
          )
          .where((row) => row.isNotEmpty)
          .toList();
      if (rows.isEmpty) return '';
      final width = rows
          .map((row) => row.length)
          .reduce((a, b) => a > b ? a : b);
      String render(List<String> row) =>
          '| ${[...row, ...List.filled(width - row.length, '')].join(' | ')} |';
      return [
        render(rows.first),
        render(List.filled(width, '---')),
        ...rows.skip(1).map(render),
      ].join('\n');
    }
    final value = inline(e).trim();
    if (RegExp(r'^h[1-6]$').hasMatch(e.localName ?? '')) {
      return '${'#' * int.parse(e.localName![1])} $value';
    }
    if (e.localName == 'blockquote') return '> $value';
    return value;
  }

  void addImage(dom.Element image) {
    if (images.length >= 8) return;
    // Prefer a real lazy image, then a bounded responsive candidate, then src.
    final srcset =
        image.attributes['data-srcset'] ?? image.attributes['srcset'];
    final candidates = <({String url, int width})>[];
    for (final part in (srcset ?? '').split(',')) {
      final match = RegExp(r'^\s*(\S+)\s+(\d+)w\s*$').firstMatch(part);
      if (match != null) {
        candidates.add((url: match[1]!, width: int.parse(match[2]!)));
      }
    }
    candidates.sort((a, b) => a.width.compareTo(b.width));
    final suitable = candidates
        .where((c) => c.width >= 640 && c.width <= 1600)
        .toList();
    final responsive = suitable.isNotEmpty
        ? suitable.first.url
        : candidates.isNotEmpty
        ? candidates.last.url
        : null;
    final raw =
        image.attributes['data-src'] ??
        image.attributes['data-original'] ??
        responsive ??
        image.attributes['src'];
    if (raw == null) return;
    final uri = baseUrl?.resolve(raw) ?? Uri.tryParse(raw);
    if (uri == null || !HttpSourcePageLoader.isPublicPage(uri)) return;
    dom.Element? figure = image.parent;
    while (figure != null && figure.localName != 'figure') {
      figure = figure.parent;
    }
    final label =
        figure?.querySelector('figcaption')?.text ??
        image.attributes['alt'] ??
        '';
    final width = int.tryParse(image.attributes['width'] ?? '');
    final height = int.tryParse(image.attributes['height'] ?? '');
    if (label.trim().isEmpty ||
        (width != null && width < 120) ||
        (height != null && height < 80) ||
        RegExp(
          r'logo|avatar|icon|pixel|tracking|badge',
          caseSensitive: false,
        ).hasMatch('$raw $label')) {
      return;
    }
    if (!seenImages.add(uri.toString())) return;
    images.add(
      SourcePageImage(
        uri.toString(),
        label.trim().substring(0, label.trim().length.clamp(0, 240)),
        sections.length,
      ),
    );
  }

  void visit(dom.Element element) {
    if (characters >= 24000 || sections.length >= 180) return;
    if (element.localName == 'img') {
      addImage(element);
      return;
    }
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
      for (final image in element.querySelectorAll('img')) {
        addImage(image);
      }
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
    List.unmodifiable(images),
  );
}
