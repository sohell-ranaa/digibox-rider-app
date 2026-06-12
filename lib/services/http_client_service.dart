import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../exceptions/app_exceptions.dart';
import '../utils/logger.dart';
import '../utils/retry_policy.dart';
import '../config/api_config.dart';

/// HTTP client service with timeout, retry, and circuit breaker
class HttpClientService {
  final Duration timeout;
  final CircuitBreaker _circuitBreaker;
  final http.Client _client;

  HttpClientService({
    Duration? timeout,
    CircuitBreaker? circuitBreaker,
    http.Client? client,
  })  : timeout = timeout ?? ApiConfig.config.connectionTimeout,
        _circuitBreaker = circuitBreaker ?? CircuitBreaker(),
        _client = client ?? http.Client();

  /// GET request with retry and timeout
  Future<http.Response> get(
    Uri uri, {
    Map<String, String>? headers,
    bool useRetry = true,
  }) async {
    AppLogger.apiCall('GET', uri.toString());

    return await _executeWithProtection(
      () => _client.get(uri, headers: headers).timeout(
            timeout,
            onTimeout: () => throw TimeoutException(
              'GET request timed out after ${timeout.inSeconds}s: ${uri.toString()}',
              timeout,
            ),
          ),
      useRetry: useRetry,
    );
  }

