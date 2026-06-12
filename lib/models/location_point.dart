class LocationPoint {
  final int? id;
  final int? riderId;
  final int dutySessionId;
  final double latitude;
  final double longitude;
  final double? accuracy;
  final double? speed;
  final double? bearing;
  final double? altitude;
  final DateTime recordedAt;
  final bool isSynced;

  LocationPoint({
    this.id,
    this.riderId,
    required this.dutySessionId,
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.speed,
    this.bearing,
    this.altitude,
    required this.recordedAt,
    this.isSynced = false,
  });

  factory LocationPoint.fromJson(Map<String, dynamic> json) {
    return LocationPoint(
      id: json['id'],
      riderId: json['rider_id'],
      dutySessionId: json['duty_session_id'],
      latitude: double.parse(json['latitude'].toString()),
      longitude: double.parse(json['longitude'].toString()),
      accuracy: json['accuracy'] != null ? double.tryParse(json['accuracy'].toString()) : null,
      speed: json['speed'] != null ? double.tryParse(json['speed'].toString()) : null,
      bearing: json['bearing'] != null ? double.tryParse(json['bearing'].toString()) : null,
      altitude: json['altitude'] != null ? double.tryParse(json['altitude'].toString()) : null,
      recordedAt: DateTime.parse(json['recorded_at']),
      isSynced: json['is_synced'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'duty_session_id': dutySessionId,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'speed': speed,
      'bearing': bearing,
      'altitude': altitude,
      'recorded_at': recordedAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toLocalDb() {
    return {
      'id': id,
      'rider_id': riderId,
      'duty_session_id': dutySessionId,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'speed': speed,
      'bearing': bearing,
      'altitude': altitude,
      'recorded_at': recordedAt.toIso8601String(),
      'is_synced': isSynced ? 1 : 0,
    };
  }

  factory LocationPoint.fromLocalDb(Map<String, dynamic> map) {
    return LocationPoint(
      id: map['id'],
      riderId: map['rider_id'],
      dutySessionId: map['duty_session_id'],
      latitude: map['latitude'],
      longitude: map['longitude'],
      accuracy: map['accuracy'],
      speed: map['speed'],
      bearing: map['bearing'],
      altitude: map['altitude'],
      recordedAt: DateTime.parse(map['recorded_at']),
      isSynced: map['is_synced'] == 1,
    );
  }
}
