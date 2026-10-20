import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import '../models/claim_review_item.dart';

/// One wrapping paragraph, with hit targets on text spans rather than cards.
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

  List<InlineSpan> _spans(ClaimReviewItem item, TextStyle base) {
    final tap = _taps.putIfAbsent(item.id, TapGestureRecognizer.new);
    tap.onTap = () {
      widget.onActivate(item);
      if (item.canBeSaved) widget.onToggle(item.id);
    };
    if (_parsed[item.id]?.text != item.text) {
      _parsed[item.id] = (
        text: item.text,
        nodes: md.Document(extensionSet: md.ExtensionSet.gitHubFlavored)
            .parseLines(item.text.split('\n')),
      );
    }
    final spans = <InlineSpan>[];
    void add(String text, TextStyle style) {
      spans.add(TextSpan(
        text: text,
        style: style,
        recognizer: tap,
        mouseCursor: SystemMouseCursors.click,
        onEnter: (_) => widget.onActivate(item),
      ));
    }

    void visit(md.Node node, TextStyle style) {
      if (node is md.Text) {
        add(node.text, style);
        return;
      }
      if (node is! md.Element) return;
      final tag = node.tag;
      var next = style;
      if (tag == 'strong' || RegExp(r'^h[1-6]$').hasMatch(tag)) {
        next = next.copyWith(fontWeight: FontWeight.bold);
      }
      if (tag == 'em') next = next.copyWith(fontStyle: FontStyle.italic);
      if (tag == 'code' || tag == 'pre') {
        next = next.copyWith(fontFamily: 'monospace');
      }
      if (tag == 'del') {
        next = next.copyWith(decoration: TextDecoration.lineThrough);
      }
      if (tag == 'br') add('\n', next);
      if (tag == 'li') add('• ', next);
      if (tag == 'img') add(node.attributes['alt'] ?? 'Image', next);
      for (final child in node.children ?? <md.Node>[]) {
        visit(child, next);
      }
      if (tag == 'p' ||
          tag == 'li' ||
          tag == 'pre' ||
          tag == 'tr' ||
          RegExp(r'^h[1-6]$').hasMatch(tag)) {
        add('\n', style);
      } else if (tag == 'td' || tag == 'th') {
        add('  ', style);
      }
    }

    for (final node in _parsed[item.id]!.nodes) {
      visit(node, base);
    }
    // Ordinary sentences flow together, without a separate block per claim.
    while (spans.isNotEmpty && (spans.last as TextSpan).text == '\n') {
      spans.removeLast();
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final ids = widget.items.map((item) => item.id).toSet();
    for (final id in _taps.keys.where((id) => !ids.contains(id)).toList()) {
      _taps.remove(id)!.dispose();
      _parsed.remove(id);
    }
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyLarge!.copyWith(height: 1.7);
    return MouseRegion(
      onExit: (_) => widget.onLeave(),
      child: Listener(
        onPointerSignal: widget.onPointerSignal,
        child: Text.rich(
          key: const Key('continuous-claims-text'),
          TextSpan(children: [
            for (final item in widget.items) ...[
              TextSpan(
                children: _spans(
                    item,
                    base.copyWith(
                      decoration: widget.selectedIds.contains(item.id)
                          ? TextDecoration.none
                          : TextDecoration.lineThrough,
                      color: widget.selectedIds.contains(item.id)
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                      backgroundColor: widget.activeId == item.id
                          ? theme.colorScheme.primaryContainer
                          : Colors.transparent,
                    )),
              ),
              const TextSpan(text: ' '),
            ],
          ]),
          style: base,
        ),
      ),
    );
  }
}
