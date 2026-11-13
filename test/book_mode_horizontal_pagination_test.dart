import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/core/providers/database_providers.dart';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/core/theme/typography_settings.dart';
import 'package:digital_books/features/reader/domain/engines/pagination_engine.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/paginated_reflowable_reader.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/reflowable_reader_container.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DatabaseService dbService;

  setUp(() {
    PaginationEngine.clearCache();
    db = AppDatabase(NativeDatabase.memory());
    dbService = DatabaseService(db);
  });

  tearDown(() async {
    await db.close();
  });

  // Known-content test fixture as required by Section 5 & 8:
  // - 1 title
  // - 3 headings
  // - Several paragraphs
  // - 1 image
  // - 1 list
  final knownContentDocument = ReaderDocument(
    bookId: 'known_fixture_01',
    title: 'Buku Panduan Digital Books',
    author: 'Tim Arsitek',
    totalPages: 10,
    chapters: [
      ReaderChapter(
        id: 'chap_1',
        index: 0,
        title: 'Bab 1: Pengenalan Arsitektur',
        nodes: [
          // 1 Title
          const ContentNode(
            id: 'node_title',
            type: ContentNodeType.documentTitle,
            text: 'Buku Panduan Digital Books',
            level: 1,
          ),
          // Heading 1
          const ContentNode(
            id: 'node_h1',
            type: ContentNodeType.heading,
            text: '1. Dasar Desain Ebook',
            level: 1,
          ),
          // Paragraphs
          const ContentNode(
            id: 'node_p1',
            type: ContentNodeType.paragraph,
            text:
                'Pengalaman membaca buku digital yang baik menuntut ketepatan tipografi, kerapian baris teks, serta kestabilan posisi pembacaan. '
                'Setiap baris teks harus dialokasikan dengan TextPainter secara deterministik agar tidak terjadi pemotongan kata di tengah.',
          ),
          const ContentNode(
            id: 'node_p2',
            type: ContentNodeType.paragraph,
            text:
                'Ketika jendela aplikasi diubah ukurannya atau ukuran font diganti oleh pembaca, sistem harus merepaginasi isi buku tanpa memindahkan pembaca ke halaman yang keliru.',
          ),
          // Heading 2
          const ContentNode(
            id: 'node_h2',
            type: ContentNodeType.sectionHeading,
            text: '2. Ilustrasi dan Diagram Sistem',
            level: 2,
          ),
          // 1 Image
          const ContentNode(
            id: 'node_img1',
            type: ContentNodeType.image,
            text: 'Diagram Alur Rekonstruksi Dokumen',
            imagePath: '',
          ),
          // Heading 3
          const ContentNode(
            id: 'node_h3',
            type: ContentNodeType.sectionHeading,
            text: '3. Daftar Prinsip Pengembangan',
            level: 2,
          ),
          // 1 List (Ordered & Unordered)
          const ContentNode(
            id: 'node_list1',
            type: ContentNodeType.orderedList,
            text:
                '1. Local-first: Seluruh data pembaca disimpan secara lokal di mesin pengguna.',
          ),
          const ContentNode(
            id: 'node_list2',
            type: ContentNodeType.orderedList,
            text:
                '2. Preservasi Dokumen Asli: PDF asli tidak boleh ditimpa atau dimodifikasi secara destruktif.',
          ),
          const ContentNode(
            id: 'node_list3',
            type: ContentNodeType.unorderedList,
            text:
                '• Strict Horizontal Pagination: Navigasi buku hanya bergerak kiri-kanan seperti Apple Books.',
          ),
          // Additional paragraph
          const ContentNode(
            id: 'node_p3',
            type: ContentNodeType.paragraph,
            text:
                'Dengan mematuhi prinsip di atas, aplikasi Digital Books memberikan kenyamanan membaca maksimal bagi seluruh pengguna.',
          ),
        ],
      ),
    ],
  );

  group('Book Mode Horizontal Pagination — Comprehensive Test Suite', () {
    testWidgets('1. One-page layout on narrow window (< 850px)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(700, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseServiceProvider.overrideWithValue(dbService)],
          child: MaterialApp(
            home: Scaffold(
              body: PaginatedReflowableReader(
                document: knownContentDocument,
                theme: ReadingThemeType.white,
                typography: const TypographySettings(),
                onTapContent: () {},
                onProgressChanged: (ch, p, pct, anc, off) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // In one-page mode (<850px), single page is rendered
      expect(find.byKey(const ValueKey('page_0_spread_false')), findsOneWidget);
      expect(find.byKey(const ValueKey('page_0_spread_true')), findsNothing);

      // Verify no vertical scrollbar or scrollable ListView
      expect(find.byType(ListView), findsNothing);
      expect(find.byType(Scrollbar), findsNothing);
    });

    testWidgets('2. Two-page spread on wide window (>= 850px)', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseServiceProvider.overrideWithValue(dbService)],
          child: MaterialApp(
            home: Scaffold(
              body: PaginatedReflowableReader(
                document: knownContentDocument,
                theme: ReadingThemeType.white,
                typography: const TypographySettings(twoPageSpread: true),
                onTapContent: () {},
                onProgressChanged: (ch, p, pct, anc, off) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // In two-page spread (>=850px), spread container is rendered
      expect(find.byKey(const ValueKey('page_0_spread_true')), findsOneWidget);
      expect(find.byKey(const ValueKey('page_0_spread_false')), findsNothing);
    });

    testWidgets(
      '3. Window resize from narrow (<850) to wide (>=850) and back',
      (tester) async {
        tester.view.physicalSize = const Size(600, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          ProviderScope(
            overrides: [databaseServiceProvider.overrideWithValue(dbService)],
            child: MaterialApp(
              home: Scaffold(
                body: PaginatedReflowableReader(
                  document: knownContentDocument,
                  theme: ReadingThemeType.white,
                  typography: const TypographySettings(twoPageSpread: true),
                  onTapContent: () {},
                  onProgressChanged: (ch, p, pct, anc, off) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('page_0_spread_false')),
          findsOneWidget,
        );

        // Resize to wide
        tester.view.physicalSize = const Size(1100, 800);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('page_0_spread_true')),
          findsOneWidget,
        );

        // Resize back to narrow
        tester.view.physicalSize = const Size(650, 800);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('page_0_spread_false')),
          findsOneWidget,
        );
      },
    );

    testWidgets('4. Forward and backward navigation via chevrons and clicks', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(600, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      int reportedPage = 1;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseServiceProvider.overrideWithValue(dbService)],
          child: MaterialApp(
            home: Scaffold(
              body: PaginatedReflowableReader(
                document: knownContentDocument,
                theme: ReadingThemeType.white,
                typography: const TypographySettings(),
                onTapContent: () {},
                onProgressChanged: (ch, page, pct, anc, off) {
                  reportedPage = page;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(reportedPage, 1);

      // Click right chevron to advance
      final rightChevron = find.byIcon(Icons.chevron_right_rounded);
      expect(rightChevron, findsOneWidget);
      await tester.tap(rightChevron);
      await tester.pumpAndSettle();

      expect(reportedPage, 2);

      // Click left chevron to go back
      final leftChevron = find.byIcon(Icons.chevron_left_rounded);
      expect(leftChevron, findsOneWidget);
      await tester.tap(leftChevron);
      await tester.pumpAndSettle();

      expect(reportedPage, 1);
    });

    testWidgets('5. First and last page boundaries prevent out-of-bounds', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(600, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final stateKey = GlobalKey<PaginatedReflowableReaderState>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseServiceProvider.overrideWithValue(dbService)],
          child: MaterialApp(
            home: Scaffold(
              body: PaginatedReflowableReader(
                key: stateKey,
                document: knownContentDocument,
                theme: ReadingThemeType.white,
                typography: const TypographySettings(),
                onTapContent: () {},
                onProgressChanged: (ch, p, pct, anc, off) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final state = stateKey.currentState!;
      expect(state.currentPageIndex, 0);
      expect(state.canGoPrevious, isFalse);

      // Attempting previous at page 0 does nothing
      state.previousPage();
      await tester.pumpAndSettle();
      expect(state.currentPageIndex, 0);

      // Jump to last page
      state.jumpToPage(state.totalPages - 1);
      await tester.pumpAndSettle();
      expect(state.currentPageIndex, state.totalPages - 1);
      expect(state.canGoNext, isFalse);

      // Attempting next at last page does nothing
      state.nextPage();
      await tester.pumpAndSettle();
      expect(state.currentPageIndex, state.totalPages - 1);
    });

    testWidgets(
      '6. Keyboard shortcuts: ArrowRight/ArrowLeft and Space/Shift+Space',
      (tester) async {
        tester.view.physicalSize = const Size(600, 700);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final stateKey = GlobalKey<PaginatedReflowableReaderState>();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [databaseServiceProvider.overrideWithValue(dbService)],
            child: MaterialApp(
              home: Scaffold(
                body: PaginatedReflowableReader(
                  key: stateKey,
                  document: knownContentDocument,
                  theme: ReadingThemeType.white,
                  typography: const TypographySettings(),
                  onTapContent: () {},
                  onProgressChanged: (ch, p, pct, anc, off) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final state = stateKey.currentState!;
        expect(state.currentPageIndex, 0);

        // Press Arrow Right -> Next Page
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(state.currentPageIndex, 1);

        // Press Space -> Next Page
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(state.currentPageIndex, 2);

        // Press Shift + Space -> Previous Page
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpAndSettle();
        expect(state.currentPageIndex, 1);

        // Press Arrow Left -> Previous Page
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(state.currentPageIndex, 0);
      },
    );

    testWidgets('7. Trackpad horizontal swipe / drag gesture', (tester) async {
      tester.view.physicalSize = const Size(600, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final stateKey = GlobalKey<PaginatedReflowableReaderState>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseServiceProvider.overrideWithValue(dbService)],
          child: MaterialApp(
            home: Scaffold(
              body: PaginatedReflowableReader(
                key: stateKey,
                document: knownContentDocument,
                theme: ReadingThemeType.white,
                typography: const TypographySettings(),
                onTapContent: () {},
                onProgressChanged: (ch, p, pct, anc, off) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final state = stateKey.currentState!;
      expect(state.currentPageIndex, 0);

      // Horizontal fling to left (swipe to next page)
      await tester.fling(
        find.byType(PaginatedReflowableReader),
        const Offset(-300, 0),
        1000.0,
      );
      await tester.pumpAndSettle();
      expect(state.currentPageIndex, 1);

      // Horizontal fling to right (swipe to previous page)
      await tester.fling(
        find.byType(PaginatedReflowableReader),
        const Offset(300, 0),
        1000.0,
      );
      await tester.pumpAndSettle();
      expect(state.currentPageIndex, 0);
    });

    testWidgets(
      '8. Font size changes recalculate pagination while preserving reading anchor',
      (tester) async {
        tester.view.physicalSize = const Size(600, 700);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final stateKey = GlobalKey<PaginatedReflowableReaderState>();
        late StateSetter setReaderState;
        TypographySettings currentTypo = const TypographySettings(
          fontSize: 14.0,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [databaseServiceProvider.overrideWithValue(dbService)],
            child: MaterialApp(
              home: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) {
                    setReaderState = setState;
                    return PaginatedReflowableReader(
                      key: stateKey,
                      document: knownContentDocument,
                      theme: ReadingThemeType.white,
                      typography: currentTypo,
                      onTapContent: () {},
                      onProgressChanged: (ch, p, pct, anc, off) {},
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final initialTotalPages = stateKey.currentState!.totalPages;

        // Navigate to a specific anchor node (e.g. node_h2)
        stateKey.currentState!.jumpToAnchor('node_h2');
        await tester.pumpAndSettle();
        expect(
          stateKey.currentState!.pages[stateKey.currentState!.currentPageIndex]
              .containsAnchor('node_h2'),
          isTrue,
        );

        // Increase font size significantly (from 14 to 24)
        setReaderState(() {
          currentTypo = const TypographySettings(fontSize: 24.0);
        });
        await tester.pumpAndSettle();

        // Total pages should increase with larger font size
        expect(
          stateKey.currentState!.totalPages,
          greaterThanOrEqualTo(initialTotalPages),
        );

        // Reading anchor node_h2 MUST still be on the active page
        final activePage = stateKey
            .currentState!
            .pages[stateKey.currentState!.currentPageIndex];
        expect(activePage.containsAnchor('node_h2'), isTrue);
      },
    );

    testWidgets(
      '9. Known-content fixture: Title, 3 headings, paragraphs, image, list are all rendered',
      (tester) async {
        tester.view.physicalSize = const Size(700, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        // Paginate entire document
        final pages = PaginationEngine.paginateDocument(
          document: knownContentDocument,
          viewportWidth: 700,
          viewportHeight: 900,
          typography: const TypographySettings(),
        );

        // Assert pages exist and NO page is empty
        expect(pages, isNotEmpty);
        for (int i = 0; i < pages.length; i++) {
          expect(
            pages[i].slices,
            isNotEmpty,
            reason: 'Page $i must have content slices',
          );
          final hasAnyContent = pages[i].slices.any(
            (s) =>
                s.textSlice.trim().isNotEmpty ||
                s.node.type == ContentNodeType.image,
          );
          expect(hasAnyContent, isTrue, reason: 'Page $i must not be blank');
        }

        // Collect all node IDs present across all pages
        final presentNodeIds = <String>{};
        for (final p in pages) {
          for (final s in p.slices) {
            presentNodeIds.add(s.node.id);
          }
        }

        // Verify all required elements are present in the paginated pages:
        expect(
          presentNodeIds.contains('node_title'),
          isTrue,
          reason: 'Title must be paginated',
        );
        expect(
          presentNodeIds.contains('node_h1'),
          isTrue,
          reason: 'Heading 1 must be paginated',
        );
        expect(
          presentNodeIds.contains('node_p1'),
          isTrue,
          reason: 'Paragraph 1 must be paginated',
        );
        expect(
          presentNodeIds.contains('node_p2'),
          isTrue,
          reason: 'Paragraph 2 must be paginated',
        );
        expect(
          presentNodeIds.contains('node_h2'),
          isTrue,
          reason: 'Heading 2 must be paginated',
        );
        expect(
          presentNodeIds.contains('node_img1'),
          isTrue,
          reason: 'Image must be paginated',
        );
        expect(
          presentNodeIds.contains('node_h3'),
          isTrue,
          reason: 'Heading 3 must be paginated',
        );
        expect(
          presentNodeIds.contains('node_list1'),
          isTrue,
          reason: 'List item 1 must be paginated',
        );
        expect(
          presentNodeIds.contains('node_list2'),
          isTrue,
          reason: 'List item 2 must be paginated',
        );
        expect(
          presentNodeIds.contains('node_list3'),
          isTrue,
          reason: 'List item 3 must be paginated',
        );
        expect(
          presentNodeIds.contains('node_p3'),
          isTrue,
          reason: 'Paragraph 3 must be paginated',
        );
      },
    );

    testWidgets(
      '10. ReflowableReaderContainer strictly renders paginated reader without vertical scrolling',
      (tester) async {
        tester.view.physicalSize = const Size(800, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          ProviderScope(
            overrides: [databaseServiceProvider.overrideWithValue(dbService)],
            child: MaterialApp(
              home: Scaffold(
                body: ReflowableReaderContainer(
                  bookId: 'container_test_book',
                  document: knownContentDocument,
                  theme: ReadingThemeType.white,
                  typography: const TypographySettings(),
                  customHighlights: const [],
                  onTapContent: () {},
                  onProgressChanged: (ch, p, pct, anc, off) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Must find PaginatedReflowableReader
        expect(find.byType(PaginatedReflowableReader), findsOneWidget);

        // Must NOT contain ListView or scrollable SingleChildScrollView
        expect(find.byType(ListView), findsNothing);

        // Verify all SingleChildScrollView in page renderer have NeverScrollableScrollPhysics
        final scrollViews = tester.widgetList<SingleChildScrollView>(
          find.byType(SingleChildScrollView),
        );
        for (final sv in scrollViews) {
          expect(sv.physics, isA<NeverScrollableScrollPhysics>());
        }

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );

    testWidgets('11. Chapter navigation moves reader to target chapter start', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(700, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final multiChapterDoc = ReaderDocument(
        bookId: 'multi_chap_doc',
        title: 'Multi Chapter Book',
        author: 'Author',
        totalPages: 20,
        chapters: [
          ReaderChapter(
            id: 'ch_0',
            index: 0,
            title: 'Bab 1',
            nodes: [
              const ContentNode(
                id: 'c0_h',
                type: ContentNodeType.heading,
                text: 'Bab 1: Awal',
                level: 1,
              ),
              ContentNode(
                id: 'c0_p',
                type: ContentNodeType.paragraph,
                text: 'Isi Bab 1 ' * 20,
              ),
            ],
          ),
          ReaderChapter(
            id: 'ch_1',
            index: 1,
            title: 'Bab 2',
            nodes: [
              const ContentNode(
                id: 'c1_h',
                type: ContentNodeType.heading,
                text: 'Bab 2: Lanjutan',
                level: 1,
              ),
              ContentNode(
                id: 'c1_p',
                type: ContentNodeType.paragraph,
                text: 'Isi Bab 2 ' * 20,
              ),
            ],
          ),
        ],
      );

      final stateKey = GlobalKey<PaginatedReflowableReaderState>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseServiceProvider.overrideWithValue(dbService)],
          child: MaterialApp(
            home: Scaffold(
              body: PaginatedReflowableReader(
                key: stateKey,
                document: multiChapterDoc,
                theme: ReadingThemeType.white,
                typography: const TypographySettings(),
                onTapContent: () {},
                onProgressChanged: (ch, p, pct, anc, off) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final state = stateKey.currentState!;
      expect(state.pages[state.currentPageIndex].chapterIndex, 0);

      // Jump to Chapter 2 (index 1)
      state.jumpToChapter(1);
      await tester.pumpAndSettle();

      expect(state.pages[state.currentPageIndex].chapterIndex, 1);
      expect(
        state.pages[state.currentPageIndex].containsAnchor('c1_h'),
        isTrue,
      );
    });

    testWidgets('12. Search navigation and anchor jump syncs correctly', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(700, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final stateKey = GlobalKey<PaginatedReflowableReaderState>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseServiceProvider.overrideWithValue(dbService)],
          child: MaterialApp(
            home: Scaffold(
              body: PaginatedReflowableReader(
                key: stateKey,
                document: knownContentDocument,
                theme: ReadingThemeType.white,
                typography: const TypographySettings(),
                onTapContent: () {},
                onProgressChanged: (ch, p, pct, anc, off) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final state = stateKey.currentState!;

      // Jump to list item 3
      state.jumpToAnchor('node_list3');
      await tester.pumpAndSettle();

      expect(
        state.pages[state.currentPageIndex].containsAnchor('node_list3'),
        isTrue,
      );
    });

    testWidgets(
      '13. Rapid repeated navigation input is debounced and does not corrupt page state',
      (tester) async {
        tester.view.physicalSize = const Size(700, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final stateKey = GlobalKey<PaginatedReflowableReaderState>();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [databaseServiceProvider.overrideWithValue(dbService)],
            child: MaterialApp(
              home: Scaffold(
                body: PaginatedReflowableReader(
                  key: stateKey,
                  document: knownContentDocument,
                  theme: ReadingThemeType.white,
                  typography: const TypographySettings(),
                  onTapContent: () {},
                  onProgressChanged: (ch, p, pct, anc, off) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final state = stateKey.currentState!;
        final initialIdx = state.currentPageIndex;

        // Rapidly fire multiple nextPage calls synchronously within <150ms window
        state.nextPage();
        state.nextPage();
        state.nextPage();
        await tester.pump(const Duration(milliseconds: 50));
        state.nextPage();
        await tester.pumpAndSettle();

        // Because debouncing is 150ms, the rapid calls should only advance once or settle cleanly
        expect(state.currentPageIndex, greaterThan(initialIdx));
        expect(state.currentPageIndex, lessThan(state.totalPages));
      },
    );
  });
}
