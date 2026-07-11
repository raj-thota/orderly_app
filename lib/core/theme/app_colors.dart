import 'package:flutter/material.dart';

/// Central color tokens. Do not hardcode Color(0xFF...) in widgets — use these.
class AppColors {
  AppColors._();

  // Brand — V1 indigo (per V1.0.0 mock; confirm exact hex against Figma)
  static const Color primary = Color(0xFF5B4FE9);
  static const Color primaryDark = Color(0xFF4638C9);
  static const Color accent = Color(0xFFE0A82E); // warm gold (legacy, unused in V1 mock)

  // AI surfaces (lilac cards: summary, suggested reply, brief chips)
  static const Color aiSurface = Color(0xFFF1EFFE);
  static const Color aiAccent = Color(0xFF7A6CF0);

  // Today brief card gradient
  static const Color briefGradientStart = Color(0xFF7C6BF7);
  static const Color briefGradientEnd = Color(0xFF5B4FE9);

  // Surfaces
  static const Color background = Color(0xFFF6F7FB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF3F0FF);

  // Text
  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF6B7280);

  // Semantic
  static const Color success = Color(0xFF0F9D58);
  static const Color warning = Color(0xFFE08B00);
  static const Color danger = Color(0xFFDC2626);
  static const Color info = Color(0xFF2563EB);

  // Money
  static const Color money = Color(0xFF0F9D58);
  static const Color dues = Color(0xFFDC2626);

  static const Color border = Color(0xFFE5E7EB);
}
