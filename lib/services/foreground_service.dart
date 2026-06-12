import 'dart:async';
import 'dart:isolate';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import '../models/location_point.dart';
import '../utils/logger.dart';
import 'storage_service.dart';

/// Foreground service for reliable location tracking during duty
class ForegroundLocationService {
  static const String _channelId = 'digibox_location_tracking';
  static const String _channelName = 'Digibox Location Tracking';
  static const int _notificationId = 1001;

  /// Initialize the foreground service
  static Future<void> initialize() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _channelId,
        channelName: _channelName,
        channelDescription: 'Tracks rider location during duty',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 3000, // 3 seconds - aggressive tracking to keep app alive when screen locked
        isOnceEvent: false,
        autoRunOnBoot: false,
        allowWakeLock: true, // CRITICAL: Prevents CPU from sleeping
        allowWifiLock: false,
      ),
    );
  }

  /// Start foreground service for duty tracking
  static Future<bool> startService({
    required int riderId,
    required int dutySessionId,
  }) async {
    AppLogger.i('Starting foreground location service for duty session $dutySessionId');

    try {
      // Request notification permission
      final isRunning = await FlutterForegroundTask.isRunningService;
      if (!isRunning) {
        final permission = await FlutterForegroundTask.requestNotificationPermission();
        if (permission != NotificationPermission.granted) {
          AppLogger.w('Notification permission not granted');
          // Continue anyway as tracking is more important
        }
      }

      // Start the foreground service
      final result = await FlutterForegroundTask.startService(
        notificationTitle: 'Duty Active',
        notificationText: 'Tracking your location...',
        callback: startCallback,
      );

      if (result.success) {
        // Foreground service started successfully
        // Note: Data passing to foreground task needs to be done through shared preferences
        // or another persistence mechanism in the current API version
        AppLogger.i('Foreground service started successfully for rider $riderId, session $dutySessionId');
        return true;
      } else {
        AppLogger.e('Failed to start foreground service: ${result.error}');
        return false;
      }
    } catch (e) {
      AppLogger.e('Exception starting foreground service: $e');
      return false;
    }
  }

  /// Update notification text
  static Future<void> updateNotification({
    required String title,
    required String text,
  }) async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: text,
      );
    }
  }

  /// Stop foreground service
  static Future<bool> stopService() async {
    AppLogger.i('Stopping foreground location service');

    try {
      final isRunning = await FlutterForegroundTask.isRunningService;
      if (isRunning) {
        final result = await FlutterForegroundTask.stopService();
        AppLogger.i('Foreground service stopped: ${result.success}');
        return result.success;
      }
      return true;
    } catch (e) {
      AppLogger.e('Exception stopping foreground service: $e');
      return false;
    }
  }

  /// Check if service is running
  static Future<bool> isRunning() async {
    return await FlutterForegroundTask.isRunningService;
  }
}

/// Entry point for the foreground task isolate
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(LocationTaskHandler());
}

/// Task handler that runs in the foreground service isolate
class LocationTaskHandler extends TaskHandler {
  int? _riderId;
  int? _dutySessionId;
  Timer? _trackingTimer;
  final StorageService _storageService = StorageService();
  bool _isInitialized = false;

  @override
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {
    AppLogger.i('LocationTaskHandler started');
    _isInitialized = true;
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp, SendPort? sendPort) async {
    // This is called every 5 minutes based on foregroundTaskOptions.interval
    if (_riderId != null && _dutySessionId != null) {
      await _trackLocation();
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, SendPort? sendPort) async {
    AppLogger.i('LocationTaskHandler destroyed');
    _trackingTimer?.cancel();
  }

  @override
  void onReceiveData(Object data) {
    AppLogger.d('Received data in foreground task: $data');

    if (data is Map<String, dynamic>) {
      final action = data['action'] as String?;

      if (action == 'start') {
        _riderId = data['rider_id'] as int?;
        _dutySessionId = data['duty_session_id'] as int?;
        AppLogger.i('Tracking started for rider $_riderId, duty session $_dutySessionId');
      } else if (action == 'stop') {
        AppLogger.i('Tracking stopped');
        _riderId = null;
        _dutySessionId = null;
        _trackingTimer?.cancel();
      }
    }
  }

  @override
  void onNotificationButtonPressed(String id) {
    AppLogger.d('Notification button pressed: $id');
  }

  @override
  void onNotificationPressed() {
    AppLogger.d('Notification pressed');
    // Could navigate to app here
    FlutterForegroundTask.launchApp('/');
  }

  /// Track current location
  Future<void> _trackLocation() async {
    try {
      AppLogger.i('Tracking location in foreground service');

      // Check location permission
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        AppLogger.e('Location permission denied in foreground service');
        return;
      }

      // Get current position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Location timeout');
        },
      );

      // Create location point
      final locationPoint = LocationPoint(
        riderId: _riderId!,
        dutySessionId: _dutySessionId!,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        altitude: position.altitude,
        speed: position.speed,
        bearing: position.heading,
        recordedAt: DateTime.now(),
        isSynced: false,
      );

      // Save to local database
      await _storageService.saveLocation(locationPoint);

      AppLogger.i(
        'Location tracked: (${position.latitude}, ${position.longitude}) accuracy: ${position.accuracy}m',
      );

      // Update notification with location info
      FlutterForegroundTask.updateService(
        notificationTitle: 'Duty Active',
        notificationText:
            'Location: ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}',
      );
    } catch (e) {
      AppLogger.e('Failed to track location in foreground service: $e');
    }
  }
}
