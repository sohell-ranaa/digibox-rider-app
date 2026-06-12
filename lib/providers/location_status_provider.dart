import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';

class LocationStatusProvider with ChangeNotifier {
  bool _isEnabled = false;
  bool _hasPermission = false;
  Timer? _statusCheckTimer;

  bool get isEnabled => _isEnabled;
  bool get hasPermission => _hasPermission;
  bool get isActive => _isEnabled && _hasPermission;

  LocationStatusProvider() {
    _initialize();
  }

  Future<void> _initialize() async {
    debugPrint('📍 [LocationStatus] Initializing...');
    await _checkStatus();

    // Check status every 10 seconds
    _statusCheckTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _checkStatus();
    });
  }

  Future<void> _checkStatus() async {
    try {
      // Check if location service is enabled (GPS on/off)
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      // Check permission status
      final permission = await Geolocator.checkPermission();
      final hasPermission = permission == LocationPermission.always ||
                           permission == LocationPermission.whileInUse;

      final wasActive = isActive;
      _isEnabled = serviceEnabled;
      _hasPermission = hasPermission;

      if (wasActive != isActive) {
        debugPrint('📍 [LocationStatus] Changed: GPS ${_isEnabled ? "ON" : "OFF"}, Permission ${_hasPermission ? "GRANTED" : "DENIED"}');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('📍 [LocationStatus] Error checking status: $e');
    }
  }

  /// Manually refresh status
  Future<void> refresh() async {
    await _checkStatus();
  }

  @override
  void dispose() {
    _statusCheckTimer?.cancel();
    super.dispose();
  }
}
