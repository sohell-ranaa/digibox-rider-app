import 'package:flutter/material.dart';

/// App color palette - centralized color definitions (Professional Blue/Grey Material Design)
class AppColors {
  // Primary brand colors (Material Blue 700 - Professional)
  static const Color primary = Color(0xFF1976D2);  // Material Blue 700
  static const Color primaryDark = Color(0xFF1565C0);  // Material Blue 800
  static const Color primaryLight = Color(0xFF42A5F5);  // Material Blue 400
  static const Color primaryVeryLight = Color(0xFFE3F2FD);  // Material Blue 50

  // Secondary colors (Blue Grey palette)
  static const Color secondary = Color(0xFF607D8B);  // Blue Grey 500
  static const Color secondaryDark = Color(0xFF455A64);  // Blue Grey 700
  static const Color secondaryLight = Color(0xFF90A4AE);  // Blue Grey 300

  // Accent colors
  static const Color accent = Color(0xFFFF9800);  // Orange
  static const Color accentDark = Color(0xFFF57C00);
  static const Color accentLight = Color(0xFFFFB74D);

  // Status colors
  static const Color success = Color(0xFF4CAF50);  // Green
  static const Color successDark = Color(0xFF388E3C);
  static const Color successLight = Color(0xFF81C784);

  static const Color warning = Color(0xFFFF9800);  // Orange
  static const Color warningDark = Color(0xFFF57C00);
  static const Color warningLight = Color(0xFFFFB74D);

  static const Color error = Color(0xFFF44336);  // Red
  static const Color errorDark = Color(0xFFD32F2F);
  static const Color errorLight = Color(0xFFE57373);

  static const Color info = Color(0xFF2196F3);  // Blue
  static const Color infoDark = Color(0xFF1976D2);
  static const Color infoLight = Color(0xFF64B5F6);

  // Duty status colors
  static const Color dutyActive = Color(0xFF4CAF50);  // Green - on duty
  static const Color dutyInactive = Color(0xFF9E9E9E);  // Grey - off duty
  static const Color dutyPaused = Color(0xFFFF9800);  // Orange - paused

  // GPS & Connectivity status
  static const Color gpsActive = Color(0xFF4CAF50);  // Green
  static const Color gpsInactive = Color(0xFFF44336);  // Red
  static const Color internetActive = Color(0xFF4CAF50);  // Green
  static const Color internetInactive = Color(0xFF9E9E9E);  // Grey

  // Neutral colors
  static const Color background = Color(0xFFF5F5F5);  // Light grey
  static const Color surface = Color(0xFFFFFFFF);  // White
  static const Color surfaceDark = Color(0xFF424242);  // Dark grey

  static const Color textPrimary = Color(0xFF212121);  // Almost black
  static const Color textSecondary = Color(0xFF757575);  // Medium grey
  static const Color textHint = Color(0xFF9E9E9E);  // Light grey
  static const Color textInverse = Color(0xFFFFFFFF);  // White

  static const Color divider = Color(0xFFBDBDBD);
  static const Color border = Color(0xFFE0E0E0);

  // Map colors
  static const Color riderMarker = success;
  static const Color installationMarker = info;
  static const Color visitMarker = error;
  static const Color routeLine = primary;
  static const Color geofenceCircle = Color(0x404CAF50);  // Semi-transparent green

  // Chart colors
  static const List<Color> chartColors = [
    primary,
    accent,
    success,
    warning,
    error,
    info,
  ];
}
