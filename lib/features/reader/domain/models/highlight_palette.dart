import 'package:flutter/material.dart';
import '../../../../core/theme/reading_theme.dart';

enum HighlightColorType {
  yellow('Kuning', 'yellow'),
  green('Hijau', 'green'),
  blue('Biru', 'blue'),
  pink('Merah Muda', 'pink'),
  purple('Ungu', 'purple'),
  gold('Emas', 'gold');

  final String label;
  final String key;
  const HighlightColorType(this.label, this.key);

  static HighlightColorType fromKey(String? key) {
    if (key == null) return HighlightColorType.yellow;
    final lower = key.toLowerCase();
    for (final c in HighlightColorType.values) {
      if (lower.contains(c.key)) return c;
    }
    if (lower.contains('red')) return HighlightColorType.pink;
    return HighlightColorType.yellow;
  }

  Color get primaryColor {
    switch (this) {
      case HighlightColorType.yellow:
        return const Color(0xFFFFD600);
      case HighlightColorType.green:
        return const Color(0xFF34C759);
      case HighlightColorType.blue:
        return const Color(0xFF007AFF);
      case HighlightColorType.pink:
        return const Color(0xFFFF2D55);
      case HighlightColorType.purple:
        return const Color(0xFFAF52DE);
      case HighlightColorType.gold:
        return const Color(0xFFD4AF37);
    }
  }

  Color getBackgroundColor(ReadingThemeType theme) {
    if (theme.isDark) {
      switch (this) {
        case HighlightColorType.yellow:
          return const Color(0xFFFFD600).withValues(alpha: 0.35);
        case HighlightColorType.green:
          return const Color(0xFF34C759).withValues(alpha: 0.35);
        case HighlightColorType.blue:
          return const Color(0xFF007AFF).withValues(alpha: 0.40);
        case HighlightColorType.pink:
          return const Color(0xFFFF2D55).withValues(alpha: 0.35);
        case HighlightColorType.purple:
          return const Color(0xFFAF52DE).withValues(alpha: 0.38);
        case HighlightColorType.gold:
          return const Color(0xFFD4AF37).withValues(alpha: 0.40);
      }
    }

    if (theme == ReadingThemeType.sepia ||
        theme == ReadingThemeType.warmPaper) {
      switch (this) {
        case HighlightColorType.yellow:
          return const Color(0xFFFFE082).withValues(alpha: 0.50);
        case HighlightColorType.green:
          return const Color(0xFFA5D6A7).withValues(alpha: 0.50);
        case HighlightColorType.blue:
          return const Color(0xFF90CAF9).withValues(alpha: 0.50);
        case HighlightColorType.pink:
          return const Color(0xFFF48FB1).withValues(alpha: 0.45);
        case HighlightColorType.purple:
          return const Color(0xFFCE93D8).withValues(alpha: 0.45);
        case HighlightColorType.gold:
          return const Color(0xFFFFD54F).withValues(alpha: 0.50);
      }
    }

    // Default (White / Light)
    switch (this) {
      case HighlightColorType.yellow:
        return const Color(0xFFFFF176).withValues(alpha: 0.55);
      case HighlightColorType.green:
        return const Color(0xFFA5D6A7).withValues(alpha: 0.55);
      case HighlightColorType.blue:
        return const Color(0xFF90CAF9).withValues(alpha: 0.55);
      case HighlightColorType.pink:
        return const Color(0xFFF48FB1).withValues(alpha: 0.50);
      case HighlightColorType.purple:
        return const Color(0xFFCE93D8).withValues(alpha: 0.50);
      case HighlightColorType.gold:
        return const Color(0xFFFFE082).withValues(alpha: 0.55);
    }
  }
}
