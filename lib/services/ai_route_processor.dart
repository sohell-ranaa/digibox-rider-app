import 'dart:math';
import 'package:geolocator/geolocator.dart';
import '../utils/app_logger.dart';

/// AI-powered route processor
/// Provides intelligent GPS processing with:
/// - Activity detection (stopped, slow, normal, fast)
/// - Outlier detection and removal
/// - Douglas-Peucker path simplification
/// - Speed-based segmentation
class AIRouteProcessor {
  // Activity thresholds (speed in km/h)
  static const double _stoppedThreshold = 2.0;
  static const double _slowThreshold = 10.0;
  static const double _normalThreshold = 30.0;
  static const double _fastThreshold = 60.0;

  // Outlier detection parameters
  static const double _maxAccelerationMps2 = 5.0; // Max acceleration 5 m/s² (reasonable for motorbike)
  static const double _maxJumpDistanceMeters = 500.0; // Max sudden jump in position
  static const int _outlierWindowSize = 5; // Points to consider for outlier detection

  // Douglas-Peucker simplification tolerance (meters)
  // 2.0 = High accuracy mode (95%+ accuracy, 30-40% compression)
  static const double _simplificationTolerance = 2.0;

  /// Detect activity type based on speed
  static String detectActivity(double speedMps) {
    final speedKmh = speedMps * 3.6;

    if (speedKmh < _stoppedThreshold) return 'stopped';
    if (speedKmh < _slowThreshold) return 'slow';
    if (speedKmh < _normalThreshold) return 'normal';
    if (speedKmh < _fastThreshold) return 'fast';
    return 'highway';
  }

  /// Detect if a point is an outlier based on surrounding points
  static bool isOutlier(List<Position> points, int index) {
    if (index < 1 || index >= points.length - 1) return false;

    final current = points[index];
    final previous = points[index - 1];
    final next = points.length > index + 1 ? points[index + 1] : null;

    // Check distance jump from previous
    final distFromPrev = Geolocator.distanceBetween(
      previous.latitude,
      previous.longitude,
      current.latitude,
      current.longitude,
    );

    if (distFromPrev > _maxJumpDistanceMeters) {
      AppLogger.w('Outlier detected: Jump of ${distFromPrev.toStringAsFixed(1)}m from previous point');
      return true;
    }

    // Check acceleration (if we have speed data)
    if (current.speed > 0 && previous.speed > 0) {
      final timeDiff = current.timestamp.difference(previous.timestamp).inSeconds;
      if (timeDiff > 0) {
        final acceleration = (current.speed - previous.speed).abs() / timeDiff;
        if (acceleration > _maxAccelerationMps2) {
          AppLogger.w('Outlier detected: Acceleration of ${acceleration.toStringAsFixed(2)} m/s²');
          return true;
        }
      }
    }

    // Check if point deviates significantly from trajectory (if we have next point)
    if (next != null) {
      final distToNext = Geolocator.distanceBetween(
        current.latitude,
        current.longitude,
        next.latitude,
        next.longitude,
      );

      // If distance to next is also very large, likely an outlier
      if (distToNext > _maxJumpDistanceMeters) {
        return true;
      }

      // Calculate perpendicular distance from line (previous -> next)
      final perpendicularDist = _perpendicularDistance(
        current.latitude,
        current.longitude,
        previous.latitude,
        previous.longitude,
        next.latitude,
        next.longitude,
      );

      // If point is far from the trajectory, it's an outlier
      if (perpendicularDist > 50.0) {
        AppLogger.w('Outlier detected: ${perpendicularDist.toStringAsFixed(1)}m deviation from trajectory');
        return true;
      }
    }

    return false;
  }

  /// Remove outliers from a list of positions
  static List<Position> removeOutliers(List<Position> positions) {
    if (positions.length < 3) return positions;

    final filtered = <Position>[];

    for (int i = 0; i < positions.length; i++) {
      if (!isOutlier(positions, i)) {
        filtered.add(positions[i]);
      }
    }

    AppLogger.i('Outlier removal: ${positions.length} → ${filtered.length} points (${positions.length - filtered.length} removed)');

    return filtered;
  }

