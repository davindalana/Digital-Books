import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/features/reader/domain/engines/anchor_resolution_engine.dart';
import 'package:digital_books/features/reader/domain/engines/in_book_search_engine.dart';
import 'package:digital_books/features/reader/domain/engines/reflowable_highlight_span_builder.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'package:digital_books/features/reader/domain/models/reading_navigation_history.dart';
import 'package:digital_books/features/reader/domain/models/toc_item.dart';
import 'package:digital_books/features/reader/presentation/widgets/book_search_dialog.dart';
import 'package:digital_books/features/reader/presentation/widgets/search_traversal_bar.dart';
import 'package:digital_books/features/reader/presentation/widgets/toc_dialog.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testReaderDocument = ReaderDocument(
    bookId: 'book_discovery_test',
    title: 'Filosofi Hidup Stoikisme Modern',
    author: 'Henry Manampiring & Epictetus',
    totalPages: 50,
    chapters: [
      ReaderChapter(
        id: 'ch_0',
        index: 0,
        title: 'Bab 1: Kendali Diri',
        nodes: [
          const ContentNode(
            id: 'ch0_h1',
            type: ContentNodeType.heading,
            text: 'Bab 1: Kendali Diri',
            level: 1,
            sourcePdfPage: 1,
          ),
          const ContentNode(
            id: 'ch0_p1',
            type: ContentNodeType.paragraph,
            text:
                'Ada hal-hal yang berada di bawah kendali kita, dan ada hal-hal yang tidak berada di bawah kendali kita. Pikiran dan tindakan kita adalah kuasa kita.',
            sourcePdfPage: 1,
          ),
          const ContentNode(
            id: 'ch0_h2',
            type: ContentNodeType.heading,
            text: 'Bagian A: Menghadapi Kecemasan',
            level: 2,
            sourcePdfPage: 2,
          ),
          const ContentNode(
            id: 'ch0_q1',
            type: ContentNodeType.quote,
            text:
                'Ketenangan batin sejati bermula dari penerimaan tulus terhadap hal yang di luar kendali.',
            sourcePdfPage: 2,
          ),
          const ContentNode(
            id: 'ch0_p2',
            type: ContentNodeType.paragraph,
            text:
                'Ketika kita memahami dikotomi kendali, ketenangan batin tidak lagi menjadi impian kosong melainkan kenyataan hidup sehari-hari.',
            sourcePdfPage: 3,
          ),
        ],
      ),
      ReaderChapter(
        id: 'ch_1',
        index: 1,
        title: 'Bab 2: Manajemen Persepsi',
        nodes: [
          const ContentNode(
            id: 'ch1_h1',
            type: ContentNodeType.heading,
            text: 'Bab 2: Manajemen Persepsi',
            level: 1,
            sourcePdfPage: 4,
          ),
          const ContentNode(
            id: 'ch1_p1',
            type: ContentNodeType.paragraph,
            text:
                'Bukan peristiwa yang merisaukan manusia, melainkan penilaian yang dibuat tentang peristiwa tersebut. Di sini ketenangan batin diuji dalam badai cobaan.',
            sourcePdfPage: 4,
          ),
          const ContentNode(
            id: 'ch1_h2',
            type: ContentNodeType.heading,
            text: 'Bagian B: Latihan Mental Harian',
            level: 2,
            sourcePdfPage: 5,
          ),
          const ContentNode(
            id: 'ch1_p2',
            type: ContentNodeType.paragraph,
            text:
                'Setiap pagi ingatkan dirimu bahwa kamu akan menghadapi orang-orang yang sulit, namun kendali tetap di tanganmu.',
            sourcePdfPage: 5,
          ),
        ],
      ),
    ],
  );

  group('Phase 2.4 — Table of Contents (TOC) Tests', () {
    test('Builds hierarchical TOC with nested subheadings', () {
      final toc = TocHierarchyBuilder.buildFromDocument(testReaderDocument);

      expect(toc.length, equals(2)); // 2 Chapters
      expect(toc[0].title, equals('Bab 1: Kendali Diri'));
      expect(toc[0].level, equals(1));
      expect(toc[0].hasChildren, isTrue);
      expect(
        toc[0].children.length,
        equals(1),
      ); // 'Bagian A: Menghadapi Kecemasan'
      expect(
        toc[0].children[0].title,
        equals('Bagian A: Menghadapi Kecemasan'),
      );
      expect(toc[0].children[0].level, equals(2));
      expect(toc[0].children[0].anchorNodeId, equals('ch0_h2'));

      expect(toc[1].title, equals('Bab 2: Manajemen Persepsi'));
      expect(toc[1].children.length, equals(1));
      expect(
        toc[1].children[0].title,
        equals('Bagian B: Latihan Mental Harian'),
      );
    });

    test(
      'Gracefully handles document with empty chapters or no explicit headings',
      () {
        const emptyDoc = ReaderDocument(
          bookId: 'empty_doc',
          title: 'Buku Kosong',
          author: 'Anon',
          chapters: [
            ReaderChapter(
              id: 'ch_empty',
              index: 0,
              title: 'Hanya Paragraf',
              nodes: [
                ContentNode(
                  id: 'p_only',
                  type: ContentNodeType.paragraph,
                  text: 'Hanya teks biasa tanpa heading.',
                ),
              ],
            ),
          ],
        );

        final toc = TocHierarchyBuilder.buildFromDocument(emptyDoc);
        expect(toc.length, equals(1));
        expect(toc[0].title, equals('Hanya Paragraf'));
        expect(toc[0].hasChildren, isFalse);
      },
    );

    test('Finds active TOC item matching anchorNodeId or chapter', () {
      final toc = TocHierarchyBuilder.buildFromDocument(testReaderDocument);

      final activeSection = TocHierarchyBuilder.findActiveItem(
        items: toc,
        currentChapterIndex: 0,
        currentAnchorNodeId: 'ch0_h2',
      );
      expect(activeSection, isNotNull);
      expect(activeSection!.title, equals('Bagian A: Menghadapi Kecemasan'));

      final fallbackChapter = TocHierarchyBuilder.findActiveItem(
        items: toc,
        currentChapterIndex: 1,
        currentAnchorNodeId: 'ch1_p2',
      );
      expect(fallbackChapter, isNotNull);
      expect(fallbackChapter!.title, equals('Bab 2: Manajemen Persepsi'));
    });
  });

  group('Phase 2.4 — In-Book Search Engine Tests', () {
    test(
      'Exact and partial match across chapters with result count and snippets',
      () async {
        final results = await InBookSearchEngine.search(
          document: testReaderDocument,
          query: 'kendali',
        );

        // 'kendali' appears:
        // ch0_h1: "Bab 1: Kendali Diri" (1)
        // ch0_p1: "bawah kendali kita... bawah kendali kita" (2)
        // ch0_q1: "luar kendali" (1)
        // ch0_p2: "dikotomi kendali" (1)
        // ch1_p2: "namun kendali tetap" (1)
        // Total 6 occurrences
        expect(results.length, equals(6));
        expect(results.any((r) => r.chapterIndex == 0), isTrue);
        expect(results.any((r) => r.chapterIndex == 1), isTrue);

        final first = results.first;
        expect(first.matchedText.toLowerCase(), equals('kendali'));
        expect(first.snippet, contains('Kendali'));
        expect(first.startOffset, isNonNegative);
        expect(first.endOffset, greaterThan(first.startOffset));
      },
    );

    test('Case-insensitive search matching uppercase/mixed query', () async {
      final resultsUpper = await InBookSearchEngine.search(
        document: testReaderDocument,
        query: 'KENDALI',
      );
      final resultsLower = await InBookSearchEngine.search(
        document: testReaderDocument,
        query: 'kendali',
      );

      expect(resultsUpper.length, equals(resultsLower.length));
    });

    test(
      'Empty query returns empty list, non-existent query returns empty list',
      () async {
        final emptyResults = await InBookSearchEngine.search(
          document: testReaderDocument,
          query: '   ',
        );
        expect(emptyResults, isEmpty);

        final noMatchResults = await InBookSearchEngine.search(
          document: testReaderDocument,
          query: 'KecerdasanBuatanQuantum999',
        );
        expect(noMatchResults, isEmpty);
      },
    );

    test(
      'Cooperative async cancellation halts search early when token is stale',
      () async {
        bool isStale = false;
        final results = await InBookSearchEngine.search(
          document: testReaderDocument,
          query: 'kendali',
          isCancelled: () => isStale,
        );
        expect(results.length, equals(6));

        // Now cancel
        isStale = true;
        final cancelledResults = await InBookSearchEngine.search(
          document: testReaderDocument,
          query: 'kendali',
          isCancelled: () => isStale,
        );
        expect(cancelledResults, isEmpty);
      },
    );
  });

  group('Phase 2.4 — Disambiguation for Repeated Text (Phase 2.3 Risk A)', () {
    test(
      'Correctly disambiguates identical text appearing multiple times using context',
      () {
        // 'ketenangan batin' appears in:
        // ch0_q1: 'Ketenangan batin sejati bermula dari...'
        // ch0_p2: 'Ketika kita memahami dikotomi kendali, ketenangan batin tidak lagi...'
        // ch1_p1: 'Di sini ketenangan batin diuji dalam badai cobaan.'

        // Target instance 2 in ch0_p2
        final res = AnchorResolutionEngine.resolveAnchor(
          document: testReaderDocument,
          chapterId: 'ch_0',
          anchorNodeId: 'ch0_p2',
          selectedText: 'ketenangan batin',
          startOffset: 999, // Intentional corrupt offset
          endOffset: 1015,
          prefixContext: 'Ketika kita memahami dikotomi kendali, ',
          suffixContext: ' tidak lagi menjadi impian kosong',
        );

        expect(res.isResolved, isTrue);
        expect(res.resolvedNodeId, equals('ch0_p2'));
        expect(res.confidence, equals(0.95)); // Context match confidence
        final nodeText = testReaderDocument.chapters[0].nodes[4].text;
        expect(
          nodeText.substring(res.resolvedStartOffset, res.resolvedEndOffset),
          equals('ketenangan batin'),
        );
      },
    );
  });

  group('Phase 2.4 — Reading Navigation History Tests', () {
    test(
      'Records locations, ignores consecutive duplicates, and supports back/forward',
      () {
        final history = ReadingNavigationHistory(bookId: 'book_history_test');

        expect(history.canGoBack, isFalse);
        expect(history.canGoForward, isFalse);

        final loc1 = NavigationHistoryEntry(
          bookId: 'book_history_test',
          chapterIndex: 0,
          anchorNodeId: 'ch0_p1',
          pageNumber: 1,
        );
        final loc2 = NavigationHistoryEntry(
          bookId: 'book_history_test',
          chapterIndex: 0,
          anchorNodeId: 'ch0_p2',
          pageNumber: 3,
        );
        final loc3 = NavigationHistoryEntry(
          bookId: 'book_history_test',
          chapterIndex: 1,
          anchorNodeId: 'ch1_p1',
          pageNumber: 4,
        );

        history.recordLocation(loc1);
        expect(history.canGoBack, isFalse); // Only 1 item

        // Duplicate should not increase stack
        history.recordLocation(loc1);
        expect(history.length, equals(1));

        history.recordLocation(loc2);
        history.recordLocation(loc3);
        expect(history.length, equals(3));
        expect(history.canGoBack, isTrue);
        expect(history.canGoForward, isFalse);

        // Back to loc2
        final backTo2 = history.goBack();
        expect(backTo2?.anchorNodeId, equals('ch0_p2'));
        expect(history.canGoBack, isTrue);
        expect(history.canGoForward, isTrue);

        // Back to loc1
        final backTo1 = history.goBack();
        expect(backTo1?.anchorNodeId, equals('ch0_p1'));
        expect(history.canGoBack, isFalse);

        // Forward to loc2
        final fwdTo2 = history.goForward();
        expect(fwdTo2?.anchorNodeId, equals('ch0_p2'));

        // Forward to loc3
        final fwdTo3 = history.goForward();
        expect(fwdTo3?.anchorNodeId, equals('ch1_p1'));
        expect(history.canGoForward, isFalse);
      },
    );

    test('Book isolation: rejects locations from a different bookId', () {
      final history = ReadingNavigationHistory(bookId: 'book_A');
      final locOther = NavigationHistoryEntry(
        bookId: 'book_B',
        chapterIndex: 0,
        anchorNodeId: 'node_x',
      );

      history.recordLocation(locOther);
      expect(history.length, equals(0));
    });
  });

  group(
    'Phase 2.4 — Database Migration v2 to v3 with Existing Data (Phase 2.3 Risk C)',
    () {
      test(
        'Migrates database preserving existing v2 books, highlights, and bookmarks intact',
        () async {
          final db = AppDatabase(NativeDatabase.memory());
          final now = DateTime.now();

          // Insert pre-existing v2 record
          await db
              .into(db.books)
              .insert(
                BooksCompanion(
                  id: const drift.Value('book_v2_compat'),
                  title: const drift.Value('Buku Warisan v2'),
                  author: const drift.Value('Penulis Klasik'),
                  originalPdfPath: const drift.Value('/tmp/v2.pdf'),
                  createdAt: drift.Value(now),
                  updatedAt: drift.Value(now),
                ),
              );

          await db
              .into(db.bookmarks)
              .insert(
                BookmarksCompanion(
                  id: const drift.Value('bm_v2'),
                  bookId: const drift.Value('book_v2_compat'),
                  position: const drift.Value(7),
                  label: const drift.Value('Halaman 7'),
                  createdAt: drift.Value(now),
                ),
              );

          await db
              .into(db.highlights)
              .insert(
                HighlightsCompanion(
                  id: const drift.Value('hl_v2'),
                  bookId: const drift.Value('book_v2_compat'),
                  chapterId: const drift.Value('ch_0'),
                  selectedText: const drift.Value('Teks dari v2'),
                  startPosition: const drift.Value(1),
                  endPosition: const drift.Value(1),
                  color: const drift.Value('yellow'),
                  createdAt: drift.Value(now),
                ),
              );

          // Verify schema version is at least 3
          expect(db.schemaVersion, greaterThanOrEqualTo(3));

          // Verify existing rows are intact
          final allBooks = await db.select(db.books).get();
          expect(allBooks.any((b) => b.id == 'book_v2_compat'), isTrue);

          final allBms = await db.select(db.bookmarks).get();
          final bm = allBms.firstWhere((b) => b.id == 'bm_v2');
          expect(bm.position, equals(7));
          expect(bm.anchorNodeId, isNull); // Default for pre-v3 records

          final allHls = await db.select(db.highlights).get();
          final hl = allHls.firstWhere((h) => h.id == 'hl_v2');
          expect(hl.selectedText, equals('Teks dari v2'));
          expect(hl.anchorNodeId, isNull);

          await db.close();
        },
      );
    },
  );

  group('Phase 2.4 — Search Highlighting Coexistence with Annotations', () {
    test(
      'Span builder applies active search highlight alongside user highlight',
      () {
        final text =
            'Ketika kita memahami dikotomi kendali, ketenangan batin terwujud.';

        final userHl = Highlight(
          id: 'user_hl_1',
          bookId: 'book_discovery_test',
          chapterId: 'ch_0',
          selectedText: 'dikotomi kendali',
          startPosition: 0,
          endPosition: 0,
          color: 'yellow',
          note: 'Penting',
          anchorNodeId: 'ch0_p2',
          startOffset: 21,
          endOffset: 37,
          anchorVersion: 1,
          createdAt: DateTime.now(),
        );

        const activeSearch = ActiveSearchMatch(
          nodeId: 'ch0_p2',
          startOffset: 21,
          endOffset: 29, // Matches 'dikotomi' inside the user highlight
          isActive: true,
        );

        final span = ReflowableHighlightSpanBuilder.buildRichSpan(
          text: text,
          sliceStartOffset: 0,
          sliceEndOffset: text.length,
          highlightsForNode: [userHl],
          searchMatchesForNode: [activeSearch],
          baseStyle: const TextStyle(fontSize: 16.0, color: Colors.black),
          theme: ReadingThemeType.white,
        );

        expect(span.children, isNotNull);
        // The overlapping word 'dikotomi' must have search background + user highlight context
        expect(span.children!.length, greaterThanOrEqualTo(3));
      },
    );
  });

  group('Phase 2.4 — Discovery UI Widgets Tests', () {
    testWidgets(
      'SearchTraversalBar renders query and triggers next/previous/close',
      (tester) async {
        int nextCount = 0;
        int prevCount = 0;
        bool closed = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SearchTraversalBar(
                query: 'kendali',
                currentIndex: 2,
                totalCount: 14,
                theme: ReadingThemeType.white,
                onNext: () => nextCount++,
                onPrevious: () => prevCount++,
                onClose: () => closed = true,
              ),
            ),
          ),
        );

        expect(find.text('kendali'), findsOneWidget);
        expect(find.text('3 dari 14'), findsOneWidget);

        await tester.tap(find.byTooltip('Hasil Berikutnya (Enter)'));
        expect(nextCount, equals(1));

        await tester.tap(find.byTooltip('Previous result (Shift+Enter)'));
        expect(prevCount, equals(1));

        await tester.tap(find.byTooltip('Finish search (Esc)'));
        expect(closed, isTrue);
      },
    );

    testWidgets(
      'TocDialog displays hierarchical chapters and nested subheadings',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: TocDialog(
                  bookId: 'book_discovery_test',
                  readerDocument: testReaderDocument,
                  currentChapterIndex: 0,
                  currentAnchorNodeId: 'ch0_h1',
                  onNavigateToChapter: (ch, page) {},
                  onNavigateToPosition: (_) {},
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('Table of Contents'), findsOneWidget);
        expect(find.text('Bab 1: Kendali Diri'), findsOneWidget);
        expect(find.text('Bab 2: Manajemen Persepsi'), findsOneWidget);
        // Nested heading in auto-expanded current chapter
        expect(find.text('Bagian A: Menghadapi Kecemasan'), findsOneWidget);
      },
    );

    testWidgets('BookSearchDialog searches and delivers selected result', (
      tester,
    ) async {
      InBookSearchResult? selectedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BookSearchDialog(
              readerDocument: testReaderDocument,
              theme: ReadingThemeType.white,
              onNavigateToResult: (res) {
                selectedResult = res;
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Enter search query
      await tester.enterText(find.byType(TextField), 'kendali');
      // Wait for debounce timer (250ms)
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('6 hasil ditemukan'), findsOneWidget);

      // Tap first result
      await tester.tap(find.text('Bab 1: Kendali Diri').first);
      await tester.pumpAndSettle();

      expect(selectedResult, isNotNull);
      expect(selectedResult!.matchedText.toLowerCase(), equals('kendali'));
    });
  });
}
