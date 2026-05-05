import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class GrepinkFab extends StatefulWidget {
  final VoidCallback? onPressed;
  final bool isSaving;
  final bool showSuccess;
  final IconData icon;

  const GrepinkFab({
    super.key,
    this.onPressed,
    this.isSaving = false,
    this.showSuccess = false,
    this.icon = Icons.add,
  });

  @override
  State<GrepinkFab> createState() => _GrepinkFabState();
}

class _GrepinkFabState extends State<GrepinkFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scale = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    Future.microtask(() {
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

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;

    Widget iconChild;
    if (widget.isSaving) {
      iconChild = const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          color: AppColors.surface,
          strokeWidth: 2.5,
        ),
      );
    } else if (widget.showSuccess) {
      iconChild = const Icon(Icons.check, color: AppColors.surface, size: 28);
    } else {
      iconChild = Icon(widget.icon, color: AppColors.surface, size: 28);
    }

    final fab = FloatingActionButton(
      onPressed: widget.isSaving ? null : widget.onPressed,
      tooltip: widget.showSuccess ? 'Saved' : 'Save',
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primaryAction, AppColors.primaryAccent],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryAction.withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(child: iconChild),
      ),
    );

    if (reduce) return fab;

    return FadeTransition(
      opacity: _opacity,
      child: ScaleTransition(scale: _scale, child: fab),
    );
  }
}
