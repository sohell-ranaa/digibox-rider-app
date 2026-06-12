import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../theme/app_colors.dart';
import '../providers/duty_provider.dart';
import '../services/storage_service.dart';
import '../services/ai_route_processor.dart';
import '../utils/app_logger.dart';

/// Map screen showing current location and today's route
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  final StorageService _storage = StorageService();

  Position? _currentPosition;
  List<LatLng> _todayRoute = [];
  List<Map<String, dynamic>> _routeSegments = []; // For colored segments
  bool _isLoading = true;
  String? _errorMessage;
  bool _mapReady = false;
  Timer? _realtimeUpdateTimer;

  LatLng _center = const LatLng(23.8103, 90.4125);

  @override
  void initState() {
    super.initState();
    _initializeMap();
    _startRealtimeTracking();
  }

  @override
  void dispose() {
    _realtimeUpdateTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeMap() async {
    await _getCurrentLocation();
    await _loadTodayRoute();
  }

  // Start realtime position tracking
  void _startRealtimeTracking() {
    _realtimeUpdateTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted) {
        _updateCurrentPosition();
      }
    });
  }

  // Update current position in realtime
  Future<void> _updateCurrentPosition() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (mounted) {
        setState(() {
          _currentPosition = position;
        });
      }
    } catch (e) {
      // Silently fail - don't spam user
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        setState(() {
          _errorMessage = 'Location permission required';
          _isLoading = false;
        });
        return;
      }

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _errorMessage = 'Please enable GPS';
          _isLoading = false;
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final newCenter = LatLng(position.latitude, position.longitude);

      setState(() {
        _currentPosition = position;
        _center = newCenter;
        _isLoading = false;
      });

      if (_mapReady) {
        _mapController.move(newCenter, 15.0);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadTodayRoute() async {
    try {
      final locations = await _storage.getTodaysLocations();

      if (locations.isEmpty) {
        setState(() {
          _routeSegments = [];
          _todayRoute = [];
        });
        return;
      }

      AppLogger.i('🗺️ [Map] Loading route: ${locations.length} points');

      // Convert LocationPoints to Positions for AI processing
      final positions = locations.map((loc) => Position(
        latitude: loc.latitude,
        longitude: loc.longitude,
        timestamp: loc.recordedAt,
        accuracy: loc.accuracy ?? 10.0,
        altitude: loc.altitude ?? 0,
        altitudeAccuracy: 0,
        heading: loc.bearing ?? 0,
        headingAccuracy: 0,
        speed: loc.speed ?? 0,
        speedAccuracy: 0,
      )).toList();

      // === AI PROCESSING ===
      // Note: Kalman filtering already applied during collection
      // Here we apply: outlier detection + simplification
      final cleanedPositions = AIRouteProcessor.removeOutliers(positions);
      final simplifiedPositions = cleanedPositions.length > 100
          ? AIRouteProcessor.simplifyPath(cleanedPositions, tolerance: 8.0)
          : cleanedPositions;

      AppLogger.i('🗺️ [Map] AI processed: ${positions.length} → ${simplifiedPositions.length} points');

      // Convert back to location-like objects for segment creation
      final processedLocations = simplifiedPositions.map((pos) {
        return {'latitude': pos.latitude, 'longitude': pos.longitude, 'speed': pos.speed};
      }).toList();

      // Create colored route segments based on speed
      final segments = _createRouteSegments(processedLocations);

      setState(() {
        _routeSegments = segments;
        _todayRoute = simplifiedPositions
            .map((pos) => LatLng(pos.latitude, pos.longitude))
            .toList();
      });

      // Center on latest point
      if (_todayRoute.isNotEmpty && _mapReady) {
        _mapController.move(_todayRoute.last, 15.0);
      }
    } catch (e) {
      AppLogger.e('❌ [Map] Error loading route: $e');
    }
  }

  // Create colored segments based on speed/activity
  List<Map<String, dynamic>> _createRouteSegments(List<dynamic> locations) {
    if (locations.length < 2) return [];

    final segments = <Map<String, dynamic>>[];
    List<LatLng> currentSegmentPoints = [LatLng(locations[0].latitude, locations[0].longitude)];
    Color currentColor = _getSpeedColor(locations[0]);
    bool currentIsStopped = _isStopped(locations[0]);

    for (int i = 1; i < locations.length; i++) {
      final loc = locations[i];
      final color = _getSpeedColor(loc);
      final isStopped = _isStopped(loc);

      // Start new segment if color or state changed
      if (color != currentColor || isStopped != currentIsStopped) {
        if (currentSegmentPoints.length >= 2) {
          segments.add({
            'points': List<LatLng>.from(currentSegmentPoints),
            'color': currentColor,
            'isStopped': currentIsStopped,
          });
        }

        currentSegmentPoints = [LatLng(loc.latitude, loc.longitude)];
        currentColor = color;
        currentIsStopped = isStopped;
      } else {
        currentSegmentPoints.add(LatLng(loc.latitude, loc.longitude));
      }
    }

    // Add last segment
    if (currentSegmentPoints.length >= 2) {
      segments.add({
        'points': currentSegmentPoints,
        'color': currentColor,
        'isStopped': currentIsStopped,
      });
    }

    return segments;
  }

  bool _isStopped(dynamic loc) {
    final speedKmh = (loc.speed ?? 0) * 3.6;
    return speedKmh < 2;
  }

  // VIBRANT COLOR PALETTE for Uber-like visualization
  Color _getSpeedColor(dynamic loc) {
    final speedKmh = (loc.speed ?? 0) * 3.6;
    if (speedKmh < 2) return const Color(0xFFDC2626);    // Bright Red - Stopped
    if (speedKmh < 10) return const Color(0xFFF59E0B);   // Amber - Slow
    if (speedKmh < 30) return const Color(0xFF10B981);   // Emerald - Normal
    if (speedKmh < 60) return const Color(0xFF3B82F6);   // Blue - Fast
    return const Color(0xFF8B5CF6);                       // Purple - Highway
  }

  // Get activity label for legend
  String _getActivityLabel(Color color) {
    if (color == const Color(0xFFDC2626)) return 'Stopped';
    if (color == const Color(0xFFF59E0B)) return 'Slow (<10 km/h)';
    if (color == const Color(0xFF10B981)) return 'Normal (10-30 km/h)';
    if (color == const Color(0xFF3B82F6)) return 'Fast (30-60 km/h)';
    return 'Highway (>60 km/h)';
  }

  Widget _buildLegendItem(Color color, String label, bool dashed) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 4,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.4),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: dashed
              ? CustomPaint(
                  painter: _DashedLinePainter(color),
                )
              : null,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.grey[800],
          ),
        ),
      ],
    );
  }

  // Dashed line painter for legend
  Widget _buildDashedLine(Color color) {
    return CustomPaint(
      size: const Size(20, 4),
      painter: _DashedLinePainter(color),
    );
  }

  // Filter out GPS noise and outliers
  List<dynamic> _filterGPSNoise(List<dynamic> points) {
    if (points.length < 3) return points;

    final filtered = <dynamic>[points[0]]; // Always keep first point

    for (int i = 1; i < points.length - 1; i++) {
      final prev = points[i - 1];
      final current = points[i];

      // Calculate distance from previous point
      final distFromPrev = Geolocator.distanceBetween(
        prev.latitude,
        prev.longitude,
        current.latitude,
        current.longitude,
      );

      // Filter out points that are too close (GPS drift when stopped)
      if (distFromPrev < 3) { // <3 meters
        final speedKmh = (current.speed ?? 0) * 3.6;
        if (speedKmh < 1) continue; // Skip if stopped
      }

      // Filter out impossible jumps (GPS errors)
      if (distFromPrev > 500) { // >500 meters in 30 seconds
        debugPrint('⚠️ [Map] Filtered GPS outlier: ${distFromPrev.toStringAsFixed(1)}m jump');
        continue;
      }

      // Check accuracy - filter poor quality points
      if (current.accuracy != null && current.accuracy > 50) {
        continue; // Skip points with >50m accuracy
      }

      filtered.add(current);
    }

    filtered.add(points[points.length - 1]); // Always keep last point
    return filtered;
  }

  // Simplify path using Douglas-Peucker algorithm
  List<dynamic> _simplifyPath(List<dynamic> points, double tolerance) {
    if (points.length < 3) return points;

    return _douglasPeucker(points, tolerance);
  }

  List<dynamic> _douglasPeucker(List<dynamic> points, double tolerance) {
    if (points.length < 3) return points;

    double maxDistance = 0;
    int maxIndex = 0;

    // Find point with maximum distance from line
    for (int i = 1; i < points.length - 1; i++) {
      final distance = _perpendicularDistance(
        points[i],
        points[0],
        points[points.length - 1],
      );

      if (distance > maxDistance) {
        maxDistance = distance;
        maxIndex = i;
      }
    }

    // If max distance is greater than tolerance, recursively simplify
    if (maxDistance > tolerance) {
      final left = _douglasPeucker(points.sublist(0, maxIndex + 1), tolerance);
      final right = _douglasPeucker(points.sublist(maxIndex), tolerance);

      return [...left.sublist(0, left.length - 1), ...right];
    } else {
      return [points[0], points[points.length - 1]];
    }
  }

  // Calculate perpendicular distance from point to line
  double _perpendicularDistance(dynamic point, dynamic lineStart, dynamic lineEnd) {
    final x = point.latitude;
    final y = point.longitude;
    final x1 = lineStart.latitude;
    final y1 = lineStart.longitude;
    final x2 = lineEnd.latitude;
    final y2 = lineEnd.longitude;

    final A = x - x1;
    final B = y - y1;
    final C = x2 - x1;
    final D = y2 - y1;

    final dot = A * C + B * D;
    final lenSq = C * C + D * D;
    double param = -1;

    if (lenSq != 0) param = dot / lenSq;

    double xx, yy;

    if (param < 0) {
      xx = x1;
      yy = y1;
    } else if (param > 1) {
      xx = x2;
      yy = y2;
    } else {
      xx = x1 + param * C;
      yy = y1 + param * D;
    }

    final dx = x - xx;
    final dy = y - yy;

    return (dx * dx + dy * dy);
  }

  @override
  Widget build(BuildContext context) {
    final dutyProvider = context.watch<DutyProvider>();
    final isOnline = dutyProvider.isOnline;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Live Tracking',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (_currentPosition != null)
            IconButton(
              icon: const Icon(Icons.my_location, color: AppColors.primary),
              tooltip: 'Center on me',
              onPressed: () {
                _mapController.move(
                  LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                  15.0,
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.primary),
            tooltip: 'Refresh',
            onPressed: _initializeMap,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 13.0,
              minZoom: 5.0,
              maxZoom: 18.0,
              onMapReady: () {
                setState(() => _mapReady = true);
                if (_currentPosition != null) {
                  _mapController.move(
                    LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                    15.0,
                  );
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.digibox.rider',
                maxNativeZoom: 19,
              ),

              // Today's route with VIBRANT colored segments + glow effect
              if (_routeSegments.isNotEmpty) ...[
                // Glow layer (wider, semi-transparent)
                PolylineLayer(
                  polylines: _routeSegments.map<Polyline>((segment) {
                    return Polyline(
                      points: segment['points'],
                      strokeWidth: segment['isStopped'] ? 8.0 : 12.0,
                      color: (segment['color'] as Color).withOpacity(0.3),
                    );
                  }).toList(),
                ),
                // Main route layer (sharp, vibrant)
                PolylineLayer(
                  polylines: _routeSegments.map<Polyline>((segment) {
                    return Polyline(
                      points: segment['points'],
                      strokeWidth: segment['isStopped'] ? 4.0 : 6.0,
                      color: segment['color'],
                    );
                  }).toList(),
                ),
              ],

              // Current location marker with heading
              if (_currentPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(
                        _currentPosition!.latitude,
                        _currentPosition!.longitude,
                      ),
                      width: 50,
                      height: 50,
                      child: Transform.rotate(
                        angle: (_currentPosition!.heading ?? 0) * (3.14159 / 180),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Pulse effect
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.primary.withOpacity(0.2),
                              ),
                            ),
                            // Main marker
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 3),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withOpacity(0.6),
                                    blurRadius: 10,
                                    spreadRadius: 3,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.navigation,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // Loading overlay
          if (_isLoading)
            Container(
              color: Colors.white,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),

          // Error message
          if (_errorMessage != null && !_isLoading)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade400,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => setState(() => _errorMessage = null),
                    ),
                  ],
                ),
              ),
            ),

          // Legend and Status Card
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // VIBRANT Route Legend with AI badge
                if (_routeSegments.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.auto_awesome, size: 14, color: Color(0xFF8B5CF6)),
                            const SizedBox(width: 4),
                            Text(
                              'AI-Powered Route',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[700],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          runSpacing: 6,
                          children: [
                            _buildLegendItem(const Color(0xFFDC2626), 'Stopped', true),
                            _buildLegendItem(const Color(0xFFF59E0B), 'Slow', false),
                            _buildLegendItem(const Color(0xFF10B981), 'Normal', false),
                            _buildLegendItem(const Color(0xFF3B82F6), 'Fast', false),
                            _buildLegendItem(const Color(0xFF8B5CF6), 'Highway', false),
                          ],
                        ),
                      ],
                    ),
                  ),

                // Status card
                if (isOnline)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            color: AppColors.success,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Tracking Active',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              if (_currentPosition != null)
                                Text(
                                  'Speed: ${(_currentPosition!.speed * 3.6).toStringAsFixed(1)} km/h',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          '${_todayRoute.length} pts',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Dashed line painter for legend
class _DashedLinePainter extends CustomPainter {
  final Color color;

  _DashedLinePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;

    double startX = 0;
    while (startX < size.width) {
      canvas.drawLine(
        Offset(startX, size.height / 2),
        Offset(startX + 4, size.height / 2),
        paint,
      );
      startX += 6;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
