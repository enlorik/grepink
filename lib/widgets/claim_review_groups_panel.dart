import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../models/claim_deduplication_result.dart';
import '../models/claim_review_item.dart';
import '../models/grounded_answer.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'claim_source_preview.dart';
import 'continuous_claims_text.dart';

/// Above this many items, the "Already in your notes" section starts
/// collapsed so a long list of known claims doesn't push the useful
/// (new/better-source) groups below the fold.
const int _alreadyKnownCollapseThreshold = 3;

/// Displays grouped claim review results and lets the user toggle which
/// claims are selected. This panel never saves or persists anything itself —
/// it only reflects and mutates [selectedIds] via [onToggle].
class ClaimReviewGroupsPanel extends StatefulWidget {
  final List<ClaimReviewGroup> groups;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggle;
  // Safe, already-normalized provider label — null means no label is shown.
  final String? providerLabel;
  final List<GroundedAnswerCitation> citations;
  final bool inlineSources;

  const ClaimReviewGroupsPanel({
    super.key,
    required this.groups,
    required this.selectedIds,
    required this.onToggle,
    this.providerLabel,
    this.citations = const [],
    this.inlineSources = false,
  });

  @override
  State<ClaimReviewGroupsPanel> createState() => _ClaimReviewGroupsPanelState();
}

class _ClaimReviewGroupsPanelState extends State<ClaimReviewGroupsPanel> {
  final _previewController = OverlayPortalController();
  String? _activeId;
  bool _pinned = false;
  bool _continuous = true;
  bool _previewVisible = false;
  final _sourceScroll = ScrollController();
  Timer? _hideTimer;
  String? _dismissedId;

  @override
  void dispose() {
    _hideTimer?.cancel();
    _sourceScroll.dispose();
    super.dispose();
  }

  void _showPreview() {
    if (!widget.inlineSources) _previewController.show();
    if (!_previewVisible) setState(() => _previewVisible = true);
  }

  void _hidePreview() {
    if (!widget.inlineSources) _previewController.hide();
    if (_previewVisible) setState(() => _previewVisible = false);
  }

  void _leave() {
    _hideTimer?.cancel();
    if (!_pinned) {
      _hideTimer = Timer(const Duration(milliseconds: 250), () {
        if (mounted && !_pinned) _hidePreview();
      });
    }
  }

