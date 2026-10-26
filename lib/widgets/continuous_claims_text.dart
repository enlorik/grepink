import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import '../models/claim_review_item.dart';
import '../services/markdown_list_lines.dart';

/// One reading article, preserving Markdown blocks and per-claim hit targets.
class ContinuousClaimsText extends StatefulWidget {
  final List<ClaimReviewItem> items;
  final Set<String> selectedIds;
  final String? activeId;
  final ValueChanged<ClaimReviewItem> onActivate;
  final ValueChanged<String> onToggle;
  final VoidCallback onLeave;
  final ValueChanged<PointerSignalEvent> onPointerSignal;

  const ContinuousClaimsText({
    super.key,
    required this.items,
    required this.selectedIds,
    required this.activeId,
    required this.onActivate,
    required this.onToggle,
    required this.onLeave,
    required this.onPointerSignal,
  });

  @override
  State<ContinuousClaimsText> createState() => _ContinuousClaimsTextState();
}

class _ContinuousClaimsTextState extends State<ContinuousClaimsText> {
  final _taps = <String, TapGestureRecognizer>{};
  final _parsed = <String, ({String text, List<md.Node> nodes})>{};

  @override
  void dispose() {
    for (final tap in _taps.values) {
      tap.dispose();
    }
    super.dispose();
  }

  List<md.Node> _nodes(ClaimReviewItem item) {
    if (_parsed[item.id]?.text != item.text) {
      _parsed[item.id] = (
        text: item.text,
        // AST text is consumed by Flutter, not by an HTML renderer.
        nodes: md.Document(
          extensionSet: md.ExtensionSet.gitHubFlavored,
          encodeHtml: false,
        ).parseLines(standaloneListMarkdown(item.text).split('\n')),
      );
    }
    return _parsed[item.id]!.nodes;
  }

  TextStyle _style(ClaimReviewItem item) {
    final theme = Theme.of(context);
    return theme.textTheme.bodyLarge!.copyWith(
      fontSize: 16,
      height: 1.6,
      letterSpacing: 0.1,
      decoration: widget.selectedIds.contains(item.id)
          ? TextDecoration.none
          : TextDecoration.lineThrough,
      color: widget.selectedIds.contains(item.id)
          ? theme.colorScheme.onSurface
          : theme.colorScheme.onSurfaceVariant,
      backgroundColor: widget.activeId == item.id
          ? theme.colorScheme.primary.withAlpha(14)
          : Colors.transparent,
    );
  }

  List<InlineSpan> _inline(
    ClaimReviewItem item,
    List<md.Node> nodes,
    TextStyle style,
  ) {
    final tap = _taps.putIfAbsent(item.id, TapGestureRecognizer.new);
    tap.onTap = () {
      widget.onActivate(item);
      if (item.canBeSaved) widget.onToggle(item.id);
    };
    final spans = <InlineSpan>[];
    void add(String text, TextStyle current) => spans.add(
      TextSpan(
        text: text,
        style: current,
        recognizer: tap,
        mouseCursor: SystemMouseCursors.click,
        onEnter: (_) => widget.onActivate(item),
      ),
    );
    void visit(md.Node node, TextStyle current) {
      if (node is md.Text) {
        add(node.text, current);
        return;
      }
      if (node is! md.Element) return;
      var next = current;
      if (node.tag == 'strong') {
        next = next.copyWith(fontWeight: FontWeight.w600);
      }
      if (node.tag == 'em') next = next.copyWith(fontStyle: FontStyle.italic);
      if (node.tag == 'del') {
        next = next.copyWith(decoration: TextDecoration.lineThrough);
      }
      if (node.tag == 'code') {
        next = next.copyWith(
          fontFamily: 'Consolas',
          fontFamilyFallback: const ['Menlo', 'Courier New', 'monospace'],
          fontSize: 14,
          backgroundColor: Theme.of(context).colorScheme.onSurface.withAlpha(8),
        );
      }
      if (node.tag == 'br') add('\n', next);
      if (node.tag == 'img') add(node.attributes['alt'] ?? 'Image', next);
      for (final child in node.children ?? <md.Node>[]) {
        visit(child, next);
      }
    }

    for (final node in nodes) {
      visit(node, style);
    }
    return spans;
  }

  Widget _text(
    ClaimReviewItem item,
    List<md.Node> nodes, {
    TextStyle? style,
    bool softWrap = true,
  }) => Text.rich(
    TextSpan(children: _inline(item, nodes, style ?? _style(item))),
    softWrap: softWrap,
  );

  bool _isBlock(md.Node node) =>
      node is md.Element &&
      const {
        'p',
        'ul',
        'ol',
        'pre',
        'blockquote',
        'table',
        'hr',
        'h1',
        'h2',
        'h3',
        'h4',
        'h5',
        'h6',
      }.contains(node.tag);

