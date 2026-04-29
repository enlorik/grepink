import 'package:flutter/material.dart';
import '../models/excerpt_result.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'similarity_badge.dart';

class ExcerptQuoteCard extends StatefulWidget {
  final ExcerptResult result;
  final VoidCallback? onTap;

  const ExcerptQuoteCard({
    super.key,
    required this.result,
    this.onTap,
  });

  @override
  State<ExcerptQuoteCard> createState() => _ExcerptQuoteCardState();
}

class _ExcerptQuoteCardState extends State<ExcerptQuoteCard>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulseScale;
  late final Animation<Offset> _slideUp;
  late final Animation<double> _textReveal;
  late final Animation<double> _badgePop;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );

    // Step 1: pulse in 0-150ms
    _pulseScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.85, end: 1.05), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.05, end: 1.0), weight: 10),
    ]).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.2, curve: Curves.easeOut),
    ));

    // Step 2: slide up 150-350ms
    _slideUp = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.2, 0.47, curve: Curves.easeOut),
    ));

    // Step 3: text reveal 350-550ms
    _textReveal = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.47, 0.73, curve: Curves.easeIn),
      ),
    );

    // Step 4: badge pop 550-750ms
    _badgePop = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.73, 1.0, curve: Curves.easeOutBack),
      ),
    );

    final reduce = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    if (reduce) {
      _controller.value = 1.0;
    } else {
      Future.microtask(() => _controller.forward());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    if (reduce) return _buildCard();

    return ScaleTransition(
      scale: _pulseScale,
      child: SlideTransition(
        position: _slideUp,
        child: _buildCard(),
      ),
    );
  }

  Widget _buildCard() {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.excerptQuoteBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border(
            left: const BorderSide(color: AppColors.excerptQuoteBorder, width: 3),
            top: BorderSide(color: AppColors.excerptQuoteBorder.withOpacity(0.3)),
            right: BorderSide(color: AppColors.excerptQuoteBorder.withOpacity(0.3)),
            bottom: BorderSide(color: AppColors.excerptQuoteBorder.withOpacity(0.3)),
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.result.note.title.toUpperCase(),
              style: AppTextStyles.excerptSource,
            ),
            const SizedBox(height: 8),
            AnimatedBuilder(
              animation: _textReveal,
              builder: (context, child) => Opacity(
                opacity: _textReveal.value,
                child: child,
              ),
              child: Text(
                widget.result.excerptText,
                style: AppTextStyles.excerptQuote,
              ),
            ),
            if (widget.result.showBadge) ...[
              const SizedBox(height: 12),
              AnimatedBuilder(
                animation: _badgePop,
                builder: (context, child) => Transform.scale(
                  scale: _badgePop.value,
                  alignment: Alignment.centerLeft,
                  child: Opacity(opacity: _badgePop.value, child: child),
                ),
                child: SimilarityBadge(score: widget.result.similarityScore),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
