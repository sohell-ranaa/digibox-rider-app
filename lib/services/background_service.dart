import 'package:workmanager/workmanager.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_constants.dart';
import '../models/location_point.dart';
import 'storage_service.dart';

// This function runs in the background
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      // Get duty session ID from shared preferences
      final prefs = await SharedPreferences.getInstance();
      final dutySessionId = prefs.getInt(AppConstants.keyActiveDutySessionId);
      final riderId = prefs.getInt(AppConstants.keyRiderId);

      if (dutySessionId == null || riderId == null) {
        return Future.value(true); // No active duty, skip
      }

      // Check if location service is enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return Future.value(true); // Location off, skip
      }

      // Get current location
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );

      // Save to local database
      final storage = StorageService();
      final locationPoint = LocationPoint(
        riderId: riderId,
        dutySessionId: dutySessionId,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        speed: position.speed,
        bearing: position.heading,
        altitude: position.altitude,
        recordedAt: DateTime.now(),
        isSynced: false,
      );

      await storage.saveLocation(locationPoint);

      return Future.value(true);
    } catch (e) {
      print('Background task error: $e');
      return Future.value(false);
    }
  });
}

class BackgroundService {
  // Initialize WorkManager
  void initialize() {
    Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false, // Set to false in production
    );
  }

  // Register background task
  Future<void> registerBackgroundTask() async {
    await Workmanager().registerPeriodicTask(
      AppConstants.locationTaskName,
      AppConstants.locationTaskName,
      frequency: Duration(minutes: AppConstants.backgroundIntervalMinutes),
      constraints: Constraints(
        networkType: NetworkType.not_required,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: false,
      ),
    );
  }

  // Cancel background task
  Future<void> cancelBackgroundTask() async {
    await Workmanager().cancelByUniqueName(AppConstants.locationTaskName);
  }

  // Cancel all tasks
  Future<void> cancelAllTasks() async {
    await Workmanager().cancelAll();
  }
}
