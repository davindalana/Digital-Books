// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:ui' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:digital_books/features/processing/models/extracted_page_geometry.dart';
import 'package:digital_books/features/processing/services/apple_vision_ocr_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 3.1 — Checkpoint A: Apple Vision OCR Engine Verification', () {
    const String downloadsDir = '/Users/davindalana/Downloads';
    final lautBerceritaFile = File('$downloadsDir/Laut Bercerita (Leila S. Chudori).pdf');
    final bicaraFile = File('$downloadsDir/Bicara Itu Ada Seninya (Oh Su Hyang).pdf');

    const ocrService = AppleVisionOcrService();

    setUpAll(() {
      expect(lautBerceritaFile.existsSync(), isTrue);
      expect(bicaraFile.existsSync(), isTrue);
      expect(ocrService.isAvailable, isTrue, reason: 'bin/vision_ocr must be compiled and available on macOS');
    });

    // 1. Service Availability & Configuration
    test('1. Service Availability: Binary is present and language models configured', () {
      expect(ocrService.isAvailable, isTrue);
      expect(File(ocrService.binaryPath).existsSync(), isTrue);
    });

    // 2. Real Scanned Novel Page (Laut Bercerita Page 15)
    test('2. Real Scanned Novel Page: High accuracy extraction & Indonesian text recognition', () async {
      const imgPath = 'docs/visual_evidence/enhancement_fix/laut_p15_full_original.png';
      expect(File(imgPath).existsSync(), isTrue);

      final result = await ocrService.processImage(
        imgPath,
        languages: const ['id-ID', 'en-US'],
      );

      print('\n===============================================================');
      print('CHECKPOINT A: VISION OCR ON LAUT BERCERITA P.15');
      print('===============================================================');
      print('Image dimensions: ${result.width} x ${result.height}');
      print('OCR Duration: ${result.durationMs.toStringAsFixed(1)} ms');
      print('Extracted Lines: ${result.lines.length}');
      expect(result.hasError, isFalse);
      expect(result.lines.length, greaterThanOrEqualTo(20));

      final allText = result.lines.map((l) => l.text).join('\n');
      print('Sample text excerpt (first 3 lines):');
      for (final l in result.lines.take(3)) {
        print(' - [conf=${l.confidence.toStringAsFixed(2)}, box=(${l.box.left.toStringAsFixed(3)}, ${l.box.top.toStringAsFixed(3)})] "${l.text}"');
      }

      // Verify specific Indonesian vocabulary and story elements
      expect(allText.contains('Setelah lebih dari sejam'), isTrue);
      expect(allText.contains('Manusia Pohon'), isTrue);
      expect(allText.contains('ombak'), isTrue);

      // Verify normalized coordinate system
      for (final line in result.lines) {
        expect(line.box.left, greaterThanOrEqualTo(0.0));
        expect(line.box.top, greaterThanOrEqualTo(0.0));
        expect(line.box.width, greaterThan(0.0));
        expect(line.box.height, greaterThan(0.0));
        expect(line.box.right, lessThanOrEqualTo(1.05)); // Tolerance for trailing punctuation
        expect(line.confidence, greaterThanOrEqualTo(0.50));
      }
    });

    // 3. Real Scanned Book Page (Bicara Itu Ada Seninya Page 33)
    test('3. Real Scanned Book Page: Indented paragraph detection and dialogue recognition', () async {
      const imgPath = 'docs/visual_evidence/scan_enhancement/bicara_p33_original.png';
      expect(File(imgPath).existsSync(), isTrue);

      final result = await ocrService.processImage(
        imgPath,
        languages: const ['id-ID', 'en-US'],
      );

      print('\n===============================================================');
      print('CHECKPOINT A: VISION OCR ON BICARA ITU ADA SENINYA P.33');
      print('===============================================================');
      print('OCR Duration: ${result.durationMs.toStringAsFixed(1)} ms');
      print('Extracted Lines: ${result.lines.length}');
      expect(result.hasError, isFalse);
      expect(result.lines.length, greaterThanOrEqualTo(25));

      final allText = result.lines.map((l) => l.text).join('\n');
      expect(allText.contains('Sayangnya kisah roti bagel'), isTrue);
      expect(allText.contains('Paul Robert Potts'), isTrue);

      // Find indented paragraph start lines vs standard body lines
      final indentedLines = result.lines.where((l) => l.box.left > 0.10).toList();
      final bodyLines = result.lines.where((l) => l.box.left <= 0.10).toList();

      expect(indentedLines, isNotEmpty, reason: 'Indented paragraphs must have higher left offset');
      expect(bodyLines, isNotEmpty);
      print('Detected ${indentedLines.length} indented paragraph starters and ${bodyLines.length} standard body lines');
    });

    // 4. Geometry Conversion: Maps to ExtractedPageGeometry
    test('4. Geometry Conversion: Converts normalized OCR lines to absolute ExtractedPageGeometry', () async {
      const imgPath = 'docs/visual_evidence/enhancement_fix/crop_text_original.png';
      final result = await ocrService.processImage(imgPath);
      expect(result.hasError, isFalse);

      const pageSize = Size(595.0, 842.0);
      const pageIndex = 14;
      final geometry = result.toExtractedPageGeometry(
        pageIndex: pageIndex,
        pageSize: pageSize,
      );

      expect(geometry.pageIndex, equals(pageIndex));
      expect(geometry.pageSize, equals(pageSize));
      expect(geometry.layerType, equals(PageLayerType.nativeText));
      expect(geometry.lines.length, equals(result.lines.length));

      for (final line in geometry.lines) {
        expect(line.pageIndex, equals(pageIndex));
        expect(line.bounds.left, greaterThanOrEqualTo(0.0));
        expect(line.bounds.top, greaterThanOrEqualTo(0.0));
        expect(line.bounds.width, lessThanOrEqualTo(pageSize.width));
        expect(line.fontSize, greaterThan(0.0));
        expect(line.words, isNotEmpty);
      }
    });

    // 5. Error Recovery: Gracefully handles missing files
    test('5. Error Recovery: Non-existent image file returns error without throwing exception', () async {
      final result = await ocrService.processImage('non_existent_file_path.png');
      expect(result.hasError, isTrue);
      expect(result.lines, isEmpty);
      expect(result.error, contains('does not exist'));
    });

    // 6. Direct PDF Page Processing Pipeline
    test('6. Direct PDF Page Processing: Renders and extracts a page directly from PdfDocument', () async {
      final doc = await PdfDocument.openFile(lautBerceritaFile.path);
      final page = doc.pages[14]; // Page 15

      final sw = Stopwatch()..start();
      final result = await ocrService.processPdfPage(
        page,
        scale: 1.5,
        languages: const ['id-ID', 'en-US'],
      );
      sw.stop();

      print('\n===============================================================');
      print('CHECKPOINT A: DIRECT PDF PAGE RENDER + OCR PIPELINE');
      print('===============================================================');
      print('Total Render + OCR Duration: ${sw.elapsedMilliseconds} ms');
      print('Recognized Lines: ${result.lines.length}');
      expect(result.hasError, isFalse);
      expect(result.lines.length, greaterThanOrEqualTo(20));

      await doc.dispose();
    });
  });
}
