import 'dart:math';
import 'package:geolocator/geolocator.dart';

/// PHASE 3: Road Snapping Service
/// Snaps GPS points to logical road paths using bearing and trajectory analysis
/// This reduces GPS drift and improves route accuracy without external APIs
class RoadSnappingService {
  // Recent positions for trajectory analysis
  final List<Position> _recentPositions = [];
  static const int _maxHistorySize = 10;

  // Minimum movement to consider for snapping (meters)
  static const double _minMovementThreshold = 2.0;

  /// Snap a GPS position to the most likely road position
  /// Uses bearing continuity and trajectory prediction
  Position snapToRoad(Position rawPosition) {
    // Add to history
    _recentPositions.add(rawPosition);
    if (_recentPositions.length > _maxHistorySize) {
      _recentPositions.removeAt(0);
    }

    // Need at least 3 points for road snapping
    if (_recentPositions.length < 3) {
      return rawPosition; // Not enough history
    }

    // Check if rider is moving
    if (!_isMoving(rawPosition)) {
      return rawPosition; // Don't snap when stopped
    }

    // Get expected bearing from trajectory
    final expectedBearing = _calculateExpectedBearing();
    if (expectedBearing == null) {
      return rawPosition; // Can't determine trajectory
    }

    // Get actual bearing from GPS
    final actualBearing = rawPosition.heading;

    // If bearings are similar, GPS is likely correct
    final bearingDiff = _angleDifference(expectedBearing, actualBearing);
    if (bearingDiff < 15.0) {
      return rawPosition; // GPS aligns with trajectory
    }

    // Apply bearing correction
    final snappedPosition = _applyBearingCorrection(
      rawPosition,
      expectedBearing,
      bearingDiff,
    );

    return snappedPosition;
  }

  /// Check if rider is moving (not stopped)
  bool _isMoving(Position position) {
    if (_recentPositions.length < 2) return false;

    final lastPos = _recentPositions[_recentPositions.length - 2];
    final distance = _calculateDistance(
      lastPos.latitude,
      lastPos.longitude,
      position.latitude,
      position.longitude,
    );

    return distance > _minMovementThreshold;
  }

  /// Calculate expected bearing from recent trajectory
  double? _calculateExpectedBearing() {
    if (_recentPositions.length < 3) return null;

    // Use weighted average of recent bearings
    final recentBearings = <double>[];

    for (int i = 1; i < _recentPositions.length; i++) {
      final prev = _recentPositions[i - 1];
      final curr = _recentPositions[i];

      // Only use bearings where rider was moving
      final distance = _calculateDistance(
        prev.latitude,
        prev.longitude,
        curr.latitude,
        curr.longitude,
      );

      if (distance > _minMovementThreshold) {
        final bearing = _calculateBearing(
          prev.latitude,
          prev.longitude,
          curr.latitude,
          curr.longitude,
        );
        recentBearings.add(bearing);
      }
    }

    if (recentBearings.isEmpty) return null;

    // Weighted average: recent bearings have more weight
    double weightedSum = 0.0;
    double totalWeight = 0.0;

    for (int i = 0; i < recentBearings.length; i++) {
      final weight = (i + 1).toDouble(); // Linear weighting
      weightedSum += recentBearings[i] * weight;
      totalWeight += weight;
    }

    return weightedSum / totalWeight;
  }

  /// Apply bearing correction to snap position to expected trajectory
  Position _applyBearingCorrection(
    Position rawPosition,
    double expectedBearing,
    double bearingDiff,
  ) {
    // Correction factor based on bearing difference
    // Small diff = small correction, large diff = larger correction
    final correctionFactor = (bearingDiff / 180.0).clamp(0.0, 1.0);

    // Only apply correction if GPS accuracy is poor
    if (rawPosition.accuracy < 10.0) {
      // GPS is good, minimal correction
      return rawPosition;
    }

    // Calculate correction distance (proportional to accuracy error)
    final correctionDistance = rawPosition.accuracy * correctionFactor * 0.5;

    // Apply correction in direction of expected bearing
    final correctedPosition = _movePosition(
      rawPosition.latitude,
      rawPosition.longitude,
      expectedBearing,
      correctionDistance,
    );

    return Position(
      latitude: correctedPosition['latitude']!,
      longitude: correctedPosition['longitude']!,
      timestamp: rawPosition.timestamp,
      accuracy: rawPosition.accuracy * 0.8, // Slightly better accuracy after snapping
      altitude: rawPosition.altitude,
      altitudeAccuracy: rawPosition.altitudeAccuracy,
      heading: expectedBearing, // Use corrected bearing
      headingAccuracy: rawPosition.headingAccuracy,
      speed: rawPosition.speed,
      speedAccuracy: rawPosition.speedAccuracy,
    );
  }

  /// Calculate bearing between two GPS points
  double _calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    final dLon = _toRadians(lon2 - lon1);
    final lat1Rad = _toRadians(lat1);
    final lat2Rad = _toRadians(lat2);

    final y = sin(dLon) * cos(lat2Rad);
    final x = cos(lat1Rad) * sin(lat2Rad) -
        sin(lat1Rad) * cos(lat2Rad) * cos(dLon);

    final bearing = atan2(y, x);
    return (_toDegrees(bearing) + 360) % 360; // Normalize to 0-360
  }

  /// Calculate distance between two GPS points (Haversine)
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

  /// Move a GPS position by distance and bearing
  Map<String, double> _movePosition(
    double lat,
    double lon,
    double bearing,
    double distanceMeters,
  ) {
    const earthRadius = 6371000.0; // meters

    final latRad = _toRadians(lat);
    final lonRad = _toRadians(lon);
    final bearingRad = _toRadians(bearing);
    final angularDistance = distanceMeters / earthRadius;

    final newLatRad = asin(
      sin(latRad) * cos(angularDistance) +
          cos(latRad) * sin(angularDistance) * cos(bearingRad),
    );

    final newLonRad = lonRad +
        atan2(
          sin(bearingRad) * sin(angularDistance) * cos(latRad),
          cos(angularDistance) - sin(latRad) * sin(newLatRad),
        );

    return {
      'latitude': _toDegrees(newLatRad),
      'longitude': _toDegrees(newLonRad),
    };
  }

  /// Calculate smallest angle difference between two bearings
  double _angleDifference(double bearing1, double bearing2) {
    double diff = (bearing2 - bearing1).abs();
    if (diff > 180) {
      diff = 360 - diff;
    }
    return diff;
  }

  /// Convert radians to degrees
  double _toDegrees(double radians) {
    return radians * 180.0 / pi;
  }

  /// Convert degrees to radians
  double _toRadians(double degrees) {
    return degrees * pi / 180.0;
  }

  /// Reset the service (clear history)
  void reset() {
    _recentPositions.clear();
  }
}
