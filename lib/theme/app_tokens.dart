import 'package:flutter/material.dart';

/// Set to true to re-enable the periodic Credexa+ promo overlay.
const bool kShowPromoAd = false;

class AppColors {
  AppColors._();
  static const green = Color(0xFF22C55E);
  static const greenDark = Color(0xFF16A34A);
  static const indigo = Color(0xFF6366F1);
  static const sky = Color(0xFF0EA5E9);
  static const amber = Color(0xFFF59E0B);
  static const red = Color(0xFFEF4444);
  static const slate900 = Color(0xFF0F172A);
  static const slate800 = Color(0xFF1E293B);
  static const slate700 = Color(0xFF334155);
  static const slate500 = Color(0xFF64748B);
  static const slate400 = Color(0xFF94A3B8);
  static const slate100 = Color(0xFFF1F5F9);

  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF134E4A)],
  );
  static const greenGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
  );
}

class AppRadius {
  AppRadius._();
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 22;
  static const double pill = 999;
}

/// Minimum readable sizes for text that will be screen-recorded.
class AppFont {
  AppFont._();
  static const double caption = 11;
  static const double body = 13;
}
