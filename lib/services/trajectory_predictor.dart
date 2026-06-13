import 'dart:math';
import 'package:geolocator/geolocator.dart';

/// PHASE 3: Trajectory Predictor
/// Predicts next GPS position based on recent movement patterns
/// Helps detect and correct GPS anomalies
class TrajectoryPredictor {
  // Recent positions for pattern analysis
  final List<_TrajectoryPoint> _history = [];
  static const int _maxHistorySize = 15;

  // Prediction confidence threshold
  static const double _minConfidenceForCorrection = 0.7;

  /// Store a new position in trajectory history
  void addPosition(Position position) {
    _history.add(_TrajectoryPoint(
      position: position,
      timestamp: DateTime.now(),
    ));

    if (_history.length > _maxHistorySize) {
      _history.removeAt(0);
    }
  }

  /// Predict next position based on trajectory
  /// Returns predicted position and confidence score (0.0 - 1.0)
  Map<String, dynamic>? predictNext(Duration timeAhead) {
    if (_history.length < 3) {
      return null; // Not enough data
    }

    // Calculate average velocity from recent points
    final velocity = _calculateAverageVelocity();
    if (velocity == null) {
      return null;
    }

    // Get last known position
    final lastPoint = _history.last;

    // Predict position using velocity
    final predictedLat = lastPoint.position.latitude +
        (velocity['latVelocity']! * timeAhead.inSeconds);
    final predictedLng = lastPoint.position.longitude +
        (velocity['lngVelocity']! * timeAhead.inSeconds);

    // Calculate prediction confidence based on trajectory consistency
    final confidence = _calculateConfidence();

    return {
      'latitude': predictedLat,
      'longitude': predictedLng,
      'confidence': confidence,
      'velocity': velocity,
    };
  }

  /// Validate if a new position matches predicted trajectory
  /// Returns true if position is reasonable, false if it's likely an outlier
  bool validatePosition(Position newPosition) {
    final prediction = predictNext(const Duration(seconds: 3));
    if (prediction == null) {
      return true; // Not enough data to validate
    }

    // Only apply validation if confidence is high
    if (prediction['confidence'] < _minConfidenceForCorrection) {
      return true; // Low confidence, accept position
    }

    // Calculate distance from prediction
    final distanceFromPrediction = _calculateDistance(
      prediction['latitude'],
      prediction['longitude'],
      newPosition.latitude,
      newPosition.longitude,
    );

    // Threshold based on speed and GPS accuracy
    final speed = newPosition.speed;
    final maxDeviation = max(
      newPosition.accuracy * 2, // GPS uncertainty
      speed * 3.6 * 1.5, // Speed-based threshold (km/h to m)
    );

    final isValid = distanceFromPrediction < maxDeviation;

    if (!isValid) {
      print('⚠️ [Trajectory] Position deviates ${distanceFromPrediction.toStringAsFixed(0)}m from prediction (max ${maxDeviation.toStringAsFixed(0)}m)');
    }

    return isValid;
  }

  /// Get corrected position using trajectory prediction
  Position? getCorrectedPosition(Position rawPosition) {
    final prediction = predictNext(const Duration(seconds: 1));
    if (prediction == null || prediction['confidence'] < _minConfidenceForCorrection) {
      return null; // Can't correct
    }

    // Blend raw position with prediction based on GPS accuracy
    final blendFactor = _calculateBlendFactor(rawPosition.accuracy);

    final correctedLat = rawPosition.latitude * (1 - blendFactor) +
        prediction['latitude'] * blendFactor;
    final correctedLng = rawPosition.longitude * (1 - blendFactor) +
        prediction['longitude'] * blendFactor;

    return Position(
      latitude: correctedLat,
      longitude: correctedLng,
      timestamp: rawPosition.timestamp,
      accuracy: rawPosition.accuracy * 0.7, // Improved accuracy
      altitude: rawPosition.altitude,
      altitudeAccuracy: rawPosition.altitudeAccuracy,
      heading: rawPosition.heading,
      headingAccuracy: rawPosition.headingAccuracy,
      speed: rawPosition.speed,
      speedAccuracy: rawPosition.speedAccuracy,
    );
  }

