import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../models/note.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class NoteCard extends StatefulWidget {
  final Note note;
  final int index;
  final VoidCallback? onDelete;
  final VoidCallback? onPin;

  const NoteCard({
    super.key,
    required this.note,
    required this.index,
    this.onDelete,
    this.onPin,
  });

  @override
  State<NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<NoteCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _slide = Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    final delay = widget.index * 40;
    Future.delayed(Duration(milliseconds: delay), () {
      if (mounted) {
        final reduce = MediaQuery.of(context).disableAnimations;
        if (reduce) {
          _controller.value = 1.0;
        } else {
          _controller.forward();
        }
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _relativeTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: GestureDetector(
          onLongPress: () => _showContextMenu(context),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border(
                left: BorderSide(
                  color: widget.note.isPinned ? AppColors.pinHighlight : Colors.transparent,
                  width: 3,
                ),
                top: const BorderSide(color: AppColors.dividerBorder),
                right: const BorderSide(color: AppColors.dividerBorder),
                bottom: const BorderSide(color: AppColors.dividerBorder),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryAccent.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => context.push('/note/${widget.note.id}'),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.note.title.isEmpty ? 'Untitled' : widget.note.title,
                            style: AppTextStyles.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (widget.note.embeddingPending)
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Text('⏳', style: TextStyle(fontSize: 12)),
                          ),
                        if (widget.note.isPinned)
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(Icons.push_pin, size: 14, color: AppColors.pinHighlight),
                          ),
                      ],
                    ),
                    if (widget.note.content.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        widget.note.content,
                        style: AppTextStyles.bodyMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (widget.note.tags.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: widget.note.tags.take(3).map((tag) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.tagBackground,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.tagBorder),
                          ),
                          child: Text(
                            tag,
                            style: AppTextStyles.bodySmall.copyWith(color: AppColors.deepAction),
                          ),
                        )).toList(),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      _relativeTime(widget.note.updatedAt),
                      style: AppTextStyles.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.dividerBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(
                widget.note.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                color: AppColors.pinHighlight,
              ),
              title: Text(widget.note.isPinned ? 'Unpin' : 'Pin'),
              onTap: () {
                Navigator.pop(ctx);
                widget.onPin?.call();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.deleteHighlight),
              title: const Text('Delete'),
              onTap: () {
                Navigator.pop(ctx);
                widget.onDelete?.call();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
