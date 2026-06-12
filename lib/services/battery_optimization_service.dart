import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import '../utils/app_logger.dart';

/// Service to handle battery optimization exemption requests
class BatteryOptimizationService {
  /// Request battery optimization exemption to keep GPS tracking alive
  static Future<bool> requestBatteryOptimizationExemption(BuildContext context) async {
    try {
      // Check if battery optimization is already disabled
      final status = await Permission.ignoreBatteryOptimizations.status;

      if (status.isGranted) {
        AppLogger.i('✅ Battery optimization already disabled');
        return true;
      }

      // Show dialog explaining why we need this
      final shouldRequest = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.battery_alert, color: Colors.orange),
              SizedBox(width: 12),
              Text('Battery Optimization'),
            ],
          ),
          content: const Text(
            'To keep GPS tracking active when your screen is locked, this app needs to be exempt from battery optimization.\n\n'
            'This ensures:\n'
            '• Continuous location tracking\n'
            '• Reliable data sync\n'
            '• Accurate duty records\n\n'
            'Your battery usage will be slightly higher, but tracking will work properly.',
            style: TextStyle(fontSize: 15),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Skip'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Allow'),
            ),
          ],
        ),
      );

      if (shouldRequest != true) {
        AppLogger.w('⚠️ User declined battery optimization exemption');
        return false;
      }

      // Request the permission
      final result = await Permission.ignoreBatteryOptimizations.request();

      if (result.isGranted) {
        AppLogger.i('✅ Battery optimization exemption granted');
        return true;
      } else {
        AppLogger.w('⚠️ Battery optimization exemption denied');
        return false;
      }
    } catch (e) {
      AppLogger.e('❌ Error requesting battery optimization exemption: $e');
      return false;
    }
  }

  /// Check if battery optimization is disabled
  static Future<bool> isBatteryOptimizationDisabled() async {
    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      return status.isGranted;
    } catch (e) {
      AppLogger.e('Error checking battery optimization status: $e');
      return false;
    }
  }
}
