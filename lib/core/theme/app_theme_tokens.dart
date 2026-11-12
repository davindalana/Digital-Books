import 'package:flutter/material.dart';

/// Central design tokens for Digital Books native macOS interface.
/// Encapsulates spacing, radii, color palette, typography hierarchy,
/// and interactive target sizing.
abstract final class AppThemeTokens {
  // --- 1. Spacing Scale (4, 8, 12, 16, 24, 32) ---
  static const double space4 = 4.0;
  static const double space8 = 8.0;
  static const double space12 = 12.0;
  static const double space16 = 16.0;
  static const double space24 = 24.0;
  static const double space32 = 32.0;

  // --- 2. Corner Radii (10, 14, 20) ---
  static const double radius6 = 6.0;
  static const double radius10 = 10.0;
  static const double radius14 = 14.0;
  static const double radius20 = 20.0;

  static const Radius r10 = Radius.circular(radius10);
  static const Radius r14 = Radius.circular(radius14);
  static const Radius r20 = Radius.circular(radius20);

  static const BorderRadius br6 = BorderRadius.all(Radius.circular(radius6));
  static const BorderRadius br10 = BorderRadius.all(Radius.circular(radius10));
  static const BorderRadius br14 = BorderRadius.all(Radius.circular(radius14));
  static const BorderRadius br20 = BorderRadius.all(Radius.circular(radius20));

  // --- 3. Window Shell & Responsive Breakpoints ---
  /// Expansive desktop: >= 1100pt window width.
  static const double breakpointExpansive = 1100.0;

  /// Standard desktop: 760pt .. 1099pt window width.
  static const double breakpointStandard = 760.0;

  /// Sidebar widths by breakpoint
  static const double sidebarExpansiveWidth = 240.0;
  static const double sidebarStandardWidth = 200.0;
  static const double sidebarCompactWidth = 64.0;

  /// Maximum content width in expansive mode
  static const double contentMaxWidth = 1200.0;

  /// Native macOS window controls (traffic-light) safe clearances
  static const double titlebarHeight = 52.0;
  static const double trafficLightAreaWidth = 80.0;
  static const double trafficLightSafeTopInset = 36.0;

  // --- 4. Interactive Target Constraints ---
  static const double minInteractiveTarget = 28.0;
  static const double minButtonHeight = 32.0;

  // --- 5. Animation Durations & Curves ---
  static const Duration durationFast = Duration(milliseconds: 150);
  static const Duration durationNormal = Duration(milliseconds: 200);
  static const Duration durationMedium = Duration(milliseconds: 220);
  static const Curve curveDefault = Curves.easeOutCubic;

  // --- 6. Colors: Dark Theme (Primary macOS Apple Books experience) ---
  static const Color darkBackground = Color(0xFF0B0B0D);
  static const Color darkOledBackground = Color(0xFF000000);
  static const Color darkSurface = Color(0xFF161618);
  static const Color darkSurfaceElevated = Color(0xFF1C1C1E);
  static const Color darkCard = Color(0xFF1E1E22);
  static const Color darkCardBorder = Color(0x1FFFFFFF); // ~12% white
  static const Color darkSeparator = Color(0x1AFFFFFF); // ~10% white

  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFFA1A1A6); // >= 4.5:1 contrast
  static const Color darkTextMuted = Color(0xFF636366);

  // --- 7. Colors: Light Theme ---
  static const Color lightBackground = Color(0xFFF2F2F7);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceElevated = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightCardBorder = Color(0x14000000); // ~8% black
  static const Color lightSeparator = Color(0x1A000000); // ~10% black

  static const Color lightTextPrimary = Color(0xFF000000);
  static const Color lightTextSecondary = Color(0xFF6E6E73);
  static const Color lightTextMuted = Color(0xFF8E8E93);

  // --- 8. Brand & Accent Colors ---
  static const Color goldAccent = Color(0xFFD4AF37);
  static const Color goldAccentMuted = Color(0x33D4AF37);
  static const Color blueAccent = Color(0xFF007AFF);
  static const Color redDestructive = Color(0xFFFF453A);
  static const Color greenSuccess = Color(0xFF34C759);
  static const Color orangeWarning = Color(0xFFFF9F0A);

  // --- 9. Typography Helpers ---
  static TextStyle largeTitle({required bool isDark}) => TextStyle(
    fontSize: 26.0,
    fontWeight: FontWeight.bold,
    letterSpacing: -0.5,
    color: isDark ? darkTextPrimary : lightTextPrimary,
  );

  static TextStyle sectionHeader({required bool isDark}) => TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.bold,
    letterSpacing: 1.15,
    color: isDark ? darkTextMuted : lightTextMuted,
  );

  static TextStyle body({required bool isDark, FontWeight? fontWeight}) =>
      TextStyle(
        fontSize: 13.0,
        fontWeight: fontWeight ?? FontWeight.normal,
        letterSpacing: -0.1,
        color: isDark ? darkTextPrimary : lightTextPrimary,
      );

  static TextStyle caption({required bool isDark, FontWeight? fontWeight}) =>
      TextStyle(
        fontSize: 11.5,
        fontWeight: fontWeight ?? FontWeight.normal,
        letterSpacing: 0.0,
        color: isDark ? darkTextSecondary : lightTextSecondary,
      );
}
