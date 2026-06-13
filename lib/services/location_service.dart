import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../config/app_constants.dart';
import '../models/location_point.dart';
import 'storage_service.dart';
import 'api_service.dart';
import 'kalman_gps_filter.dart';
import 'ai_route_processor.dart';
import 'road_snapping_service.dart'; // PHASE 3
import 'trajectory_predictor.dart'; // PHASE 3
import '../utils/app_logger.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class LocationService {
  // Singleton pattern for easy access
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  final StorageService _storage = StorageService();
  final ApiService _api = ApiService();
  final KalmanGPSFilter _kalmanFilter = KalmanGPSFilter();
  final RoadSnappingService _roadSnapper = RoadSnappingService(); // PHASE 3
  final TrajectoryPredictor _trajectoryPredictor = TrajectoryPredictor(); // PHASE 3
  Timer? _locationTimer;
  Timer? _batchUploadTimer;
  int? _currentDutySessionId;
  int? _riderId;
  Position? _lastValidPosition; // For outlier detection
  Position? _lastRawPosition; // For activity detection
  Duration _currentInterval = const Duration(seconds: 3); // Start with 3s (normal speed assumed)
  List<Position> _rawPositionBuffer = []; // Buffer for AI processing

  // Check and request permissions
  Future<bool> checkPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  // Request background location permission (Android)
  Future<bool> requestBackgroundPermission() async {
    final status = await Permission.locationAlways.request();
    return status.isGranted;
  }

  // Start tracking (foreground) with HIGH-FREQUENCY ADAPTIVE intervals + AI processing
  Future<void> startTracking(int dutySessionId, int riderId, ApiService apiService) async {
    _currentDutySessionId = dutySessionId;
    _riderId = riderId;
    _api.setToken(apiService.token ?? '');

    // Reset all filters for new session
    _kalmanFilter.reset();
    _roadSnapper.reset(); // PHASE 3
    _trajectoryPredictor.reset(); // PHASE 3
    _rawPositionBuffer.clear();

    AppLogger.i('🚀 [AI Tracking] Starting UBER-LIKE tracking with PHASE 3 AI...');
    AppLogger.i('   ⚡ STOPPED: 30s intervals | SLOW: 10s | NORMAL: 3s | FAST: 1s');
    AppLogger.i('   🤖 AI: Adaptive Kalman + Road Snapping + Trajectory Prediction');
    AppLogger.i('   📤 Batch upload: Every ${AppConstants.batchUploadIntervalMinutes} min');
    AppLogger.i('   🔴 REAL-TIME: Streaming to server for live map');
    AppLogger.i('   🎯 TARGET: 80-90% GPS points <10m accuracy');

    // GPS WARM-UP: Get 3 readings to improve initial accuracy
    AppLogger.i('🔥 [GPS Warm-Up] Warming up GPS for better accuracy...');
    await _warmUpGPS();

    // Record location immediately
    await _recordLocation();

    // Start adaptive periodic tracking (will adjust based on speed)
    _scheduleNextLocationCheck();

    // Start batch upload timer (every 2 minutes) with AI processing
    _batchUploadTimer = Timer.periodic(
      Duration(minutes: AppConstants.batchUploadIntervalMinutes),
      (_) {
        AppLogger.i('⏰ [Timer] Batch upload timer triggered (${AppConstants.batchUploadIntervalMinutes} min)');
        _batchUploadLocations();
      },
    );
    AppLogger.i('⏰ [Timer] Batch upload timer started - will run every ${AppConstants.batchUploadIntervalMinutes} minutes');
  }

  // GPS Warm-Up: Get 3 readings to stabilize GPS for better initial accuracy
  Future<void> _warmUpGPS() async {
    try {
      for (int i = 0; i < 3; i++) {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 5),
        );
        AppLogger.i('🔥 [Warm-Up ${i+1}/3] Accuracy: ${pos.accuracy.toStringAsFixed(1)}m');
        await Future.delayed(const Duration(milliseconds: 500));
      }
      AppLogger.i('✅ [GPS Warm-Up] Complete! GPS should be accurate now.');
    } catch (e) {
      AppLogger.w('⚠️ [GPS Warm-Up] Failed: $e (continuing anyway)');
    }
  }

  // Schedule next location check with adaptive interval
  void _scheduleNextLocationCheck() {
    _locationTimer?.cancel();
    _locationTimer = Timer(_currentInterval, () async {
      await _recordLocation();
      _scheduleNextLocationCheck(); // Re-schedule with potentially new interval
    });
  }

  // Stop tracking
  void stopTracking() {
    AppLogger.i('🛑 [LocationService] Stopping AI tracking...');
    _locationTimer?.cancel();
    _locationTimer = null;
    _batchUploadTimer?.cancel();
    _batchUploadTimer = null;
    _currentDutySessionId = null;
    _riderId = null;
    _lastValidPosition = null; // Reset for next session
    _lastRawPosition = null;
    _currentInterval = const Duration(seconds: 3); // Reset to normal speed default
    _kalmanFilter.reset(); // Reset Kalman filter
    _roadSnapper.reset(); // PHASE 3: Reset road snapping
    _trajectoryPredictor.reset(); // PHASE 3: Reset trajectory prediction
    _rawPositionBuffer.clear(); // Clear buffer
  }

  // Record current location with HIGH-FREQUENCY ADAPTIVE intervals + Kalman filtering
  Future<void> _recordLocation() async {
    try {
      if (_currentDutySessionId == null) return;

      // Get raw GPS reading with AGGRESSIVE settings for 5-10m accuracy
      Position? rawPosition;
      try {
        rawPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best, // CHANGED: best instead of bestForNavigation for tighter accuracy
          timeLimit: const Duration(seconds: 5), // CHANGED: Reduced from 10s to 5s for faster acquisition
        );
      } catch (e) {
        AppLogger.w('⚠️ GPS acquisition failed: $e');
        return;
      }

      // Basic validation
      if (!_isValidGPSPoint(rawPosition)) {
        AppLogger.w('❌ GPS rejected: Failed validation');
        return;
      }

      // === PHASE 3: ADVANCED GPS PROCESSING PIPELINE ===

      // Step 1: Kalman Filter (adaptive noise, outlier rejection)
      final kalmanFiltered = _kalmanFilter.filter(rawPosition);

      // Step 2: Trajectory Prediction (validate against expected path)
      _trajectoryPredictor.addPosition(kalmanFiltered);
      final isValidTrajectory = _trajectoryPredictor.validatePosition(kalmanFiltered);

      Position filteredPosition;
      if (!isValidTrajectory) {
        // GPS deviated from expected trajectory, try to correct
        final correctedPosition = _trajectoryPredictor.getCorrectedPosition(kalmanFiltered);
        if (correctedPosition != null) {
          AppLogger.w('📐 [Phase 3] Trajectory correction applied');
          filteredPosition = correctedPosition;
        } else {
          filteredPosition = kalmanFiltered;
        }
      } else {
        filteredPosition = kalmanFiltered;
      }

      // Step 3: Road Snapping (align to logical road path)
      final snappedPosition = _roadSnapper.snapToRoad(filteredPosition);

      // Store raw position for activity detection
      _lastRawPosition = rawPosition;

      // Add to buffer for AI processing during upload
      _rawPositionBuffer.add(snappedPosition);

      // Detect activity and adjust interval (UBER-LIKE HIGH-FREQUENCY)
      final activity = AIRouteProcessor.detectActivity(snappedPosition.speed);
      Duration newInterval;

      switch (activity) {
        case 'stopped':
          newInterval = const Duration(seconds: 30); // 30s when stopped
          break;
        case 'slow':
          newInterval = const Duration(seconds: 10); // 10s when slow (<10 km/h)
          break;
        case 'normal':
          newInterval = const Duration(seconds: 3); // 3s when normal (10-30 km/h)
          break;
        case 'fast':
        case 'highway':
          newInterval = const Duration(seconds: 1); // 1s when fast (>30 km/h)
          break;
        default:
          newInterval = const Duration(seconds: 3);
      }

      if (newInterval != _currentInterval) {
        _currentInterval = newInterval;
        AppLogger.i('🔄 Interval switched: $activity (${newInterval.inSeconds}s)');
      }

      // Skip GPS drift when stopped
      if (activity == 'stopped' && _lastValidPosition != null) {
        final driftDistance = Geolocator.distanceBetween(
          _lastValidPosition!.latitude,
          _lastValidPosition!.longitude,
          snappedPosition.latitude,
          snappedPosition.longitude,
        );

        if (driftDistance < AppConstants.stoppedDriftThreshold) {
          return; // Skip this point - just GPS drift
        }
      }

      // Calculate GPS quality confidence score (PHASE 3)
      final confidenceScore = _calculateConfidenceScore(rawPosition, snappedPosition);

      // Save PHASE 3 processed position to local database
      // CRITICAL: Convert to Bangladesh time (UTC+6) regardless of device timezone
      // Strategy: Device time → UTC → Bangladesh time (UTC+6) as local DateTime
      // This ensures consistent timestamps whether rider is in Malaysia (UTC+8) or Bangladesh (UTC+6)
      final utcNow = DateTime.now().toUtc(); // Get current time in UTC
      final utcPlus6 = utcNow.add(const Duration(hours: 6)); // UTC + 6 hours
      // Create as local DateTime (not UTC) so toIso8601String() doesn't add 'Z'
      final bangladeshTime = DateTime(
        utcPlus6.year,
        utcPlus6.month,
        utcPlus6.day,
        utcPlus6.hour,
        utcPlus6.minute,
        utcPlus6.second,
        utcPlus6.millisecond,
        utcPlus6.microsecond,
      ); // This creates a local DateTime representing Bangladesh time

      final locationPoint = LocationPoint(
        riderId: _riderId,
        dutySessionId: _currentDutySessionId!,
        latitude: snappedPosition.latitude,
        longitude: snappedPosition.longitude,
        accuracy: snappedPosition.accuracy,
        speed: snappedPosition.speed,
        bearing: snappedPosition.heading,
        altitude: snappedPosition.altitude,
        recordedAt: bangladeshTime, // Always Bangladesh time (UTC+6)
        isSynced: false,
      );

      // ALWAYS save locally first (offline-first!)
      await _storage.saveLocation(locationPoint);

      // Update last valid position
      _lastValidPosition = snappedPosition;

      final speedKmh = (snappedPosition.speed * 3.6).toStringAsFixed(1);
      final activityIcon = activity == 'stopped' ? '🛑' :
                          activity == 'slow' ? '🚶' :
                          activity == 'normal' ? '🚗' : '⚡';
      final confidenceIcon = confidenceScore > 0.8 ? '🎯' : confidenceScore > 0.6 ? '✅' : '⚠️';
      AppLogger.d('$activityIcon$confidenceIcon GPS: (${snappedPosition.latitude.toStringAsFixed(6)}, ${snappedPosition.longitude.toStringAsFixed(6)}) | Acc: ${snappedPosition.accuracy.toStringAsFixed(1)}m | Speed: ${speedKmh} km/h | Conf: ${(confidenceScore * 100).toStringAsFixed(0)}%');

      // REAL-TIME STREAMING: Send immediately to server for live map (only if good accuracy)
      if (snappedPosition.accuracy < 30) {
        _streamLocationToServer(locationPoint);
      }

      // Note: Batch upload with AI processing happens every 2 minutes
    } catch (e) {
      AppLogger.e('❌ Error recording location: $e');
    }
  }

  // Determine if rider is MOVING or STOPPED
  bool _isMoving(Position current) {
    // No previous position - assume moving
    if (_lastValidPosition == null) return true;

    // Check speed first (GPS provides this directly)
    if (current.speed > AppConstants.movementSpeedThreshold) {
      return true; // Moving (>0.5 m/s = 1.8 km/h)
    }

    // Check distance moved since last point
    final distance = Geolocator.distanceBetween(
      _lastValidPosition!.latitude,
      _lastValidPosition!.longitude,
      current.latitude,
      current.longitude,
    );

    if (distance > AppConstants.movementDistanceThreshold) {
      return true; // Moved >10 meters
    }

    // Otherwise, stopped
    return false;
  }

  // ✅ MULTI-TIER GPS validation - accept more points with confidence levels
  bool _isValidGPSPoint(Position newPosition) {
    // 1. MULTI-TIER ACCURACY CHECK: Accept GPS up to 50m (was 20m)
    // TIER 1 (<10m): Excellent - use directly
    // TIER 2 (10-20m): Good - will apply strong filtering
    // TIER 3 (20-50m): Fair - use only if recent
    // TIER 4 (>50m): Poor - reject
    if (newPosition.accuracy > 50) {
      print('⚠️ GPS REJECTED: Poor accuracy ${newPosition.accuracy.toStringAsFixed(1)}m (need <50m)');
      return false;
    }

    // 2. Check for valid coordinates
    if (newPosition.latitude == 0.0 || newPosition.longitude == 0.0) {
      print('⚠️ GPS REJECTED: Invalid coordinates (0,0)');
      return false;
    }

    // 3. Check if coordinates are within reasonable range
    if (newPosition.latitude.abs() > 90 || newPosition.longitude.abs() > 180) {
      print('⚠️ GPS REJECTED: Coordinates out of range');
      return false;
    }

    // If we have a previous position, do advanced validation
    if (_lastValidPosition != null) {
      final distance = Geolocator.distanceBetween(
        _lastValidPosition!.latitude,
        _lastValidPosition!.longitude,
        newPosition.latitude,
        newPosition.longitude,
      );

      // Calculate time difference (assuming 30-60 second intervals)
      final timeDiff = 60; // Max 60 seconds between points

      // 4. STRICT SPEED CHECK: Reject impossible speeds
      // Max realistic speed for delivery rider: 80 km/h
      final maxSpeed = 80 / 3.6; // 80 km/h in m/s = 22.2 m/s
      final impliedSpeed = distance / timeDiff; // m/s

      if (impliedSpeed > maxSpeed) {
        print('⚠️ GPS REJECTED: Impossible speed ${(impliedSpeed * 3.6).toStringAsFixed(1)} km/h (moved ${distance.toStringAsFixed(0)}m in ${timeDiff}s)');
        return false;
      }

      // 5. STRICT JUMP CHECK: Reject sudden jumps (teleportation)
      // Max realistic movement in 30s at 80 km/h = ~670m
      const maxRealisticDistance = 700; // meters
      if (distance > maxRealisticDistance) {
        print('⚠️ GPS REJECTED: Impossible jump ${distance.toStringAsFixed(0)}m (max ${maxRealisticDistance}m)');
        return false;
      }

      // 6. Accuracy degradation check
      // If new point is much less accurate than previous, reject it
      if (newPosition.accuracy > _lastValidPosition!.accuracy * 2) {
        print('⚠️ GPS REJECTED: Accuracy degraded from ${_lastValidPosition!.accuracy.toStringAsFixed(1)}m to ${newPosition.accuracy.toStringAsFixed(1)}m');
        return false;
      }
    }

    // 7. Speed sensor validation
    // Reject if reported speed is unrealistic (>100 km/h for delivery rider)
    if (newPosition.speed > 100 / 3.6) { // 100 km/h in m/s
      print('⚠️ GPS REJECTED: Impossible reported speed ${(newPosition.speed * 3.6).toStringAsFixed(1)} km/h');
      return false;
    }

    print('✅ GPS ACCEPTED: Accuracy ${newPosition.accuracy.toStringAsFixed(1)}m, Speed ${(newPosition.speed * 3.6).toStringAsFixed(1)} km/h');
    return true;
  }

  // PHASE 3: Calculate GPS confidence score (0.0 - 1.0)
  double _calculateConfidenceScore(Position rawPosition, Position processedPosition) {
    double score = 1.0;

    // Factor 1: GPS Accuracy (most important)
    if (rawPosition.accuracy < 5) {
      score *= 1.0; // Excellent
    } else if (rawPosition.accuracy < 10) {
      score *= 0.9; // Very good
    } else if (rawPosition.accuracy < 20) {
      score *= 0.75; // Good
    } else if (rawPosition.accuracy < 40) {
      score *= 0.5; // Fair
    } else {
      score *= 0.3; // Poor
    }

    // Factor 2: Trajectory Prediction Confidence
    final trajectoryStats = _trajectoryPredictor.getStats();
    if (trajectoryStats['confidence'] != null) {
      score *= (trajectoryStats['confidence'] * 0.5 + 0.5); // 50-100% weight
    }

    // Factor 3: Processing adjustments
    final processingAdjustment = (processedPosition.accuracy - rawPosition.accuracy).abs();
    if (processingAdjustment > 10) {
      score *= 0.8; // Large correction applied
    }

    return score.clamp(0.0, 1.0);
  }

  // REAL-TIME STREAMING: Send location immediately to server (non-blocking)
  void _streamLocationToServer(LocationPoint location) async {
    try {
      // Fire and forget - don't wait for response (non-blocking)
      _api.streamLocation(location).then((_) {
        // Success - map will update in real-time
      }).catchError((e) {
        // Fail silently - batch upload will catch it later
        AppLogger.w('⚠️ [Stream] Failed: $e (batch will retry)');
      });
    } catch (e) {
      // Fail silently - don't block GPS recording
    }
  }

  // Public method to manually trigger batch upload (called when internet returns)
  Future<void> syncPendingLocations() async {
    await _batchUploadLocations();
  }

  // Get current location once
  Future<Position?> getCurrentLocation() async {
    try {
      bool hasPermission = await checkPermissions();
      if (!hasPermission) return null;

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (e) {
      print('Error getting current location: $e');
      return null;
    }
  }

  // Batch upload pending locations with AI processing (called every 2 minutes)
  Future<void> _batchUploadLocations() async {
    try {
      AppLogger.i('📤 [AI Batch Upload] Checking for pending locations...');

      // Check internet connectivity
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        final pendingCount = await _storage.getPendingCount();
        AppLogger.w('📴 [AI Batch Upload] No internet. ${pendingCount} points queued locally (buffer: ${_rawPositionBuffer.length}).');
        return; // No internet, will try again in 2 minutes
      }

      final pending = await _storage.getPendingLocations();
      if (pending.isEmpty) {
        AppLogger.i('✅ [AI Batch Upload] No pending locations to upload');
        _rawPositionBuffer.clear(); // Clear buffer
        return;
      }

      AppLogger.i('📤 [AI Batch Upload] Found ${pending.length} pending points. Processing with AI...');

      // === AI PROCESSING ===
      // Step 1: Convert LocationPoint to Position for AI processing
      List<LocationPoint> toUpload;

      if (pending.length >= 10) {
        // We have enough points to apply AI compression
        AppLogger.i('🤖 [AI Processing] Converting ${pending.length} points for AI analysis...');

        final positions = pending.map((loc) => Position(
          latitude: loc.latitude,
          longitude: loc.longitude,
          timestamp: loc.recordedAt,
          accuracy: loc.accuracy ?? 10.0,
          altitude: loc.altitude ?? 0,
          heading: loc.bearing ?? 0,
          speed: loc.speed ?? 0,
          speedAccuracy: 0,
          altitudeAccuracy: 0,
          headingAccuracy: 0,
        )).toList();

        // Step 2: Apply AI compression (outlier removal + Douglas-Peucker)
        AppLogger.i('🤖 [AI Processing] Running outlier detection + path simplification...');
        final processedRoute = AIRouteProcessor.processRoute(positions);
        final processedPositions = processedRoute.processedPoints;

        // Step 3: Find corresponding LocationPoint objects
        final processedTimestamps = processedPositions.map((p) => p.timestamp).toSet();
        toUpload = pending.where((loc) => processedTimestamps.contains(loc.recordedAt)).toList();

        final compressionRatio = ((1 - toUpload.length / pending.length) * 100).toStringAsFixed(1);
        AppLogger.i('🤖 [AI Compression] ${pending.length} → ${toUpload.length} points ($compressionRatio% reduction)');
        AppLogger.i('📊 [Route Stats] Distance: ${processedRoute.totalDistanceKm.toStringAsFixed(2)} km, Duration: ${processedRoute.totalDuration.inMinutes} min');
        AppLogger.i('📊 [Network Saved] ${((pending.length - toUpload.length) * 0.2).toStringAsFixed(1)} KB data saved');

      } else {
        // Too few points, send all without compression
        toUpload = pending;
        AppLogger.i('⏭️ [AI Processing] Only ${pending.length} points - skipping compression (need 10+)');
      }

      // Upload in batches of 50 (API might have limits)
      const batchSize = 50;
      int totalUploaded = 0;

      for (int i = 0; i < toUpload.length; i += batchSize) {
        final batch = toUpload.skip(i).take(batchSize).toList();
        try {
          await _api.bulkRecordLocations(batch);

          AppLogger.i('✅ [Upload] Sent batch of ${batch.length} points to backend');
          totalUploaded += batch.length;

        } catch (e) {
          AppLogger.e('❌ [Upload] Failed to upload batch: $e');
          // Continue with next batch even if this one fails
        }
      }

      // Mark ALL pending points as synced (including filtered ones)
      // This is important: even points we didn't send are "processed"
      if (totalUploaded > 0) {
        final allIds = pending.where((l) => l.id != null).map((l) => l.id!).toList();
        if (allIds.isNotEmpty) {
          await _storage.markBatchAsSynced(allIds);
        }

        AppLogger.i('✅ [AI Batch Upload] Success! Uploaded: $totalUploaded / ${pending.length} points');
        AppLogger.i('💾 [Storage] Marked ${allIds.length} points as synced (including filtered points)');
        _rawPositionBuffer.clear(); // Clear buffer after successful upload
      }
    } catch (e) {
      AppLogger.e('❌ [AI Batch Upload] Error: $e');
    }
  }

  // Get pending count
  Future<int> getPendingCount() async {
    return await _storage.getPendingCount();
  }

  // Check if location service is enabled
  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  // Force sync - manually trigger batch upload
  Future<Map<String, dynamic>> forceSync() async {
    try {
      AppLogger.i('🔄 [Force Sync] Manual sync triggered by user...');

      // Check if there's an active session
      if (_currentDutySessionId == null) {
        AppLogger.w('⚠️ [Force Sync] No active duty session');
        return {
          'success': false,
          'message': 'No active duty session. Please go online first.',
        };
      }

      // Check internet connectivity
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        final pendingCount = await _storage.getPendingCount();
        AppLogger.w('📴 [Force Sync] No internet connection. $pendingCount points queued.');
        return {
          'success': false,
          'message': 'No internet connection. $pendingCount points queued for later sync.',
        };
      }

      // Get pending count before sync
      final pendingBefore = await _storage.getPendingCount();
      if (pendingBefore == 0) {
        AppLogger.i('✅ [Force Sync] No pending data to sync. All up to date!');
        return {
          'success': true,
          'message': 'All data is already synced!',
          'synced': 0,
        };
      }

      await _batchUploadLocations();

      // Get pending count after sync
      final pendingAfter = await _storage.getPendingCount();
      final synced = pendingBefore - pendingAfter;

      if (synced == 0) {
        AppLogger.w('⚠️ [Force Sync] Upload attempted but no points were synced. Check logs for errors.');
        return {
          'success': false,
          'message': 'Sync failed. $pendingBefore points still pending. Check internet and backend.',
        };
      }

      AppLogger.i('✅ [Force Sync] Completed! Synced $synced points.');
      return {
        'success': true,
        'message': 'Successfully synced $synced GPS points!',
        'synced': synced,
      };
    } catch (e) {
      AppLogger.e('❌ [Force Sync] Failed: $e');
      return {
        'success': false,
        'message': 'Sync failed: ${e.toString()}',
      };
    }
  }

  // Get current session statistics
  Future<Map<String, dynamic>> getSessionStats() async {
    if (_currentDutySessionId == null) {
      return {
        'totalPoints': 0,
        'pendingPoints': 0,
        'syncedPoints': 0,
        'lastSyncTime': null,
      };
    }

    final pending = await _storage.getPendingCount();
    final total = await _storage.getTotalPointsForSession(_currentDutySessionId!);

    return {
      'totalPoints': total,
      'pendingPoints': pending,
      'syncedPoints': total - pending,
      'lastSyncTime': DateTime.now(),
    };
  }
}