  /// Simplify path using Douglas-Peucker algorithm
  /// Reduces number of points while maintaining shape
  static List<Position> simplifyPath(List<Position> positions, {double? tolerance}) {
    if (positions.length < 3) return positions;

    final actualTolerance = tolerance ?? _simplificationTolerance;

    final simplified = _douglasPeucker(positions, 0, positions.length - 1, actualTolerance);

    // Always include first and last points
    if (!simplified.contains(positions.first)) {
      simplified.insert(0, positions.first);
    }
    if (!simplified.contains(positions.last)) {
      simplified.add(positions.last);
    }

    AppLogger.i('Douglas-Peucker: ${positions.length} → ${simplified.length} points (${((1 - simplified.length / positions.length) * 100).toStringAsFixed(1)}% reduction)');

    return simplified;
  }

  /// Douglas-Peucker recursive algorithm
  static List<Position> _douglasPeucker(
    List<Position> positions,
    int startIndex,
    int endIndex,
    double tolerance,
  ) {
    double maxDistance = 0.0;
    int maxIndex = 0;

    // Find point with maximum distance from line
    for (int i = startIndex + 1; i < endIndex; i++) {
      final distance = _perpendicularDistance(
        positions[i].latitude,
        positions[i].longitude,
        positions[startIndex].latitude,
        positions[startIndex].longitude,
        positions[endIndex].latitude,
        positions[endIndex].longitude,
      );

      if (distance > maxDistance) {
        maxDistance = distance;
        maxIndex = i;
      }
    }

    // If max distance is greater than tolerance, recursively simplify
    if (maxDistance > tolerance) {
      // Recursive call for both segments
      final left = _douglasPeucker(positions, startIndex, maxIndex, tolerance);
      final right = _douglasPeucker(positions, maxIndex, endIndex, tolerance);

      // Combine results (remove duplicate middle point)
      return [...left, ...right.skip(1)];
    } else {
      // Base case: just return endpoints
      return [positions[startIndex], positions[endIndex]];
    }
  }

  /// Calculate perpendicular distance from point to line
  static double _perpendicularDistance(
    double pointLat,
    double pointLng,
    double line1Lat,
    double line1Lng,
    double line2Lat,
    double line2Lng,
  ) {
    // Convert to radians
    final lat1 = line1Lat * pi / 180;
    final lng1 = line1Lng * pi / 180;
    final lat2 = line2Lat * pi / 180;
    final lng2 = line2Lng * pi / 180;
    final latP = pointLat * pi / 180;
    final lngP = pointLng * pi / 180;

    // Earth radius in meters
    const R = 6371000.0;

    // Convert to 3D cartesian coordinates
    final x1 = R * cos(lat1) * cos(lng1);
    final y1 = R * cos(lat1) * sin(lng1);
    final z1 = R * sin(lat1);

    final x2 = R * cos(lat2) * cos(lng2);
    final y2 = R * cos(lat2) * sin(lng2);
    final z2 = R * sin(lat2);

    final xP = R * cos(latP) * cos(lngP);
    final yP = R * cos(latP) * sin(lngP);
    final zP = R * sin(latP);

    // Vector from line1 to line2
    final dx = x2 - x1;
    final dy = y2 - y1;
    final dz = z2 - z1;

    // Vector from line1 to point
    final dxP = xP - x1;
    final dyP = yP - y1;
    final dzP = zP - z1;

    // Cross product
    final crossX = dyP * dz - dzP * dy;
    final crossY = dzP * dx - dxP * dz;
    final crossZ = dxP * dy - dyP * dx;

    // Magnitude of cross product
    final crossMag = sqrt(crossX * crossX + crossY * crossY + crossZ * crossZ);

    // Magnitude of line vector
    final lineMag = sqrt(dx * dx + dy * dy + dz * dz);

    // Perpendicular distance
    return lineMag > 0 ? crossMag / lineMag : 0.0;
  }

