// ignore_for_file: avoid_print, prefer_interpolation_to_compose_strings, depend_on_referenced_packages, unused_import

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:path/path.dart' as p;
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/features/processing/services/apple_vision_ocr_service.dart';
import 'package:digital_books/features/processing/services/ocr_semantic_pipeline.dart';
import 'helpers/real_book_fixtures.dart';

class MockPathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final Directory tempDir;
  MockPathProviderPlatform(this.tempDir);

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir.path;

  @override
  Future<String?> getTemporaryPath() async => tempDir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final ocrService = AppleVisionOcrService();
  late Directory tempDir;
  late DatabaseService dbService;

  final lautBerceritaPath =
      p.join(RealBookFixtures.downloadsDir, 'Laut Bercerita (Leila S. Chudori).pdf');
  final bicaraSeninyaPath =
      p.join(RealBookFixtures.downloadsDir, 'Bicara Itu Ada Seninya (Oh Su Hyang).pdf');
  final mrXPath =
      p.join(RealBookFixtures.downloadsDir, 'Kesetiaan Mr X The Devotion Of Suspect X (Keigo Higashino).pdf');

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('db_large_scale_ocr_test_');
    PathProviderPlatform.instance = MockPathProviderPlatform(tempDir);
    final db = AppDatabase(NativeDatabase.memory());
    dbService = DatabaseService(db);
    await ocrService.ensureBinaryAvailable();

    // Insert book record to satisfy foreign key constraints
    await dbService.insertBook(
      BooksCompanion.insert(
        id: 'laut-bercerita-50p-audit',
        title: 'Laut Bercerita',
        author: 'Leila S. Chudori',
        originalPdfPath: lautBerceritaPath,
        totalPages: const Value(379),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
  });

  tearDownAll(() async {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Phase 3.1.1 — Large-Scale Continuous OCR & Systematic 30-Page Sampling', () {
    test(
      '1. Systematic 30-Page Sampling Across Beginning, Middle, and End of 3 Books',
      () async {
        if (!checkFixtureOrSkip(lautBerceritaPath) ||
            !checkFixtureOrSkip(bicaraSeninyaPath) ||
            !checkFixtureOrSkip(mrXPath)) {
          return;
        }
        final samplePlans = [
          {
            'book': 'Laut Bercerita',
            'path': lautBerceritaPath,
            'pages': [14, 15, 16, 17, 150, 151, 152, 360, 361, 362], // 10 pages
          },
          {
            'book': 'Bicara Itu Ada Seninya',
            'path': bicaraSeninyaPath,
            'pages': [10, 11, 12, 13, 120, 121, 122, 240, 241, 242], // 10 pages
          },
          {
            'book': 'Kesetiaan Mr X',
            'path': mrXPath,
            'pages': [11, 12, 13, 14, 140, 141, 142, 280, 281, 282], // 10 pages
          },
        ];

        final resultsByBook = <String, List<Map<String, dynamic>>>{};

        for (final plan in samplePlans) {
          final bookTitle = plan['book'] as String;
          final pdfPath = plan['path'] as String;
          final targetPages = plan['pages'] as List<int>;
          resultsByBook[bookTitle] = [];

          final pdfDoc = await PdfDocument.openFile(pdfPath);

          for (final pageIdx in targetPages) {
            final page = pdfDoc.pages[pageIdx];
            final img = await page.render(
              width: (page.width * 1.5).round(),
              height: (page.height * 1.5).round(),
            );
            final uiImg = await img?.createImage();
            final byteData = await uiImg?.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final pngBytes = byteData!.buffer.asUint8List();

            final imgPath = p.join(
              tempDir.path,
              'sample_${bookTitle.replaceAll(" ", "_")}_p$pageIdx.png',
            );
            File(imgPath).writeAsBytesSync(pngBytes);

            final sw = Stopwatch()..start();
            final ocrResult = await ocrService.processImage(imgPath);
            sw.stop();

            final charCount = ocrResult.lines.fold<int>(
              0,
              (sum, l) => sum + l.text.length,
            );
            final wordCount = ocrResult.lines.fold<int>(
              0,
              (sum, l) =>
                  sum +
                  l.text
                      .split(RegExp(r'\s+'))
                      .where((w) => w.isNotEmpty)
                      .length,
            );
            final avgConfidence = ocrResult.lines.isEmpty
                ? 0.0
                : ocrResult.lines.fold<double>(
                        0.0,
                        (s, l) => s + l.confidence,
                      ) /
                      ocrResult.lines.length;

            resultsByBook[bookTitle]!.add({
              'pageIndex': pageIdx,
              'charCount': charCount,
              'wordCount': wordCount,
              'lineCount': ocrResult.lines.length,
              'avgConfidence': avgConfidence,
              'durationMs': sw.elapsedMilliseconds,
            });

            // Delete temporary render to prevent disk bloat
            if (File(imgPath).existsSync()) {
              File(imgPath).deleteSync();
            }
          }

          await pdfDoc.dispose();
        }

        print('\n' + '=' * 80);
        print('SYSTEMATIC 30-PAGE REPRESENTATIVE SAMPLING REPORT');
        print('=' * 80);
        print(
          'Book Title'.padRight(24) +
              '| Page Range Tested'.padRight(22) +
              '| Total Words'.padRight(14) +
              '| Avg Latency'.padRight(14) +
              '| Avg Confidence',
        );
        print('-' * 80);

        resultsByBook.forEach((book, rows) {
          final totalWords = rows.fold<int>(
            0,
            (s, r) => s + (r['wordCount'] as int),
          );
          final avgLatency =
              rows.fold<int>(0, (s, r) => s + (r['durationMs'] as int)) /
              rows.length;
          final avgConf =
              rows.fold<double>(
                0.0,
                (s, r) => s + (r['avgConfidence'] as double),
              ) /
              rows.length;
          final pageSummary =
              '${rows.first['pageIndex']}..${rows.last['pageIndex']} (10 pgs)';

          print(
            book.padRight(24) +
                '| ${pageSummary.padRight(20)}' +
                '| ${totalWords.toString().padRight(12)}' +
                '| ${avgLatency.toStringAsFixed(1)} ms'.padRight(14) +
                '| ${(avgConf * 100).toStringAsFixed(2)}%',
          );

          expect(
            totalWords,
            greaterThan(1000),
            reason:
                '$book should have meaningful extracted text across 10 pages',
          );
        });
        print('=' * 80 + '\n');
      },
    );

    test(
      '2. Continuous 50-Page Uninterrupted Batch Test & Memory/Performance Telemetry',
      () async {
        if (!checkFixtureOrSkip(lautBerceritaPath)) return;
        final pdfDoc = await PdfDocument.openFile(lautBerceritaPath);
        final startPage = 14;
        final pageCount = 50; // Pages 14 to 63
        final durations = <int>[];
        final rssSnapshots = <int, double>{};

        final initialRssMb = ProcessInfo.currentRss / (1024 * 1024);
        rssSnapshots[0] = initialRssMb;

        print('\n' + '=' * 80);
        print('CONTINUOUS 50-PAGE BATCH TELEMETRY (LAUT BERCERITA P.14-P.63)');
        print('=' * 80);

        int totalExtractedChars = 0;
        int totalExtractedWords = 0;

        for (int i = 0; i < pageCount; i++) {
          final pageIdx = startPage + i;
          final page = pdfDoc.pages[pageIdx];

          final img = await page.render(
            width: (page.width * 1.5).round(),
            height: (page.height * 1.5).round(),
          );
          final uiImg = await img?.createImage();
          final byteData = await uiImg?.toByteData(
            format: ui.ImageByteFormat.png,
          );
          final pngBytes = byteData!.buffer.asUint8List();

          final imgPath = p.join(tempDir.path, 'continuous_p$pageIdx.png');
          File(imgPath).writeAsBytesSync(pngBytes);

          final sw = Stopwatch()..start();
          final ocrResult = await ocrService.processImage(imgPath);
          sw.stop();

          durations.add(sw.elapsedMilliseconds);

          // Store into Drift database to measure persistence throughput and table growth
          await dbService.insertOcrPage(
            OcrPagesCompanion.insert(
              id: 'ocr-laut-$pageIdx',
              bookId: 'laut-bercerita-50p-audit',
              pageIndex: pageIdx,
              status: const Value('completed'),
              charCount: Value(
                ocrResult.lines.fold<int>(0, (s, l) => s + l.text.length),
              ),
              durationMs: Value(sw.elapsedMilliseconds.toDouble()),
              linesJson: jsonEncode(
                ocrResult.lines.map((l) => l.toJson()).toList(),
              ),
              createdAt: DateTime.now(),
            ),
          );

          totalExtractedChars += ocrResult.lines.fold<int>(
            0,
            (s, l) => s + l.text.length,
          );
          totalExtractedWords += ocrResult.lines.fold<int>(
            0,
            (s, l) =>
                s +
                l.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length,
          );

          if (File(imgPath).existsSync()) {
            File(imgPath).deleteSync();
          }

          // Snapshot RSS every 10 pages
          if ((i + 1) % 10 == 0) {
            final curRssMb = ProcessInfo.currentRss / (1024 * 1024);
            rssSnapshots[i + 1] = curRssMb;
            print(
              'Completed ${i + 1}/50 pages | Current RSS: ${curRssMb.toStringAsFixed(2)} MB (+${(curRssMb - initialRssMb).toStringAsFixed(2)} MB) | Last Page: ${sw.elapsedMilliseconds} ms',
            );
          }
        }

        await pdfDoc.dispose();

        // Compute statistics
        durations.sort();
        final minDuration = durations.first;
        final maxDuration = durations.last;
        final medianDuration = durations[durations.length ~/ 2];
        final p95Duration = durations[(durations.length * 0.95).floor()];
        final avgDuration =
            durations.reduce((a, b) => a + b) / durations.length;

        // Verify database record count
        final savedPages = await dbService.getOcrPagesForBook(
          'laut-bercerita-50p-audit',
        );
        expect(savedPages.length, equals(50));

        final finalRssMb = ProcessInfo.currentRss / (1024 * 1024);
        final rssDelta = finalRssMb - initialRssMb;

        print('-' * 80);
        print('CONTINUOUS RUN METRICS SUMMARY:');
        print('  Total Pages Processed:     50');
        print('  Total Words Extracted:     $totalExtractedWords');
        print('  Total Chars Extracted:     $totalExtractedChars');
        print(
          '  Average Processing Time:   ${avgDuration.toStringAsFixed(1)} ms/page',
        );
        print('  Min Latency:               $minDuration ms');
        print('  Median Latency (p50):      $medianDuration ms');
        print('  95th Percentile (p95):     $p95Duration ms');
        print('  Max Latency:               $maxDuration ms');
        print(
          '  Initial RSS Memory:        ${initialRssMb.toStringAsFixed(2)} MB',
        );
        print(
          '  Final RSS Memory:          ${finalRssMb.toStringAsFixed(2)} MB',
        );
        print(
          '  Net RSS Delta:             ${rssDelta >= 0 ? "+" : ""}${rssDelta.toStringAsFixed(2)} MB',
        );
        print('=' * 80 + '\n');

        // Assert bounded latency and memory:
        // Average duration per page must be under 350 ms
        expect(avgDuration, lessThan(350.0));
        // Memory growth over 50 continuous pages must not exceed 250 MB (strict bounded memory check)
        expect(
          rssDelta,
          lessThan(250.0),
          reason:
              'RSS memory must remain strictly bounded over continuous 50-page run',
        );
      },
    );

    test(
      '3. Semantic Pipeline Assembly & Document Serialization from 50 OCR Pages',
      () async {
        // Reconstruct BookDocument from the 50 OCR pages saved in test 2
        final pages = await dbService.getOcrPagesForBook(
          'laut-bercerita-50p-audit',
        );
        expect(pages.length, equals(50));

        final pipeline = OcrSemanticPipeline(dbService);
        final sw = Stopwatch()..start();
        final bookDoc = await pipeline.reconstructBook(
          bookId: 'laut-bercerita-50p-audit',
          pdfPath: lautBerceritaPath,
          title: 'Laut Bercerita',
          author: 'Leila S. Chudori',
        );
        sw.stop();

        expect(bookDoc, isNotNull);
        final jsonStr = jsonEncode(bookDoc!.toJson());
        final docSizeBytes = utf8.encode(jsonStr).length;
        final docSizeKb = docSizeBytes / 1024.0;

        print('\n' + '=' * 80);
        print('50-PAGE RECONSTRUCTED BOOK DOCUMENT ARTIFACT REPORT');
        print('=' * 80);
        print('  Chapters Detected:         ${bookDoc.chapters.length}');
        print(
          '  Total Book Blocks:         ${bookDoc.chapters.fold<int>(0, (s, c) => s + c.blocks.length)}',
        );
        print('  Assembly Duration:         ${sw.elapsedMilliseconds} ms');
        print(
          '  JSON Document Size:        ${docSizeKb.toStringAsFixed(2)} KB',
        );
        print('=' * 80 + '\n');

        expect(bookDoc.chapters, isNotEmpty);
        expect(bookDoc.chapters.first.blocks, isNotEmpty);
        expect(
          docSizeKb,
          lessThan(1500.0),
          reason:
              '50-page structured book document must be compact and under 1.5 MB',
        );
      },
    );
  });
}
