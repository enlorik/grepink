import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class MemoryPulseIndicator extends StatefulWidget {
  const MemoryPulseIndicator({super.key});

  @override
  State<MemoryPulseIndicator> createState() => _MemoryPulseIndicatorState();
}

class _MemoryPulseIndicatorState extends State<MemoryPulseIndicator>
    with TickerProviderStateMixin {
  final List<AnimationController> _controllers = [];
  final List<Animation<double>> _scales = [];

  @override
  void initState() {
    super.initState();

    for (int i = 0; i < 3; i++) {
      final controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 800),
      );
      final scale = Tween<double>(begin: 0.8, end: 1.2).animate(
        CurvedAnimation(parent: controller, curve: Curves.easeInOut),
      );
      _controllers.add(controller);
      _scales.add(scale);
    }

    _startAnimations();
  }

  Future<void> _startAnimations() async {
    for (int i = 0; i < _controllers.length; i++) {
      await Future.delayed(Duration(milliseconds: i * 150));
      if (mounted) {
        _controllers[i].repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;

    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: List.generate(3, (i) {
          final size = 16.0 + i * 12.0;
          if (reduce) {
            return Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.memoryPulse.withOpacity(0.3 - i * 0.08),
              ),
            );
          }
          return ScaleTransition(
            scale: _scales[i],
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.memoryPulse.withOpacity(0.3 - i * 0.08),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class AiLoadingDots extends StatefulWidget {
  const AiLoadingDots({super.key});

  @override
  State<AiLoadingDots> createState() => _AiLoadingDotsState();
}

class _AiLoadingDotsState extends State<AiLoadingDots> with TickerProviderStateMixin {
  final List<AnimationController> _controllers = [];
  final List<Animation<double>> _scales = [];

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < 3; i++) {
      final c = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      );
      final scale = Tween<double>(begin: 0.6, end: 1.0).animate(
        CurvedAnimation(parent: c, curve: Curves.easeInOut),
      );
      _controllers.add(c);
      _scales.add(scale);
    }
    _startDots();
  }

  Future<void> _startDots() async {
    for (int i = 0; i < _controllers.length; i++) {
      await Future.delayed(Duration(milliseconds: i * 150));
      if (mounted) _controllers[i].repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: ScaleTransition(
            scale: _scales[i],
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryAccent,
              ),
            ),
          ),
        );
      }),
    );
  }
}
