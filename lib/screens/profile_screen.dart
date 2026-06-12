import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/simple_card.dart';
import '../widgets/dialogs/confirmation_dialog.dart';
import 'login_screen.dart';
import 'change_password_screen.dart';

/// Profile screen - rider profile and settings
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final rider = authProvider.rider;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Profile',
          style: AppTypography.headlineMedium.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.paddingLarge),
          child: Column(
            children: [
              _buildHeader(context, rider?.name ?? 'Rider'),
              const SizedBox(height: AppSpacing.xxxl),
              _buildInfoSection(context, rider),
              const SizedBox(height: AppSpacing.paddingLarge),
              _buildSettingsSection(context),
              const SizedBox(height: AppSpacing.paddingLarge),
              _buildAboutSection(context),
              const SizedBox(height: AppSpacing.paddingLarge),
              _buildLogoutButton(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String name) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.person,
            size: 60,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: AppSpacing.padding),
        Text(
          name,
          style: AppTypography.headlineMedium.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoSection(BuildContext context, rider) {
    return SimpleCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          _buildInfoRow(
            icon: Icons.person_outline,
            label: 'Name',
            value: rider?.name ?? '-',
          ),
          const SizedBox(height: 20),
          _buildInfoRow(
            icon: Icons.account_circle_outlined,
            label: 'Username',
            value: rider?.username ?? '-',
          ),
          const SizedBox(height: 20),
          _buildInfoRow(
            icon: Icons.badge_outlined,
            label: 'Rider ID',
            value: rider?.id.toString() ?? '-',
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, color: AppColors.textSecondary, size: 24),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: AppTypography.titleMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsSection(BuildContext context) {
    return SimpleCard(
      padding: const EdgeInsets.all(20),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const ChangePasswordScreen(),
          ),
        );
      },
      child: Row(
        children: [
          const Icon(Icons.lock_outline, color: AppColors.primary, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'Change Password',
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        ],
      ),
    );
  }

  Widget _buildAboutSection(BuildContext context) {
    return SimpleCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppColors.primary, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'App Version',
                  style: AppTypography.labelMedium.copyWith(
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '1.2.11',
                  style: AppTypography.titleMedium.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: () async {
          final confirmed = await ConfirmationDialog.show(
            context: context,
            title: 'Logout',
            message: 'Are you sure you want to logout?',
            confirmText: 'Logout',
            cancelText: 'Cancel',
            icon: Icons.logout,
            iconColor: AppColors.error,
            isDestructive: true,
          );

          if (confirmed && context.mounted) {
            await context.read<AuthProvider>().logout();
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
              (route) => false,
            );
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.error,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        icon: const Icon(Icons.logout),
        label: Text(
          'Logout',
          style: AppTypography.titleMedium.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