  void _hover(ClaimReviewItem item) {
    _hideTimer?.cancel();
    final changed = _activeId != item.id;
    _activate(item);
    if (_dismissedId != item.id) _showPreview();
    if (changed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _sourceScroll.hasClients) _sourceScroll.jumpTo(0);
      });
    }
  }

  void _closePreview() {
    _hideTimer?.cancel();
    setState(() {
      _pinned = false;
      _dismissedId = _activeId;
    });
    _hidePreview();
  }

  void _scrollSource(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        !_previewVisible ||
        !_sourceScroll.hasClients ||
        _sourceScroll.position.maxScrollExtent == 0) {
      return;
    }
    // Register before the ancestor page Scrollable, so only the source moves.
    GestureBinding.instance.pointerSignalResolver.register(event, (signal) {
      if (!mounted || !_sourceScroll.hasClients) return;
      final position = _sourceScroll.position;
      _sourceScroll.jumpTo(
          (position.pixels + (signal as PointerScrollEvent).scrollDelta.dy)
              .clamp(position.minScrollExtent, position.maxScrollExtent)
              .toDouble());
    });
  }

  Widget _readingView(List<ClaimReviewItem> items, ClaimReviewItem? active) {
    final current = active ?? items.first;
    final index = items.indexWhere((item) => item.id == current.id);
    final group = widget.groups.firstWhere(
        (group) => group.items.any((item) => item.id == current.id));
    void navigate(int offset) => _hover(items[(index + offset) % items.length]);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
          'Click a sentence to ignore it; click again to include it. Hover for sources and scroll to read them.',
          style: AppTextStyles.bodySmall),
      const SizedBox(height: 12),
      ContinuousClaimsText(
        items: items,
        selectedIds: widget.selectedIds,
        activeId: active?.id,
        onActivate: _hover,
        onToggle: widget.onToggle,
        onLeave: _leave,
        onPointerSignal: _scrollSource,
      ),
      const SizedBox(height: 12),
      Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            IconButton(
                key: const Key('previous-inline-claim'),
                tooltip: 'Previous claim',
                onPressed: () => navigate(-1),
                icon: const Icon(Icons.chevron_left)),
            Text('${index + 1}/${items.length} · ${group.label}',
                key: const Key('active-claim-status'),
                style: AppTextStyles.bodySmall),
            TextButton(
                key: const Key('toggle-active-claim'),
                onPressed: current.canBeSaved
                    ? () => widget.onToggle(current.id)
                    : null,
                child: Text(current.canBeSaved
                    ? (widget.selectedIds.contains(current.id)
                        ? 'Ignore'
                        : 'Include')
                    : 'Not eligible to add')),
            TextButton(
                key: const Key('inline-claim-sources'),
                onPressed: () {
                  _dismissedId = null;
                  _hover(current);
                  setState(() => _pinned = true);
                },
                child: Text(
                    '${claimSourcePreviews(current, widget.citations).length} sources')),
            IconButton(
                key: const Key('next-inline-claim'),
                tooltip: 'Next claim',
                onPressed: () => navigate(1),
                icon: const Icon(Icons.chevron_right)),
          ]),
      if (current.reason.trim().isNotEmpty)
        ClaimFormattedText(
            data: current.reason, style: AppTextStyles.bodySmall),
    ]);
  }

  void _activate(ClaimReviewItem item) {
    if (_activeId != item.id) setState(() => _activeId = item.id);
  }

  void _togglePreview() {
    _dismissedId = null;
    _hideTimer?.cancel();
    setState(() => _pinned = !_pinned);
    if (_pinned) {
      _showPreview();
    } else {
      _hidePreview();
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = widget.groups;
    final selectedIds = widget.selectedIds;
    final onToggle = widget.onToggle;
    final providerLabel = widget.providerLabel;
    final visibleGroups =
        groups.where((group) => group.items.isNotEmpty).toList();

    if (visibleGroups.isEmpty) {
      return const SizedBox.shrink();
    }

    final ordered =
        groups.expand((group) => group.items).toList().asMap().entries.toList()
          ..sort((a, b) {
            final order = (a.value.sourceOrder ?? a.key)
                .compareTo(b.value.sourceOrder ?? b.key);
            return order == 0 ? a.key.compareTo(b.key) : order;
          });
    final items = ordered.map((entry) => entry.value).toList();
    final active = groups
        .expand((g) => g.items)
        .where((i) => i.id == _activeId)
        .firstOrNull;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1136),
        child: Container(
          key: const Key('claim-review-groups-panel'),
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.dividerBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Claim review', style: AppTextStyles.titleLarge),
                  TextButton(
                    key: const Key('claim-review-view-toggle'),
                    onPressed: () {
                      _hideTimer?.cancel();
                      _closePreview();
                      setState(() => _continuous = !_continuous);
                    },
                    child: Text(_continuous ? 'Detailed list' : 'Reading view'),
                  ),
                  TextButton.icon(
                    key: const Key('pin-source-preview'),
                    onPressed: _togglePreview,
                    icon: Icon(
                      _pinned ? Icons.push_pin : Icons.push_pin_outlined,
                    ),
                    label: Text(
                      _pinned ? 'Close source pane' : 'Keep sources open',
                    ),
                  ),
                ],
              ),
              if (providerLabel != null) ...[
                const SizedBox(height: 2),
                Text(
                  key: const Key('claim-review-provider-label'),
                  'Answered via $providerLabel',
                  style: AppTextStyles.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              LayoutBuilder(builder: (context, constraints) {
                final docked = _continuous &&
                    constraints.maxWidth >= 960 &&
                    MediaQuery.textScalerOf(context).scale(16) <= 24;
                const sourceWidth = 340.0;
                const gutter = 24.0;
                final readingWidth = docked
                    ? constraints.maxWidth - sourceWidth - gutter
                    : math.min(740.0, constraints.maxWidth);
                if (widget.inlineSources) {
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _readingView(items, active),
                        if (_previewVisible) ...[
                          const SizedBox(height: 16),
                          SizedBox(
                              height: 260,
                              child: SingleChildScrollView(
                                key: const Key('source-preview-scroll'),
                                controller: _sourceScroll,
                                child: ClaimSourcePreviewPane(
                                    item: active,
                                    citations: widget.citations,
                                    onClose: _closePreview,
                                    docked: true),
                              )),
                        ],
                      ]);
                }
                return OverlayPortal.overlayChildLayoutBuilder(
                  controller: _previewController,
                  overlayChildBuilder: (context, info) {
                    final media = MediaQuery.of(context);
                    final size = info.overlaySize;
                    final origin = MatrixUtils.transformPoint(
                        info.childPaintTransform, Offset.zero);
                    final bottom =
                        80 + media.padding.bottom + media.viewInsets.bottom;
                    final safeTop =
                        math.min(96.0 + media.padding.top, size.height * .25);
                    final top = origin.dy
                        .clamp(safeTop,
                            math.max(safeTop, size.height - bottom - 160))
                        .toDouble();
                    final height = docked
                        ? math.min(
                            640.0,
                            math.max(
                                0.0,
                                math.min(size.height - bottom,
                                        origin.dy + info.childSize.height) -
                                    top))
                        : math.max(
                            0.0,
                            math.min(
                                size.height * .45, size.height - bottom - 16));
                    Widget preview = MouseRegion(
                      onEnter: (_) => _hideTimer?.cancel(),
                      onExit: (_) => _leave(),
                      child: SingleChildScrollView(
                        key: const Key('source-preview-scroll'),
                        controller: _sourceScroll,
                        child: ClaimSourcePreviewPane(
                          item: active,
                          citations: widget.citations,
                          onClose: _closePreview,
                          docked: docked,
                        ),
                      ),
                    );
                    if (docked) {
                      preview = DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withAlpha(60)),
                        ),
                        child: Padding(
                            padding: const EdgeInsets.all(1),
                            child: ClipRRect(
                                borderRadius: BorderRadius.circular(11),
                                child: preview)),
                      );
                    }
                    return Positioned(
                      key: Key(docked
                          ? 'docked-source-preview'
                          : 'compact-source-preview'),
                      left: docked ? origin.dx + readingWidth + gutter : null,
                      right: docked ? null : 16,
                      top: docked ? top : null,
                      bottom: docked ? null : bottom,
                      width: docked
                          ? sourceWidth
                          : math.max(0, math.min(380.0, size.width - 32)),
                      child: ConstrainedBox(
                        key: const Key('source-preview-frame'),
                        constraints: BoxConstraints(maxHeight: height),
                        child: preview,
                      ),
                    );
                  },
                  child: _continuous
                      ? ConstrainedBox(
                          constraints:
                              BoxConstraints(minHeight: docked ? 320 : 0),
                          child: Row(
                              mainAxisAlignment: docked
                                  ? MainAxisAlignment.start
                                  : MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                    width: readingWidth,
                                    child: _readingView(items, active)),
                                if (docked) ...[
                                  const SizedBox(width: gutter),
                                  SizedBox(
                                    width: sourceWidth,
                                    child: Visibility(
                                      visible: !_previewVisible,
                                      maintainSize: true,
                                      maintainState: true,
                                      maintainAnimation: true,
                                      child:
                                          const _SourceWorkspacePlaceholder(),
                                    ),
                                  ),
                                ],
                              ]))
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                              for (final group in visibleGroups) ...[
                                _ClaimReviewGroupSection(
                                  group: group,
                                  selectedIds: selectedIds,
                                  onToggle: onToggle,
                                  citations: widget.citations,
                                  onPreview: _activate,
                                  onOpenSources: (item) {
                                    _activate(item);
                                    if (!_pinned) _togglePreview();
                                  },
                                ),
                                const SizedBox(height: 16),
                              ]
                            ]),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceWorkspacePlaceholder extends StatelessWidget {
  const _SourceWorkspacePlaceholder();

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('source-workspace-placeholder'),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.aiResponseBackground.withAlpha(100),
          border: Border.all(color: AppColors.dividerBorder),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.menu_book_outlined,
                  size: 20, color: AppColors.deepAction),
              SizedBox(height: 12),
              Text('Sources',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              SizedBox(height: 6),
              Text(
                  'Hover a sentence or use its Sources button to read references here.',
                  style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: AppColors.secondaryText)),
            ]),
      );
}

