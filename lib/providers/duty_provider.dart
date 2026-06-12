import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:convert';
import '../config/app_constants.dart';
import '../models/duty_session.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/background_service.dart';
import '../services/foreground_service.dart';
import '../utils/logger.dart';

class DutyProvider with ChangeNotifier {
  final LocationService _locationService = LocationService();
  final BackgroundService _backgroundService = BackgroundService();

  DutySession? _currentSession;
  bool _isOnline = false;
  bool _isLoading = false;
  Timer? _durationTimer;
  Duration _currentDuration = Duration.zero;
  String? _lastError;
  bool _hasPendingStopSync = false;

  DutySession? get currentSession => _currentSession;
  bool get isOnline => _isOnline;
  bool get isLoading => _isLoading;
  Duration get currentDuration => _currentDuration;
  String? get lastError => _lastError;
  bool get hasPendingStopSync => _hasPendingStopSync;

  // Initialize - ONLINE FIRST: Check server for active session
  Future<void> initialize(ApiService apiService) async {
    debugPrint('🔄 [DutyProvider] Initializing...');

    // Load pending sync status first
    await _loadPendingSyncStatus();

    try {
      // ONLINE FIRST: Always check server for active session
      debugPrint('🔄 [DutyProvider] Checking server for active session...');
      final serverSession = await apiService.getCurrentDuty();

      if (serverSession != null && serverSession.isActive) {
        _currentSession = serverSession;
        _isOnline = true;
        debugPrint('🔄 [DutyProvider] Found active session on server: ID ${_currentSession!.id}');

        // Save to local storage for reference
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(AppConstants.keyActiveDutySessionId, _currentSession!.id);
        await prefs.setString(AppConstants.keyActiveDutySession, json.encode(_currentSession!.toJson()));
        await prefs.setString(AppConstants.keyDutyStartedAt, _currentSession!.startedAt.toIso8601String());

        // Start duration timer
        _startDurationTimer();
      } else {
        debugPrint('🔄 [DutyProvider] No active session on server');
        _isOnline = false;
        await _clearLocalDutyState();
      }

      // Try to sync pending actions if we have internet
      if (_hasPendingStopSync) {
        debugPrint('🔄 [DutyProvider] Internet available, syncing pending actions...');
        await syncPendingActions(apiService);
      }
    } catch (e) {
      debugPrint('🔄 [DutyProvider] Failed to check server: $e');
      debugPrint('🔄 [DutyProvider] Cannot initialize without server connection');
      _isOnline = false;
      await _clearLocalDutyState();
    }

    notifyListeners();
  }