  /// POST request with retry and timeout
  Future<http.Response> post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    bool useRetry = true,
  }) async {
    final bodyData = body is Map<String, dynamic> ? body : null;
    AppLogger.apiCall('POST', uri.toString(), data: bodyData);

    return await _executeWithProtection(
      () => _client
          .post(
            uri,
            headers: headers,
            body: body,
            encoding: encoding,
          )
          .timeout(
            timeout,
            onTimeout: () => throw TimeoutException(
              'POST request timed out after ${timeout.inSeconds}s: ${uri.toString()}',
              timeout,
            ),
          ),
      useRetry: useRetry,
    );
  }

  /// PUT request with retry and timeout
  Future<http.Response> put(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    bool useRetry = true,
  }) async {
    final bodyData = body is Map<String, dynamic> ? body : null;
    AppLogger.apiCall('PUT', uri.toString(), data: bodyData);

    return await _executeWithProtection(
      () => _client
          .put(
            uri,
            headers: headers,
            body: body,
            encoding: encoding,
          )
          .timeout(
            timeout,
            onTimeout: () => throw TimeoutException(
              'PUT request timed out after ${timeout.inSeconds}s: ${uri.toString()}',
              timeout,
            ),
          ),
      useRetry: useRetry,
    );
  }

  /// DELETE request with retry and timeout
  Future<http.Response> delete(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    bool useRetry = true,
  }) async {
    AppLogger.apiCall('DELETE', uri.toString());

    return await _executeWithProtection(
      () => _client
          .delete(
            uri,
            headers: headers,
            body: body,
            encoding: encoding,
          )
          .timeout(
            timeout,
            onTimeout: () => throw TimeoutException(
              'DELETE request timed out after ${timeout.inSeconds}s: ${uri.toString()}',
              timeout,
            ),
          ),
      useRetry: useRetry,
    );
  }

  /// Execute request with circuit breaker and retry protection
  Future<http.Response> _executeWithProtection(
    Future<http.Response> Function() request, {
    required bool useRetry,
  }) async {
    try {
      // Wrap in circuit breaker
      return await _circuitBreaker.execute(() async {
        // Wrap in retry logic if enabled
        if (useRetry) {
          return await RetryPolicy.execute(
            fn: request,
          );
        } else {
          return await request();
        }
      });
    } on http.ClientException catch (e) {
      AppLogger.e('HTTP Client Exception: $e');
      throw NetworkException(
        'Network request failed',
        details: e.message,
      );
    } on TimeoutException catch (e) {
      AppLogger.e('Request timeout: $e');
      rethrow;
    } catch (e) {
      AppLogger.e('Unexpected error in HTTP request: $e');
      throw NetworkException(
        'Unexpected network error',
        details: e.toString(),
      );
    }
  }

  /// Process response and handle errors
  T processResponse<T>(
    http.Response response, {
    required T Function(Map<String, dynamic>) fromJson,
    String? endpoint,
  }) {
    AppLogger.d('Response status: ${response.statusCode}');

    if (response.statusCode >= 200 && response.statusCode < 300) {
      try {
        final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
        return fromJson(jsonData);
      } catch (e) {
        AppLogger.e('JSON parsing error: $e');
        throw ApiException(
          'Invalid response format',
          statusCode: response.statusCode,
          endpoint: endpoint,
          details: e.toString(),
        );
      }
    } else {
      _handleErrorResponse(response, endpoint);
    }

    // This should never be reached due to _handleErrorResponse throwing
    throw ApiException(
      'Unknown error',
      statusCode: response.statusCode,
      endpoint: endpoint,
    );
  }

  /// Process response for list data
  List<T> processListResponse<T>(
    http.Response response, {
    required T Function(Map<String, dynamic>) fromJson,
    String? endpoint,
  }) {
    AppLogger.d('Response status: ${response.statusCode}');

    if (response.statusCode >= 200 && response.statusCode < 300) {
      try {
        final jsonData = jsonDecode(response.body);
        if (jsonData is List) {
          return jsonData
              .cast<Map<String, dynamic>>()
              .map((item) => fromJson(item))
              .toList();
        } else if (jsonData is Map<String, dynamic> && jsonData.containsKey('data')) {
          final data = jsonData['data'];
          if (data is List) {
            return data
                .cast<Map<String, dynamic>>()
                .map((item) => fromJson(item))
                .toList();
          }
        }
        throw ApiException(
          'Invalid list response format',
          statusCode: response.statusCode,
          endpoint: endpoint,
        );
      } catch (e) {
        AppLogger.e('JSON parsing error: $e');
        throw ApiException(
          'Invalid response format',
          statusCode: response.statusCode,
          endpoint: endpoint,
          details: e.toString(),
        );
      }
    } else {
      _handleErrorResponse(response, endpoint);
    }

    throw ApiException(
      'Unknown error',
      statusCode: response.statusCode,
      endpoint: endpoint,
    );
  }

  /// Handle error responses
  void _handleErrorResponse(http.Response response, String? endpoint) {
    final statusCode = response.statusCode;
    String message;
    String? details;

    try {
      final errorData = jsonDecode(response.body);
      if (errorData is Map<String, dynamic>) {
        message = errorData['message'] ?? errorData['error'] ?? 'Request failed';
        details = errorData['details']?.toString();
      } else {
        message = 'Request failed with status $statusCode';
        details = response.body;
      }
    } catch (e) {
      message = 'Request failed with status $statusCode';
      details = response.body;
    }

    AppLogger.e('API Error: $statusCode - $message');

    // Handle specific status codes
    if (statusCode == 401 || statusCode == 403) {
      throw AuthException(message, details: details);
    } else if (statusCode == 404) {
      throw ApiException(
        'Resource not found',
        statusCode: statusCode,
        endpoint: endpoint,
        details: details,
      );
    } else if (statusCode == 422) {
      throw ValidationException(message, details: details);
    } else if (statusCode >= 500) {
      throw ApiException(
        'Server error',
        statusCode: statusCode,
        endpoint: endpoint,
        details: details,
      );
    } else {
      throw ApiException(
        message,
        statusCode: statusCode,
        endpoint: endpoint,
        details: details,
      );
    }
  }

  /// Reset the circuit breaker
  void resetCircuitBreaker() {
    _circuitBreaker.reset();
  }

  /// Check if circuit breaker is open
  bool get isCircuitBreakerOpen => _circuitBreaker.isOpen;

  /// Close the HTTP client
  void close() {
    _client.close();
  }
}