class _ClaimReviewGroupSection extends StatelessWidget {
  final ClaimReviewGroup group;
  final List<GroundedAnswerCitation> citations;
  final ValueChanged<ClaimReviewItem> onPreview;
  final ValueChanged<ClaimReviewItem> onOpenSources;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggle;

  const _ClaimReviewGroupSection({
    required this.group,
    required this.citations,
    required this.onPreview,
    required this.onOpenSources,
    required this.selectedIds,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final headerText = '${group.label} (${group.items.length})';

    // Already-known claims aren't saveable and are usually the least
    // actionable group, so they get a compact, collapsible treatment
    // instead of always taking up full space like the other groups.
    if (group.classification == ClaimNoveltyClassification.alreadyKnown) {
      // Key on whether the group starts collapsed so a new review that
      // crosses the collapse threshold recreates the ExpansionTile with the
      // correct initiallyExpanded — preventing stale expansion state from
      // the previous session leaking into the new one.
      final collapsedByDefault =
          group.items.length > _alreadyKnownCollapseThreshold;
      // Deterministic string key: encodes the collapse-default flag and the
      // ordered item IDs so that (a) the same result with ordinary rebuilds
      // preserves user expansion state, and (b) a genuinely different result
      // (different IDs or threshold side) recreates the tile and re-applies
      // initiallyExpanded — no hash-collision risk.
      final sectionKey =
          '${collapsedByDefault}_${group.items.map((i) => i.id).join('|')}';
      return _AlreadyKnownGroupSection(
        key: ValueKey(sectionKey),
        group: group,
        headerText: headerText,
        citations: citations,
        onPreview: onPreview,
        onOpenSources: onOpenSources,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(headerText, style: AppTextStyles.titleMedium),
        if (group.classification == ClaimNoveltyClassification.newClaim) ...[
          const SizedBox(height: 4),
          Text(
            key: const Key('new-claim-helper-text'),
            'New claims are selected by default.',
            style: AppTextStyles.bodySmall,
          ),
        ],
        if (group.classification ==
            ClaimNoveltyClassification.betterSource) ...[
          const SizedBox(height: 4),
          Text(
            key: const Key('better-source-helper-text'),
            'Already in your notes, but this source may improve the existing claim.',
            style: AppTextStyles.bodySmall,
          ),
        ],
        if (group.classification ==
            ClaimNoveltyClassification.contradiction) ...[
          const SizedBox(height: 4),
          Text(
            key: const Key('contradiction-helper-text'),
            'Not selected by default. Include only after reviewing the conflict.',
            style: AppTextStyles.bodySmall,
          ),
        ],
        if (group.classification == ClaimNoveltyClassification.uncertain) ...[
          const SizedBox(height: 4),
          Text(
            key: const Key('uncertain-claim-helper-text'),
            'Uncertain claims cannot be added to a draft.',
            style: AppTextStyles.bodySmall,
          ),
        ],
        const SizedBox(height: 8),
        for (final item in group.items)
          _ClaimReviewItemTile(
            key: Key('claim-review-item-${item.id}'),
            item: item,
            citations: citations,
            onPreview: onPreview,
            onOpenSources: onOpenSources,
            selected: selectedIds.contains(item.id),
            onToggle: () => onToggle(item.id),
          ),
      ],
    );
  }
}

/// Compact, collapsible rendering for the "Already in notes" group. Starts
/// collapsed once there are enough items that showing them all would push
/// the actionable groups below the fold; the user can still expand it.
class _AlreadyKnownGroupSection extends StatelessWidget {
  final ClaimReviewGroup group;
  final List<GroundedAnswerCitation> citations;
  final ValueChanged<ClaimReviewItem> onPreview;
  final ValueChanged<ClaimReviewItem> onOpenSources;
  final String headerText;

