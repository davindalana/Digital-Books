// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:digital_books/core/typography/typography_settings.dart';
import 'package:digital_books/features/reader/domain/engines/in_book_search_engine.dart';
import 'package:digital_books/features/reader/domain/engines/pagination_engine.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  test('Phase 2.6 Holistic Performance, RAM & Pagination Benchmark', () async {
    print('\n===============================================================');
    print('PHASE 2.6 HOLISTIC PERFORMANCE & MEMORY PROFILING SUITE');
    print('OS: macOS | Architecture: ${Platform.version.split(' ').first}');
    print('===============================================================\n');

    final results = <String, dynamic>{};
    final initialRss = ProcessInfo.currentRss;

    // 1. Document Cold Loading & Parsing (130,000 words, 50 chapters)
    final docGenSw = Stopwatch()..start();
    final longDoc = _generateDocument(
      title: 'The Great Novel',
      chaptersCount: 50,
      paragraphsPerChapter: 20,
      wordsPerParagraph: 130,
    );
    docGenSw.stop();

    // Serialize and deserialize to measure realistic file-to-DOM cold open time
    final jsonStr = jsonEncode(longDoc.toJson());
    final parseSw = Stopwatch()..start();
    final parsedMap = jsonDecode(jsonStr) as Map<String, dynamic>;
    final reconstructedDoc = ReaderDocument.fromJson(parsedMap);
    parseSw.stop();

    print('--- [Benchmark 1] Document Cold Open & Deserialization ---');
    print('• Document word count: ~130,000 words across 50 chapters');
    print(
      '• JSON raw size: ${(jsonStr.length / 1024.0 / 1024.0).toStringAsFixed(2)} MB',
    );
    print(
      '• Cold JSON parse & DOM construction: ${parseSw.elapsedMicroseconds / 1000.0} ms',
    );
    expect(reconstructedDoc.chapters.length, 50);

    results['document_open'] = {
      'words': 130000,
      'json_mb': jsonStr.length / 1024.0 / 1024.0,
      'parse_ms': parseSw.elapsedMicroseconds / 1000.0,
    };

    // 2. TextPainter Pagination Construction Time
    print('\n--- [Benchmark 2] TextPainter Pagination Engine ---');
    const typography = TypographySettings(
      fontSize: 18.0,
      lineSpacing: 1.6,
      twoPageSpread: false,
    );

    final paginateSw = Stopwatch()..start();
    final paginatedPages = PaginationEngine.paginateDocument(
      document: reconstructedDoc,
      typography: typography,
      viewportWidth: 650.0,
      viewportHeight: 850.0,
    );
    paginateSw.stop();

    print('• Viewport: 650x850 pt (Single-page reading spread)');
    print('• Total calculated pages: ${paginatedPages.length}');
    print(
      '• Total pagination duration: ${paginateSw.elapsedMilliseconds} ms (${(paginateSw.elapsedMilliseconds / paginatedPages.length).toStringAsFixed(2)} ms/page)',
    );
    expect(paginatedPages.length, greaterThan(100));

    results['pagination'] = {
      'total_pages': paginatedPages.length,
      'duration_ms': paginateSw.elapsedMilliseconds,
      'ms_per_page': paginateSw.elapsedMilliseconds / paginatedPages.length,
    };

    // 3. Search under Pagination Load
    print('\n--- [Benchmark 3] Search on Normalized Content ---');
    final searchSw = Stopwatch()..start();
    final matches = await InBookSearchEngine.search(
      document: reconstructedDoc,
      query: 'Sherlock',
    );
    searchSw.stop();

    print('• Search term: "Sherlock"');
    print('• Matches found: ${matches.length}');
    print('• Search duration: ${searchSw.elapsedMicroseconds / 1000.0} ms');

    results['search'] = {
      'matches': matches.length,
      'duration_ms': searchSw.elapsedMicroseconds / 1000.0,
    };

    // 4. Multi-Book Sequential Switching & Resource Disposal (10 Books)
    print('\n--- [Benchmark 4] Multi-Book Switching & Resource Disposal ---');
    final switchSw = Stopwatch()..start();
    for (int bookIdx = 0; bookIdx < 10; bookIdx++) {
      final doc = _generateDocument(
        title: 'Switch Book $bookIdx',
        chaptersCount: 10,
        paragraphsPerChapter: 15,
        wordsPerParagraph: 120,
      );
      PaginationEngine.paginateDocument(
        document: doc,
        typography: typography,
        viewportWidth: 650.0,
        viewportHeight: 850.0,
      );
      await InBookSearchEngine.search(document: doc, query: 'Holmes');
      InBookSearchEngine.clearCache(doc.bookId);
    }
    switchSw.stop();

    final postSwitchRss = ProcessInfo.currentRss;
    final rssDeltaMb = (postSwitchRss - initialRss) / 1024.0 / 1024.0;

    print(
      '• Completed 10 full document loads, paginations & searches in: ${switchSw.elapsedMilliseconds} ms (${(switchSw.elapsedMilliseconds / 10.0).toStringAsFixed(1)} ms/book)',
    );
    print(
      '• Process RSS Delta after 10 switches: ${rssDeltaMb.toStringAsFixed(2)} MB',
    );

    results['multi_book_switching'] = {
      'total_ms': switchSw.elapsedMilliseconds,
      'ms_per_book': switchSw.elapsedMilliseconds / 10.0,
      'rss_delta_mb': rssDeltaMb,
    };

    print('\n===============================================================');
    print('ALL HOLISTIC BENCHMARKS COMPLETED SUCCESSFULLY');
    print('===============================================================\n');

    final resultsFile = File(
      '/Users/davindalana/.gemini/antigravity/brain/d28b8768-0772-4001-8dca-34c07962ba48/scratch/phase_2_6_performance_profile.json',
    );
    await resultsFile.parent.create(recursive: true);
    await resultsFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(results),
    );
  });
}

