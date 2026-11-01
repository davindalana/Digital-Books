// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:digital_books/features/processing/services/scanned_image_enhancer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 3.0.1.1 — Enhancement Defect Correction & Adaptive Gutter Audit', () {
    const String downloadsDir = '/Users/davindalana/Downloads';
    final lautBerceritaFile = File('$downloadsDir/Laut Bercerita (Leila S. Chudori).pdf');
    final bicaraFile = File('$downloadsDir/Bicara Itu Ada Seninya (Oh Su Hyang).pdf');

    setUpAll(() {
      expect(lautBerceritaFile.existsSync(), isTrue, reason: 'Laut Bercerita PDF must exist');
      expect(bicaraFile.existsSync(), isTrue, reason: 'Bicara Itu Ada Seninya PDF must exist');
    });

    // =========================================================================
    // PRIORITY 1: STRONG ENHANCEMENT AUDIT & THIN CHARACTER PRESERVATION
    // =========================================================================
    test('1. Strong Enhancement: Preserves character edge anti-aliasing while deepening ink', () async {
      final doc = await PdfDocument.openFile(lautBerceritaFile.path);
      final page = doc.pages[14]; // Page 15
      final img = await page.render(
        width: (page.width * 2.0).round(),
        height: (page.height * 2.0).round(),
      );
      expect(img, isNotNull);

      final w = img!.width;
      final h = img.height;
      final rawPixels = img.pixels;
      final totalPixels = w * h;

      Map<String, double> getStats(Uint8List pixels) {
        int white = 0, paperGray = 0, edge = 0, ink = 0;
        int sumLum = 0;
        for (int i = 0; i < totalPixels * 4; i += 4) {
          final lum = (pixels[i + 2] * 77 + pixels[i + 1] * 150 + pixels[i] * 29) >> 8;
          sumLum += lum;
          if (lum >= 240) {
            white++;
          } else if (lum >= 170) {
            paperGray++;
          } else if (lum >= 90) {
            edge++;
          } else {
            ink++;
          }
        }
        return {
          'meanLum': sumLum / totalPixels,
          'whitePct': white / totalPixels * 100,
          'paperPct': paperGray / totalPixels * 100,
          'edgePct': edge / totalPixels * 100,
          'inkPct': ink / totalPixels * 100,
        };
      }

      final rawStats = getStats(rawPixels);

      // Enhance with all three tiers
      final gentlePixels = ScannedImageEnhancer.enhanceBgra(
        srcPixels: rawPixels,
        width: w,
        height: h,
        config: const ScanEnhancementConfig(isEnabled: true, intensity: ScanEnhancementIntensity.gentle),
      );
      final gentleStats = getStats(gentlePixels);

      final balancedPixels = ScannedImageEnhancer.enhanceBgra(
        srcPixels: rawPixels,
        width: w,
        height: h,
        config: const ScanEnhancementConfig(isEnabled: true, intensity: ScanEnhancementIntensity.balanced),
      );
      final balancedStats = getStats(balancedPixels);

      final strongPixels = ScannedImageEnhancer.enhanceBgra(
        srcPixels: rawPixels,
        width: w,
        height: h,
        config: const ScanEnhancementConfig(isEnabled: true, intensity: ScanEnhancementIntensity.strong),
      );
      final strongStats = getStats(strongPixels);

      print('\n===============================================================');
      print('PRIORITY 1: REAL-WORLD SCANNED NOVEL ENHANCEMENT METRICS (P.15)');
      print('===============================================================');
      print('ORIGINAL: White ${rawStats['whitePct']!.toStringAsFixed(1)}% | Edge ${rawStats['edgePct']!.toStringAsFixed(2)}% | Ink ${rawStats['inkPct']!.toStringAsFixed(2)}%');
      print('GENTLE:   White ${gentleStats['whitePct']!.toStringAsFixed(1)}% | Edge ${gentleStats['edgePct']!.toStringAsFixed(2)}% | Ink ${gentleStats['inkPct']!.toStringAsFixed(2)}%');
      print('BALANCED: White ${balancedStats['whitePct']!.toStringAsFixed(1)}% | Edge ${balancedStats['edgePct']!.toStringAsFixed(2)}% | Ink ${balancedStats['inkPct']!.toStringAsFixed(2)}%');
      print('STRONG:   White ${strongStats['whitePct']!.toStringAsFixed(1)}% | Edge ${strongStats['edgePct']!.toStringAsFixed(2)}% | Ink ${strongStats['inkPct']!.toStringAsFixed(2)}%');

      // 1. Paper background is cleanly lifted
      expect(gentleStats['whitePct'], greaterThan(rawStats['whitePct']!));
      expect(balancedStats['whitePct'], greaterThanOrEqualTo(gentleStats['whitePct']!));
      expect(strongStats['whitePct'], greaterThanOrEqualTo(balancedStats['whitePct']!));

      // 2. Solid ink density is deepened without washout
      expect(strongStats['inkPct'], greaterThan(rawStats['inkPct']! * 1.30),
          reason: 'Strong mode must deepen text ink by at least +30%');

      // 3. Edge anti-aliasing preservation: edge pixel percentage must remain substantial (>= 0.35%)
      expect(strongStats['edgePct'], greaterThanOrEqualTo(0.35),
          reason: 'Tamed Strong mode must retain edge pixels >= 0.35% to protect thin strokes and punctuation');

      img.dispose();
      await doc.dispose();
    });

    // =========================================================================
    // PRIORITY 2: ADAPTIVE GUTTER SHADOW DETECTION ON REAL DOCUMENTS
    // =========================================================================
    test('2. Adaptive Gutter: Accurately differentiates flat pages from real binding shadows', () async {
      // 1. Laut Bercerita P.15: Flat novel scan with clean white inner margin
      final lautDoc = await PdfDocument.openFile(lautBerceritaFile.path);
      final lautP15 = lautDoc.pages[14];
      final lautImg = await lautP15.render(
        width: (lautP15.width * 1.0).round(),
        height: (lautP15.height * 1.0).round(),
      );
      expect(lautImg, isNotNull);

      final lautLeftConfig = const ScanEnhancementConfig(
        isEnabled: true,
        removeGutterShadow: true,
        isLeftPage: true, // test gutter on right edge
      );
      final lautEnhanced = ScannedImageEnhancer.enhanceBgra(
        srcPixels: lautImg!.pixels,
        width: lautImg.width,
        height: lautImg.height,
        config: lautLeftConfig,
      );

      // Verify that flat margin at right edge received NO artificial gutter boost
      final rightEdgeIdx = (lautImg.width - 1) * 4;
      final lautRawLum = (lautImg.pixels[rightEdgeIdx + 2] * 77 + lautImg.pixels[rightEdgeIdx + 1] * 150 + lautImg.pixels[rightEdgeIdx] * 29) >> 8;
      final lautEnhLum = lautEnhanced[rightEdgeIdx];
      print('Laut Bercerita P.15 Gutter Margin: Raw Lum = $lautRawLum, Enhanced Lum = $lautEnhLum (Delta = ${lautEnhLum - lautRawLum})');
      // Margin was already clean paper, so delta is strictly bounded
      expect(lautEnhLum - lautRawLum, lessThanOrEqualTo(5),
          reason: 'Flat margin must not receive artificial gutter brightness offset');

      lautImg.dispose();
      await lautDoc.dispose();

      // 2. Bicara Itu Ada Seninya P.1: Scanned book page with strong spine shadow
      final bicaraDoc = await PdfDocument.openFile(bicaraFile.path);
      final bicaraP1 = bicaraDoc.pages[0];
      final bicaraImg = await bicaraP1.render(
        width: (bicaraP1.width * 1.0).round(),
        height: (bicaraP1.height * 1.0).round(),
      );
      expect(bicaraImg, isNotNull);

      final bicaraRightConfig = const ScanEnhancementConfig(
        isEnabled: true,
        removeGutterShadow: true,
        isLeftPage: false, // Right page: gutter on left edge (x=0)
      );
      final bicaraEnhanced = ScannedImageEnhancer.enhanceBgra(
        srcPixels: bicaraImg!.pixels,
        width: bicaraImg.width,
        height: bicaraImg.height,
        config: bicaraRightConfig,
      );

      int sumRawShadowPaper = 0;
      int sumEnhShadowPaper = 0;
      int countShadowPaper = 0;
      final gutterW = (bicaraImg.width * 0.16).round();
      for (int y = 0; y < bicaraImg.height; y += 4) {
        for (int x = 2; x < gutterW; x += 4) {
          final idx = (y * bicaraImg.width + x) * 4;
          final rawL = (bicaraImg.pixels[idx + 2] * 77 + bicaraImg.pixels[idx + 1] * 150 + bicaraImg.pixels[idx] * 29) >> 8;
          if (rawL >= 100) {
            sumRawShadowPaper += rawL;
            sumEnhShadowPaper += bicaraEnhanced[idx];
            countShadowPaper++;
          }
        }
      }
      expect(countShadowPaper, greaterThan(0));
      final meanRawShadow = sumRawShadowPaper / countShadowPaper;
      final meanEnhShadow = sumEnhShadowPaper / countShadowPaper;
      print('Bicara Itu Ada Seninya P.1 Gutter Shadow Paper: Raw Mean = ${meanRawShadow.toStringAsFixed(1)}, Enhanced Mean = ${meanEnhShadow.toStringAsFixed(1)} (Lift = ${(meanEnhShadow - meanRawShadow).toStringAsFixed(1)})');
      expect(meanEnhShadow, greaterThan(meanRawShadow),
          reason: 'Shadowed paper in gutter margin must be brightened by adaptive gutter compensation');

      // 3. Text protection near gutter edge:
      // Verify that dark ink (lum < 90) does NOT get washed out by gutter compensation
      const w = 50, h = 50;
      final synthPixels = Uint8List(w * h * 4);
      // Gutter shadow with dark text right at the inner edge (x=0)
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final idx = (y * w + x) * 4;
          int lum;
          if (x == 0) {
            lum = 40; // Dark text ink near margin
          } else {
            // Spine shadow gradient: 160 at edge to 235 at core
            final t = math.min(1.0, x / 10.0);
            lum = (160 + (t * 75)).round();
          }
          synthPixels[idx] = lum;
          synthPixels[idx + 1] = lum;
          synthPixels[idx + 2] = lum;
          synthPixels[idx + 3] = 255;
        }
      }

      final synthEnhanced = ScannedImageEnhancer.enhanceBgra(
        srcPixels: synthPixels,
        width: w,
        height: h,
        config: const ScanEnhancementConfig(
          isEnabled: true,
          removeGutterShadow: true,
          isLeftPage: false, // Gutter on left
          intensity: ScanEnhancementIntensity.balanced,
        ),
      );

      // Dark text at x=0 must remain deep dark (< 50) and not washed out to paper gray
      final textAtGutter = synthEnhanced[0];
      print('Text at Gutter Margin: Raw = 40, Enhanced = $textAtGutter (Text Preserved: ${textAtGutter < 50})');
      expect(textAtGutter, lessThan(50),
          reason: 'Dark text at gutter margin must remain crisp dark ink and not be bleached by gutter boost');

      bicaraImg.dispose();
      await bicaraDoc.dispose();
    });
  });
}
