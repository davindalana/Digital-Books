// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:digital_books/features/processing/services/scanned_image_enhancer.dart';
import 'helpers/real_book_fixtures.dart';
import 'helpers/test_evidence_dir.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Phase 3.0.1.1: Visual Crop Comparison of Thin Strokes and Punctuation',
    () async {
      final evidenceDir = resolveTestEvidenceDir('enhancement_fix');
      Directory(evidenceDir).createSync(recursive: true);

      final lautFile = File(
        '${RealBookFixtures.downloadsDir}/Laut Bercerita (Leila S. Chudori).pdf',
      );
      final bicaraFile = File(
        '${RealBookFixtures.downloadsDir}/Bicara Itu Ada Seninya (Oh Su Hyang).pdf',
      );

      if (!checkFixtureOrSkip(lautFile) || !checkFixtureOrSkip(bicaraFile)) return;

      final lautDoc = await PdfDocument.openFile(lautFile.path);
      final bicaraDoc = await PdfDocument.openFile(bicaraFile.path);
      final lautPage = lautDoc.pages[14]; // Page 15
      // High-resolution 2.5x rendering for pixel inspection
      const scale = 2.5;
      final lautImage = await lautPage.render(
        width: (lautPage.width * scale).round(),
        height: (lautPage.height * scale).round(),
      );
      expect(lautImage, isNotNull);

      final w = lautImage!.width;
      final h = lautImage.height;
      final rawPixels = lautImage.pixels;

      Future<Uint8List> bgraToPng(Uint8List bgra, int width, int height) async {
        final comp = ui.PictureRecorder();
        final canvas = ui.Canvas(comp);
        final completer = Completer<ui.Image>();
        ui.decodeImageFromPixels(
          bgra,
          width,
          height,
          ui.PixelFormat.bgra8888,
          (img) => completer.complete(img),
        );
        final img = await completer.future;
        canvas.drawImage(img, ui.Offset.zero, ui.Paint());
        final picture = comp.endRecording();
        final rendered = await picture.toImage(width, height);
        final byteData = await rendered.toByteData(
          format: ui.ImageByteFormat.png,
        );
        img.dispose();
        rendered.dispose();
        picture.dispose();
        return byteData!.buffer.asUint8List();
      }

      Future<Uint8List> cropBgraToPng(
        Uint8List bgra,
        int fullW,
        int fullH,
        int cropX,
        int cropY,
        int cropW,
        int cropH,
      ) async {
        final cropBgra = Uint8List(cropW * cropH * 4);
        for (int y = 0; y < cropH; y++) {
          final srcRow = (cropY + y) * fullW * 4;
          final dstRow = y * cropW * 4;
          for (int x = 0; x < cropW; x++) {
            final srcIdx = srcRow + ((cropX + x) * 4);
            final dstIdx = dstRow + (x * 4);
            cropBgra[dstIdx] = bgra[srcIdx];
            cropBgra[dstIdx + 1] = bgra[srcIdx + 1];
            cropBgra[dstIdx + 2] = bgra[srcIdx + 2];
            cropBgra[dstIdx + 3] = bgra[srcIdx + 3];
          }
        }
        return bgraToPng(cropBgra, cropW, cropH);
      }

      // Process all 4 tiers
      final originalPng = await bgraToPng(rawPixels, w, h);
      await File(
        '$evidenceDir/laut_p15_full_original.png',
      ).writeAsBytes(originalPng);

      final gentlePixels = ScannedImageEnhancer.enhanceBgra(
        srcPixels: rawPixels,
        width: w,
        height: h,
        config: const ScanEnhancementConfig(
          isEnabled: true,
          intensity: ScanEnhancementIntensity.gentle,
        ),
      );
      final gentlePng = await bgraToPng(gentlePixels, w, h);
      await File(
        '$evidenceDir/laut_p15_full_gentle.png',
      ).writeAsBytes(gentlePng);

      final balancedPixels = ScannedImageEnhancer.enhanceBgra(
        srcPixels: rawPixels,
        width: w,
        height: h,
        config: const ScanEnhancementConfig(
          isEnabled: true,
          intensity: ScanEnhancementIntensity.balanced,
        ),
      );
      final balancedPng = await bgraToPng(balancedPixels, w, h);
      await File(
        '$evidenceDir/laut_p15_full_balanced.png',
      ).writeAsBytes(balancedPng);

      final strongPixels = ScannedImageEnhancer.enhanceBgra(
        srcPixels: rawPixels,
        width: w,
        height: h,
        config: const ScanEnhancementConfig(
          isEnabled: true,
          intensity: ScanEnhancementIntensity.strong,
        ),
      );
      final strongPng = await bgraToPng(strongPixels, w, h);
      await File(
        '$evidenceDir/laut_p15_full_strong.png',
      ).writeAsBytes(strongPng);

      // Dynamically locate actual non-white text bounding box on the page
      int minX = w, maxX = 0, minY = h, maxY = 0;
      for (int y = 0; y < h; y += 4) {
        final rowOffset = y * w * 4;
        for (int x = 0; x < w; x += 4) {
          final idx = rowOffset + (x * 4);
          final b = rawPixels[idx];
          final g = rawPixels[idx + 1];
          final r = rawPixels[idx + 2];
          final lum = (r * 77 + g * 150 + b * 29) >> 8;
          if (lum < 220) {
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
          }
        }
      }
      expect(minX < maxX && minY < maxY, isTrue, reason: 'Page must have detected text');

      // Crop a centered region inside the actual text bounding box containing dialogue and punctuation
      final textW = maxX - minX;
      final textH = maxY - minY;
      final cropX = minX + (textW * 0.1).round();
      final cropY = minY + (textH * 0.2).round();
      final cropW = (textW * 0.8).round();
      final cropH = (textH * 0.4).round();

      final cropOriginal = await cropBgraToPng(
        rawPixels,
        w,
        h,
        cropX,
        cropY,
        cropW,
        cropH,
      );
      await File(
        '$evidenceDir/crop_punctuation_original.png',
      ).writeAsBytes(cropOriginal);

      final cropGentle = await cropBgraToPng(
        gentlePixels,
        w,
        h,
        cropX,
        cropY,
        cropW,
        cropH,
      );
      await File(
        '$evidenceDir/crop_punctuation_gentle.png',
      ).writeAsBytes(cropGentle);

      final cropBalanced = await cropBgraToPng(
        balancedPixels,
        w,
        h,
        cropX,
        cropY,
        cropW,
        cropH,
      );
      await File(
        '$evidenceDir/crop_punctuation_balanced.png',
      ).writeAsBytes(cropBalanced);

      final cropStrong = await cropBgraToPng(
        strongPixels,
        w,
        h,
        cropX,
        cropY,
        cropW,
        cropH,
      );
      await File(
        '$evidenceDir/crop_punctuation_strong.png',
      ).writeAsBytes(cropStrong);

      // Guard: Crops must not be solid single color
      expect(cropOriginal.toSet().length, greaterThan(1));
      expect(cropGentle.toSet().length, greaterThan(1));
      expect(cropBalanced.toSet().length, greaterThan(1));
      expect(cropStrong.toSet().length, greaterThan(1));

      // Guard: Each tier must produce distinct PNG bytes
      final cropHashes = {
        sha256.convert(cropOriginal).toString(),
        sha256.convert(cropGentle).toString(),
        sha256.convert(cropBalanced).toString(),
        sha256.convert(cropStrong).toString(),
      };
      expect(
        cropHashes.length,
        equals(4),
        reason: 'Each enhancement tier must produce distinct punctuation crop pixels',
      );

      print('Visual crops generated in $evidenceDir');
      lautImage.dispose();
      await lautDoc.dispose();
      await bicaraDoc.dispose();
    },
  );
}
