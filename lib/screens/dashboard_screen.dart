import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import '../providers/duty_provider.dart';
import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/dialogs/stop_duty_dialog.dart';
import '../services/battery_optimization_service.dart';

/// Dashboard screen - main duty control and status overview
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isInternetConnected = false;
  bool _isGPSEnabled = false;
  int _pendingSync = 0;
  Timer? _statusTimer;
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _checkStatuses();
    _statusTimer = Timer.periodic(const Duration(seconds: 5), (_) => _checkStatuses());

    // Listen to connectivity changes
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((ConnectivityResult result) {
      if (mounted) {
        _checkStatuses();
      }
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkStatuses() async {
    try {
      // Check internet connectivity
      final connectivityResult = await Connectivity().checkConnectivity();
      final isConnected = connectivityResult != ConnectivityResult.none;

      // Check GPS
      final gpsEnabled = await Geolocator.isLocationServiceEnabled();

      // Get pending sync count
      final dutyProvider = context.read<DutyProvider>();
      final pending = await dutyProvider.getPendingSyncCount();

      if (mounted) {
        setState(() {
          _isInternetConnected = isConnected;
          _isGPSEnabled = gpsEnabled;
          _pendingSync = pending;
        });
      }
    } catch (e) {
      debugPrint('Error checking statuses: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        title: const Text(
          'Dashboard',
          style: TextStyle(
            color: AppColors.textInverse,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.paddingLarge),
          child: Column(
            children: [
              _buildHeader(context),
              const SizedBox(height: AppSpacing.padding),
              _buildStatusIndicators(),
              const SizedBox(height: AppSpacing.xxl),
              _buildDutyControl(context),
              const SizedBox(height: AppSpacing.xxl),
              _buildQuickStats(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();

    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hello,',
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            authProvider.rider?.name ?? 'Rider',
            style: AppTypography.headlineMedium.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDutyControl(BuildContext context) {
    final dutyProvider = context.watch<DutyProvider>();

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: dutyProvider.isOnline
              ? const Color(0xFFE8F5E9) // Light green for online
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: dutyProvider.isLoading
            ? Center(
                child: CircularProgressIndicator(
                  color: dutyProvider.isOnline ? AppColors.success : AppColors.primary,
                  strokeWidth: 3,
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Icon(
                    dutyProvider.isOnline
                        ? Icons.check_circle
                        : Icons.power_settings_new,
                    size: 64,
                    color: dutyProvider.isOnline ? AppColors.success : AppColors.textSecondary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    dutyProvider.isOnline ? 'ON DUTY' : 'OFF DUTY',
                    style: AppTypography.headlineMedium.copyWith(
                      color: dutyProvider.isOnline ? AppColors.success : AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    dutyProvider.getFormattedDuration(),
                    style: TextStyle(
                      fontSize: 36,
                      color: dutyProvider.isOnline ? AppColors.success : AppColors.textPrimary,
                      fontWeight: FontWeight.w300,
                      fontFamily: 'monospace',
                      letterSpacing: 2,
                    ),
                  ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: dutyProvider.isLoading
                      ? null
                      : () async {
                          final authProvider = context.read<AuthProvider>();
                          final apiService = authProvider.apiService;
                          final riderId = authProvider.rider?.id;

                          if (riderId == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Rider information not available')),
                            );
                            return;
                          }

                          if (dutyProvider.isOnline) {
                            // Show confirmation dialog before going offline
                            debugPrint('🛑 [Dashboard] Go Offline button pressed - showing confirmation dialog');

                            final confirmed = await showDialog<bool>(
                              context: context,
                              barrierDismissible: false,
                              builder: (BuildContext context) {
                                return StopDutyDialog(
                                  currentSession: dutyProvider.currentSession,
                                  currentDuration: dutyProvider.currentDuration,
                                  onConfirm: () {},
                                );
                              },
                            );

                            if (confirmed == true) {
                              debugPrint('🛑 [Dashboard] User confirmed going offline');
                              final success = await dutyProvider.stopDuty(apiService);
                              debugPrint('🛑 [Dashboard] Go Offline result: $success');
                              if (!context.mounted) return;

                              if (success) {
                                // Check if sync is pending (offline mode)
                                if (dutyProvider.hasPendingStopSync) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('You are now offline\n(Will sync with server when online)'),
                                      backgroundColor: Colors.orange,
                                      duration: Duration(seconds: 5),
                                    ),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('You are now offline'),
                                      backgroundColor: AppColors.success,
                                      duration: Duration(seconds: 3),
                                    ),
                                  );
                                }
                              } else {
                                // Show the ACTUAL error message (should rarely happen now)
                                final errorMsg = dutyProvider.lastError ?? 'Failed to stop tracking. Please try again.';
                                debugPrint('❌ [Dashboard] Go Offline failed: $errorMsg');

                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(errorMsg),
                                    backgroundColor: AppColors.error,
                                    duration: const Duration(seconds: 5),
                                    action: SnackBarAction(
                                      label: 'OK',
                                      textColor: Colors.white,
                                      onPressed: () {},
                                    ),
                                  ),
                                );
                              }
                            } else {
                              debugPrint('🛑 [Dashboard] User cancelled going offline');
                            }
                          } else {
                            debugPrint('✅ [Dashboard] Go Online button pressed');

                            // Request battery optimization exemption for reliable background tracking
                            await BatteryOptimizationService.requestBatteryOptimizationExemption(context);
                            if (!context.mounted) return;

                            final success = await dutyProvider.startDuty(apiService, riderId);
                            if (!context.mounted) return;

                            if (success) {
                              debugPrint('✅ [Dashboard] Go Online succeeded');
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('You are now online'),
                                  backgroundColor: AppColors.success,
                                  duration: Duration(seconds: 3),
                                ),
                              );
                            } else {
                              // Show the ACTUAL error message
                              final errorMsg = dutyProvider.lastError ?? 'Failed to go online. Please try again.';
                              debugPrint('❌ [Dashboard] Go Online failed: $errorMsg');

                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(errorMsg),
                                  backgroundColor: AppColors.error,
                                  duration: const Duration(seconds: 5),
                                  action: SnackBarAction(
                                    label: 'OK',
                                    textColor: Colors.white,
                                    onPressed: () {},
                                  ),
                                ),
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: dutyProvider.isOnline
                        ? AppColors.error
                        : AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: Text(
                    dutyProvider.isOnline ? 'Go Offline' : 'Go Online',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                // Force sync button (only show when online)
                if (dutyProvider.isOnline) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: dutyProvider.isLoading
                        ? null
                        : () async {
                            final result = await dutyProvider.forceSync();
                            if (!context.mounted) return;

                            final success = result['success'] ?? false;
                            final message = result['message'] ?? 'Unknown result';

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(message),
                                backgroundColor: success ? AppColors.success : AppColors.error,
                                duration: Duration(seconds: success ? 2 : 4),
                              ),
                            );

                            await _checkStatuses(); // Refresh stats
                          },
                    icon: const Icon(Icons.sync, size: 18),
                    label: Text(
                      _pendingSync > 0 ? 'Sync Now ($_pendingSync pending)' : 'Force Sync',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(color: AppColors.primary, width: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ],
            ),
      ),
    );
  }

  Widget _buildQuickStats(BuildContext context) {
    final dutyProvider = context.watch<DutyProvider>();

    // Calculate duration from current session (cumulative)
    String durationText = '0h 0m';
    if (dutyProvider.currentSession != null) {
      final duration = dutyProvider.currentDuration;
      final hours = duration.inHours;
      final minutes = duration.inMinutes % 60;
      durationText = '${hours}h ${minutes}m';
    }

    return Column(
      children: [
        // Row 1: Duration and Status
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                icon: Icons.timer_outlined,
                iconColor: AppColors.primary,
                label: 'Total Duration',
                value: durationText,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildStatCard(
                icon: dutyProvider.isOnline ? Icons.check_circle_outline : Icons.cancel_outlined,
                iconColor: dutyProvider.isOnline ? const Color(0xFF4CAF50) : AppColors.textSecondary,
                label: 'Status',
                value: dutyProvider.isOnline ? 'Online' : 'Offline',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Row 2: GPS Points and Sync Status
        Row(
          children: [
            Expanded(
              child: FutureBuilder<Map<String, dynamic>>(
                future: dutyProvider.getSessionStats(),
                builder: (context, snapshot) {
                  final totalPoints = snapshot.data?['totalPoints'] ?? 0;
                  return _buildStatCard(
                    icon: Icons.location_on_outlined,
                    iconColor: const Color(0xFF3B82F6),
                    label: 'GPS Points',
                    value: '$totalPoints',
                  );
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildStatCard(
                icon: _pendingSync > 0 ? Icons.cloud_upload_outlined : Icons.cloud_done_outlined,
                iconColor: _pendingSync > 0 ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                label: _pendingSync > 0 ? 'Pending Sync' : 'Synced',
                value: _pendingSync > 0 ? '$_pendingSync' : '✓',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 20,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTypography.titleLarge.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicators() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatusItem(
            icon: Icons.wifi,
            label: 'Internet',
            isActive: _isInternetConnected,
            activeColor: AppColors.success,
            inactiveColor: AppColors.error,
          ),
          Container(width: 1, height: 24, color: AppColors.border),
          _buildStatusItem(
            icon: Icons.gps_fixed,
            label: 'GPS',
            isActive: _isGPSEnabled,
            activeColor: AppColors.success,
            inactiveColor: AppColors.error,
          ),
          Container(width: 1, height: 24, color: AppColors.border),
          _buildStatusItem(
            icon: Icons.sync,
            label: 'Sync',
            isActive: _pendingSync == 0,
            activeColor: AppColors.success,
            inactiveColor: AppColors.warning,
            badge: _pendingSync > 0 ? _pendingSync.toString() : null,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusItem({
    required IconData icon,
    required String label,
    required bool isActive,
    required Color activeColor,
    required Color inactiveColor,
    String? badge,
  }) {
    final color = isActive ? activeColor : inactiveColor;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: color,
              size: 20,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: AppTypography.labelSmall.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        if (badge != null)
          Positioned(
            right: -8,
            top: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(10),
              ),
              constraints: const BoxConstraints(
                minWidth: 18,
                minHeight: 18,
              ),
              child: Text(
                badge,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}
