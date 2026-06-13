import 'dart:math';
import 'package:geolocator/geolocator.dart';

/// Kalman Filter for GPS data smoothing
/// Reduces GPS noise and provides more accurate location estimates
///
/// The Kalman filter works by:
/// 1. Predicting the next state based on previous velocity
/// 2. Measuring the actual GPS reading
/// 3. Combining prediction and measurement with optimal weights
/// 4. Continuously updating the estimate
class KalmanGPSFilter {
  // State variables
  double _latitude = 0.0;
  double _longitude = 0.0;
  double _velocityLat = 0.0;
  double _velocityLng = 0.0;

  // Error covariance matrix (simplified 2D case)
  double _errorLat = 1000.0; // Initial uncertainty (large)
  double _errorLng = 1000.0;

  // Process noise (how much we trust the prediction model)
  // ADAPTIVE: Changes based on vehicle speed and state
  double _processNoise = 0.5;

  // Measurement noise (GPS accuracy uncertainty)
  double _measurementNoise = 10.0; // Will be updated based on actual GPS accuracy

  // Speed tracking for adaptive filtering
  double _lastSpeed = 0.0;

  // Outlier detection threshold
  static const double _outlierThresholdMeters = 100.0; // Reject jumps >100m

  // Time of last update
  DateTime? _lastUpdateTime;

  // Has the filter been initialized?
  bool _isInitialized = false;

  /// Process a new GPS position through the Kalman filter
  /// Returns smoothed position with reduced noise
  Position filter(Position measurement) {
    final now = DateTime.now();

    // First measurement - initialize filter
    if (!_isInitialized) {
      _latitude = measurement.latitude;
      _longitude = measurement.longitude;
      _velocityLat = 0.0;
      _velocityLng = 0.0;
      _errorLat = measurement.accuracy;
      _errorLng = measurement.accuracy;
      _measurementNoise = measurement.accuracy;
      _lastUpdateTime = now;
      _isInitialized = true;

      return measurement; // Return original first measurement
    }

    // Calculate time delta
    final dt = _lastUpdateTime != null
        ? now.difference(_lastUpdateTime!).inMilliseconds / 1000.0
        : 1.0;

    // Clamp dt to reasonable values (0.1s to 60s)
    final deltaTime = dt.clamp(0.1, 60.0);

    // === ADAPTIVE PROCESS NOISE (Phase 3) ===
    // Adjust process noise based on speed and GPS accuracy
    _updateAdaptiveNoise(measurement.speed, measurement.accuracy);

    // === OUTLIER DETECTION (Phase 3) ===
    // Reject GPS jumps that are physically impossible
    if (_isOutlier(measurement, deltaTime)) {
      // Return last known good position instead of bad measurement
      return Position(
        latitude: _latitude,
        longitude: _longitude,
        timestamp: measurement.timestamp,
        accuracy: _errorLat,
        altitude: measurement.altitude,
        altitudeAccuracy: measurement.altitudeAccuracy,
        heading: measurement.heading,
        headingAccuracy: measurement.headingAccuracy,
        speed: _lastSpeed,
        speedAccuracy: measurement.speedAccuracy,
      );
    }

    // === PREDICTION STEP ===
    // Predict next state based on velocity
    final predictedLat = _latitude + (_velocityLat * deltaTime);
    final predictedLng = _longitude + (_velocityLng * deltaTime);

    // Predict error covariance (uncertainty grows over time)
    final predictedErrorLat = _errorLat + _processNoise;
    final predictedErrorLng = _errorLng + _processNoise;

    // === UPDATE STEP ===
    // Update measurement noise based on GPS accuracy
    _measurementNoise = measurement.accuracy.clamp(5.0, 50.0);

    // Calculate Kalman gain (0 = trust prediction, 1 = trust measurement)
    final kalmanGainLat = predictedErrorLat / (predictedErrorLat + _measurementNoise);
    final kalmanGainLng = predictedErrorLng / (predictedErrorLng + _measurementNoise);

    // Update state estimate by blending prediction and measurement
    _latitude = predictedLat + kalmanGainLat * (measurement.latitude - predictedLat);
    _longitude = predictedLng + kalmanGainLng * (measurement.longitude - predictedLng);

    // Update velocity estimate
    final measuredVelocityLat = (measurement.latitude - predictedLat) / deltaTime;
    final measuredVelocityLng = (measurement.longitude - predictedLng) / deltaTime;

    _velocityLat = _velocityLat + kalmanGainLat * (measuredVelocityLat - _velocityLat);
    _velocityLng = _velocityLng + kalmanGainLng * (measuredVelocityLng - _velocityLng);

    // Update error covariance
    _errorLat = (1 - kalmanGainLat) * predictedErrorLat;
    _errorLng = (1 - kalmanGainLng) * predictedErrorLng;

    // Store update time and speed
    _lastUpdateTime = now;
    _lastSpeed = measurement.speed;

    // Return smoothed position
    return Position(
      latitude: _latitude,
      longitude: _longitude,
      timestamp: measurement.timestamp,
      accuracy: sqrt(_errorLat * _errorLat + _errorLng * _errorLng),
      altitude: measurement.altitude,
      altitudeAccuracy: measurement.altitudeAccuracy,
      heading: measurement.heading,
      headingAccuracy: measurement.headingAccuracy,
      speed: measurement.speed,
      speedAccuracy: measurement.speedAccuracy,
    );
  }

