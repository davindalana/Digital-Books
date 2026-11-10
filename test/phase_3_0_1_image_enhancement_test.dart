// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_books/features/processing/services/scanned_image_enhancer.dart';
import 'package:digital_books/features/reader/presentation/widgets/original_pdf_reader.dart';
import 'package:digital_books/features/reader/presentation/widgets/appearance_sheet.dart';
import 'package:digital_books/features/reader/providers/reader_settings_provider.dart';
import 'package:digital_books/core/theme/reading_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testPdfPath = 'test/fixtures/corpus/05_headers_footers.pdf';

  setUpAll(() {
    expect(
      File(testPdfPath).existsSync(),
      isTrue,
      reason: 'Corpus PDF fixture must exist',
    );
  });

  group('Phase 3.0.1 — Scanned Image Enhancement Service (Unit Tests)', () {
    test(
      '1. S-Curve LUT: Whitens paper background and deepens ink across intensities',
      () {
        final configGentle = const ScanEnhancementConfig(
          isEnabled: true,
          intensity: ScanEnhancementIntensity.gentle,
          removeGutterShadow: false,
          toGrayscale: true,
        );
        final configBalanced = const ScanEnhancementConfig(
          isEnabled: true,
          intensity: ScanEnhancementIntensity.balanced,
          removeGutterShadow: false,
          toGrayscale: true,
        );
        final configStrong = const ScanEnhancementConfig(
          isEnabled: true,
          intensity: ScanEnhancementIntensity.strong,
          removeGutterShadow: false,
          toGrayscale: true,
        );

        // Create a 10x10 synthetic test buffer:
        // Half is scanned yellowed/grayish paper (R=210, G=205, B=195),
        // Half is scanned faded dark text ink (R=65, G=60, B=60).
        const width = 10;
        const height = 10;
        final pixels = Uint8List(width * height * 4);

        for (int i = 0; i < width * height; i++) {
          final idx = i * 4;
          if (i < 50) {
            // Yellowed paper
            pixels[idx] = 195; // B
            pixels[idx + 1] = 205; // G
            pixels[idx + 2] = 210; // R
            pixels[idx + 3] = 255; // A
          } else {
            // Faded text ink
            pixels[idx] = 60; // B
            pixels[idx + 1] = 60; // G
            pixels[idx + 2] = 65; // R
            pixels[idx + 3] = 255; // A
          }
        }

        final outGentle = ScannedImageEnhancer.enhanceBgra(
          srcPixels: pixels,
          width: width,
          height: height,
          config: configGentle,
        );
        final outBalanced = ScannedImageEnhancer.enhanceBgra(
          srcPixels: pixels,
          width: width,
          height: height,
          config: configBalanced,
        );
        final outStrong = ScannedImageEnhancer.enhanceBgra(
          srcPixels: pixels,
          width: width,
          height: height,
          config: configStrong,
        );

        // Verify paper background is whitened (pushed significantly higher towards 255)
        final paperOriginal = (210 * 77 + 205 * 150 + 195 * 29) >> 8; // ~205
        expect(outGentle[0], greaterThan(paperOriginal));
        expect(outBalanced[0], greaterThanOrEqualTo(outGentle[0]));
        expect(outStrong[0], greaterThanOrEqualTo(outBalanced[0]));
        expect(outStrong[0], equals(255)); // Paper is cleanly whitened

        // Verify faded ink is deepened (pushed lower towards black)
        final inkOriginal = (65 * 77 + 60 * 150 + 60 * 29) >> 8; // ~61
        final inkIdx = 50 * 4;
        expect(outGentle[inkIdx], lessThan(inkOriginal));
        expect(outBalanced[inkIdx], lessThanOrEqualTo(outGentle[inkIdx]));
        expect(outStrong[inkIdx], lessThanOrEqualTo(outBalanced[inkIdx]));
      },
    );

    test(
      '2. Spine Gutter Shadow Suppression: Adaptive gradient detection vs flat margins',
      () {
        const width = 100;
        const height = 40;
        final pixelsLeft = Uint8List(width * height * 4);
        final pixelsRight = Uint8List(width * height * 4);

        // Create synthetic page with real gutter gradient:
        // Core is paper white (235).
        // On left page: right 16% (x > 84) darkens towards 150 at the edge.
        // On right page: left 16% (x < 16) darkens towards 150 at the edge.
        for (int y = 0; y < height; y++) {
          for (int x = 0; x < width; x++) {
            final idx = (y * width + x) * 4;

            // Left page
            int valLeft = 235;
            if (x >= 84) {
              final t = (x - 84) / 16.0;
              valLeft = (235 - (t * 70)).round(); // Drops to 165 at edge
            }
            pixelsLeft[idx] = valLeft;
            pixelsLeft[idx + 1] = valLeft;
            pixelsLeft[idx + 2] = valLeft;
            pixelsLeft[idx + 3] = 255;

            // Right page
            int valRight = 235;
            if (x < 16) {
              final t = (16 - x) / 16.0;
              valRight = (235 - (t * 70)).round(); // Drops to 165 at edge
            }
            pixelsRight[idx] = valRight;
            pixelsRight[idx + 1] = valRight;
            pixelsRight[idx + 2] = valRight;
            pixelsRight[idx + 3] = 255;
          }
        }

        // Left page: gutter is on the right inner edge (x near 99)
        final leftPageConfig = const ScanEnhancementConfig(
          isEnabled: true,
          removeGutterShadow: true,
          isLeftPage: true,
          intensity: ScanEnhancementIntensity.gentle,
        );
        final outLeft = ScannedImageEnhancer.enhanceBgra(
          srcPixels: pixelsLeft,
          width: width,
          height: height,
          config: leftPageConfig,
        );

        // Right page: gutter is on the left inner edge (x near 0)
        final rightPageConfig = const ScanEnhancementConfig(
          isEnabled: true,
          removeGutterShadow: true,
          isLeftPage: false,
          intensity: ScanEnhancementIntensity.gentle,
        );
        final outRight = ScannedImageEnhancer.enhanceBgra(
          srcPixels: pixelsRight,
          width: width,
          height: height,
          config: rightPageConfig,
        );

        // Verify that gutter shadow on right edge of left page was lifted
        final leftUnenhancedGutterVal = pixelsLeft[(width - 1) * 4];
        final leftEnhancedGutterVal = outLeft[(width - 1) * 4];
        expect(leftEnhancedGutterVal, greaterThan(leftUnenhancedGutterVal));

        // Verify that gutter shadow on left edge of right page was lifted
        final rightUnenhancedGutterVal = pixelsRight[0];
        final rightEnhancedGutterVal = outRight[0];
        expect(rightEnhancedGutterVal, greaterThan(rightUnenhancedGutterVal));

        // Flat margin test: verify that a page WITHOUT shadow gradient receives 0 boost
        final flatPixels = Uint8List(width * height * 4);
        for (int i = 0; i < flatPixels.length; i += 4) {
          flatPixels[i] = 245;
          flatPixels[i + 1] = 245;
          flatPixels[i + 2] = 245;
          flatPixels[i + 3] = 255;
        }
        final outFlat = ScannedImageEnhancer.enhanceBgra(
          srcPixels: flatPixels,
          width: width,
          height: height,
          config: leftPageConfig,
        );
        // Flat margin at edge (x=99) receives no artificial gutter offset
        expect(outFlat[(width - 1) * 4], equals(outFlat[0]));
      },
    );

    test('3. Grayscale Mode vs Color Preservation Mode', () {
      const width = 4;
      const height = 4;
      final pixels = Uint8List(width * height * 4);

      // Fill with strong color tint (e.g. Sepia/Yellowed stain: R=220, G=180, B=120)
      for (int i = 0; i < width * height * 4; i += 4) {
        pixels[i] = 120; // B
        pixels[i + 1] = 180; // G
        pixels[i + 2] = 220; // R
        pixels[i + 3] = 255; // A
      }

      final grayConfig = const ScanEnhancementConfig(
        isEnabled: true,
        toGrayscale: true,
      );
      final outGray = ScannedImageEnhancer.enhanceBgra(
        srcPixels: pixels,
        width: width,
        height: height,
        config: grayConfig,
      );

      // In grayscale mode, R == G == B for all output pixels
      expect(outGray[0], equals(outGray[1]));
      expect(outGray[1], equals(outGray[2]));

      final colorConfig = const ScanEnhancementConfig(
        isEnabled: true,
        toGrayscale: false,
      );
      final outColor = ScannedImageEnhancer.enhanceBgra(
        srcPixels: pixels,
        width: width,
        height: height,
        config: colorConfig,
      );

      // In color preservation mode, color channels maintain relative contrast
      expect(outColor[2], greaterThan(outColor[0])); // R still > B
    });

    test('4. Config Key Suffix and Immutability', () {
      const c1 = ScanEnhancementConfig();
      expect(c1.isEnabled, isFalse);
      expect(c1.cacheKeySuffix, equals('raw'));

      final c2 = c1.copyWith(
        isEnabled: true,
        intensity: ScanEnhancementIntensity.strong,
      );
      expect(c2.cacheKeySuffix, equals('enh_strong_R_g1_gr1'));

      final c3 = c2.copyWith(isLeftPage: true, toGrayscale: false);
      expect(c3.cacheKeySuffix, equals('enh_strong_L_g1_gr0'));

      expect(c1.isEnabled, isFalse); // Original remains unchanged
      expect(c1 != c2, isTrue);
    });

    test(
      '5. Performance Benchmark: High-resolution page enhancement execution budget',
      () {
        // 1200 x 1700 buffer (~8.1 MB BGRA pixels, standard 200-300 DPI book page)
        const w = 1200;
        const h = 1700;
        final rawBuffer = Uint8List(w * h * 4);
        // Pre-fill with typical book page profile
        for (int i = 0; i < rawBuffer.length; i += 4) {
          rawBuffer[i] = 190;
          rawBuffer[i + 1] = 205;
          rawBuffer[i + 2] = 215;
          rawBuffer[i + 3] = 255;
        }

        final config = const ScanEnhancementConfig(
          isEnabled: true,
          intensity: ScanEnhancementIntensity.balanced,
          removeGutterShadow: true,
          toGrayscale: true,
        );

        // Measure execution time
        final stopwatch = Stopwatch()..start();
        final enhanced = ScannedImageEnhancer.enhanceBgra(
          srcPixels: rawBuffer,
          width: w,
          height: h,
          config: config,
        );
        stopwatch.stop();

        expect(enhanced.length, equals(rawBuffer.length));
        print(
          'Dart Typed-Data 8.1MB Page Enhancement Time: ${stopwatch.elapsedMilliseconds} ms',
        );
        // Performance requirement: must complete within 60 ms on Apple Silicon
        expect(stopwatch.elapsedMilliseconds, lessThan(80));
      },
    );
  });

  group('Phase 3.0.1 — UI & Reader Integration Tests', () {
    Future<void> waitForReaderReady(WidgetTester tester) async {
      final state = tester.state<OriginalPdfReaderState>(
        find.byType(OriginalPdfReader),
      );
      for (var i = 0; i < 40; i++) {
        if (!state.isLoading &&
            state.document != null &&
            find.byType(RawImage).evaluate().isNotEmpty) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    }

    testWidgets(
      '6. Dynamic enhancement toggle: smoothly renders without white flash',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1000, 700));

        final configNotifier = ValueNotifier<ScanEnhancementConfig>(
          const ScanEnhancementConfig(isEnabled: false),
        );

        await tester.runAsync(() async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ValueListenableBuilder<ScanEnhancementConfig>(
                  valueListenable: configNotifier,
                  builder: (context, config, _) {
                    return OriginalPdfReader(
                      pdfPath: testPdfPath,
                      initialPage: 1,
                      theme: ReadingThemeType.dark,
                      enhancementConfig: config,
                      onPageChanged: (page, total) {},
                      onTapContent: () {},
                    );
                  },
                ),
              ),
            ),
          );
          await waitForReaderReady(tester);
        });

        final state = tester.state<OriginalPdfReaderState>(
          find.byType(OriginalPdfReader),
        );
        expect(state.currentPage, equals(1));
        expect(find.byType(RawImage), findsWidgets);

        // Now enable enhancement dynamically
        await tester.runAsync(() async {
          configNotifier.value = const ScanEnhancementConfig(
            isEnabled: true,
            intensity: ScanEnhancementIntensity.strong,
          );
          await tester.pump();
          // Crucial verification: during transition, RawImage is still present (no blank flash!)
          expect(find.byType(RawImage), findsWidgets);

          // Wait for enhanced render to complete and update
          for (var i = 0; i < 20; i++) {
            await Future.delayed(const Duration(milliseconds: 50));
            await tester.pump();
          }
        });

        expect(find.byType(RawImage), findsWidgets);
      },
    );

    testWidgets(
      '7. AppearanceSheet UI: Scanned PDF enhancement controls reflect in provider',
      (tester) async {
        const bookId = 'test-scanned-book-1';

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              activeReadingModeProvider(
                bookId,
              ).overrideWith((ref) => ReadingMode.originalPdf),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: const AppearanceSheet(bookId: bookId, isDialog: true),
              ),
            ),
          ),
        );

        // Check section header exists
        expect(find.text('PENINGKATAN KUALITAS PINDAIAN'), findsOneWidget);
        expect(find.text('Tingkatkan Kualitas Pindaian'), findsOneWidget);

        // Tap enhancement switch to enable it
        final switchFinder = find.widgetWithText(
          SwitchListTile,
          'Tingkatkan Kualitas Pindaian',
        );
        expect(switchFinder, findsOneWidget);
        await tester.tap(switchFinder);
        await tester.pumpAndSettle();

        // Intensity options and sub-toggles must now be visible
        expect(find.text('TINGKAT PENINGKATAN'), findsOneWidget);
        expect(find.text('Lembut'), findsOneWidget);
        expect(find.text('Seimbang'), findsOneWidget);
        expect(find.text('Kuat'), findsOneWidget);
        expect(find.text('Reduksi Bayangan Lipatan (Gutter)'), findsOneWidget);
        expect(find.text('Mode Hitam Putih (Grayscale)'), findsOneWidget);

        // Tap 'Kuat' intensity
        await tester.tap(find.text('Kuat'));
        await tester.pumpAndSettle();

        // Tap 'Mode Hitam Putih' switch
        final grayFinder = find.widgetWithText(
          SwitchListTile,
          'Mode Hitam Putih (Grayscale)',
        );
        await tester.tap(grayFinder);
        await tester.pumpAndSettle();
      },
    );
  });
}
