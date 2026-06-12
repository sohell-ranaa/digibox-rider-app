import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../models/duty_session.dart';

class StopDutyDialog extends StatelessWidget {
  final DutySession? currentSession;
  final Duration currentDuration;
  final VoidCallback onConfirm;

  const StopDutyDialog({
    super.key,
    required this.currentSession,
    required this.currentDuration,
    required this.onConfirm,
  });

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final startTime = currentSession?.startedAt;
    final durationText = _formatDuration(currentDuration);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.borderRadiusCard),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.paddingLarge),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Warning Icon
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                size: 40,
                color: AppColors.warning,
              ),
            ),
            const SizedBox(height: AppSpacing.padding),

            // Title
            Text(
              'Go Offline?',
              style: AppTypography.headlineSmall.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.paddingSmall),

            // Warning Message
            Container(
              padding: const EdgeInsets.all(AppSpacing.padding),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppSpacing.borderRadius),
                border: Border.all(
                  color: AppColors.warning.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: AppSpacing.paddingSmall),
                  Expanded(
                    child: Text(
                      'Location tracking will be stopped and you will go offline.',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.paddingLarge),

            // Session Summary
            Container(
              padding: const EdgeInsets.all(AppSpacing.padding),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(AppSpacing.borderRadius),
                border: Border.all(
                  color: AppColors.border,
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    'Session Summary',
                    style: AppTypography.titleSmall.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.padding),

                  // Duration
                  _buildSummaryRow(
                    icon: Icons.access_time,
                    label: 'Duration',
                    value: durationText,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: AppSpacing.paddingSmall),

                  // Start Time
                  if (startTime != null)
                    _buildSummaryRow(
                      icon: Icons.schedule,
                      label: 'Started at',
                      value: _formatTime(startTime),
                      color: AppColors.success,
                    ),
                  const SizedBox(height: AppSpacing.paddingSmall),

                  // End Time (current time)
                  _buildSummaryRow(
                    icon: Icons.alarm_off,
                    label: 'Ending at',
                    value: _formatTime(DateTime.now()),
                    color: AppColors.error,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.paddingLarge),

            // Buttons
            Row(
              children: [
                // Cancel Button
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.borderRadius),
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: AppTypography.buttonText.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.padding),

                // Confirm Button
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop(true);
                      onConfirm();
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.borderRadius),
                      ),
                    ),
                    child: Text(
                      'Go Offline',
                      style: AppTypography.buttonText.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: AppSpacing.paddingSmall),
        Expanded(
          child: Text(
            label,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Text(
          value,
          style: AppTypography.titleSmall.copyWith(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