  /// PHASE 3: Adaptive process noise based on speed and GPS quality
  void _updateAdaptiveNoise(double speed, double accuracy) {
    // Speed in m/s (convert to km/h for readability)
    final speedKmh = speed * 3.6;

    // Base noise levels for different states
    if (speedKmh < 1.0) {
      // STOPPED: Very low noise, trust position more
      _processNoise = 0.1;
    } else if (speedKmh < 10.0) {
      // SLOW (walking/stopped): Low noise
      _processNoise = 0.3;
    } else if (speedKmh < 30.0) {
      // NORMAL (city riding): Medium noise
      _processNoise = 0.5;
    } else {
      // FAST (highway): Higher noise, more dynamic
      _processNoise = 0.8;
    }

    // Adjust for GPS accuracy: worse GPS = higher noise
    if (accuracy > 20) {
      _processNoise *= 1.5; // Increase noise for poor GPS
    }

    // Keep within reasonable bounds
    _processNoise = _processNoise.clamp(0.1, 2.0);
  }

  /// PHASE 3: Outlier detection - reject impossible GPS jumps
  bool _isOutlier(Position measurement, double deltaTime) {
    // Calculate distance from last position
    final distanceMeters = _calculateDistance(
      _latitude,
      _longitude,
      measurement.latitude,
      measurement.longitude,
    );

    // Calculate implied speed (m/s)
    final impliedSpeed = distanceMeters / deltaTime;

    // Max realistic speed for delivery rider: 100 km/h = 27.8 m/s
    const maxRealisticSpeed = 30.0; // m/s (108 km/h with buffer)

    // Reject if speed is impossible
    if (impliedSpeed > maxRealisticSpeed) {
      print('⚠️ [Kalman] OUTLIER REJECTED: ${distanceMeters.toStringAsFixed(0)}m jump in ${deltaTime.toStringAsFixed(1)}s (${(impliedSpeed * 3.6).toStringAsFixed(1)} km/h)');
      return true;
    }

    // Reject if jump is too large regardless of time
    if (distanceMeters > _outlierThresholdMeters) {
      print('⚠️ [Kalman] OUTLIER REJECTED: ${distanceMeters.toStringAsFixed(0)}m jump (max $_outlierThresholdMeters m)');
      return true;
    }

    return false;
  }

  /// Calculate distance between two GPS points using Haversine formula
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000.0; // meters

    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) *
            sin(dLon / 2) * sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  /// Convert degrees to radians
  double _toRadians(double degrees) {
    return degrees * pi / 180.0;
  }

  /// Reset the filter (useful when starting new session)
  void reset() {
    _latitude = 0.0;
    _longitude = 0.0;
    _velocityLat = 0.0;
    _velocityLng = 0.0;
    _errorLat = 1000.0;
    _errorLng = 1000.0;
    _lastUpdateTime = null;
    _isInitialized = false;
  }

  /// Get current filtered position estimate
  Map<String, double> get currentEstimate => {
        'latitude': _latitude,
        'longitude': _longitude,
        'velocityLat': _velocityLat,
        'velocityLng': _velocityLng,
        'errorLat': _errorLat,
        'errorLng': _errorLng,
      };

  /// Check if filter is initialized
  bool get isInitialized => _isInitialized;
}
