// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show Rect;
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/features/reader/domain/engines/in_book_search_engine.dart';
import 'package:digital_books/features/reader/domain/models/search_geometry.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late DatabaseService dbService;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dbService = DatabaseService(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('Phase 3.2.1 — Large Book Search Performance Benchmark', () {
    test('Empirical Latency Breakdown across 100, 265, and 394 Pages', () async {
      // Benchmark page corpus generator
      Future<void> populateCorpus(String bookId, int pageCount) async {
        await dbService.insertBook(
          BooksCompanion(
            id: drift.Value(bookId),
            title: drift.Value('Benchmark Book $pageCount Pages'),
            author: const drift.Value('Benchmark Author'),
            originalPdfPath: drift.Value('/dummy/$bookId.pdf'),
            totalPages: drift.Value(pageCount),
            createdAt: drift.Value(DateTime.now()),
            updatedAt: drift.Value(DateTime.now()),
          ),
        );

        final dummyParagraph =
            'Setelah lebih dari sejam kami berada di atas mobil dengan mata yang masih ditutup dan tangan terikat, '
            'akhirnya si Manusia Pohon menarikku keluar mobil dan bersama yang lain menggiringku ke sebuah tempat, '
            'udara terbuka. Aku ditendang agar berjalan dengan lekas. Jalan semakin menanjak dan aku mendengar debur ombak '
            'yang pecah. Aku bisa mencium aroma asin laut di antara angin yang mengacak rambut. Sekali lagi, suara ombak '
            'yang deras itu pecah tak seirama. Di manakah aku? Apakah kami masih di wilayah Jakarta? Karena aku sering '
            'berhenti untuk mengira-ngira lokasi, sebuah tangan besar mendorong punggungku agar aku berjalan lebih cepat. '
            'Setelah berjalan cukup jauh, kini salah satu dari mereka berteriak agar aku menaiki sebuah speedboat. '
            'Bau asin laut kembali menusuk cuping hidungku. Kudengar seseorang menyalakan motor speedboat itu.';

        // Generate realistic tokens per page (approx 120 words per page)
        final words = dummyParagraph.split(RegExp(r'\s+'));
        final tokens = <SearchTokenGeometry>[];
        int charCursor = 0;
        for (int w = 0; w < words.length; w++) {
          final word = words[w];
          final start = dummyParagraph.indexOf(word, charCursor);
          final end = start + word.length;
          charCursor = end;
          tokens.add(
            SearchTokenGeometry(
              text: word,
              start: start,
              end: end,
              box: Rect.fromLTWH(
                (w % 10) * 0.08 + 0.1,
                (w ~/ 10) * 0.04 + 0.1,
                0.07,
                0.03,
              ),
              isChrome: (w == 0 || w == words.length - 1),
            ),
          );
        }
        final geomJson = jsonEncode(tokens.map((t) => t.toJson()).toList());

        for (int p = 0; p < pageCount; p++) {
          await dbService.insertSearchPage(
            BookSearchPagesCompanion(
              id: drift.Value('${bookId}_p$p'),
              bookId: drift.Value(bookId),
              pageIndex: drift.Value(p),
              plainText: drift.Value(dummyParagraph),
              rawText: drift.Value(dummyParagraph),
              geometryJson: drift.Value(geomJson),
              isOcr: const drift.Value(true),
              indexVersion: const drift.Value(1),
              indexedAt: drift.Value(DateTime.now()),
            ),
          );
        }
      }

      print(
        '\n===============================================================',
      );
      print('PHASE 3.2.1 LARGE BOOK PERFORMANCE BENCHMARK (EMPIRICAL)');
      print('===============================================================');

      for (final targetPages in [100, 265, 394]) {
        final bookId = 'book_perf_$targetPages';

        // 1. Index Insertion Latency
        final indexStopwatch = Stopwatch()..start();
        await populateCorpus(bookId, targetPages);
        indexStopwatch.stop();
        final totalIndexMs = indexStopwatch.elapsedMilliseconds;
        final perPageIndexMs = totalIndexMs / targetPages;

        // 2. Query Execution Latency (10 iterations per query type)
        // A. Frequent Term ("laut" - 3 matches per page)
        final freqStopwatch = Stopwatch()..start();
        const iterations = 5;
        int freqCount = 0;
        for (int i = 0; i < iterations; i++) {
          final res = await InBookSearchEngine.searchIndexedBook(
            bookId: bookId,
            dbService: dbService,
            query: 'laut',
            includeChrome: false,
          );
          freqCount = res.length;
        }
        freqStopwatch.stop();
        final freqAvgMs = freqStopwatch.elapsedMilliseconds / iterations;

        // B. Specific Multi-word Phrase ("Manusia Pohon" - 1 match per page)
        final phraseStopwatch = Stopwatch()..start();
        int phraseCount = 0;
        for (int i = 0; i < iterations; i++) {
          final res = await InBookSearchEngine.searchIndexedBook(
            bookId: bookId,
            dbService: dbService,
            query: 'Manusia Pohon',
            includeChrome: false,
          );
          phraseCount = res.length;
        }
        phraseStopwatch.stop();
        final phraseAvgMs = phraseStopwatch.elapsedMilliseconds / iterations;

        // C. Negative Search (Non-existent term)
        final negStopwatch = Stopwatch()..start();
        for (int i = 0; i < iterations; i++) {
          await InBookSearchEngine.searchIndexedBook(
            bookId: bookId,
            dbService: dbService,
            query: 'antariksa_tidak_ada',
            includeChrome: false,
          );
        }
        negStopwatch.stop();
        final negAvgMs = negStopwatch.elapsedMilliseconds / iterations;

        // 3. Subcomponent Breakdown Timing
        // Measure isolated DB load
        final dbStopwatch = Stopwatch()..start();
        final pages = await dbService.getSearchPagesForBook(bookId);
        dbStopwatch.stop();
        final dbLoadMs = dbStopwatch.elapsedMilliseconds;

        // Measure isolated text scan & snippet generation
        final scanStopwatch = Stopwatch()..start();
        int scanMatches = 0;
        for (final p in pages) {
          final lower = p.plainText.toLowerCase();
          int idx = 0;
          while ((idx = lower.indexOf('laut', idx)) != -1) {
            scanMatches++;
            final pre = math.max(0, idx - 40);
            final post = math.min(p.plainText.length, idx + 4 + 40);
            p.plainText.substring(pre, post);
            idx += 4;
          }
        }
        scanStopwatch.stop();
        expect(scanMatches, greaterThan(0));
        final scanSnippetMs = scanStopwatch.elapsedMicroseconds / 1000.0;

        // Measure isolated bounding box resolution
        final geomStopwatch = Stopwatch()..start();
        for (final p in pages) {
          final rawList = jsonDecode(p.geometryJson) as List<dynamic>;
          rawList
              .map(
                (j) => SearchTokenGeometry.fromJson(j as Map<String, dynamic>),
              )
              .toList();
        }
        geomStopwatch.stop();
        final geomParseMs = geomStopwatch.elapsedMicroseconds / 1000.0;

        // 4. Navigation Latency: Result -> Highlight Prep
        final navStopwatch = Stopwatch()..start();
        final sampleMatch = InBookSearchResult(
          id: 'perf_test_match',
          chapterIndex: 0,
          chapterId: 'ch0',
          chapterTitle: 'Ch 0',
          nodeId: 'n0',
          sourcePdfPage: 15,
          startOffset: 100,
          endOffset: 104,
          matchedText: 'laut',
          snippet: '…aroma asin laut di…',
          prefixContext: 'aroma asin ',
          suffixContext: ' di',
          boundingBoxes: const [Rect.fromLTWH(0.2, 0.3, 0.1, 0.03)],
          isCrossPage: false,
          isOcr: true,
        );
        // Prepare highlight map
        final highlights = {
          sampleMatch.sourcePdfPage: sampleMatch.boundingBoxes,
        };
        expect(highlights[15]!.length, equals(1));
        navStopwatch.stop();
        final navLatencyMs = navStopwatch.elapsedMicroseconds / 1000.0;

        print('Corpus: $targetPages Pages');
        print(
          '  • Indexing Latency:          $totalIndexMs ms (${perPageIndexMs.toStringAsFixed(2)} ms/page)',
        );
        print('  • Database Page Load:        $dbLoadMs ms');
        print(
          '  • Text Scan + Snippet:       ${scanSnippetMs.toStringAsFixed(2)} ms',
        );
        print(
          '  • Token Geometry Parse:      ${geomParseMs.toStringAsFixed(2)} ms',
        );
        print(
          '  • Query Frequent ("laut"):    ${freqAvgMs.toStringAsFixed(2)} ms ($freqCount matches)',
        );
        print(
          '  • Query Phrase ("Manusia P"): ${phraseAvgMs.toStringAsFixed(2)} ms ($phraseCount matches)',
        );
        print(
          '  • Query Negative:            ${negAvgMs.toStringAsFixed(2)} ms (0 matches)',
        );
        print(
          '  • Nav to Highlight Prep:     ${navLatencyMs.toStringAsFixed(3)} ms',
        );
        print(
          '---------------------------------------------------------------',
        );

        // Latency SLA Assertions:
        // Even for 394 pages, query execution should complete well under 250 ms
        expect(freqAvgMs, lessThan(250.0));
        expect(phraseAvgMs, lessThan(250.0));
        expect(negAvgMs, lessThan(250.0));
      }
      print(
        '===============================================================\n',
      );
    });
  });
}
