// ignore_for_file: avoid_print

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_books/features/processing/services/geometry_aware_pdf_extractor.dart';
import 'helpers/corpus_pdf_generator.dart';

void main() {
  test('Phase 2.7 Extraction Performance, Latency and Asset Memory Benchmark', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final tempDir = await Directory.systemTemp.createTemp('db_perf_bench_');
    final corpusDir = Directory('test/fixtures/corpus');
    if (!corpusDir.existsSync() || corpusDir.listSync().isEmpty) {
      await CorpusPdfGenerator.generateAllCorpusFiles(corpusDir);
    }

    final files = corpusDir.listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    print('\n===============================================================');
    print('PHASE 2.7 GEOMETRY-AWARE EXTRACTION PERFORMANCE SUITE');
    print('===============================================================\n');

    final initialRss = ProcessInfo.currentRss;
    int grandTotalPages = 0;
    int grandTotalLines = 0;
    int grandTotalImages = 0;
    int grandTotalImageBytes = 0;
    double grandTotalDuration = 0;

    for (final file in files) {
      final name = file.uri.pathSegments.last;
      final sw = Stopwatch()..start();
      final result = await GeometryAwarePdfExtractor.extractDocument(
        pdfFile: file,
        bookId: 'bench_${name.replaceAll('.pdf', '')}',
        imageOutputDir: tempDir,
        extractImagesToDisk: true,
      );
      sw.stop();

      final totalImgBytes = result.pages
          .expand((p) => p.images)
          .fold<int>(0, (sum, img) => sum + img.bytesLength);

      grandTotalPages += result.totalPages;
      grandTotalLines += result.totalTextLines;
      grandTotalImages += result.totalImages;
      grandTotalImageBytes += totalImgBytes;
      grandTotalDuration += result.durationMs;

      print('[$name]');
      print(
        '• Pages: ${result.totalPages} | Text Lines: ${result.totalTextLines} | Images: ${result.totalImages}',
      );
      print(
        '• Duration: ${result.durationMs.toStringAsFixed(2)} ms (${(result.durationMs / result.totalPages).toStringAsFixed(2)} ms/page)',
      );
      print(
        '• Text Layer: ${result.hasUsableTextLayer ? "YES (Selectable)" : "NO (Scanned)"}',
      );
      print('• Recommendation: ${result.recommendedReaderTier}');
      if (result.totalImages > 0) {
        print(
          '• Extracted Images Total Size: ${(totalImgBytes / 1024.0).toStringAsFixed(2)} KB',
        );
      }
      print('---------------------------------------------------------------');
    }

    final postRss = ProcessInfo.currentRss;
    final rssDeltaMb = (postRss - initialRss) / 1024.0 / 1024.0;

    print('\n===============================================================');
    print('GRAND TOTALS & AGGREGATE PERFORMANCE METRICS:');
    print('• Total Documents Processed: ${files.length}');
    print('• Total Pages Analyzed: $grandTotalPages');
    print('• Total Lines with Geometry: $grandTotalLines');
    print(
      '• Total Images Extracted: $grandTotalImages (${(grandTotalImageBytes / 1024.0).toStringAsFixed(2)} KB on disk)',
    );
    print(
      '• Total Extraction Duration: ${grandTotalDuration.toStringAsFixed(2)} ms',
    );
    print(
      '• Mean Extraction Latency: ${(grandTotalDuration / grandTotalPages).toStringAsFixed(2)} ms/page',
    );
    print('• Process RSS Memory Delta: ${rssDeltaMb.toStringAsFixed(2)} MB');
    print('===============================================================\n');

    expect(grandTotalPages, equals(14));
    expect(grandTotalLines, greaterThan(25));
    expect(grandTotalImages, equals(5));

    await tempDir.delete(recursive: true);
  });
}