  /// Segment route by speed/activity
  /// Returns list of segments, each with consistent activity level
  static List<RouteSegment> segmentByActivity(List<Position> positions) {
    if (positions.isEmpty) return [];

    final segments = <RouteSegment>[];
    List<Position> currentSegment = [positions.first];
    String currentActivity = detectActivity(positions.first.speed);

    for (int i = 1; i < positions.length; i++) {
      final position = positions[i];
      final activity = detectActivity(position.speed);

      // If activity changed, start new segment
      if (activity != currentActivity) {
        segments.add(RouteSegment(
          points: List.from(currentSegment),
          activity: currentActivity,
          startTime: currentSegment.first.timestamp,
          endTime: currentSegment.last.timestamp,
        ));

        currentSegment = [position];
        currentActivity = activity;
      } else {
        currentSegment.add(position);
      }
    }

    // Add last segment
    if (currentSegment.isNotEmpty) {
      segments.add(RouteSegment(
        points: currentSegment,
        activity: currentActivity,
        startTime: currentSegment.first.timestamp,
        endTime: currentSegment.last.timestamp,
      ));
    }

    AppLogger.i('Route segmented into ${segments.length} segments by activity');

    return segments;
  }

  /// Process raw GPS data through full AI pipeline
  /// Returns optimized, cleaned, and segmented route data
  static ProcessedRoute processRoute(List<Position> rawPositions) {
    AppLogger.i('🤖 Starting AI route processing: ${rawPositions.length} raw points');

    // Step 1: Remove outliers
    final cleanedPositions = removeOutliers(rawPositions);

    // Step 2: Simplify path (only if we have many points)
    final simplifiedPositions = cleanedPositions.length > 50
        ? simplifyPath(cleanedPositions)
        : cleanedPositions;

    // Step 3: Segment by activity
    final segments = segmentByActivity(simplifiedPositions);

    // Calculate statistics
    double totalDistance = 0.0;
    for (int i = 1; i < simplifiedPositions.length; i++) {
      totalDistance += Geolocator.distanceBetween(
        simplifiedPositions[i - 1].latitude,
        simplifiedPositions[i - 1].longitude,
        simplifiedPositions[i].latitude,
        simplifiedPositions[i].longitude,
      );
    }

    final duration = simplifiedPositions.last.timestamp
        .difference(simplifiedPositions.first.timestamp);

    AppLogger.i('🤖 AI processing complete: ${simplifiedPositions.length} optimized points, '
        '${segments.length} segments, ${(totalDistance / 1000).toStringAsFixed(2)} km, '
        '${duration.inMinutes} minutes');

    return ProcessedRoute(
      originalPoints: rawPositions,
      processedPoints: simplifiedPositions,
      segments: segments,
      totalDistanceKm: totalDistance / 1000,
      totalDuration: duration,
      compressionRatio: simplifiedPositions.length / rawPositions.length,
    );
  }
}

/// Represents a segment of the route with consistent activity
class RouteSegment {
  final List<Position> points;
  final String activity; // 'stopped', 'slow', 'normal', 'fast', 'highway'
  final DateTime startTime;
  final DateTime endTime;

  RouteSegment({
    required this.points,
    required this.activity,
    required this.startTime,
    required this.endTime,
  });

  Duration get duration => endTime.difference(startTime);

  double get averageSpeed {
    if (points.isEmpty) return 0.0;
    final totalSpeed = points.fold<double>(0.0, (sum, p) => sum + p.speed);
    return totalSpeed / points.length;
  }
}

/// Processed route data with statistics
class ProcessedRoute {
  final List<Position> originalPoints;
  final List<Position> processedPoints;
  final List<RouteSegment> segments;
  final double totalDistanceKm;
  final Duration totalDuration;
  final double compressionRatio;

  ProcessedRoute({
    required this.originalPoints,
    required this.processedPoints,
    required this.segments,
    required this.totalDistanceKm,
    required this.totalDuration,
    required this.compressionRatio,
  });

  int get pointsRemoved => originalPoints.length - processedPoints.length;

  double get compressionPercentage => (1 - compressionRatio) * 100;
}
