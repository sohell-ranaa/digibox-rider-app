/// Custom exception classes for structured error handling
library;

/// Base exception class
class AppException implements Exception {
  final String message;
  final String? details;

  AppException(this.message, {this.details});

  @override
  String toString() => details != null ? '$message: $details' : message;
}

/// Network-related exceptions
class NetworkException extends AppException {
  NetworkException(super.message, {super.details});
}

/// API-related exceptions
class ApiException extends AppException {
  final int? statusCode;
  final String? endpoint;

  ApiException(
    super.message, {
    this.statusCode,
    this.endpoint,
    super.details,
  });

  @override
  String toString() {
    final buffer = StringBuffer(message);
    if (statusCode != null) buffer.write(' (Status: $statusCode)');
    if (endpoint != null) buffer.write(' [Endpoint: $endpoint]');
    if (details != null) buffer.write(': $details');
    return buffer.toString();
  }
}

/// Authentication exceptions
class AuthException extends AppException {
  AuthException(super.message, {super.details});
}

/// Storage/Database exceptions
class StorageException extends AppException {
  StorageException(super.message, {super.details});
}

/// Location/GPS exceptions
class LocationException extends AppException {
  LocationException(super.message, {super.details});
}

/// Validation exceptions
class ValidationException extends AppException {
  final Map<String, String>? fieldErrors;

  ValidationException(super.message, {this.fieldErrors, super.details});

  @override
  String toString() {
    if (fieldErrors != null && fieldErrors!.isNotEmpty) {
      return '$message\nErrors: ${fieldErrors!.entries.map((e) => '${e.key}: ${e.value}').join(', ')}';
    }
    return super.toString();
  }
}

/// Timeout exceptions
class TimeoutException extends AppException {
  final Duration timeout;

  TimeoutException(super.message, this.timeout, {super.details});

  @override
  String toString() => '$message (Timeout: ${timeout.inSeconds}s)';
}

/// Geofence/Visit detection exceptions
class GeofenceException extends AppException {
  GeofenceException(super.message, {super.details});
}

/// Offline/Sync exceptions
class SyncException extends AppException {
  final int? pendingCount;

  SyncException(super.message, {this.pendingCount, super.details});

  @override
  String toString() {
    if (pendingCount != null) {
      return '$message (Pending items: $pendingCount)';
    }
    return super.toString();
  }
}
