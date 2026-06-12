import 'dart:async';
import 'package:retry/retry.dart';
import '../exceptions/app_exceptions.dart';
import 'logger.dart';

/// Retry policy for network requests with exponential backoff
class RetryPolicy {
  /// Default retry configuration
  static const RetryOptions defaultRetry = RetryOptions(
    maxAttempts: 3,
    delayFactor: Duration(seconds: 1),
    randomizationFactor: 0.25,
    maxDelay: Duration(seconds: 10),
  );

  /// Aggressive retry for critical operations
  static const RetryOptions aggressiveRetry = RetryOptions(
    maxAttempts: 5,
    delayFactor: Duration(milliseconds: 500),
    randomizationFactor: 0.25,
    maxDelay: Duration(seconds: 5),
  );

  /// Single attempt (no retry)
  static const RetryOptions noRetry = RetryOptions(
    maxAttempts: 1,
  );

  /// Execute a function with retry logic
  ///
  /// [fn] - The function to execute
  /// [retryOptions] - Retry configuration (defaults to defaultRetry)
  /// [retryIf] - Optional predicate to determine if retry should happen
  static Future<T> execute<T>({
    required Future<T> Function() fn,
    RetryOptions? retryOptions,
    bool Function(Exception)? retryIf,
  }) async {
    final options = retryOptions ?? defaultRetry;
    int attempt = 0;

    return await options.retry(
      () async {
        attempt++;
        try {
          AppLogger.d('Retry attempt $attempt/${options.maxAttempts}');
          return await fn();
        } catch (e) {
          if (e is Exception) {
            AppLogger.w('Attempt $attempt failed: $e');

            // Check if we should retry this exception
            if (retryIf != null && !retryIf(e)) {
              AppLogger.e('Exception not retryable, throwing immediately');
              rethrow;
            }
          }
          rethrow;
        }
      },
      retryIf: (e) {
        // Default retry conditions
        if (retryIf != null) {
          return retryIf(e);
        }

        // Retry on network errors, timeouts, and temporary server errors
        if (e is NetworkException) return true;
        if (e is TimeoutException) return true;
        if (e is ApiException) {
          // Retry on 5xx server errors and 429 (too many requests)
          if (e.statusCode != null) {
            return e.statusCode! >= 500 || e.statusCode == 429;
          }
        }

        return false;
      },
    );
  }

  /// Execute with default retry policy
  static Future<T> withDefaultRetry<T>(Future<T> Function() fn) {
    return execute(fn: fn, retryOptions: defaultRetry);
  }

  /// Execute with aggressive retry policy
  static Future<T> withAggressiveRetry<T>(Future<T> Function() fn) {
    return execute(fn: fn, retryOptions: aggressiveRetry);
  }

  /// Execute without retry
  static Future<T> withoutRetry<T>(Future<T> Function() fn) {
    return execute(fn: fn, retryOptions: noRetry);
  }

  /// Custom retry with specific conditions
  static Future<T> withCustomRetry<T>({
    required Future<T> Function() fn,
    required int maxAttempts,
    required Duration delayFactor,
    bool Function(Exception)? retryIf,
  }) {
    return execute(
      fn: fn,
      retryOptions: RetryOptions(
        maxAttempts: maxAttempts,
        delayFactor: delayFactor,
      ),
      retryIf: retryIf,
    );
  }
}

/// Circuit breaker pattern to prevent cascading failures
class CircuitBreaker {
  final int failureThreshold;
  final Duration resetTimeout;

  int _failureCount = 0;
  DateTime? _lastFailureTime;
  bool _isOpen = false;

  CircuitBreaker({
    this.failureThreshold = 5,
    this.resetTimeout = const Duration(minutes: 1),
  });

  /// Check if circuit is open (blocking requests)
  bool get isOpen => _isOpen;

  /// Execute a function with circuit breaker protection
  Future<T> execute<T>(Future<T> Function() fn) async {
    // Check if circuit should be reset
    if (_isOpen && _lastFailureTime != null) {
      if (DateTime.now().difference(_lastFailureTime!) > resetTimeout) {
        AppLogger.i('Circuit breaker reset after timeout');
        _reset();
      }
    }

    // Block if circuit is open
    if (_isOpen) {
      AppLogger.e('Circuit breaker is OPEN, request blocked');
      throw NetworkException(
        'Service temporarily unavailable',
        details: 'Circuit breaker is open due to repeated failures',
      );
    }

    try {
      final result = await fn();
      _onSuccess();
      return result;
    } catch (e) {
      _onFailure();
      rethrow;
    }
  }

  void _onSuccess() {
    if (_failureCount > 0) {
      AppLogger.i('Circuit breaker: success, resetting failure count');
      _failureCount = 0;
    }
  }

  void _onFailure() {
    _failureCount++;
    _lastFailureTime = DateTime.now();

    AppLogger.w('Circuit breaker: failure $_failureCount/$failureThreshold');

    if (_failureCount >= failureThreshold) {
      _isOpen = true;
      AppLogger.e('Circuit breaker OPENED after $failureThreshold failures');
    }
  }

  void _reset() {
    _failureCount = 0;
    _isOpen = false;
    _lastFailureTime = null;
  }

  /// Manually reset the circuit breaker
  void reset() {
    AppLogger.i('Circuit breaker manually reset');
    _reset();
  }
}
