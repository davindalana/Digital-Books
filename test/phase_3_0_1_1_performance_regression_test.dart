// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:digital_books/features/processing/services/scanned_image_enhancer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Phase 3.0.1.1: Comprehensive Performance, Latency & Memory Regression',
    () async {
      final bicaraFile = File(
        '/Users/davindalana/Downloads/Bicara Itu Ada Seninya (Oh Su Hyang).pdf',
      );
      expect(bicaraFile.existsSync(), isTrue);

      final initialRss = ProcessInfo.currentRss;

      // 1. Cold Document Open Latency (64 MB PDF)
      final openSw = Stopwatch()..start();
      final doc = await PdfDocument.openFile(bicaraFile.path);
      openSw.stop();
      final openMs = openSw.elapsedMilliseconds;

      expect(doc.pages.length, equals(255));

      // 2. High-Resolution Single Page Enhancement Latency across Gentle, Balanced, Strong
      const w = 1123;
      const h = 1684;
      final totalBytes = w * h * 4;
      final testPixels = Uint8List(totalBytes);
      for (int i = 0; i < totalBytes; i += 4) {
        testPixels[i] = 195;
        testPixels[i + 1] = 205;
        testPixels[i + 2] = 210;
        testPixels[i + 3] = 255;
      }

      final gentleSw = Stopwatch()..start();
      ScannedImageEnhancer.enhanceBgra(
        srcPixels: testPixels,
        width: w,
        height: h,
        config: const ScanEnhancementConfig(
          isEnabled: true,
          intensity: ScanEnhancementIntensity.gentle,
        ),
      );
      gentleSw.stop();
      final gentleMs = gentleSw.elapsedMilliseconds;

      final balancedSw = Stopwatch()..start();
      ScannedImageEnhancer.enhanceBgra(
        srcPixels: testPixels,
        width: w,
        height: h,
        config: const ScanEnhancementConfig(
          isEnabled: true,
          intensity: ScanEnhancementIntensity.balanced,
        ),
      );
      balancedSw.stop();
      final balancedMs = balancedSw.elapsedMilliseconds;

      final strongSw = Stopwatch()..start();
      ScannedImageEnhancer.enhanceBgra(
        srcPixels: testPixels,
        width: w,
        height: h,
        config: const ScanEnhancementConfig(
          isEnabled: true,
          intensity: ScanEnhancementIntensity.strong,
        ),
      );
      strongSw.stop();
      final strongMs = strongSw.elapsedMilliseconds;

      // 3. Multi-page Pipeline: Render + Adaptive Gutter + Enhancement for 8 consecutive pages
      final pipeSw = Stopwatch()..start();
      for (int p = 10; p < 18; p++) {
        final page = doc.pages[p];
        final img = await page.render(
          width: (page.width * 1.5).round(),
          height: (page.height * 1.5).round(),
        );
        if (img != null) {
          final isLeft = (p + 1) % 2 == 0;
          ScannedImageEnhancer.enhanceBgra(
            srcPixels: img.pixels,
            width: img.width,
            height: img.height,
            config: ScanEnhancementConfig(
              isEnabled: true,
              intensity: ScanEnhancementIntensity.balanced,
              isLeftPage: isLeft,
              removeGutterShadow: true,
            ),
          );
          img.dispose();
        }
      }
      pipeSw.stop();
      final totalPipeMs = pipeSw.elapsedMilliseconds;
      final perPageMs = totalPipeMs / 8.0;

      final finalRss = ProcessInfo.currentRss;
      final rssDeltaMb = (finalRss - initialRss) / (1024 * 1024);

      print(
        '\n===============================================================',
      );
      print('PHASE 3.0.1.1 PERFORMANCE & MEMORY REGRESSION BENCHMARK');
      print('===============================================================');
      print('Cold Document Open (64 MB PDF): $openMs ms (Target: <= 200 ms)');
      print('Gentle Enhancement (7.5 MB raw buffer): $gentleMs ms');
      print('Balanced Enhancement (7.5 MB raw buffer): $balancedMs ms');
      print('Strong Enhancement (7.5 MB raw buffer): $strongMs ms');
      print(
        '8-Page Full Pipeline (Render + Adaptive Gutter + Enhance): $totalPipeMs ms (${perPageMs.toStringAsFixed(1)} ms/page)',
      );
      print(
        'Process RSS Memory Delta: ${rssDeltaMb.toStringAsFixed(2)} MB (Budget: <= 150 MB)',
      );

      expect(openMs, lessThanOrEqualTo(200));
      expect(perPageMs, lessThanOrEqualTo(60.0));
      expect(rssDeltaMb, lessThanOrEqualTo(150.0));

      await doc.dispose();
    },
  );
}
