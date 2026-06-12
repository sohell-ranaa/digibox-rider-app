import 'package:logger/logger.dart';

/// Global logger instance with custom configuration
class AppLogger {
  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 2,
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
    level: Level.debug, // Change to Level.info for production
  );

  /// Log debug message
  static void debug(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.d(message, error: error, stackTrace: stackTrace);
  }

  /// Log debug message (alias)
  static void d(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.d(message, error: error, stackTrace: stackTrace);
  }

  /// Log info message
  static void info(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.i(message, error: error, stackTrace: stackTrace);
  }

  /// Log info message (alias)
  static void i(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.i(message, error: error, stackTrace: stackTrace);
  }

  /// Log warning message
  static void warning(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.w(message, error: error, stackTrace: stackTrace);
  }

  /// Log warning message (alias)
  static void w(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.w(message, error: error, stackTrace: stackTrace);
  }

  /// Log error message
  static void error(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.e(message, error: error, stackTrace: stackTrace);
  }

  /// Log error message (alias)
  static void e(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.e(message, error: error, stackTrace: stackTrace);
  }

  /// Log fatal/critical error
  static void fatal(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.f(message, error: error, stackTrace: stackTrace);
  }

  /// Log fatal/critical error (alias)
  static void f(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.f(message, error: error, stackTrace: stackTrace);
  }

  /// Log API call
  static void apiCall(String method, String endpoint, {Map<String, dynamic>? data}) {
    _logger.d('API $method $endpoint', error: data);
  }

  /// Log API response
  static void apiResponse(String endpoint, int statusCode, {dynamic data}) {
    _logger.i('API Response: $endpoint [$statusCode]', error: data);
  }

  /// Log location tracking event
  static void location(String message, {double? lat, double? lng}) {
    if (lat != null && lng != null) {
      _logger.d('$message (Lat: $lat, Lng: $lng)');
    } else {
      _logger.d(message);
    }
  }

  /// Log duty session event
  static void duty(String message, {String? sessionId}) {
    _logger.i('Duty: $message${sessionId != null ? ' [Session: $sessionId]' : ''}');
  }

  /// Log sync event
  static void sync(String message, {int? count}) {
    _logger.i('Sync: $message${count != null ? ' ($count items)' : ''}');
  }

  /// Log geofence event
  static void geofence(String message, {String? installationName}) {
    _logger.i('Geofence: $message${installationName != null ? ' [$installationName]' : ''}');
  }
}
