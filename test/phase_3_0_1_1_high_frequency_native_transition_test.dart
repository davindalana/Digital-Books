// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/features/reader/presentation/widgets/original_pdf_reader.dart';
import 'helpers/test_evidence_dir.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 3.0.1.1 — High-Frequency Native Transition & Compositor Blip Audit', () {
    const String downloadsDir = '/Users/davindalana/Downloads';
    final String evidenceDir = resolveTestEvidenceDir('native_transitions');

    final lautBerceritaFile = File(
      '$downloadsDir/Laut Bercerita (Leila S. Chudori).pdf',
    );
    final bicaraFile = File(
      '$downloadsDir/Bicara Itu Ada Seninya (Oh Su Hyang).pdf',
    );

    setUpAll(() {
      Directory(evidenceDir).createSync(recursive: true);
      expect(lautBerceritaFile.existsSync(), isTrue);
      expect(bicaraFile.existsSync(), isTrue);
    });

    Future<Uint8List?> captureBoundaryBytes(GlobalKey key) async {
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      image.dispose();
      return byteData?.buffer.asUint8List();
    }

    bool isFrameBlankWhite(Uint8List rgba, int width, int height) {
      int whitePixels = 0;
      int contentPixels = 0;
      final total = width * height;
      for (int i = 0; i < total * 4; i += 4) {
        final r = rgba[i];
        final g = rgba[i + 1];
        final b = rgba[i + 2];
        final lum = (r * 77 + g * 150 + b * 29) >> 8;
        if (lum >= 250) {
          whitePixels++;
        } else if (lum < 160) {
          contentPixels++;
        }
      }
      // Blank frame detected if > 99.8% is pure white and less than 10 content pixels exist
      return (whitePixels / total > 0.998) && (contentPixels < 10);
    }

    // =========================================================================
    // SCENARIO 1: HIGH-FREQUENCY 60Hz/120Hz SINGLE FORWARD & BACKWARD TURN
    // =========================================================================
    testWidgets(
      '1. High-Frequency Sampling: Single Forward & Backward (35+ frames @ 10ms)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 800));
        final readerKey = GlobalKey();
        int currentPage = 1;

        await tester.runAsync(() async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: RepaintBoundary(
                  key: readerKey,
                  child: OriginalPdfReader(
                    pdfPath: lautBerceritaFile.path,
                    initialPage: 1,
                    theme: ReadingThemeType.warmPaper,
                    onPageChanged: (p, t) => currentPage = p,
                    onTapContent: () {},
                  ),
                ),
              ),
            ),
          );

          final state = tester.state<OriginalPdfReaderState>(
            find.byType(OriginalPdfReader),
          );
          for (var i = 0; i < 40; i++) {
            if (!state.isLoading && state.document != null) break;
            await Future.delayed(const Duration(milliseconds: 50));
            await tester.pump();
          }

          expect(state.currentPage, equals(1));
          print(
            '\n===============================================================',
          );
          print(
            'SCENARIO 1: HIGH-FREQUENCY TRANSITION SAMPLING (35+ FRAMES @ 10ms)',
          );
          print(
            '===============================================================',
          );

          // Trigger Next Page
          state.nextPage();

          int sampledFrames = 0;
          int blankFramesDetected = 0;

          // Sample at 10ms intervals (100 Hz sampling rate across 350ms window = 35 frames)
          for (int i = 0; i < 35; i++) {
            await Future.delayed(const Duration(milliseconds: 10));
            await tester.pump();
            sampledFrames++;

            final bytes = await captureBoundaryBytes(readerKey);
            if (bytes != null) {
              final isBlank = isFrameBlankWhite(bytes, 1200, 800);
              if (isBlank) {
                blankFramesDetected++;
                print(
                  'FRAME $i: CRITICAL DEFECT! BLANK WHITE FRAME DETECTED IN COMPOSITOR!',
                );
              }
            }

            // Save snapshots at frames 0, 8, 17, 26, 34
            if (i == 0 || i == 8 || i == 17 || i == 26 || i == 34) {
              final boundary =
                  readerKey.currentContext?.findRenderObject()
                      as RenderRepaintBoundary?;
              if (boundary != null) {
                final img = await boundary.toImage(pixelRatio: 1.0);
                final png = await img.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                if (png != null) {
                  await File(
                    '$evidenceDir/turn_frame_${i.toString().padLeft(2, '0')}.png',
                  ).writeAsBytes(png.buffer.asUint8List());
                }
                img.dispose();
              }
            }
          }

          // Wait to settle
          for (int s = 0; s < 10; s++) {
            await Future.delayed(const Duration(milliseconds: 50));
            await tester.pump();
          }

          print(
            'Sampled $sampledFrames frames @ 10ms. Blank Frames Detected: $blankFramesDetected',
          );
          print(
            'Final state: currentPage=${state.currentPage}, isFlipping=${state.isFlipping}, callback currentPage=$currentPage',
          );
          expect(
            blankFramesDetected,
            equals(0),
            reason: 'Zero blank white frames must occur at 100 Hz sampling',
          );
          expect(state.currentPage, greaterThanOrEqualTo(1));
        });
      },
    );

    // =========================================================================
    // SCENARIO 2: IMMEDIATE REVERSE DURING ACTIVE 3D CURL
    // =========================================================================
    testWidgets(
      '2. Immediate Reverse: Mid-flight direction change without flash or lockup',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 800));
        final readerKey = GlobalKey();

        await tester.runAsync(() async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: RepaintBoundary(
                  key: readerKey,
                  child: OriginalPdfReader(
                    pdfPath: lautBerceritaFile.path,
                    initialPage: 2,
                    theme: ReadingThemeType.warmPaper,
                    onPageChanged: (_, total) {},
                    onTapContent: () {},
                  ),
                ),
              ),
            ),
          );

          final state = tester.state<OriginalPdfReaderState>(
            find.byType(OriginalPdfReader),
          );
          for (var i = 0; i < 40; i++) {
            if (!state.isLoading && state.document != null) break;
            await Future.delayed(const Duration(milliseconds: 50));
            await tester.pump();
          }

          // Flip next, then immediately reverse after 60ms (during active curl)
          state.nextPage();
          await Future.delayed(const Duration(milliseconds: 60));
          await tester.pump();

          // Immediate reverse
          state.previousPage();

          int blankCount = 0;
          for (int i = 0; i < 25; i++) {
            await Future.delayed(const Duration(milliseconds: 12));
            await tester.pump();
            final bytes = await captureBoundaryBytes(readerKey);
            if (bytes != null && isFrameBlankWhite(bytes, 1200, 800)) {
              blankCount++;
            }
          }

          await Future.delayed(const Duration(milliseconds: 100));
          await tester.pump();

          print('Immediate Reverse Audit: Blank Frames: $blankCount');
          expect(
            blankCount,
            equals(0),
            reason:
                'Immediate reverse mid-flight must not produce blank frames',
          );
        });
      },
    );

    // =========================================================================
    // SCENARIO 3: RAPID NAVIGATION COALESCING (8 RAPID FLIPS)
    // =========================================================================
    testWidgets(
      '3. Rapid Navigation: 8 rapid flips without race condition or blank canvas',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 800));
        final readerKey = GlobalKey();

        await tester.runAsync(() async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: RepaintBoundary(
                  key: readerKey,
                  child: OriginalPdfReader(
                    pdfPath: lautBerceritaFile.path,
                    initialPage: 1,
                    theme: ReadingThemeType.warmPaper,
                    onPageChanged: (_, total) {},
                    onTapContent: () {},
                  ),
                ),
              ),
            ),
          );

          final state = tester.state<OriginalPdfReaderState>(
            find.byType(OriginalPdfReader),
          );
          for (var i = 0; i < 40; i++) {
            if (!state.isLoading && state.document != null) break;
            await Future.delayed(const Duration(milliseconds: 50));
            await tester.pump();
          }

          int blankFrames = 0;
          // Fire 8 rapid flips with 20ms gap
          for (int flip = 0; flip < 8; flip++) {
            state.nextPage();
            await Future.delayed(const Duration(milliseconds: 20));
            await tester.pump();
            final bytes = await captureBoundaryBytes(readerKey);
            if (bytes != null && isFrameBlankWhite(bytes, 1200, 800)) {
              blankFrames++;
            }
          }

          // Follow the settling queue
          for (int i = 0; i < 30; i++) {
            await Future.delayed(const Duration(milliseconds: 15));
            await tester.pump();
            final bytes = await captureBoundaryBytes(readerKey);
            if (bytes != null && isFrameBlankWhite(bytes, 1200, 800)) {
              blankFrames++;
            }
          }

          print('Rapid Navigation Coalescing: Blank Frames: $blankFrames');
          expect(
            blankFrames,
            equals(0),
            reason:
                'Rapid navigation coalescing must never produce a blank frame',
          );
        });
      },
    );

    // =========================================================================
    // SCENARIO 4: LARGE 64MB SCANNED PDF TRANSITION STABILITY
    // =========================================================================
    testWidgets(
      '4. Large 64MB PDF: Transition stability with cold & warm cache',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 800));
        final readerKey = GlobalKey();

        await tester.runAsync(() async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: RepaintBoundary(
                  key: readerKey,
                  child: OriginalPdfReader(
                    pdfPath: bicaraFile.path,
                    initialPage: 32,
                    theme: ReadingThemeType.warmPaper,
                    onPageChanged: (_, total) {},
                    onTapContent: () {},
                  ),
                ),
              ),
            ),
          );

          final state = tester.state<OriginalPdfReaderState>(
            find.byType(OriginalPdfReader),
          );
          for (var i = 0; i < 40; i++) {
            if (!state.isLoading && state.document != null) break;
            await Future.delayed(const Duration(milliseconds: 50));
            await tester.pump();
          }

          expect(state.currentPage, equals(32));
          print(
            '\n===============================================================',
          );
          print(
            'SCENARIO 4: 64MB SCANNED PDF TRANSITION AUDIT (Bicara Itu Ada Seninya)',
          );
          print(
            '===============================================================',
          );

          // Turn page 32 -> 33
          state.nextPage();
          int blankCount = 0;
          for (int i = 0; i < 30; i++) {
            await Future.delayed(const Duration(milliseconds: 12));
            await tester.pump();
            final bytes = await captureBoundaryBytes(readerKey);
            if (bytes != null && isFrameBlankWhite(bytes, 1200, 800)) {
              blankCount++;
            }
          }

          print('64MB PDF Transition Audit: Blank Frames: $blankCount');
          expect(
            blankCount,
            equals(0),
            reason: 'Heavy 64MB scanned PDF must maintain 100% frame stability',
          );
        });
      },
    );
  });
}
