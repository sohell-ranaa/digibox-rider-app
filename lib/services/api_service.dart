import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../config/api_config.dart';
import '../models/duty_session.dart';
import '../models/location_point.dart';
import '../models/installation_location.dart';
import '../exceptions/app_exceptions.dart';
import 'http_client_service.dart';

class ApiService {
  String? _token;
  late final HttpClientService _httpClient;

  ApiService({HttpClientService? httpClient}) {
    _httpClient = httpClient ?? HttpClientService();
  }

  String? get token => _token;

  void setToken(String token) {
    _token = token;
  }

  void clearToken() {
    _token = null;
  }

  Map<String, String> _getHeaders() {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }

    return headers;
  }

  /// Reset circuit breaker (useful after network recovery)
  void resetCircuitBreaker() {
    _httpClient.resetCircuitBreaker();
  }

  /// Check if circuit breaker is blocking requests
  bool get isCircuitBreakerOpen => _httpClient.isCircuitBreakerOpen;

  // Authentication
  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final response = await _httpClient.post(
        Uri.parse(ApiConfig.login),
        headers: _getHeaders(),
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
        useRetry: false, // Don't retry login attempts
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _token = data['token'];
        return data;
      } else {
        throw AuthException('Login failed', details: response.body);
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException('Login failed', details: e.toString());
    }
  }

  Future<void> logout() async {
    try {
      final response = await _httpClient.post(
        Uri.parse(ApiConfig.logout),
        headers: _getHeaders(),
        useRetry: false,
      );

      if (response.statusCode == 200) {
        clearToken();
      } else {
        throw ApiException('Logout failed', statusCode: response.statusCode);
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Logout failed', details: e.toString());
    }
  }

  Future<void> changePassword(String currentPassword, String newPassword) async {
    try {
      final response = await _httpClient.put(
        Uri.parse(ApiConfig.changePassword),
        headers: _getHeaders(),
        body: jsonEncode({
          'current_password': currentPassword,
          'new_password': newPassword,
          'new_password_confirmation': newPassword,
        }),
      );

      if (response.statusCode != 200) {
        final data = jsonDecode(response.body);
        throw ApiException(
          data['message'] ?? 'Failed to change password',
          statusCode: response.statusCode,
          endpoint: ApiConfig.changePassword,
          details: response.body,
        );
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Failed to change password', details: e.toString());
    }
  }

  // Duty Management
  Future<DutySession> startDuty() async {
    try {
      debugPrint('✅ [ApiService] Calling POST ${ApiConfig.dutyStart}');
      debugPrint('✅ [ApiService] Token: ${_token != null ? "Present (${_token!.substring(0, 10)}...)" : "MISSING"}');

      final response = await _httpClient.post(
        Uri.parse(ApiConfig.dutyStart),
        headers: _getHeaders(),
      );

      debugPrint('✅ [ApiService] Response status: ${response.statusCode}');
      debugPrint('✅ [ApiService] Response body: ${response.body}');

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        debugPrint('✅ [ApiService] Duty session created successfully');
        return DutySession.fromJson(data['duty_session']);
      } else {
        debugPrint('❌ [ApiService] Start duty failed with status ${response.statusCode}');
        throw ApiException(
          'Failed to start duty',
          statusCode: response.statusCode,
          endpoint: ApiConfig.dutyStart,
          details: response.body,
        );
      }
    } catch (e) {
      debugPrint('❌ [ApiService] Exception in startDuty: $e');
      if (e is ApiException) rethrow;
      throw ApiException('Failed to start duty', details: e.toString());
    }
  }

  Future<DutySession> stopDuty() async {
    try {
      debugPrint('🛑 [ApiService] Calling POST ${ApiConfig.dutyStop}');
      debugPrint('🛑 [ApiService] Token: ${_token != null ? "Present (${_token!.substring(0, 10)}...)" : "MISSING"}');

      final response = await _httpClient.post(
        Uri.parse(ApiConfig.dutyStop),
        headers: _getHeaders(),
      );

      debugPrint('🛑 [ApiService] Response status: ${response.statusCode}');
      debugPrint('🛑 [ApiService] Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return DutySession.fromJson(data['duty_session']);
      } else {
        throw ApiException(
          'Failed to stop duty',
          statusCode: response.statusCode,
          endpoint: ApiConfig.dutyStop,
          details: response.body,
        );
      }
    } catch (e) {
      debugPrint('🛑 [ApiService] Exception: $e');
      if (e is ApiException) rethrow;
      throw ApiException('Failed to stop duty', details: e.toString());
    }
  }

  Future<DutySession?> getCurrentDuty() async {
    try {
      final response = await _httpClient.get(
        Uri.parse(ApiConfig.dutyCurrent),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['duty_session'] != null) {
          return DutySession.fromJson(data['duty_session']);
        }
        return null;
      } else {
        throw ApiException(
          'Failed to get current duty',
          statusCode: response.statusCode,
          endpoint: ApiConfig.dutyCurrent,
        );
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Failed to get current duty', details: e.toString());
    }
  }

  Future<List<DutySession>> getDutyHistory({DateTime? from, DateTime? to}) async {
    try {
      var url = ApiConfig.dutyHistory;
      final queryParams = <String, String>{};

      if (from != null) {
        queryParams['from'] = from.toIso8601String().split('T')[0];
      }

      if (to != null) {
        queryParams['to'] = to.toIso8601String().split('T')[0];
      }

      if (queryParams.isNotEmpty) {
        url += '?${Uri(queryParameters: queryParams).query}';
      }

      final response = await _httpClient.get(
        Uri.parse(url),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final sessions = (data['sessions'] as List)
            .map((json) => DutySession.fromJson(json))
            .toList();
        return sessions;
      } else {
        throw ApiException(
          'Failed to get duty history',
          statusCode: response.statusCode,
          endpoint: ApiConfig.dutyHistory,
        );
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Failed to get duty history', details: e.toString());
    }
  }

  // Location Recording
  Future<void> recordLocation(LocationPoint location) async {
    try {
      final response = await _httpClient.post(
        Uri.parse(ApiConfig.locationRecord),
        headers: _getHeaders(),
        body: jsonEncode(location.toJson()),
      );

      if (response.statusCode != 201) {
        throw ApiException(
          'Failed to record location',
          statusCode: response.statusCode,
          endpoint: ApiConfig.locationRecord,
        );
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Failed to record location', details: e.toString());
    }
  }

  // REAL-TIME STREAMING: Send single location immediately (non-blocking)
  Future<void> streamLocation(LocationPoint location) async {
    try {
      final response = await _httpClient.post(
        Uri.parse(ApiConfig.locationStream),
        headers: _getHeaders(),
        body: jsonEncode(location.toJson()),
      ).timeout(const Duration(seconds: 3)); // Quick timeout - don't block

      if (response.statusCode != 200 && response.statusCode != 201) {
        debugPrint('⚠️ [Stream] Failed: ${response.statusCode}');
      }
    } catch (e) {
      // Fail silently - batch upload will catch it
      debugPrint('⚠️ [Stream] Error: $e');
    }
  }

  Future<void> bulkRecordLocations(List<LocationPoint> locations) async {
    try {
      debugPrint('📤 [API] Bulk upload: ${locations.length} locations to ${ApiConfig.locationBulk}');

      final locationsJson = locations.map((l) => l.toJson()).toList();
      final requestBody = jsonEncode({'locations': locationsJson});

      debugPrint('📤 [API] Request size: ${requestBody.length} bytes');
      debugPrint('📤 [API] First location: ${locationsJson.isNotEmpty ? locationsJson[0] : "none"}');

      final response = await _httpClient.post(
        Uri.parse(ApiConfig.locationBulk),
        headers: _getHeaders(),
        body: requestBody,
      );

      debugPrint('📥 [API] Response status: ${response.statusCode}');
      debugPrint('📥 [API] Response body: ${response.body}');

      if (response.statusCode != 201) {
        debugPrint('❌ [API] Bulk upload failed: ${response.statusCode} - ${response.body}');
        throw ApiException(
          'Failed to bulk record locations: ${response.body}',
          statusCode: response.statusCode,
          endpoint: ApiConfig.locationBulk,
        );
      }

      debugPrint('✅ [API] Bulk upload successful: ${locations.length} locations');
    } catch (e) {
      debugPrint('❌ [API] Exception during bulk upload: $e');
      if (e is ApiException) rethrow;
      throw ApiException('Failed to bulk record locations', details: e.toString());
    }
  }

  // Installation Locations
  Future<List<InstallationLocation>> getInstallations() async {
    try {
      final response = await _httpClient.get(
        Uri.parse(ApiConfig.installations),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final installations = (data['installations'] as List)
            .map((json) => InstallationLocation.fromJson(json))
            .toList();
        return installations;
      } else {
        throw ApiException(
          'Failed to get installations',
          statusCode: response.statusCode,
          endpoint: ApiConfig.installations,
        );
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Failed to get installations', details: e.toString());
    }
  }

  // System Events
  Future<void> recordEvent(String eventType, DateTime occurredAt, int? dutySessionId) async {
    try {
      final response = await _httpClient.post(
        Uri.parse(ApiConfig.eventsRecord),
        headers: _getHeaders(),
        body: jsonEncode({
          'event_type': eventType,
          'occurred_at': occurredAt.toIso8601String(),
          'duty_session_id': dutySessionId,
        }),
      );

      if (response.statusCode != 201) {
        throw ApiException(
          'Failed to record event',
          statusCode: response.statusCode,
          endpoint: ApiConfig.eventsRecord,
        );
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Failed to record event', details: e.toString());
    }
  }

  // Reports
  Future<Map<String, dynamic>> getDailyReport(DateTime date) async {
    try {
      final dateStr = date.toIso8601String().split('T')[0];
      final response = await _httpClient.get(
        Uri.parse('${ApiConfig.reportsDaily}?date=$dateStr'),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw ApiException(
          'Failed to get daily report',
          statusCode: response.statusCode,
          endpoint: ApiConfig.reportsDaily,
        );
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Failed to get daily report', details: e.toString());
    }
  }

  /// Close the HTTP client
  void dispose() {
    _httpClient.close();
  }
}
