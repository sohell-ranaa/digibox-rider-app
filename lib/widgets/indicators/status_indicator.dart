import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// Status indicator with icon, label, and color
class StatusIndicator extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final Color? activeColor;
  final Color? inactiveColor;
  final VoidCallback? onTap;

  const StatusIndicator({
    super.key,
    required this.icon,
    required this.label,
    required this.isActive,
    this.activeColor,
    this.inactiveColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive
        ? (activeColor ?? AppColors.success)
        : (inactiveColor ?? AppColors.textSecondary);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.borderRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.paddingSmall,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: AppTypography.labelSmall.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// Duty status indicator (large)
class DutyStatusIndicator extends StatelessWidget {
  final bool isOnDuty;
  final String duration;

  const DutyStatusIndicator({
    super.key,
    required this.isOnDuty,
    required this.duration,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.padding),
      decoration: BoxDecoration(
        color: isOnDuty
            ? AppColors.successLight.withOpacity(0.1)
            : AppColors.dutyInactive.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusCard),
        border: Border.all(
          color: isOnDuty ? AppColors.success : AppColors.dutyInactive,
          width: 2,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isOnDuty ? Icons.play_circle_filled : Icons.pause_circle_filled,
            color: isOnDuty ? AppColors.success : AppColors.dutyInactive,
            size: 32,
          ),
          const SizedBox(width: AppSpacing.padding),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isOnDuty ? 'Online' : 'Offline',
                style: AppTypography.titleMedium.copyWith(
                  color: isOnDuty ? AppColors.success : AppColors.dutyInactive,
                ),
              ),
              Text(
                duration,
                style: AppTypography.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
