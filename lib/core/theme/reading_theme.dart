import 'package:flutter/material.dart';

enum ReadingThemeType {
  white(
    'White',
    Color(0xFFFFFFFF),
    Color(0xFF1C1C1E),
    Color(0xFF8E8E93),
    Color(0xFFF2F2F7),
  ),
  sepia(
    'Sepia',
    Color(0xFFF8F1E3),
    Color(0xFF433422),
    Color(0xFF8A7761),
    Color(0xFFEDE4D2),
  ),
  warmPaper(
    'Warm Paper',
    Color(0xFFFAF6EE),
    Color(0xFF2C2723),
    Color(0xFF7E766D),
    Color(0xFFF0EBE1),
  ),
  dark(
    'Dark',
    Color(0xFF1C1C1E),
    Color(0xFFE5E5EA),
    Color(0xFF8E8E93),
    Color(0xFF2C2C2E),
  ),
  black(
    'Black',
    Color(0xFF000000),
    Color(0xFFFFFFFF),
    Color(0xFFA1A1A6),
    Color(0xFF141416),
  );

  final String label;
  final Color backgroundColor;
  final Color textColor;
  final Color secondaryTextColor;
  final Color surfaceColor;

  const ReadingThemeType(
    this.label,
    this.backgroundColor,
    this.textColor,
    this.secondaryTextColor,
    this.surfaceColor,
  );

  bool get isDark =>
      this == ReadingThemeType.dark || this == ReadingThemeType.black;
}
