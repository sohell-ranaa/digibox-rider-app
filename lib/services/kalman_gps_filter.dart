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
  // Lower = trust prediction more, Higher = trust measurements more
  static const double _processNoise = 0.5;

  // Measurement noise (GPS accuracy uncertainty)
  double _measurementNoise = 10.0; // Will be updated based on actual GPS accuracy

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

    // Store update time
    _lastUpdateTime = now;

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
