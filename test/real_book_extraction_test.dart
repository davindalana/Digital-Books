// ignore_for_file: avoid_print

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:digital_books/features/processing/services/geometry_aware_pdf_extractor.dart';
import 'helpers/real_book_fixtures.dart';

void main() {
  test('Evaluate Geometry-Aware Extractor on Real User Books', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final tempDir = await Directory.systemTemp.createTemp(
      'db_real_books_bench_',
    );

    final lbFile = File(
      p.join(RealBookFixtures.originalsDir, '8565c1aa-0bb7-4876-8fd6-38ce318d3ed4.pdf'),
    );
    if (!checkFixtureOrSkip(lbFile)) {
      await tempDir.delete(recursive: true);
      return;
    }
    if (lbFile.existsSync()) {
      print('\n--- Evaluating Real User Book: Laut Bercerita ---');
      // Test first 20 pages
      final sw = Stopwatch()..start();
      final result = await GeometryAwarePdfExtractor.extractDocument(
        pdfFile: lbFile,
        bookId: 'real_laut_bercerita_eval',
        imageOutputDir: tempDir,
        extractImagesToDisk: false,
      );
      sw.stop();

      print('• Total Pages: ${result.totalPages}');
      print('• Total Text Lines with Geometry: ${result.totalTextLines}');
      print('• Total Images Detected: ${result.totalImages}');
      print('• Has Usable Text Layer: ${result.hasUsableTextLayer}');
      print('• Layer Breakdown: ${result.layerBreakdown}');
      print('• Recommendation: ${result.recommendedReaderTier}');
      print(
        '• Duration for entire 394-page book: ${sw.elapsedMilliseconds} ms (${(sw.elapsedMilliseconds / result.totalPages).toStringAsFixed(2)} ms/page)',
      );

      // Laut Bercerita has JBIG2 raster pages with 0 native vector text lines
      expect(result.totalTextLines, equals(0));
      expect(result.hasUsableTextLayer, isFalse);
      expect(result.recommendedReaderTier, contains('Original PDF Reader'));
    }

    await tempDir.delete(recursive: true);
  });
}
