class InstallationLocation {
  final int id;
  final String name;
  final String? address;
  final double latitude;
  final double longitude;
  final int geofenceRadiusMeters;
  final bool isActive;

  InstallationLocation({
    required this.id,
    required this.name,
    this.address,
    required this.latitude,
    required this.longitude,
    required this.geofenceRadiusMeters,
    required this.isActive,
  });

  factory InstallationLocation.fromJson(Map<String, dynamic> json) {
    return InstallationLocation(
      id: json['id'],
      name: json['name'],
      address: json['address'],
      latitude: double.parse(json['latitude'].toString()),
      longitude: double.parse(json['longitude'].toString()),
      geofenceRadiusMeters: json['geofence_radius_meters'] ?? 100,
      isActive: json['is_active'] ?? true,
    );
  }
}
