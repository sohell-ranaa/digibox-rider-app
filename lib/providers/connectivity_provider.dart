import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import 'duty_provider.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../utils/logger.dart';

class ConnectivityProvider with ChangeNotifier {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;

  bool _isOnline = false;
  ConnectivityResult _connectionType = ConnectivityResult.none;
  DutyProvider? _dutyProvider;
  ApiService? _apiService;
  LocationService? _locationService;

  bool get isOnline => _isOnline;
  ConnectivityResult get connectionType => _connectionType;

  String get connectionStatus {
    if (!_isOnline) return 'Offline';

    if (_connectionType == ConnectivityResult.wifi) {
      return 'WiFi';
    } else if (_connectionType == ConnectivityResult.mobile) {
      return 'Mobile Data';
    } else if (_connectionType == ConnectivityResult.ethernet) {
      return 'Ethernet';
    } else {
      return 'Online';
    }
  }

  ConnectivityProvider() {
    _initialize();
  }

  // Set duty provider, API service, and location service for auto-sync
  void setDependencies(DutyProvider dutyProvider, ApiService apiService, LocationService locationService) {
    _dutyProvider = dutyProvider;
    _apiService = apiService;
    _locationService = locationService;
    debugPrint('📡 [Connectivity] Dependencies set for auto-sync (duty + locations)');
  }

  Future<void> _initialize() async {
    debugPrint('📡 [Connectivity] Initializing...');

    try {
      // Check initial connectivity
      final result = await _connectivity.checkConnectivity();
      _updateConnectionStatus(result);

      // Listen for connectivity changes
      _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
        (ConnectivityResult result) {
          _updateConnectionStatus(result);
        },
        onError: (error) {
          debugPrint('📡 [Connectivity] Stream error: $error');
        },
      );
    } catch (e) {
      debugPrint('📡 [Connectivity] Initialization error: $e');
    }
  }

  void _updateConnectionStatus(ConnectivityResult result) async {
    final wasOffline = !_isOnline;
    _connectionType = result;
    _isOnline = result != ConnectivityResult.none;

    if (wasOffline != _isOnline) {
      debugPrint('📡 [Connectivity] Status changed: ${_isOnline ? "ONLINE" : "OFFLINE"} ($result)');
      AppLogger.i('Connection status: ${_isOnline ? "Online" : "Offline"}');
    }

    notifyListeners();

    // When internet returns after being offline, sync ALL pending data
    if (wasOffline && _isOnline) {
      debugPrint('📡 [Connectivity] Internet restored! Syncing all pending data...');
      AppLogger.i('Internet connection restored, syncing...');

      // Wait a bit for connection to stabilize
      await Future.delayed(const Duration(seconds: 2));

      try {
        // Sync pending duty actions (stop/start)
        if (_dutyProvider != null && _apiService != null) {
          await _dutyProvider!.syncPendingActions(_apiService!);
          debugPrint('✅ [Connectivity] Duty sync completed');
        }

        // Sync pending location data (batch upload)
        if (_locationService != null) {
          await _locationService!.syncPendingLocations();
          debugPrint('✅ [Connectivity] Location sync completed');
        }

        debugPrint('✅ [Connectivity] Auto-sync ALL completed');
      } catch (e) {
        debugPrint('❌ [Connectivity] Auto-sync failed: $e');
      }
    }
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}