  const _AlreadyKnownGroupSection({
    super.key,
    required this.group,
    required this.citations,
    required this.onPreview,
    required this.onOpenSources,
    required this.headerText,
  });

  @override
  Widget build(BuildContext context) {
    final collapsedByDefault =
        group.items.length > _alreadyKnownCollapseThreshold;
    // Material is required so that the ExpansionTile's internal ListTile paints
    // ink/splashes onto this surface rather than the panel's outer DecoratedBox.
    // Without it Flutter 3.44+ throws an assertion (ListTile in DecoratedBox).
    return Material(
      color: Colors.transparent,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const Key('already-known-section'),
          initiallyExpanded: !collapsedByDefault,
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          title: Text(headerText, style: AppTextStyles.titleMedium),
          subtitle: Text(
            'Not saved — shown so you know Grepink already has this.',
            style: AppTextStyles.bodySmall,
          ),
          children: [
            for (final item in group.items)
              _ClaimReviewItemTile(
                key: Key('claim-review-item-${item.id}'),
                item: item,
                citations: citations,
                onPreview: onPreview,
                onOpenSources: onOpenSources,
                selected: false,
                onToggle: () {},
              ),
          ],
        ),
      ),
    );
  }
}

class _ClaimReviewItemTile extends StatelessWidget {
  final ClaimReviewItem item;
  final List<GroundedAnswerCitation> citations;
  final ValueChanged<ClaimReviewItem> onPreview;
  final ValueChanged<ClaimReviewItem> onOpenSources;
  final bool selected;
  final VoidCallback onToggle;

