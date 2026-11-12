import 'package:flutter_test/flutter_test.dart';
import 'package:digital_books/core/constants/app_strings.dart';
import 'package:digital_books/core/utils/reading_progress_calculator.dart';

void main() {
  group('ReadingProgressCalculator — Unified Phase 5 Specifications', () {
    test('1. Unopened book returns 0.0 fraction and "Belum dibaca"', () {
      final fraction = ReadingProgressCalculator.calculatePdfFraction(
        lastVisiblePage: 0,
        totalPages: 100,
      );
      expect(fraction, 0.0);
      expect(
        ReadingProgressCalculator.formatProgressText(progressPercentage: 0.0),
        AppStrings.statusBelumDibaca,
      );
      expect(
        ReadingProgressCalculator.formatProgressText(progressPercentage: null),
        AppStrings.statusBelumDibaca,
      );
    });

    test(
      '2. T=255, N=1 (0.39%) displays "Baru dimulai" (percentage < 1%) and includes PDF page info',
      () {
        final fraction = ReadingProgressCalculator.calculatePdfFraction(
          lastVisiblePage: 1,
          totalPages: 255,
        );
        expect(fraction, closeTo(0.00392, 0.0001));
        final pct = ReadingProgressCalculator.formatPercentage(fraction);
        expect(pct, 0); // floor of 0.39% is 0

        final label = ReadingProgressCalculator.formatProgressText(
          progressPercentage: fraction,
          lastReadingMode: 'pdf',
          currentPosition: 1,
          totalPages: 255,
        );
        expect(label, 'Baru dimulai • Hal. 1 dari 255');
      },
    );

    test('3. PDF page 1 of 100 (1.0%) displays "1% Selesai • Hal. 1 dari 100"', () {
      final fraction = ReadingProgressCalculator.calculatePdfFraction(
        lastVisiblePage: 1,
        totalPages: 100,
      );
      expect(fraction, 0.01);
      final label = ReadingProgressCalculator.formatProgressText(
        progressPercentage: fraction,
        lastReadingMode: 'pdf',
        currentPosition: 1,
        totalPages: 100,
      );
      expect(label, '1% Selesai • Hal. 1 dari 100');
    });

    test(
      '4. PDF two-page spread (pages 20-21 of 100) uses last visible page 21',
      () {
        final fraction = ReadingProgressCalculator.calculatePdfFraction(
          lastVisiblePage: 21,
          totalPages: 100,
        );
        expect(fraction, 0.21);
        final label = ReadingProgressCalculator.formatProgressText(
          progressPercentage: fraction,
          lastReadingMode: 'pdf',
          currentPosition: 21,
          totalPages: 100,
        );
        expect(label, '21% Selesai • Hal. 21 dari 100');
      },
    );

    test(
      '5. Near complete (99.8%) never rounds up to 100% (floors and clamps to 99%)',
      () {
        const fraction = 0.998;
        final pct = ReadingProgressCalculator.formatPercentage(fraction);
        expect(pct, 99); // Must NOT be 100

        final label = ReadingProgressCalculator.formatProgressText(
          progressPercentage: fraction,
          lastReadingMode: 'pdf',
          currentPosition: 254,
          totalPages: 255,
        );
        expect(label, '99% Selesai • Hal. 254 dari 255');
      },
    );

    test('6. Completed book (fraction >= 0.999 or >= 1.0) displays "Selesai"', () {
      final fraction = ReadingProgressCalculator.calculatePdfFraction(
        lastVisiblePage: 255,
        totalPages: 255,
      );
      expect(fraction, 1.0);
      expect(ReadingProgressCalculator.formatPercentage(fraction), 100);

      expect(
        ReadingProgressCalculator.formatProgressText(
          progressPercentage: 1.0,
          lastReadingMode: 'pdf',
          currentPosition: 255,
          totalPages: 255,
        ),
        AppStrings.statusSelesai,
      );
      expect(
        ReadingProgressCalculator.formatProgressText(
          progressPercentage: 0.9995,
          lastReadingMode: 'pdf',
        ),
        AppStrings.statusSelesai,
      );
    });

    test('7. Single page book (T=1, N=1) reaches 1.0 (100% Selesai)', () {
      final fraction = ReadingProgressCalculator.calculatePdfFraction(
        lastVisiblePage: 1,
        totalPages: 1,
      );
      expect(fraction, 1.0);
      expect(ReadingProgressCalculator.formatPercentage(fraction), 100);
      expect(
        ReadingProgressCalculator.formatProgressText(
          progressPercentage: fraction,
          lastReadingMode: 'pdf',
          currentPosition: 1,
          totalPages: 1,
        ),
        AppStrings.statusSelesai,
      );
    });

    test('8. Corrupted metadata zero or negative pages safely returns 0.0', () {
      final fraction = ReadingProgressCalculator.calculatePdfFraction(
        lastVisiblePage: 5,
        totalPages: 0,
      );
      expect(fraction, 0.0);
      expect(
        ReadingProgressCalculator.formatProgressText(
          progressPercentage: fraction,
          lastReadingMode: 'pdf',
          currentPosition: 5,
          totalPages: 0,
        ),
        AppStrings.statusBelumDibaca,
      );
    });

    test('9. Continuous scroll normalization: 500 / 2000 = 25%', () {
      final fraction = ReadingProgressCalculator.calculateReflowableFraction(
        currentOffset: 500,
        totalLength: 2000,
      );
      expect(fraction, 0.25);
      expect(ReadingProgressCalculator.formatPercentage(fraction), 25);
      expect(
        ReadingProgressCalculator.formatProgressText(
          progressPercentage: fraction,
          lastReadingMode: 'reflowable_paginated',
        ),
        '25% Selesai',
      );
    });

    test('10. Invalid NaN or negative values gracefully handled as 0.0', () {
      expect(
        ReadingProgressCalculator.formatPercentage(double.nan),
        0,
      );
      expect(
        ReadingProgressCalculator.formatPercentage(-0.5),
        0,
      );
      expect(
        ReadingProgressCalculator.formatProgressText(
          progressPercentage: double.nan,
        ),
        AppStrings.statusBelumDibaca,
      );
    });

    test(
      '11. Legacy Data Compatibility: lastReadingMode is null, progress=0.06, position=20',
      () {
        // Must show percentage only; must NOT show "Halaman 20" or guess mode
        final label = ReadingProgressCalculator.formatProgressText(
          progressPercentage: 0.06,
          lastReadingMode: null,
          currentPosition: 20,
          totalPages: 255,
        );
        expect(label, '6% Selesai');
      },
    );

    test('12. Reflowable mode with chapter information', () {
      final withTitle = ReadingProgressCalculator.formatProgressText(
        progressPercentage: 0.14,
        lastReadingMode: 'reflowable_paginated',
        currentChapter: 3,
        chapterTitle: 'Bab 3: Seni Membujuk',
      );
      expect(withTitle, '14% Selesai • Bab 3: Seni Membujuk');

      final withNumberOnly = ReadingProgressCalculator.formatProgressText(
        progressPercentage: 0.14,
        lastReadingMode: 'reflowable_paginated',
        currentChapter: 3,
      );
      expect(withNumberOnly, '14% Selesai • Bab 3');
    });

    test('13. Reflowable reading time estimation based on 200 words/min', () {
      // 500 words at 200 wpm = ceil(2.5) = 3 minutes
      final estimate = ReadingProgressCalculator.estimateReflowableRemainingTime(
        remainingWords: 500,
      );
      expect(estimate, '±3 mnt tersisa');
      expect(
        ReadingProgressCalculator.timeEstimateTooltip,
        'Perkiraan berdasarkan 200 kata per menit',
      );

      // Non-positive returns null
      expect(
        ReadingProgressCalculator.estimateReflowableRemainingTime(
          remainingWords: 0,
        ),
        isNull,
      );
    });
  });
}
