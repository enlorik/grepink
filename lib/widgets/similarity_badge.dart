import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class SimilarityBadge extends StatelessWidget {
  final double score;

  const SimilarityBadge({super.key, required this.score});

  String get _label {
    if (score >= 0.95) return 'EXACT MATCH';
    if (score >= 0.85) return 'YOU SOLVED THIS BEFORE';
    if (score >= 0.72) return 'SIMILAR PROBLEM';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final label = _label;
    if (label.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.similarityBadge,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: AppTextStyles.similarityBadge,
      ),
    );
  }
}
