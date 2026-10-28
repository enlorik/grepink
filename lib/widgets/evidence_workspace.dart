import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import '../models/grounded_answer.dart';
import '../services/source_page_loader.dart';
import '../theme/app_colors.dart';
import 'source_page_reader.dart';

/// One evidence selection survives focus changes between note and research.
class EvidenceSelection {
  final String passage;
  final List<GroundedAnswerCitation> sources;
  const EvidenceSelection(this.passage, this.sources);
}

class EvidenceController extends ValueNotifier<EvidenceSelection?> {
  EvidenceController() : super(null);
  final scroll = ScrollController();
  int index = 0;
  bool pinned = false;

  void inspect(String passage, List<GroundedAnswerCitation> sources) {
    if (pinned || sources.isEmpty) return;
    if (value?.passage == passage &&
        value!.sources.map((s) => s.url).join('\n') ==
            sources.map((s) => s.url).join('\n')) {
      return;
    }
    index = 0;
    value = EvidenceSelection(passage, List.unmodifiable(sources));
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  void select(int offset) {
    if (value == null) return;
    index = (index + offset) % value!.sources.length;
    if (scroll.hasClients) scroll.jumpTo(0);
    notifyListeners();
  }

  void clear() {
    pinned = false;
    index = 0;
    value = null;
  }

  void wheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || value == null) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (!scroll.hasClients) return;
      final position = scroll.position;
      final delta = event.scrollDelta.dy;
      if ((delta > 0 && position.pixels >= position.maxScrollExtent - .5) ||
          (delta < 0 && position.pixels <= position.minScrollExtent + .5)) {
        if (value!.sources.length > 1) select(delta > 0 ? 1 : -1);
      } else {
        scroll.jumpTo(
          (position.pixels + delta)
              .clamp(0.0, position.maxScrollExtent)
              .toDouble(),
        );
      }
    });
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }
}

class EvidencePane extends StatelessWidget {
  final EvidenceController controller;
  final SourcePageLoader? loader;
  const EvidencePane({super.key, required this.controller, this.loader});

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<EvidenceSelection?>(
    valueListenable: controller,
    builder: (context, selection, _) {
      final source = selection == null
          ? null
          : selection.sources[controller.index];
      return LayoutBuilder(
        builder: (context, box) {
          final compact = box.maxHeight < 300;
          return Container(
            key: const Key('workspace-evidence'),
            decoration: const BoxDecoration(
              color: AppColors.backgroundStart,
              border: Border(left: BorderSide(color: AppColors.dividerBorder)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Evidence',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (selection != null) ...[
                        IconButton(
                          tooltip: 'Previous source',
                          onPressed: () => controller.select(-1),
                          icon: const Icon(Icons.chevron_left, size: 18),
                        ),
                        Text(
                          '${controller.index + 1}/${selection.sources.length}',
                        ),
                        IconButton(
                          tooltip: 'Next source',
                          onPressed: () => controller.select(1),
                          icon: const Icon(Icons.chevron_right, size: 18),
                        ),
                        IconButton(
                          tooltip: controller.pinned
                              ? 'Follow hovered text'
                              : 'Pin this evidence',
                          onPressed: () {
                            controller.pinned = !controller.pinned;
                            controller.select(0);
                          },
                          icon: Icon(
                            controller.pinned
                                ? Icons.push_pin
                                : Icons.push_pin_outlined,
                            size: 16,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: source == null
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            'Hover a sourced passage to check its evidence here.\n\nScroll over the passage to read quotes and move between sources.',
                          ),
                        )
                      : SingleChildScrollView(
                          key: const Key('workspace-evidence-scroll'),
                          controller: controller.scroll,
                          padding: compact
                              ? const EdgeInsets.fromLTRB(16, 6, 16, 12)
                              : const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (!compact) ...[
                                Text(
                                  selection!.passage,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(fontStyle: FontStyle.italic),
                                ),
                                const SizedBox(height: 12),
                              ],
                              Text(
                                source.title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              if (!compact) ...[
                                const SizedBox(height: 4),
                                Text(
                                  Uri.tryParse(source.url)?.host ?? '',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                              SizedBox(height: compact ? 6 : 16),
                              SourcePageReader(
                                url: source.url,
                                passage: selection!.passage,
                                savedExcerpt: source.snippet,
                                loader: loader,
                              ),
                              const SizedBox(height: 12),
                              TextButton.icon(
                                onPressed: () => Clipboard.setData(
                                  ClipboardData(text: source.url),
                                ),
                                icon: const Icon(Icons.copy, size: 16),
                                label: const Text('Copy source link'),
                              ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
