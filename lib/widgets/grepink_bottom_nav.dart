import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class GrepinkBottomNav extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const GrepinkBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  State<GrepinkBottomNav> createState() => _GrepinkBottomNavState();
}

class _GrepinkBottomNavState extends State<GrepinkBottomNav> {
  static const _items = [
    _NavItem(icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Notes'),
    _NavItem(icon: Icons.search_outlined, activeIcon: Icons.search, label: 'Search'),
    _NavItem(icon: Icons.settings_outlined, activeIcon: Icons.settings, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryAccent.withOpacity(0.12),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              for (int i = 0; i < _items.length; i++)
                Expanded(child: _NavButton(
                  item: _items[i],
                  isActive: widget.currentIndex == i,
                  onTap: () => widget.onTap(i),
                )),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem({required this.icon, required this.activeIcon, required this.label});
}

class _NavButton extends StatefulWidget {
  final _NavItem item;
  final bool isActive;
  final VoidCallback onTap;

  const _NavButton({required this.item, required this.isActive, required this.onTap});

  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _NavButtonState extends State<_NavButton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: widget.isActive ? 1.0 : 0.0,
    );
    _scale = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void didUpdateWidget(_NavButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
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
    final color = widget.isActive ? AppColors.primaryAction : AppColors.secondaryText;

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.isActive)
            Container(
              width: 32,
              height: 3,
              decoration: BoxDecoration(
                color: AppColors.primaryAction,
                borderRadius: BorderRadius.circular(2),
              ),
            )
          else
            const SizedBox(height: 3),
          const SizedBox(height: 6),
          reduce
              ? Icon(
                  widget.isActive ? widget.item.activeIcon : widget.item.icon,
                  color: color,
                  size: 22,
                )
              : ScaleTransition(
                  scale: _scale,
                  child: Icon(
                    widget.isActive ? widget.item.activeIcon : widget.item.icon,
                    color: color,
                    size: 22,
                  ),
                ),
          const SizedBox(height: 4),
          Text(
            widget.item.label,
            style: AppTextStyles.bodySmall.copyWith(
              color: color,
              fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
