import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_constants.dart';
import '../models/rider.dart';
import '../services/api_service.dart';

class AuthProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  Rider? _rider;
  String? _token;
  bool _isLoggedIn = false;
  bool _isLoading = false;

  Rider? get rider => _rider;
  bool get isLoggedIn => _isLoggedIn;
  bool get isLoading => _isLoading;
  ApiService get apiService => _apiService;

  // Initialize - check if user is already logged in
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _isLoggedIn = prefs.getBool(AppConstants.keyIsLoggedIn) ?? false;
    _token = prefs.getString(AppConstants.keyAuthToken);

    if (_isLoggedIn && _token != null) {
      _apiService.setToken(_token!);
      final riderId = prefs.getInt(AppConstants.keyRiderId);
      final riderName = prefs.getString(AppConstants.keyRiderName);

      if (riderId != null && riderName != null) {
        _rider = Rider(
          id: riderId,
          username: '',
          name: riderName,
          isActive: true,
        );
      }
    }

    notifyListeners();
  }

  // Login
  Future<bool> login(String username, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _apiService.login(username, password);
      _token = response['token'];
      _rider = Rider.fromJson(response['rider']);
      _isLoggedIn = true;

      // Save to local storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.keyAuthToken, _token!);
      await prefs.setInt(AppConstants.keyRiderId, _rider!.id);
      await prefs.setString(AppConstants.keyRiderName, _rider!.name);
      await prefs.setBool(AppConstants.keyIsLoggedIn, true);

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      print('Login error: $e');
      return false;
    }
  }

  // Logout
  Future<void> logout() async {
    try {
      await _apiService.logout();
    } catch (e) {
      print('Logout error: $e');
    }

    // Clear local storage
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    _rider = null;
    _token = null;
    _isLoggedIn = false;
    _apiService.clearToken();

    notifyListeners();
  }

  // Change Password
  Future<void> changePassword(String currentPassword, String newPassword) async {
    _isLoading = true;
    notifyListeners();

    try {
      await _apiService.changePassword(currentPassword, newPassword);
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }
}
