class Rider {
  final int id;
  final String username;
  final String name;
  final String? phone;
  final String? email;
  final bool isActive;

  Rider({
    required this.id,
    required this.username,
    required this.name,
    this.phone,
    this.email,
    required this.isActive,
  });

  factory Rider.fromJson(Map<String, dynamic> json) {
    return Rider(
      id: json['id'],
      username: json['username'],
      name: json['name'],
      phone: json['phone'],
      email: json['email'],
      isActive: json['is_active'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'name': name,
      'phone': phone,
      'email': email,
      'is_active': isActive,
    };
  }
}
