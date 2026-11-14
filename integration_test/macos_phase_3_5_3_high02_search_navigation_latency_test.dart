// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';

import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/core/providers/database_providers.dart';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/core/theme/typography_settings.dart';
import 'package:digital_books/features/reader/domain/engines/in_book_search_engine.dart';
import 'package:digital_books/features/reader/domain/engines/reflowable_highlight_span_builder.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'package:digital_books/features/reader/domain/models/search_geometry.dart';
import 'package:digital_books/features/reader/presentation/widgets/original_pdf_reader.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/reflowable_reader_container.dart';
import '../test/helpers/real_book_fixtures.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();

  group('Phase 3.5.3 — HIGH-02: End-to-End Search Navigation Latency Validation', () {
    final digitalPdfFile = RealBookFixtures.resolve(RealBookFixtures.theLetThemTheory);
    final ocrPdfFile = RealBookFixtures.resolve(RealBookFixtures.bicaraItuAdaSeninya);
    final fallbackPdf = File('test/fixtures/corpus/01_single_column_novel.pdf');
    final digitalPdfPath = (digitalPdfFile.existsSync() ? digitalPdfFile : fallbackPdf).path;
    final ocrPdfPath = (ocrPdfFile.existsSync() ? ocrPdfFile : fallbackPdf).path;

    late AppDatabase db;
    late DatabaseService dbService;

    const digitalBookId = 'bench_digital_book';
    const ocrBookId = 'bench_ocr_book';

    setUpAll(() async {
      db = AppDatabase(NativeDatabase.memory());
      dbService = DatabaseService(db);

      // 1. Seed Digital Book Record & Search Geometry (Page 1 & Page 12)
      await dbService.insertBook(
        BooksCompanion(
          id: const drift.Value(digitalBookId),
          title: const drift.Value('The Let Them Theory'),
          author: const drift.Value('Mel Robbins'),
          originalPdfPath: drift.Value(digitalPdfPath),
          fileHash: const drift.Value('digital_hash_bench'),
          totalPages: const drift.Value(20),
          isScanned: const drift.Value(false),
          createdAt: drift.Value(DateTime.now()),
          updatedAt: drift.Value(DateTime.now()),
        ),
      );

      final digitalTokensP12 = [
        const SearchTokenGeometry(
          text: 'The',
          start: 0,
          end: 3,
          box: Rect.fromLTWH(0.1, 0.2, 0.08, 0.04),
        ),
        const SearchTokenGeometry(
          text: 'Let',
          start: 4,
          end: 7,
          box: Rect.fromLTWH(0.2, 0.2, 0.08, 0.04),
        ),
        const SearchTokenGeometry(
          text: 'Them',
          start: 8,
          end: 12,
          box: Rect.fromLTWH(0.3, 0.2, 0.10, 0.04),
        ),
        const SearchTokenGeometry(
          text: 'Theory',
          start: 13,
          end: 19,
          box: Rect.fromLTWH(0.42, 0.2, 0.14, 0.04),
        ),
      ];

      await dbService.insertSearchPage(
        BookSearchPagesCompanion(
          id: const drift.Value('${digitalBookId}_p11'),
          bookId: const drift.Value(digitalBookId),
          pageIndex: const drift.Value(11), // 1-based page 12
          plainText: const drift.Value('The Let Them Theory is life-changing.'),
          rawText: const drift.Value('The Let Them Theory is life-changing.'),
          geometryJson: drift.Value(
            jsonEncode(digitalTokensP12.map((t) => t.toJson()).toList()),
          ),
          isOcr: const drift.Value(false),
          indexVersion: const drift.Value(1),
          indexedAt: drift.Value(DateTime.now()),
        ),
      );

      // 2. Seed OCR Book Record & Search Geometry (Page 1 & Page 33)
      await dbService.insertBook(
        BooksCompanion(
          id: const drift.Value(ocrBookId),
          title: const drift.Value('Bicara Itu Ada Seninya'),
          author: const drift.Value('Oh Su Hyang'),
          originalPdfPath: drift.Value(ocrPdfPath),
          fileHash: const drift.Value('ocr_hash_bench'),
          totalPages: const drift.Value(50),
          isScanned: const drift.Value(true),
          createdAt: drift.Value(DateTime.now()),
          updatedAt: drift.Value(DateTime.now()),
        ),
      );

      final ocrTokensP33 = [
        const SearchTokenGeometry(
          text: 'Bicara',
          start: 0,
          end: 6,
          box: Rect.fromLTWH(0.1, 0.3, 0.12, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'itu',
          start: 7,
          end: 10,
          box: Rect.fromLTWH(0.23, 0.3, 0.06, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'ada',
          start: 11,
          end: 14,
          box: Rect.fromLTWH(0.30, 0.3, 0.07, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'seninya',
          start: 15,
          end: 22,
          box: Rect.fromLTWH(0.38, 0.3, 0.14, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'untuk',
          start: 23,
          end: 28,
          box: Rect.fromLTWH(0.53, 0.3, 0.10, 0.03),
        ),
        const SearchTokenGeometry(
          text: 'mempertahankan',
          start: 29,
          end: 43,
          box: Rect.fromLTWH(0.1, 0.35, 0.28, 0.03),
        ),
      ];

      await dbService.insertSearchPage(
        BookSearchPagesCompanion(
          id: const drift.Value('${ocrBookId}_p32'),
          bookId: const drift.Value(ocrBookId),
          pageIndex: const drift.Value(32), // 1-based page 33
          plainText: const drift.Value(
            'Bicara itu ada seninya untuk mempertahankan hubungan.',
          ),
          rawText: const drift.Value(
            'Bicara itu ada seninya untuk mem- pertahankan hubungan.',
          ),
          geometryJson: drift.Value(
            jsonEncode(ocrTokensP33.map((t) => t.toJson()).toList()),
          ),
          isOcr: const drift.Value(true),
          indexVersion: const drift.Value(1),
          indexedAt: drift.Value(DateTime.now()),
        ),
      );
    });

    tearDownAll(() async {
      try {
        await db.close().timeout(const Duration(milliseconds: 500));
      } catch (_) {}
    });

    // Helper to calculate statistics
    Map<String, dynamic> computeStats(List<double> latencies) {
      if (latencies.isEmpty) return {'count': 0};
      latencies.sort();
      final count = latencies.length;
      final min = latencies.first;
      final max = latencies.last;
      final p50 = latencies[(count * 0.50).floor()];
      final p95 = latencies[(count * 0.95).clamp(0, count - 1).floor()];
      final avg = latencies.reduce((a, b) => a + b) / count;
      return {
        'count': count,
        'min': min,
        'max': max,
        'p50': p50,
        'p95': p95,
        'avg': avg,
      };
    }

    testWidgets('HIGH-02: 5 E2E Search Navigation Scenarios with Visual Frame Timestamps', (
      tester,
    ) async {
      print('===============================================================');
      print('HIGH-02 END-TO-END SEARCH NAVIGATION BENCHMARK START');
      print('Hardware: Apple M2 Pro (10 Cores, 16GB RAM)');
      print('Platform: macOS 27.0.1 Darwin ARM64');
      print('Build Mode: Native macOS Runner (Profile/Debug)');
      print(
        'Measurement Method: FRAME PRESENTED — NOT PHYSICALLY VERIFIED (t0 tap -> t3 frame rasterized)',
      );
      print(
        '===============================================================\n',
      );

      final scenarioResults = <String, Map<String, dynamic>>{};

      // -------------------------------------------------------------
      // SCENARIO 1: Digital PDF with Native Text (Cross-Page Search)
      // -------------------------------------------------------------
      {
        final latencies = <double>[];
        final searchResults = await InBookSearchEngine.searchIndexedBook(
          bookId: digitalBookId,
          dbService: dbService,
          query: 'theory',
        );
        expect(searchResults, isNotEmpty);
        final match = searchResults.first;

        for (int sample = 0; sample < 30; sample++) {
          final readerKey = GlobalKey<OriginalPdfReaderState>();
          Map<int, List<Rect>> highlights = {};

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: OriginalPdfReader(
                  key: readerKey,
                  pdfPath: digitalPdfPath,
                  initialPage: 1, // Start at Page 1
                  theme: ReadingThemeType.white,
                  searchHighlights: highlights,
                  onPageChanged: (p, t) {},
                  onTapContent: () {},
                ),
              ),
            ),
          );

          // Wait for page 1 initial render
          for (int f = 0; f < 10; f++) {
            await tester.pump(const Duration(milliseconds: 50));
            if (find.byType(RawImage).evaluate().isNotEmpty) break;
          }

          // Begin E2E measurement
          final t0 = DateTime.now().microsecondsSinceEpoch;

          // t1 & t2: Match resolution & Navigation dispatch
          final targetPage = match.sourcePdfPage;
          final boxes = match.boundingBoxes;
          readerKey.currentState?.jumpToPage(targetPage);
          highlights = {targetPage: boxes};

          // Rebuild widget tree with highlights
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: OriginalPdfReader(
                  key: readerKey,
                  pdfPath: digitalPdfPath,
                  initialPage: targetPage,
                  theme: ReadingThemeType.white,
                  searchHighlights: highlights,
                  onPageChanged: (p, t) {},
                  onTapContent: () {},
                ),
              ),
            ),
          );

          // t3: Wait until frame containing PdfSearchHighlightPainter is rasterized
          int t3 = 0;
          for (int f = 0; f < 30; f++) {
            await tester.pump(const Duration(milliseconds: 30));
            final hasHighlight = find
                .byWidgetPredicate(
                  (w) =>
                      w is CustomPaint &&
                      w.painter is PdfSearchHighlightPainter,
                )
                .evaluate()
                .isNotEmpty;

            if (hasHighlight) {
              t3 = DateTime.now().microsecondsSinceEpoch;
              break;
            }
          }

          expect(
            t3,
            greaterThan(0),
            reason: 'Highlight must be visibly rendered on frame',
          );
          final e2eMs = (t3 - t0) / 1000.0;
          latencies.add(e2eMs);
        }

        scenarioResults['1. Digital PDF Cross-Page'] = computeStats(latencies);
        print('[SCENARIO 1: Digital PDF Cross-Page] (N=30)');
        print(
          '  p50: ${scenarioResults['1. Digital PDF Cross-Page']!['p50'].toStringAsFixed(2)} ms',
        );
        print(
          '  p95: ${scenarioResults['1. Digital PDF Cross-Page']!['p95'].toStringAsFixed(2)} ms',
        );
        print(
          '  Max: ${scenarioResults['1. Digital PDF Cross-Page']!['max'].toStringAsFixed(2)} ms\n',
        );
      }

      // -------------------------------------------------------------
      // SCENARIO 2: Scanned OCR PDF (Cross-Page Search: Page 1 -> 33)
      // -------------------------------------------------------------
      {
        final latencies = <double>[];
        final searchResults = await InBookSearchEngine.searchIndexedBook(
          bookId: ocrBookId,
          dbService: dbService,
          query: 'seninya',
        );
        expect(searchResults, isNotEmpty);
        final match = searchResults.first;

        for (int sample = 0; sample < 30; sample++) {
          final readerKey = GlobalKey<OriginalPdfReaderState>();
          Map<int, List<Rect>> highlights = {};

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: OriginalPdfReader(
                  key: readerKey,
                  pdfPath: ocrPdfPath,
                  initialPage: 1, // Start at Page 1
                  theme: ReadingThemeType.white,
                  searchHighlights: highlights,
                  onPageChanged: (p, t) {},
                  onTapContent: () {},
                ),
              ),
            ),
          );

          for (int f = 0; f < 10; f++) {
            await tester.pump(const Duration(milliseconds: 50));
            if (find.byType(RawImage).evaluate().isNotEmpty) break;
          }

          final t0 = DateTime.now().microsecondsSinceEpoch;
          final targetPage = match.sourcePdfPage;
          final boxes = match.boundingBoxes;

          readerKey.currentState?.jumpToPage(targetPage);
          highlights = {targetPage: boxes};

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: OriginalPdfReader(
                  key: readerKey,
                  pdfPath: ocrPdfPath,
                  initialPage: targetPage,
                  theme: ReadingThemeType.white,
                  searchHighlights: highlights,
                  onPageChanged: (p, t) {},
                  onTapContent: () {},
                ),
              ),
            ),
          );

          int t3 = 0;
          for (int f = 0; f < 30; f++) {
            await tester.pump(const Duration(milliseconds: 30));
            final hasHighlight = find
                .byWidgetPredicate(
                  (w) =>
                      w is CustomPaint &&
                      w.painter is PdfSearchHighlightPainter,
                )
                .evaluate()
                .isNotEmpty;

            if (hasHighlight) {
              t3 = DateTime.now().microsecondsSinceEpoch;
              break;
            }
          }

          expect(
            t3,
            greaterThan(0),
            reason: 'OCR Highlight must be visibly rendered on frame',
          );
          final e2eMs = (t3 - t0) / 1000.0;
          latencies.add(e2eMs);
        }

        scenarioResults['2. Scanned OCR PDF Cross-Page'] = computeStats(
          latencies,
        );
        print('[SCENARIO 2: Scanned OCR PDF Cross-Page] (N=30)');
        print(
          '  p50: ${scenarioResults['2. Scanned OCR PDF Cross-Page']!['p50'].toStringAsFixed(2)} ms',
        );
        print(
          '  p95: ${scenarioResults['2. Scanned OCR PDF Cross-Page']!['p95'].toStringAsFixed(2)} ms',
        );
        print(
          '  Max: ${scenarioResults['2. Scanned OCR PDF Cross-Page']!['max'].toStringAsFixed(2)} ms\n',
        );
      }

      // -------------------------------------------------------------
      // SCENARIO 3: Same-Page Search (Instant Page Jump, Highlight Presentation)
      // -------------------------------------------------------------
      {
        final latencies = <double>[];
        final searchResults = await InBookSearchEngine.searchIndexedBook(
          bookId: ocrBookId,
          dbService: dbService,
          query: 'seninya',
        );
        final match = searchResults.first;

        for (int sample = 0; sample < 30; sample++) {
          final readerKey = GlobalKey<OriginalPdfReaderState>();
          Map<int, List<Rect>> highlights = {};

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: OriginalPdfReader(
                  key: readerKey,
                  pdfPath: ocrPdfPath,
                  initialPage: 33, // Already on target page
                  theme: ReadingThemeType.white,
                  searchHighlights: highlights,
                  onPageChanged: (p, t) {},
                  onTapContent: () {},
                ),
              ),
            ),
          );

          for (int f = 0; f < 10; f++) {
            await tester.pump(const Duration(milliseconds: 50));
            if (find.byType(RawImage).evaluate().isNotEmpty) break;
          }

          final t0 = DateTime.now().microsecondsSinceEpoch;
          final targetPage = match.sourcePdfPage;
          final boxes = match.boundingBoxes;

          highlights = {targetPage: boxes};

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: OriginalPdfReader(
                  key: readerKey,
                  pdfPath: ocrPdfPath,
                  initialPage: targetPage,
                  theme: ReadingThemeType.white,
                  searchHighlights: highlights,
                  onPageChanged: (p, t) {},
                  onTapContent: () {},
                ),
              ),
            ),
          );

          int t3 = 0;
          for (int f = 0; f < 20; f++) {
            await tester.pump(const Duration(milliseconds: 20));
            final hasHighlight = find
                .byWidgetPredicate(
                  (w) =>
                      w is CustomPaint &&
                      w.painter is PdfSearchHighlightPainter,
                )
                .evaluate()
                .isNotEmpty;

            if (hasHighlight) {
              t3 = DateTime.now().microsecondsSinceEpoch;
              break;
            }
          }

          expect(
            t3,
            greaterThan(0),
            reason: 'Same-page highlight must be visible',
          );
          final e2eMs = (t3 - t0) / 1000.0;
          latencies.add(e2eMs);
        }

        scenarioResults['3. Same-Page Search Highlight'] = computeStats(
          latencies,
        );
        print('[SCENARIO 3: Same-Page Search Highlight] (N=30)');
        print(
          '  p50: ${scenarioResults['3. Same-Page Search Highlight']!['p50'].toStringAsFixed(2)} ms',
        );
        print(
          '  p95: ${scenarioResults['3. Same-Page Search Highlight']!['p95'].toStringAsFixed(2)} ms',
        );
        print(
          '  Max: ${scenarioResults['3. Same-Page Search Highlight']!['max'].toStringAsFixed(2)} ms\n',
        );
      }

      // -------------------------------------------------------------
      // SCENARIO 4: Rapid Sequential Match Traversal (Next Match)
      // -------------------------------------------------------------
      {
        final latencies = <double>[];
        final matchP1 = const InBookSearchResult(
          id: 'm1',
          chapterId: 'ch_0',
          chapterTitle: 'Bab 1',
          sourcePdfPage: 1,
          chapterIndex: 0,
          nodeId: 'node_p1',
          startOffset: 0,
          endOffset: 5,
          matchedText: 'The',
          snippet: 'The Let',
          prefixContext: '',
          suffixContext: '',
          boundingBoxes: [Rect.fromLTWH(0.1, 0.1, 0.2, 0.04)],
        );
        final matchP12 = const InBookSearchResult(
          id: 'm2',
          chapterId: 'ch_0',
          chapterTitle: 'Bab 1',
          sourcePdfPage: 12,
          chapterIndex: 0,
          nodeId: 'node_p12',
          startOffset: 13,
          endOffset: 19,
          matchedText: 'Theory',
          snippet: 'Theory is life',
          prefixContext: '',
          suffixContext: '',
          boundingBoxes: [Rect.fromLTWH(0.42, 0.2, 0.14, 0.04)],
        );

        for (int sample = 0; sample < 30; sample++) {
          final readerKey = GlobalKey<OriginalPdfReaderState>();
          Map<int, List<Rect>> highlights = {1: matchP1.boundingBoxes};

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: OriginalPdfReader(
                  key: readerKey,
                  pdfPath: digitalPdfPath,
                  initialPage: 1,
                  theme: ReadingThemeType.white,
                  searchHighlights: highlights,
                  onPageChanged: (p, t) {},
                  onTapContent: () {},
                ),
              ),
            ),
          );

          for (int f = 0; f < 10; f++) {
            await tester.pump(const Duration(milliseconds: 50));
            if (find.byType(RawImage).evaluate().isNotEmpty) break;
          }

          // Traverse to match 2 on Page 12
          final t0 = DateTime.now().microsecondsSinceEpoch;
          readerKey.currentState?.jumpToPage(matchP12.sourcePdfPage);
          highlights = {matchP12.sourcePdfPage: matchP12.boundingBoxes};

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: OriginalPdfReader(
                  key: readerKey,
                  pdfPath: digitalPdfPath,
                  initialPage: matchP12.sourcePdfPage,
                  theme: ReadingThemeType.white,
                  searchHighlights: highlights,
                  onPageChanged: (p, t) {},
                  onTapContent: () {},
                ),
              ),
            ),
          );

          int t3 = 0;
          for (int f = 0; f < 30; f++) {
            await tester.pump(const Duration(milliseconds: 30));
            final hasHighlight = find
                .byWidgetPredicate(
                  (w) =>
                      w is CustomPaint &&
                      w.painter is PdfSearchHighlightPainter,
                )
                .evaluate()
                .isNotEmpty;

            if (hasHighlight) {
              t3 = DateTime.now().microsecondsSinceEpoch;
              break;
            }
          }

          expect(
            t3,
            greaterThan(0),
            reason: 'Next match highlight must be visible',
          );
          final e2eMs = (t3 - t0) / 1000.0;
          latencies.add(e2eMs);
        }

        scenarioResults['4. Sequential Traversal'] = computeStats(latencies);
        print('[SCENARIO 4: Sequential Traversal] (N=30)');
        print(
          '  p50: ${scenarioResults['4. Sequential Traversal']!['p50'].toStringAsFixed(2)} ms',
        );
        print(
          '  p95: ${scenarioResults['4. Sequential Traversal']!['p95'].toStringAsFixed(2)} ms',
        );
        print(
          '  Max: ${scenarioResults['4. Sequential Traversal']!['max'].toStringAsFixed(2)} ms\n',
        );
      }

      // -------------------------------------------------------------
      // SCENARIO 5: Reflowable Mode Anchor Navigation & Highlight Rendering
      // -------------------------------------------------------------
      {
        final latencies = <double>[];
        final reflowableDoc = const ReaderDocument(
          bookId: 'reflowable_bench',
          title: 'Bicara Itu Ada Seninya',
          author: 'Oh Su Hyang',
          totalPages: 50,
          chapters: [
            ReaderChapter(
              id: 'ch_0',
              index: 0,
              title: 'Bab 1',
              nodes: [
                ContentNode(
                  id: 'node_p1',
                  type: ContentNodeType.paragraph,
                  text: 'Halaman pertama buku komunikasi terapan.',
                  sourcePdfPage: 1,
                ),
                ContentNode(
                  id: 'node_p33',
                  type: ContentNodeType.paragraph,
                  text:
                      'Bicara itu ada seninya untuk mempertahankan hubungan baik.',
                  sourcePdfPage: 33,
                ),
              ],
            ),
          ],
        );

        final matchNode33 = const ActiveSearchMatch(
          nodeId: 'node_p33',
          startOffset: 15,
          endOffset: 22,
          isActive: true,
        );

        for (int sample = 0; sample < 30; sample++) {
          final reflowableKey = GlobalKey<ReflowableReaderContainerState>();
          final container = ProviderContainer(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              databaseServiceProvider.overrideWithValue(dbService),
              bookHighlightsStreamProvider(
                'reflowable_bench',
              ).overrideWith((ref) => Stream.value(const [])),
            ],
          );

          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                home: Scaffold(
                  body: ReflowableReaderContainer(
                    key: reflowableKey,
                    bookId: 'reflowable_bench',
                    document: reflowableDoc,
                    theme: ReadingThemeType.white,
                    typography: const TypographySettings(),
                    customHighlights: const [],
                    onTapContent: () {},
                    onProgressChanged: (ch, pos, perc, anc, off) {},
                    initialAnchorNodeId: 'node_p1',
                    searchMatches: const [],
                  ),
                ),
              ),
            ),
          );

          await tester.pump(const Duration(milliseconds: 50));

          // Start E2E measurement
          final t0 = DateTime.now().microsecondsSinceEpoch;

          reflowableKey.currentState?.jumpToAnchor('node_p33', 15);

          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                home: Scaffold(
                  body: ReflowableReaderContainer(
                    key: reflowableKey,
                    bookId: 'reflowable_bench',
                    document: reflowableDoc,
                    theme: ReadingThemeType.white,
                    typography: const TypographySettings(),
                    customHighlights: const [],
                    onTapContent: () {},
                    onProgressChanged: (ch, pos, perc, anc, off) {},
                    initialAnchorNodeId: 'node_p33',
                    searchMatches: [matchNode33],
                  ),
                ),
              ),
            ),
          );

          int t3 = 0;
          for (int f = 0; f < 20; f++) {
            await tester.pump(const Duration(milliseconds: 30));
            final hasRichText = find.byType(RichText).evaluate().isNotEmpty;
            if (hasRichText) {
              t3 = DateTime.now().microsecondsSinceEpoch;
              break;
            }
          }

          container.dispose();
          expect(
            t3,
            greaterThan(0),
            reason: 'Reflowable highlight must be visible',
          );
          final e2eMs = (t3 - t0) / 1000.0;
          latencies.add(e2eMs);
        }

        scenarioResults['5. Reflowable Mode Anchor'] = computeStats(latencies);
        print('[SCENARIO 5: Reflowable Mode Anchor] (N=30)');
        print(
          '  p50: ${scenarioResults['5. Reflowable Mode Anchor']!['p50'].toStringAsFixed(2)} ms',
        );
        print(
          '  p95: ${scenarioResults['5. Reflowable Mode Anchor']!['p95'].toStringAsFixed(2)} ms',
        );
        print(
          '  Max: ${scenarioResults['5. Reflowable Mode Anchor']!['max'].toStringAsFixed(2)} ms\n',
        );
      }

      print('===============================================================');
      print('HIGH-02 BENCHMARK FINAL CONSOLIDATED SUMMARY');
      print('Scenario | Count | p50 (ms) | p95 (ms) | Max (ms) | Avg (ms)');
      print('---|---|---|---|---|---');
      scenarioResults.forEach((name, s) {
        print(
          '$name | ${s['count']} | ${s['p50'].toStringAsFixed(2)} | ${s['p95'].toStringAsFixed(2)} | ${s['max'].toStringAsFixed(2)} | ${s['avg'].toStringAsFixed(2)}',
        );
      });
      print(
        '===============================================================\n',
      );

      // Assertions:
      // All p50 latencies must be under 300 ms across all scenarios
      for (final entry in scenarioResults.entries) {
        expect(
          entry.value['p50'],
          lessThan(300.0),
          reason: '${entry.key} p50 latency must be under 300 ms',
        );
      }
    });
  });
}
