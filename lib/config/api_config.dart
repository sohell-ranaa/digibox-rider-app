/// Environment configuration
enum Environment {
  development,
  staging,
  production,
}

class ApiConfig {
  // Current environment (change this to switch environments)
  static const Environment currentEnvironment = Environment.production;

  // Environment-specific configurations
  static const Map<Environment, EnvironmentConfig> _envConfigs = {
    Environment.development: EnvironmentConfig(
      baseUrl: 'http://172.16.0.89:7999/api',
      enableLogging: true,
      enableCertificatePinning: false,
      connectionTimeout: Duration(seconds: 30),
      receiveTimeout: Duration(seconds: 30),
    ),
    Environment.staging: EnvironmentConfig(
      baseUrl: 'https://staging-api.digibox.com/api',
      enableLogging: true,
      enableCertificatePinning: true,
      connectionTimeout: Duration(seconds: 30),
      receiveTimeout: Duration(seconds: 30),
    ),
    Environment.production: EnvironmentConfig(
      baseUrl: 'https://tracking-rider.digibox.com.bd/api',
      enableLogging: false,
      enableCertificatePinning: false,
      connectionTimeout: Duration(seconds: 30),
      receiveTimeout: Duration(seconds: 30),
    ),
  };

  // Get current environment configuration
  static EnvironmentConfig get config => _envConfigs[currentEnvironment]!;

  // Base URL for current environment
  static String get baseUrl => config.baseUrl;

  // Auth endpoints
  static String get login => '$baseUrl/auth/login';
  static String get logout => '$baseUrl/auth/logout';
  static String get me => '$baseUrl/auth/me';
  static String get changePassword => '$baseUrl/auth/change-password';

  // Duty endpoints
  static String get dutyStart => '$baseUrl/duty/start';
  static String get dutyStop => '$baseUrl/duty/stop';
  static String get dutyCurrent => '$baseUrl/duty/current';
  static String get dutyHistory => '$baseUrl/duty/history';

  // Location endpoints
  static String get locationRecord => '$baseUrl/locations/record';
  static String get locationBulk => '$baseUrl/locations/bulk';
  static String get locationStream => '$baseUrl/locations/stream'; // Real-time streaming
  static String get installations => '$baseUrl/installations';

  // Events endpoints
  static String get eventsRecord => '$baseUrl/events/record';

  // Reports endpoints
  static String get reportsDaily => '$baseUrl/reports/daily';

  // FCM token endpoint (DISABLED - backend not implemented)
  // static String get fcmToken => '$baseUrl/fcm/token';

  // Check if HTTPS is enabled
  static bool get isHttps => baseUrl.startsWith('https');

  // Get environment name
  static String get environmentName {
    switch (currentEnvironment) {
      case Environment.development:
        return 'Development';
      case Environment.staging:
        return 'Staging';
      case Environment.production:
        return 'Production';
    }
  }
}

/// Environment-specific configuration
class EnvironmentConfig {
  final String baseUrl;
  final bool enableLogging;
  final bool enableCertificatePinning;
  final Duration connectionTimeout;
  final Duration receiveTimeout;

  const EnvironmentConfig({
    required this.baseUrl,
    required this.enableLogging,
    required this.enableCertificatePinning,
    required this.connectionTimeout,
    required this.receiveTimeout,
  });
}
