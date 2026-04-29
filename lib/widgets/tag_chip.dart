import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class TagChip extends StatelessWidget {
  final String label;
  final VoidCallback? onDelete;
  final bool isEditable;

  const TagChip({
    super.key,
    required this.label,
    this.onDelete,
    this.isEditable = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: (isEditable && onDelete != null) ? 6 : 12,
        top: 5,
        bottom: 5,
      ),
      decoration: BoxDecoration(
        color: AppColors.tagBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.tagBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.deepAction),
          ),
          if (isEditable && onDelete != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onDelete,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: AppColors.deepAction.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close,
                  size: 10,
                  color: AppColors.deepAction,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
