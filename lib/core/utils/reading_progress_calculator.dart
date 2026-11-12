import 'package:digital_books/core/constants/app_strings.dart';

/// Single source of truth for reading progress calculation, formatting, and estimation.
///
/// Follows Digital Books Phase 5 Unified Progress Specification:
/// 1. Canonical fraction in range [0.0, 1.0].
/// 2. PDF calculation uses the last visible page of the spread (N_last / T) so 100% is reachable.
/// 3. Rounding is strictly floor with clamp(0, 99) unless fraction >= 1.0.
/// 4. Values < 1% (e.g. 1/255 = 0.39%) display "Baru dimulai".
/// 5. "Hal. X dari T" is rendered ONLY when lastReadingMode == 'pdf'.
/// 6. Legacy data (lastReadingMode == null) renders percentage only without guessing.
/// 7. Time estimation is allowed ONLY for Reflowable text mode based on loaded word counts.
class ReadingProgressCalculator {
  ReadingProgressCalculator._();

  /// Standard adult reading speed baseline for reflowable text estimation.
  static const int defaultWordsPerMinute = 200;

  /// Tooltip message for reading time estimation.
  static const String timeEstimateTooltip =
      'Perkiraan berdasarkan 200 kata per menit';

  /// Calculates the canonical progress fraction [0.0, 1.0] for a PDF document.
  ///
  /// [lastVisiblePage] is the 1-based index of the last visible page in the active spread
  /// (e.g. in a two-page spread showing pages 20 and 21, [lastVisiblePage] is 21).
  /// This ensures that reaching the final page of the document yields 1.0 (100%).
  static double calculatePdfFraction({
    required int lastVisiblePage,
    required int totalPages,
  }) {
    if (totalPages <= 0 || lastVisiblePage <= 0) return 0.0;
    if (lastVisiblePage >= totalPages) return 1.0;
    final fraction = lastVisiblePage / totalPages;
    if (fraction.isNaN || fraction.isInfinite || fraction <= 0.0) return 0.0;
    return fraction.clamp(0.0, 1.0);
  }

  /// Calculates the canonical progress fraction [0.0, 1.0] for reflowable content.
  ///
  /// [currentOffset] and [totalLength] can represent character offsets, word counts,
  /// or normalized scroll/page indices.
  static double calculateReflowableFraction({
    required num currentOffset,
    required num totalLength,
  }) {
    if (totalLength <= 0 || currentOffset <= 0) return 0.0;
    if (currentOffset >= totalLength) return 1.0;
    final fraction = currentOffset / totalLength;
    if (fraction.isNaN || fraction.isInfinite || fraction <= 0.0) return 0.0;
    return fraction.toDouble().clamp(0.0, 1.0);
  }

  /// Formats the fraction [0.0, 1.0] into an integer percentage.
  ///
  /// Rules:
  /// - Non-positive, NaN, or infinite returns 0.
  /// - Values >= 1.0 return 100.
  /// - All other values use floor and are clamped to 0..99 (so 99.8% never rounds to 100%).
  static int formatPercentage(double fraction) {
    if (fraction.isNaN || fraction.isInfinite || fraction <= 0.0) return 0;
    if (fraction >= 1.0) return 100;
    final pct = (fraction * 100).floor();
    return pct.clamp(0, 99);
  }

  /// Formats reading progress into a user-facing label string.
  ///
  /// Rules:
  /// - If [progressPercentage] <= 0.0: returns "Belum dibaca".
  /// - If [progressPercentage] >= 0.999: returns "Selesai".
  /// - If [formatPercentage] < 1: displays "Baru dimulai".
  /// - "Hal. X dari T" is appended ONLY when [lastReadingMode] == 'pdf'.
  /// - If [lastReadingMode] is null (legacy data) or reflowable, page counts are NEVER shown.
  /// - If [lastReadingMode] is reflowable and chapter info is available: appends chapter title.
  static String formatProgressText({
    required double? progressPercentage,
    String? lastReadingMode,
    int? currentPosition,
    int? totalPages,
    int? currentChapter,
    String? chapterTitle,
  }) {
    final pctValue = progressPercentage ?? 0.0;
    if (pctValue.isNaN || pctValue.isInfinite || pctValue <= 0.0) {
      return AppStrings.statusBelumDibaca;
    }
    if (pctValue >= 0.999) {
      return AppStrings.statusSelesai;
    }

    final int pct = formatPercentage(pctValue);
    final bool isJustStarted = pct < 1;
    final String basePct =
        isJustStarted ? AppStrings.statusBaruDimulai : '$pct% Selesai';

    // Rule 2: "Hal. X dari T" ONLY when lastReadingMode == 'pdf'
    if (lastReadingMode == 'pdf') {
      if (currentPosition != null &&
          currentPosition > 0 &&
          totalPages != null &&
          totalPages > 0) {
        return '$basePct • Hal. $currentPosition dari $totalPages';
      }
      return basePct;
    }

    // Rule 2: Reflowable text mode: append chapter name/number only if valid
    if (lastReadingMode != null && lastReadingMode != 'pdf') {
      if (chapterTitle != null && chapterTitle.trim().isNotEmpty) {
        return '$basePct • ${chapterTitle.trim()}';
      }
      if (currentChapter != null && currentChapter > 0) {
        return '$basePct • Bab $currentChapter';
      }
      return basePct;
    }

    // Rule 2: Legacy data (lastReadingMode == null) -> percentage only!
    return basePct;
  }

  /// Estimates the remaining reading time in minutes for reflowable text mode.
  ///
  /// Returns null if [remainingWords] <= 0 or if not applicable.
  /// Formatted as "±X mnt tersisa" where X is ceil(remainingWords / [wordsPerMinute]).
  static String? estimateReflowableRemainingTime({
    required int remainingWords,
    int wordsPerMinute = defaultWordsPerMinute,
  }) {
    if (remainingWords <= 0 || wordsPerMinute <= 0) return null;
    final minutes = (remainingWords / wordsPerMinute).ceil();
    if (minutes <= 0) return null;
    return '±$minutes mnt tersisa';
  }
}
