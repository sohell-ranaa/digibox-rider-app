import 'package:flutter/material.dart';

/// App shadow definitions for elevation and depth
class AppShadows {
  // Elevation shadows (Material Design)
  static const List<BoxShadow> elevation1 = [
    BoxShadow(
      color: Color(0x1F000000),
      offset: Offset(0, 1),
      blurRadius: 3,
      spreadRadius: 0,
    ),
  ];

  static const List<BoxShadow> elevation2 = [
    BoxShadow(
      color: Color(0x24000000),
      offset: Offset(0, 2),
      blurRadius: 6,
      spreadRadius: 0,
    ),
  ];

  static const List<BoxShadow> elevation3 = [
    BoxShadow(
      color: Color(0x26000000),
      offset: Offset(0, 3),
      blurRadius: 8,
      spreadRadius: 0,
    ),
  ];

  static const List<BoxShadow> elevation4 = [
    BoxShadow(
      color: Color(0x29000000),
      offset: Offset(0, 4),
      blurRadius: 10,
      spreadRadius: 0,
    ),
  ];

  static const List<BoxShadow> elevation6 = [
    BoxShadow(
      color: Color(0x2E000000),
      offset: Offset(0, 6),
      blurRadius: 16,
      spreadRadius: 0,
    ),
  ];

  static const List<BoxShadow> elevation8 = [
    BoxShadow(
      color: Color(0x33000000),
      offset: Offset(0, 8),
      blurRadius: 20,
      spreadRadius: 1,
    ),
  ];

  // Named shadows for specific components
  static const List<BoxShadow> card = elevation2;
  static const List<BoxShadow> cardHover = elevation4;
  static const List<BoxShadow> button = elevation2;
  static const List<BoxShadow> bottomNav = elevation8;
  static const List<BoxShadow> dialog = elevation6;

  // Colored shadows for special effects
  static List<BoxShadow> primaryShadow = [
    BoxShadow(
      color: const Color(0xFF1976D2).withOpacity(0.2),
      offset: const Offset(0, 4),
      blurRadius: 12,
      spreadRadius: 0,
    ),
  ];

  static List<BoxShadow> successShadow = [
    BoxShadow(
      color: const Color(0xFF4CAF50).withOpacity(0.2),
      offset: const Offset(0, 4),
      blurRadius: 12,
      spreadRadius: 0,
    ),
  ];

  static List<BoxShadow> errorShadow = [
    BoxShadow(
      color: const Color(0xFFF44336).withOpacity(0.2),
      offset: const Offset(0, 4),
      blurRadius: 12,
      spreadRadius: 0,
    ),
  ];
}
