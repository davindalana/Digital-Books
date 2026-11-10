// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:digital_books/features/processing/services/scanned_image_enhancer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Phase 3.0.1.1: Visual Crop Comparison of Thin Strokes and Punctuation',
    () async {
      const evidenceDir = 'docs/visual_evidence/enhancement_fix';
      Directory(evidenceDir).createSync(recursive: true);

      final lautFile = File(
        '/Users/davindalana/Downloads/Laut Bercerita (Leila S. Chudori).pdf',
      );
      final bicaraFile = File(
        '/Users/davindalana/Downloads/Bicara Itu Ada Seninya (Oh Su Hyang).pdf',
      );

      expect(lautFile.existsSync(), isTrue);
      expect(bicaraFile.existsSync(), isTrue);

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

      // Zoom crop on dialogue with quotation marks and commas (around middle of page)
      final cropX = (w * 0.18).round();
      final cropY = (h * 0.38).round();
      final cropW = (w * 0.65).round();
      final cropH = (h * 0.20).round();

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

      print('Visual crops generated in $evidenceDir');
      lautImage.dispose();
      await lautDoc.dispose();
      await bicaraDoc.dispose();
    },
  );
}
