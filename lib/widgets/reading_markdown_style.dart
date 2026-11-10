import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// One restrained type scale for notes and extracted article text.
MarkdownStyleSheet readingMarkdownStyle(
  BuildContext context, {
  bool compact = false,
}) {
  final theme = Theme.of(context);
  final body = theme.textTheme.bodyLarge!.copyWith(
    fontSize: compact ? 14 : 15,
    height: 1.45,
    letterSpacing: 0,
    color: theme.colorScheme.onSurface,
  );
  TextStyle heading(double size) => body.copyWith(
    fontSize: size,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: -.3,
  );
  return MarkdownStyleSheet.fromTheme(theme).copyWith(
    p: body,
    h1: heading(compact ? 18 : 24),
    h2: heading(compact ? 16 : 20),
    h3: heading(compact ? 15 : 17),
    h4: heading(16),
    h5: heading(15),
    h6: heading(14),
    strong: const TextStyle(fontWeight: FontWeight.w600),
    blockSpacing: 8,
    listBullet: body,
    listIndent: 22,
    code: body.copyWith(fontFamily: 'monospace', fontSize: compact ? 12 : 14),
    codeblockPadding: const EdgeInsets.all(12),
    codeblockDecoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(8),
    ),
    blockquotePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    blockquoteDecoration: BoxDecoration(
      border: Border(
        left: BorderSide(
          color: theme.colorScheme.primary.withValues(alpha: .35),
          width: 2,
        ),
      ),
    ),
  );
}