ReaderDocument _generateDocument({
  required String title,
  required int chaptersCount,
  required int paragraphsPerChapter,
  required int wordsPerParagraph,
}) {
  final chapters = <ReaderChapter>[];

  final sampleWords = [
    'Sherlock',
    'Holmes',
    'looked',
    'thoughtfully',
    'at',
    'the',
    'letter',
    'and',
    'smiled',
    'calmly.',
    'The',
    'investigation',
    'had',
    'begun',
    'in',
    'London',
    'during',
    'a',
    'cold',
    'rainy',
    'November',
    'evening.',
    'Watson',
    'recorded',
    'every',
    'detail',
    'carefully',
    'in',
    'his',
    'leather',
    'journal.',
    'Truth',
    'demands',
    'rigor',
    'and',
    'patience.',
  ];

  for (int ch = 0; ch < chaptersCount; ch++) {
    final nodes = <ContentNode>[];
    nodes.add(
      ContentNode(
        id: 'h_${ch}_0',
        type: ContentNodeType.heading,
        text: 'Chapter ${ch + 1}: The Great Mystery of Section $ch',
        level: 1,
      ),
    );

    for (int p = 1; p <= paragraphsPerChapter; p++) {
      final buffer = StringBuffer();
      for (int w = 0; w < wordsPerParagraph; w++) {
        buffer.write(sampleWords[(ch + p + w) % sampleWords.length]);
        buffer.write(' ');
      }
      nodes.add(
        ContentNode(
          id: 'p_${ch}_$p',
          type: ContentNodeType.paragraph,
          text: buffer.toString().trim(),
        ),
      );
    }

    chapters.add(
      ReaderChapter(
        id: 'ch_$ch',
        index: ch,
        title: 'Chapter ${ch + 1}',
        nodes: nodes,
      ),
    );
  }

  return ReaderDocument(
    bookId: 'doc_${chaptersCount}_chapters',
    title: title,
    author: 'Benchmark Suite',
    chapters: chapters,
  );
}
