class DutySession {
  final int id;
  final int riderId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int? totalDurationMinutes;
  final double totalDistanceKm;
  final int totalStops;
  final String status;

  DutySession({
    required this.id,
    required this.riderId,
    required this.startedAt,
    this.endedAt,
    this.totalDurationMinutes,
    required this.totalDistanceKm,
    required this.totalStops,
    required this.status,
  });

  factory DutySession.fromJson(Map<String, dynamic> json) {
    return DutySession(
      id: json['id'],
      riderId: json['rider_id'],
      startedAt: DateTime.parse(json['started_at']),
      endedAt: json['ended_at'] != null ? DateTime.parse(json['ended_at']) : null,
      totalDurationMinutes: json['total_duration_minutes'],
      totalDistanceKm: double.tryParse(json['total_distance_km']?.toString() ?? '0') ?? 0.0,
      totalStops: json['total_stops'] ?? 0,
      status: json['status'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'rider_id': riderId,
      'started_at': startedAt.toIso8601String(),
      'ended_at': endedAt?.toIso8601String(),
      'total_duration_minutes': totalDurationMinutes,
      'total_distance_km': totalDistanceKm,
      'total_stops': totalStops,
      'status': status,
    };
  }

  bool get isActive => status == 'active';

  // Create a copy with optional parameter overrides
  DutySession copyWith({
    int? id,
    int? riderId,
    DateTime? startedAt,
    DateTime? endedAt,
    int? totalDurationMinutes,
    double? totalDistanceKm,
    int? totalStops,
    String? status,
  }) {
    return DutySession(
      id: id ?? this.id,
      riderId: riderId ?? this.riderId,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      totalDurationMinutes: totalDurationMinutes ?? this.totalDurationMinutes,
      totalDistanceKm: totalDistanceKm ?? this.totalDistanceKm,
      totalStops: totalStops ?? this.totalStops,
      status: status ?? this.status,
    );
  }
}
