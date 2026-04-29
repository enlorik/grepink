import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class GrepinkSearchBar extends StatefulWidget {
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextEditingController? controller;
  final FocusNode? focusNode;

  const GrepinkSearchBar({
    super.key,
    this.onChanged,
    this.onSubmitted,
    this.controller,
    this.focusNode,
  });

  @override
  State<GrepinkSearchBar> createState() => _GrepinkSearchBarState();
}

class _GrepinkSearchBarState extends State<GrepinkSearchBar>
    with SingleTickerProviderStateMixin {
  static const _placeholders = [
    'Search your notes...',
    'Try: suffix automaton',
    'Ask me anything...',
    'What did I learn today?',
    'Did I solve this before?',
  ];

  int _placeholderIndex = 0;
  Timer? _timer;
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      value: 1.0,
    );
    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut);
    _startRotation();
  }

  void _startRotation() {
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_controller.text.isEmpty) {
        _fadeController.reverse().then((_) {
          if (mounted) {
            setState(() {
              _placeholderIndex = (_placeholderIndex + 1) % _placeholders.length;
            });
            _fadeController.forward();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _fadeController.dispose();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.dividerBorder),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryAccent.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          const Icon(Icons.search, color: AppColors.primaryAccent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                if (_controller.text.isEmpty)
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Text(
                      _placeholders[_placeholderIndex],
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.placeholderText,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                TextField(
                  controller: _controller,
                  focusNode: widget.focusNode,
                  style: AppTextStyles.bodyLarge,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    fillColor: Colors.transparent,
                    filled: false,
                  ),
                  onChanged: (value) {
                    setState(() {});
                    widget.onChanged?.call(value);
                  },
                  onSubmitted: widget.onSubmitted,
                  textInputAction: TextInputAction.search,
                ),
              ],
            ),
          ),
          if (_controller.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                _controller.clear();
                setState(() {});
                widget.onChanged?.call('');
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Icon(Icons.close, color: AppColors.secondaryText, size: 18),
              ),
            )
          else
            const SizedBox(width: 16),
        ],
      ),
    );
  }
}