  // Clear local duty state
  Future<void> _clearLocalDutyState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.keyActiveDutySessionId);
    await prefs.remove(AppConstants.keyActiveDutySession);
    await prefs.remove(AppConstants.keyDutyStartedAt);
  }

  // Sync pending actions when internet connection is restored
  Future<void> syncPendingActions(ApiService apiService) async {
    debugPrint('🔄 [Sync] Checking for pending actions...');
    final prefs = await SharedPreferences.getInstance();

    // Check for pending stop sync
    final hasPendingStop = prefs.getBool(AppConstants.keyPendingStopSync) ?? false;
    if (hasPendingStop) {
      debugPrint('🔄 [Sync] Found pending stop sync, processing...');

      final sessionIdStr = prefs.getString(AppConstants.keyPendingStopSessionId);
      final pendingTime = prefs.getString(AppConstants.keyPendingStopTime);

      if (sessionIdStr != null && sessionIdStr.isNotEmpty) {
        try {
          debugPrint('🔄 [Sync] Syncing stop for session $sessionIdStr (pending since $pendingTime)');
          await apiService.stopDuty();
          debugPrint('✅ [Sync] Pending stop synced successfully');

          _hasPendingStopSync = false;
          await _clearPendingStopSync();
          notifyListeners();
        } catch (e) {
          debugPrint('❌ [Sync] Pending stop sync failed: $e');
          debugPrint('⚠️ [Sync] Will retry next time internet is available');
          // Keep the pending flag, will retry next time
        }
      }
    } else {
      debugPrint('✅ [Sync] No pending actions found');
    }
  }

  // Check and load pending sync status on initialization
  Future<void> _loadPendingSyncStatus() async {
    final prefs = await SharedPreferences.getInstance();
    _hasPendingStopSync = prefs.getBool(AppConstants.keyPendingStopSync) ?? false;

    if (_hasPendingStopSync) {
      final pendingTime = prefs.getString(AppConstants.keyPendingStopTime);
      debugPrint('⚠️ [Sync] Pending stop sync detected from: $pendingTime');
    }
  }

  // Start duty
  Future<bool> startDuty(ApiService apiService, int riderId) async {
    _isLoading = true;
    _lastError = null;
    notifyListeners();

    try {
      AppLogger.i('✅ Starting duty for rider ID: $riderId');

      // 1. Verify authentication token
      if (apiService.token == null || apiService.token!.isEmpty) {
        AppLogger.e('❌ Cannot start duty - no auth token present');
        _lastError = 'Not authenticated. Please login again.';
        _isLoading = false;
        notifyListeners();
        return false;
      }
      AppLogger.i('✅ Auth token verified: ${apiService.token!.substring(0, 10)}...');

      // 2. Check location permissions
      AppLogger.i('🔍 Checking location permissions...');
      bool hasPermission = await _locationService.checkPermissions();
      if (!hasPermission) {
        AppLogger.e('❌ Location permission denied');
        _lastError = 'Location permission required. Please grant location access in settings.';
        _isLoading = false;
        notifyListeners();
        return false;
      }
      AppLogger.i('✅ Location permission granted');

      // 3. Check GPS enabled
      AppLogger.i('🔍 Checking GPS status...');
      bool gpsEnabled = await Geolocator.isLocationServiceEnabled();
      if (!gpsEnabled) {
        AppLogger.e('❌ GPS is disabled');
        _lastError = 'GPS is disabled. Please enable location services.';
        _isLoading = false;
        notifyListeners();
        return false;
      }
      AppLogger.i('✅ GPS is enabled');

      // 4. Request background permission
      AppLogger.i('🔍 Requesting background permission...');
      await _locationService.requestBackgroundPermission();

      // 5. Start duty session via API
      AppLogger.i('🌐 Calling API to start duty session...');
      _currentSession = await apiService.startDuty();
      AppLogger.i('✅ Duty session started: ID ${_currentSession!.id}');
      _isOnline = true;

      // Save to local storage - FULL SESSION DATA for offline support
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(AppConstants.keyActiveDutySessionId, _currentSession!.id);
      await prefs.setString(AppConstants.keyActiveDutySession, json.encode(_currentSession!.toJson()));
      await prefs.setString(AppConstants.keyDutyStartedAt, _currentSession!.startedAt.toIso8601String());

      // Start foreground service for reliable tracking
      AppLogger.i('Starting foreground service for duty session ${_currentSession!.id}');
      final foregroundStarted = await ForegroundLocationService.startService(
        riderId: riderId,
        dutySessionId: _currentSession!.id,
      );

      if (!foregroundStarted) {
        AppLogger.w('Foreground service failed to start, falling back to standard tracking');
      }

      // Start location tracking (foreground)
      await _locationService.startTracking(
        _currentSession!.id,
        riderId,
        apiService,
      );

      // Start background tracking as backup
      await _backgroundService.registerBackgroundTask();

      // Start duration timer
      _startDurationTimer();

      // Update foreground notification with formatted duration
      _updateForegroundNotification();

      _isLoading = false;
      _lastError = null;
      notifyListeners();
      return true;
    } catch (e, stackTrace) {
      // Extract detailed error message for debugging
      String errorMsg = e.toString();

      // Try to extract API error details
      if (errorMsg.contains('ApiException')) {
        // Keep the detailed error for debugging
        AppLogger.e('❌ API Error: $errorMsg');
        _lastError = errorMsg.replaceAll('ApiException:', '').replaceAll('Exception:', '').trim();
      } else if (errorMsg.contains('SocketException') || errorMsg.contains('Failed host lookup')) {
        _lastError = 'No internet connection. Please check your network and try again.';
      } else if (errorMsg.contains('TimeoutException')) {
        _lastError = 'Connection timeout. Please check your internet connection.';
      } else {
        // Clean up generic exception prefix
        _lastError = errorMsg.replaceAll('Exception:', '').trim();
        if (_lastError?.isEmpty ?? true || _lastError == 'null') {
          _lastError = 'Failed to go online. Please try again.';
        }
      }

      _isLoading = false;
      notifyListeners();

      AppLogger.e('❌ Error starting duty: $e');
      AppLogger.e('❌ Stack trace: $stackTrace');
      debugPrint('❌ [DutyProvider] Start duty failed: $e');
      debugPrint('❌ [DutyProvider] Stack trace: $stackTrace');
      return false;
    }
  }

  // Stop duty - ONLINE FIRST: Sync with server first
  // OFFLINE-FIRST: Stop duty locally first, sync with server later
  Future<bool> stopDuty(ApiService apiService) async {
    debugPrint('🛑 [DutyProvider] stopDuty() called - OFFLINE-FIRST MODE');
    _isLoading = true;
    notifyListeners();

    try {
      // STEP 1: ALWAYS stop locally first (this never fails)
      debugPrint('🛑 [DutyProvider] Step 1: Stopping locally...');
      await _stopLocally();

      _isOnline = false;
      _isLoading = false;
      notifyListeners();

      debugPrint('✅ [DutyProvider] Local stop successful, rider is now OFFLINE');

      // STEP 2: Try to sync with server (non-blocking, failures are OK)
      debugPrint('🛑 [DutyProvider] Step 2: Attempting server sync...');
      try {
        final stoppedSession = await apiService.stopDuty();
        debugPrint('✅ [DutyProvider] Server sync successful');
        _currentSession = stoppedSession;
        _hasPendingStopSync = false;
        await _clearPendingStopSync();
        notifyListeners();
      } catch (e) {
        // Server sync failed, but we're already offline locally - that's OK!
        debugPrint('⚠️ [DutyProvider] Server sync failed (will retry later): $e');
        debugPrint('⚠️ [DutyProvider] Rider is offline locally, sync queued for later');

        _hasPendingStopSync = true;
        await _savePendingStopSync();
        notifyListeners();

        // Don't set error message - this is expected in offline scenarios
      }

      // Return true because local stop succeeded (most important)
      return true;
    } catch (e, stackTrace) {
      debugPrint('❌ [DutyProvider] CRITICAL: Local stop failed: $e');
      debugPrint('❌ [DutyProvider] Stack trace: $stackTrace');
      AppLogger.e('Critical error stopping duty locally: $e');

      _lastError = 'Failed to stop tracking services. Please try again.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Stop all local tracking services
  Future<void> _stopLocally() async {
    try {
      // Stop foreground service
      debugPrint('🛑 [Local] Stopping foreground service...');
      await ForegroundLocationService.stopService();

      // Stop location tracking
      debugPrint('🛑 [Local] Stopping location tracking...');
      _locationService.stopTracking();

      // Stop background tracking
      debugPrint('🛑 [Local] Canceling background task...');
      await _backgroundService.cancelBackgroundTask();

      // Stop duration timer
      debugPrint('🛑 [Local] Stopping duration timer...');
      _stopDurationTimer();

      // Update current session end time locally
      if (_currentSession != null) {
        _currentSession = _currentSession!.copyWith(
          endedAt: DateTime.now(),
          status: 'completed',
        );
        debugPrint('🛑 [Local] Session updated: ${_currentSession!.id} ended at ${_currentSession!.endedAt}');
      }

      // Save local state
      debugPrint('🛑 [Local] Saving local stop state...');
      await _saveLocalStopState();

      debugPrint('✅ [Local] All tracking services stopped successfully');
    } catch (e, stackTrace) {
      debugPrint('❌ [Local] Error stopping locally: $e');
      debugPrint('❌ [Local] Stack trace: $stackTrace');
      rethrow;
    }
  }

  // Save the local stop state to SharedPreferences
  Future<void> _saveLocalStopState() async {
    final prefs = await SharedPreferences.getInstance();

    // Save ended session for reference
    if (_currentSession != null) {
      await prefs.setString(
        AppConstants.keyLastEndedSession,
        json.encode(_currentSession!.toJson()),
      );
    }

    // Clear active session keys
    await prefs.remove(AppConstants.keyActiveDutySessionId);
    await prefs.remove(AppConstants.keyActiveDutySession);
    await prefs.remove(AppConstants.keyDutyStartedAt);

    debugPrint('✅ [Local] Local state saved successfully');
  }

  // Save pending stop sync information
  Future<void> _savePendingStopSync() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.keyPendingStopSync, true);
    await prefs.setString(
      AppConstants.keyPendingStopSessionId,
      _currentSession?.id.toString() ?? '',
    );
    await prefs.setString(
      AppConstants.keyPendingStopTime,
      DateTime.now().toIso8601String(),
    );
    debugPrint('⚠️ [Sync] Pending stop sync saved for later');
  }

  // Clear pending stop sync information
  Future<void> _clearPendingStopSync() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.keyPendingStopSync);
    await prefs.remove(AppConstants.keyPendingStopSessionId);
    await prefs.remove(AppConstants.keyPendingStopTime);
    debugPrint('✅ [Sync] Pending stop sync cleared');
  }

  // Start duration timer
  void _startDurationTimer() {
    _durationTimer?.cancel();
    _updateDuration();

    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateDuration();
    });
  }

  // Update duration
  void _updateDuration() {
    if (_currentSession != null) {
      _currentDuration = DateTime.now().difference(_currentSession!.startedAt);
      notifyListeners();

      // Update foreground notification every minute
      if (_currentDuration.inSeconds % 60 == 0) {
        _updateForegroundNotification();
      }
    }
  }

  // Update foreground notification with current duration
  void _updateForegroundNotification() {
    if (_isOnline) {
      ForegroundLocationService.updateNotification(
        title: 'Online - ${getFormattedDuration()}',
        text: 'Smart tracking: 30s moving, 1min stopped',
      );
    }
  }

  // Stop duration timer
  void _stopDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = null;
    // Don't reset duration - it should persist across online/offline toggles
    // Duration is calculated from session start time, so it will be correct when timer restarts
  }

  // Format duration as HH:MM:SS
  String getFormattedDuration() {
    final hours = _currentDuration.inHours.toString().padLeft(2, '0');
    final minutes = (_currentDuration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (_currentDuration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  // Trigger sync when connectivity returns
  Future<void> syncPendingData(ApiService apiService) async {
    try {
      debugPrint('🔄 [DutyProvider] Syncing pending location data...');

      // Sync pending locations
      await _locationService.syncPendingLocations();

      final pendingCount = await _locationService.getPendingCount();
      debugPrint('🔄 [DutyProvider] Sync complete. Pending locations: $pendingCount');

      notifyListeners();
    } catch (e) {
      debugPrint('🔄 [DutyProvider] Error syncing pending data: $e');
    }
  }

  // Get pending sync count
  Future<int> getPendingSyncCount() async {
    return await _locationService.getPendingCount();
  }

  // Force sync - manually trigger upload
  Future<Map<String, dynamic>> forceSync() async {
    try {
      _isLoading = true;
      notifyListeners();

      final result = await _locationService.forceSync();

      _isLoading = false;
      notifyListeners();

      return result;
    } catch (e) {
      debugPrint('❌ [DutyProvider] Force sync failed: $e');
      _isLoading = false;
      notifyListeners();
      return {
        'success': false,
        'message': 'Sync failed: ${e.toString()}',
      };
    }
  }

  // Get current session statistics
  Future<Map<String, dynamic>> getSessionStats() async {
    if (_currentSession == null) {
      return {
        'duration': '00:00:00',
        'totalPoints': 0,
        'pendingPoints': 0,
        'syncedPoints': 0,
        'distance': 0.0,
      };
    }

    final stats = await _locationService.getSessionStats();

    return {
      'duration': getFormattedDuration(),
      'totalPoints': stats['totalPoints'] ?? 0,
      'pendingPoints': stats['pendingPoints'] ?? 0,
      'syncedPoints': stats['syncedPoints'] ?? 0,
      'distance': 0.0, // TODO: Calculate from GPS points
    };
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    super.dispose();
  }
}