  /// Calculate average velocity from recent trajectory
  Map<String, double>? _calculateAverageVelocity() {
    if (_history.length < 3) return null;

    double totalLatVelocity = 0.0;
    double totalLngVelocity = 0.0;
    int count = 0;

    for (int i = 1; i < _history.length; i++) {
      final prev = _history[i - 1];
      final curr = _history[i];

      final dt = curr.timestamp.difference(prev.timestamp).inSeconds;
      if (dt == 0) continue;

      final latVel = (curr.position.latitude - prev.position.latitude) / dt;
      final lngVel = (curr.position.longitude - prev.position.longitude) / dt;

      // Weight recent velocities more heavily
      final weight = (i / _history.length) + 0.5;
      totalLatVelocity += latVel * weight;
      totalLngVelocity += lngVel * weight;
      count++;
    }

    if (count == 0) return null;

    return {
      'latVelocity': totalLatVelocity / count,
      'lngVelocity': totalLngVelocity / count,
    };
  }

  /// Calculate confidence score based on trajectory consistency
  double _calculateConfidence() {
    if (_history.length < 5) {
      return 0.3; // Low confidence with limited data
    }

    // Calculate variance in speed and bearing
    final speeds = <double>[];
    final bearings = <double>[];

    for (int i = 1; i < _history.length; i++) {
      final prev = _history[i - 1];
      final curr = _history[i];

      speeds.add(curr.position.speed);

      final bearing = _calculateBearing(
        prev.position.latitude,
        prev.position.longitude,
        curr.position.latitude,
        curr.position.longitude,
      );
      bearings.add(bearing);
    }

    // Low variance = high confidence
    final speedVariance = _calculateVariance(speeds);
    final bearingVariance = _calculateVariance(bearings);

    // Normalize variances to confidence (0.0 - 1.0)
    final speedConfidence = 1.0 / (1.0 + speedVariance / 10.0);
    final bearingConfidence = 1.0 / (1.0 + bearingVariance / 100.0);

    // Combined confidence
    return (speedConfidence + bearingConfidence) / 2.0;
  }

  /// Calculate blend factor for position correction
  /// Poor GPS accuracy = blend more with prediction
  double _calculateBlendFactor(double gpsAccuracy) {
    if (gpsAccuracy < 10.0) {
      return 0.1; // Good GPS, minimal blending
    } else if (gpsAccuracy < 20.0) {
      return 0.3; // Moderate GPS, some blending
    } else if (gpsAccuracy < 40.0) {
      return 0.5; // Poor GPS, equal blending
    } else {
      return 0.7; // Very poor GPS, mostly use prediction
    }
  }

  /// Calculate variance of a list of values
  double _calculateVariance(List<double> values) {
    if (values.isEmpty) return 0.0;

    final mean = values.reduce((a, b) => a + b) / values.length;
    final squaredDiffs = values.map((v) => pow(v - mean, 2));
    return squaredDiffs.reduce((a, b) => a + b) / values.length;
  }

  /// Calculate bearing between two points
  double _calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    final dLon = _toRadians(lon2 - lon1);
    final lat1Rad = _toRadians(lat1);
    final lat2Rad = _toRadians(lat2);

    final y = sin(dLon) * cos(lat2Rad);
    final x = cos(lat1Rad) * sin(lat2Rad) -
        sin(lat1Rad) * cos(lat2Rad) * cos(dLon);

    final bearing = atan2(y, x);
    return (_toDegrees(bearing) + 360) % 360;
  }

  /// Calculate distance between two points (Haversine)
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

  double _toRadians(double degrees) => degrees * pi / 180.0;
  double _toDegrees(double radians) => radians * 180.0 / pi;

  /// Reset the predictor
  void reset() {
    _history.clear();
  }

  /// Get statistics about current trajectory
  Map<String, dynamic> getStats() {
    if (_history.isEmpty) {
      return {'points': 0, 'confidence': 0.0};
    }

    return {
      'points': _history.length,
      'confidence': _calculateConfidence(),
      'avgSpeed': _history.map((p) => p.position.speed).reduce((a, b) => a + b) / _history.length,
    };
  }
}

/// Internal class to store trajectory point with timestamp
class _TrajectoryPoint {
  final Position position;
  final DateTime timestamp;

  _TrajectoryPoint({
    required this.position,
    required this.timestamp,
  });
}