  List<Widget> _children(ClaimReviewItem item, List<md.Node> nodes) {
    final result = <Widget>[];
    var inline = <md.Node>[];
    void flush() {
      if (inline.isNotEmpty) {
        result.add(_text(item, inline));
        inline = [];
      }
    }

    for (final node in nodes) {
      if (_isBlock(node)) {
        flush();
        result.add(_block(item, node as md.Element));
      } else {
        inline.add(node);
      }
    }
    flush();
    return result;
  }

  Widget _block(ClaimReviewItem item, md.Element node) {
    final nodes = node.children ?? <md.Node>[];
    final tag = node.tag;
    final theme = Theme.of(context);
    if (RegExp(r'^h[1-6]$').hasMatch(tag)) {
      final level = int.parse(tag.substring(1));
      return Semantics(
        header: true,
        child: Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: _text(
            item,
            nodes,
            style: _style(item).copyWith(
              fontSize: level <= 2 ? 22 : 18,
              height: 1.3,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
        ),
      );
    }
    if (tag == 'ul' || tag == 'ol') {
      final entries = nodes
          .whereType<md.Element>()
          .where((n) => n.tag == 'li')
          .toList();
      final start = int.tryParse(node.attributes['start'] ?? '') ?? 1;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < entries.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 26,
                    child: Text(
                      tag == 'ol' ? '${start + i}.' : '•',
                      style: _style(item),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _children(
                        item,
                        entries[i].children ?? <md.Node>[],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }
    if (tag == 'pre') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.onSurface.withAlpha(5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: _text(item, nodes, softWrap: false),
        ),
      );
    }
    if (tag == 'blockquote') {
      return Container(
        padding: const EdgeInsets.only(left: 14, top: 4, bottom: 4),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: theme.colorScheme.primary.withAlpha(65),
              width: 3,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _children(item, nodes),
        ),
      );
    }
    if (tag == 'table') {
      final rows = <md.Element>[];
      void collect(md.Node child) {
        if (child is! md.Element) return;
        if (child.tag == 'tr') {
          rows.add(child);
          return;
        }
        for (final nested in child.children ?? <md.Node>[]) {
          collect(nested);
        }
      }

      collect(node);
      if (rows.isEmpty) return const SizedBox.shrink();
      final columns = rows
          .map((row) => row.children!.length)
          .reduce((a, b) => a > b ? a : b);
      return LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth > columns * 140
              ? constraints.maxWidth
              : columns * 140.0;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              child: Table(
                border: TableBorder(
                  horizontalInside: BorderSide(color: theme.dividerColor),
                ),
                children: [
                  for (final row in rows)
                    TableRow(
                      children: [
                        for (var i = 0; i < columns; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 10,
                            ),
                            child: i >= row.children!.length
                                ? const SizedBox.shrink()
                                : _text(
                                    item,
                                    (row.children![i] as md.Element).children ??
                                        <md.Node>[],
                                    style: _style(item).copyWith(
                                      fontSize: 14,
                                      fontWeight:
                                          (row.children![i] as md.Element)
                                                  .tag ==
                                              'th'
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          );
        },
      );
    }
    if (tag == 'hr') return const Divider(height: 24);
    return _text(item, nodes);
  }

  List<Widget> _article() {
    final blocks = <Widget>[];
    var paragraph = <InlineSpan>[];
    var characters = 0;
    void flush() {
      if (paragraph.isEmpty) return;
      blocks.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text.rich(
            TextSpan(children: paragraph),
            style: Theme.of(
              context,
            ).textTheme.bodyLarge!.copyWith(fontSize: 16, height: 1.6),
          ),
        ),
      );
      paragraph = [];
      characters = 0;
    }

    for (final item in widget.items) {
      final nodes = _nodes(item);
      for (var i = 0; i < nodes.length; i++) {
        final node = nodes[i];
        if (node is md.Element && node.tag == 'p') {
          // Keep sentences flowing, while respecting explicit paragraphs and
          // breaking long runs only at claim boundaries, never inside a claim.
          if (i > 0 || characters > 420) flush();
          paragraph.add(
            TextSpan(
              children: _inline(
                item,
                node.children ?? <md.Node>[],
                _style(item),
              ),
            ),
          );
          paragraph.add(const TextSpan(text: ' '));
          characters += node.textContent.length;
        } else {
          flush();
          blocks.add(
            Padding(
              padding: EdgeInsets.only(
                bottom: 10,
                left: (MarkdownListLine.parse(item.text)?.indent ?? 0) * 8.0,
              ),
              child: node is md.Element
                  ? _block(item, node)
                  : _text(item, [node]),
            ),
          );
        }
      }
    }
    flush();
    return blocks;
  }

  @override
  Widget build(BuildContext context) {
    final ids = widget.items.map((item) => item.id).toSet();
    for (final id in _taps.keys.where((id) => !ids.contains(id)).toList()) {
      _taps.remove(id)!.dispose();
      _parsed.remove(id);
    }
    return MouseRegion(
      onExit: (_) => widget.onLeave(),
      child: Listener(
        onPointerSignal: widget.onPointerSignal,
        child: Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 740),
            child: Column(
              key: const Key('continuous-claims-text'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _article(),
            ),
          ),
        ),
      ),
    );
  }
}