  const _ClaimReviewItemTile({
    super.key,
    required this.item,
    required this.citations,
    required this.onPreview,
    required this.onOpenSources,
    required this.selected,
    required this.onToggle,
  });

  Widget? _buildSubtitle() {
    final lines = <Widget>[];
    if (item.reason.trim().isNotEmpty) {
      lines.add(ClaimFormattedText(
          data: item.reason, style: AppTextStyles.bodySmall));
    }
    // Only alreadyKnown and betterSource results have confirmed local matches.
    // For newClaim and others the dedup service may return a low-similarity
    // bestMatch in matchedLocalEvidence even though the claim is genuinely new,
    // so showing "Matches your notes" there would be misleading.
    final isConfirmedMatch =
        item.classification == ClaimNoveltyClassification.alreadyKnown ||
            item.classification == ClaimNoveltyClassification.betterSource;
    if (isConfirmedMatch && item.matchedLocalEvidenceIds.isNotEmpty) {
      final matches = <String>[];
      for (var i = 0; i < item.matchedLocalEvidenceIds.length; i++) {
        final title = i < item.matchedLocalEvidenceTitles.length
            ? item.matchedLocalEvidenceTitles[i]
            : '';
        matches.add(
          title.trim().isEmpty ? item.matchedLocalEvidenceIds[i] : title,
        );
      }
      lines.add(
        Text(
          key: Key('claim-review-matched-evidence-${item.id}'),
          'Matches your notes: ${matches.join(', ')}',
          style: AppTextStyles.bodySmall,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    if (lines.isEmpty) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines,
    );
  }

  Widget _buildSources() {
    final sources = claimSourcePreviews(item, citations);
    if (sources.isNotEmpty) {
      final first = sources.first;
      return Tooltip(
        message:
            '${first.title}\n${first.excerpt == null ? "Source excerpt unavailable." : sourcePlainText(first.excerpt!)}',
        child: TextButton.icon(
          key: Key('claim-review-sources-${item.id}'),
          onPressed: () => onOpenSources(item),
          icon: const Icon(Icons.source_outlined, size: 16),
          label: Text(
            '${sources.length} ${sources.length == 1 ? "source" : "sources"}',
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: AppColors.aiResponseBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.dividerBorder),
      ),
      child: MouseRegion(
        onEnter: (_) => onPreview(item),
        child: Focus(
          onFocusChange: (focused) {
            if (focused) onPreview(item);
          },
          child: Material(
            color: Colors.transparent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CheckboxListTile(
                  value: selected,
                  onChanged: item.canBeSaved ? (_) => onToggle() : null,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: ClaimFormattedText(
                      data: item.text, style: AppTextStyles.bodyMedium),
                  subtitle: _buildSubtitle(),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 60),
                  child: _buildSources(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
