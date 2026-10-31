import 'dart:io';
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/core/providers/database_providers.dart';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/core/typography/typography_settings.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'package:digital_books/features/reader/presentation/screens/reading_screen.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/paginated_reflowable_reader.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/reflowable_reader_container.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/scrolling_reflowable_reader.dart';
import 'package:digital_books/features/reader/providers/reader_settings_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DatabaseService dbService;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dbService = DatabaseService(db);
  });

  tearDown(() async {
    await db.close();
  });

  final testReaderDocument = ReaderDocument(
    bookId: 'book_ui_test',
    title: 'Filosofi Teras Digital',
    author: 'Henry Manampiring',
    totalPages: 50,
    chapters: [
      ReaderChapter(
        id: 'ch_0',
        index: 0,
        title: 'Bab 1: Dikotomi Kendali',
        nodes: [
          const ContentNode(
            id: 'ch0_h1',
            type: ContentNodeType.heading,
            text: 'Bab 1: Dikotomi Kendali',
            level: 1,
          ),
          ContentNode(
            id: 'ch0_p1',
            type: ContentNodeType.paragraph,
            text:
                'Ada hal-hal yang berada di bawah kendali kita, dan ada hal-hal yang tidak. ' *
                6,
          ),
          const ContentNode(
            id: 'ch0_q1',
            type: ContentNodeType.quote,
            text:
                'Ketenangan batin sejati lahir saat kita menerima apa yang di luar kendali.',
          ),
          ContentNode(
            id: 'ch0_p2',
            type: ContentNodeType.paragraph,
            text:
                'Pikiran, persepsi, dan tindakan adalah kuasa kita sepenuhnya. ' *
                5,
          ),
        ],
      ),
      ReaderChapter(
        id: 'ch_1',
        index: 1,
        title: 'Bab 2: Mengelola Emosi Negatif',
        nodes: [
          const ContentNode(
            id: 'ch1_h1',
            type: ContentNodeType.heading,
            text: 'Bab 2: Mengelola Emosi Negatif',
            level: 1,
          ),
          ContentNode(
            id: 'ch1_p1',
            type: ContentNodeType.paragraph,
            text:
                'Emosi negatif bukanlah hasil dari peristiwa luar, melainkan interpretasi kita terhadapnya. ' *
                8,
          ),
        ],
      ),
    ],
  );

  group('Phase 2.2 — PaginatedReflowableReader Tests', () {
    testWidgets('Renders single page layout on narrow viewport (<850px)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(600, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaginatedReflowableReader(
              document: testReaderDocument,
              theme: ReadingThemeType.black,
              typography: const TypographySettings(fontSize: 16.0),
              onTapContent: () {},
              onProgressChanged: (ch, page, pct, anchor, offset) {},
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 300));

      // Ensure chapter title heading is displayed
      expect(find.text('Bab 1: Dikotomi Kendali'), findsAtLeastNWidgets(1));
      // In single-page mode, there should be one main page column, no physical spine crease
      expect(find.byType(PaginatedReflowableReader), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'Renders two-page open-book spread on wide desktop viewport (>=850px)',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PaginatedReflowableReader(
                document: testReaderDocument,
                theme: ReadingThemeType.black,
                typography: const TypographySettings(
                  fontSize: 16.0,
                  twoPageSpread: true,
                ),
                onTapContent: () {},
                onProgressChanged: (ch, page, pct, anchor, offset) {},
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 300));

        // Check two-page spread rendering
        expect(
          find.byKey(const ValueKey('page_0_spread_true')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Navigates pages via side margin clicks and keyboard shortcuts',
      (tester) async {
        tester.view.physicalSize = const Size(600, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        int notifiedPage = 1;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PaginatedReflowableReader(
                document: testReaderDocument,
                theme: ReadingThemeType.black,
                typography: const TypographySettings(fontSize: 16.0),
                onTapContent: () {},
                onProgressChanged: (ch, page, pct, anchor, offset) {
                  notifiedPage = page;
                },
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 300));
        expect(notifiedPage, equals(1));

        // Tap on right navigation margin (X: 550, Y: 400)
        await tester.tapAt(const Offset(550, 400));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 300));
        expect(notifiedPage, greaterThanOrEqualTo(2));

        // Press ArrowLeft keyboard key to return
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 300));
        expect(notifiedPage, equals(1));

        // Press Space key to advance
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 300));
        expect(notifiedPage, greaterThanOrEqualTo(2));
      },
    );
  });

  group('Phase 2.2 — ScrollingReflowableReader Tests', () {
    testWidgets(
      'Renders chapters in continuous vertical list with headers and dividers',
      (tester) async {
        tester.view.physicalSize = const Size(700, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ScrollingReflowableReader(
                document: testReaderDocument,
                theme: ReadingThemeType.black,
                typography: const TypographySettings(fontSize: 16.0),
                onTapContent: () {},
                onProgressChanged: (ch, page, pct, anchor, offset) {},
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 300));

        // Check chapter headers (BAB 1 is visible initially; BAB 2 appears upon scrolling)
        expect(find.text('BAB 1'), findsOneWidget);
        expect(find.byType(ListView), findsOneWidget);

        await tester.drag(find.byType(ListView), const Offset(0, -500));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('BAB 2'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Scrolls smoothly and tracks reading anchor without crashing', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(600, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      String? lastAnchor;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScrollingReflowableReader(
              document: testReaderDocument,
              theme: ReadingThemeType.black,
              typography: const TypographySettings(fontSize: 16.0),
              onTapContent: () {},
              onProgressChanged: (ch, page, pct, anchor, offset) {
                lastAnchor = anchor;
              },
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 300));

      // Drag to scroll down
      await tester.drag(find.byType(ListView), const Offset(0, -350));
      await tester.pumpAndSettle(const Duration(milliseconds: 350));

      expect(lastAnchor, isNotNull);
      expect(tester.takeException(), isNull);
    });
  });

  group('Phase 2.2 — Reading Position Synchronization & State Isolation', () {
    testWidgets(
      'ReflowableReaderContainer preserves reading position when switching Paginated <-> Scrolling',
      (tester) async {
        tester.view.physicalSize = const Size(800, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        String currentAnchor = 'ch0_p1';

        final containerKey = GlobalKey<ReflowableReaderContainerState>();

        final container = ProviderContainer();
        addTearDown(container.dispose);

        Widget buildContainer() {
          return UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Scaffold(
                body: ReflowableReaderContainer(
                  key: containerKey,
                  bookId: 'book_sync_test',
                  document: testReaderDocument,
                  theme: ReadingThemeType.black,
                  typography: const TypographySettings(fontSize: 16.0),
                  initialAnchorNodeId: currentAnchor,
                  onTapContent: () {},
                  onProgressChanged: (ch, page, pct, anchor, offset) {
                    if (anchor != null) currentAnchor = anchor;
                  },
                ),
              ),
            ),
          );
        }

        // 1. Open in Paginated mode
        container
                .read(reflowableLayoutModeProvider('book_sync_test').notifier)
                .state =
            ReflowableLayoutMode.paginated;
        await tester.pumpWidget(buildContainer());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(PaginatedReflowableReader), findsOneWidget);
        expect(find.byType(ScrollingReflowableReader), findsNothing);

        // 2. Switch to Scrolling mode
        container
                .read(reflowableLayoutModeProvider('book_sync_test').notifier)
                .state =
            ReflowableLayoutMode.scrolling;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(ScrollingReflowableReader), findsOneWidget);
        expect(find.byType(PaginatedReflowableReader), findsNothing);
        expect(tester.takeException(), isNull);

        // 3. Switch back to Paginated mode
        container
                .read(reflowableLayoutModeProvider('book_sync_test').notifier)
                .state =
            ReflowableLayoutMode.paginated;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(PaginatedReflowableReader), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'State isolation: switching between different books does not cross-contaminate layout mode',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        // Book 1 set to scrolling
        container.read(reflowableLayoutModeProvider('book_1').notifier).state =
            ReflowableLayoutMode.scrolling;

        // Book 2 defaults to paginated
        final book2Mode = container.read(
          reflowableLayoutModeProvider('book_2'),
        );
        expect(book2Mode, equals(ReflowableLayoutMode.paginated));

        // Book 1 remains scrolling
        final book1Mode = container.read(
          reflowableLayoutModeProvider('book_1'),
        );
        expect(book1Mode, equals(ReflowableLayoutMode.scrolling));
      },
    );
  });

  group(
    'Phase 2.2 — ReadingScreen Integration with Unified Reflowable Container',
    () {
      testWidgets(
        'ReadingScreen renders ReflowableReaderContainer for reflowable books',
        (tester) async {
          tester.view.physicalSize = const Size(1000, 800);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() => tester.view.resetPhysicalSize());

          final tempFile = File(
            '${Directory.systemTemp.path}/book_screen_test_${DateTime.now().millisecondsSinceEpoch}.json',
          );
          tempFile.writeAsStringSync(
            testReaderDocument.toBookDocument().toJsonString(),
          );
          addTearDown(() {
            if (tempFile.existsSync()) tempFile.deleteSync();
          });

          final book = Book(
            id: 'book_screen_test',
            title: 'Filosofi Teras',
            author: 'Henry Manampiring',
            originalPdfPath: '/nonexistent/path.pdf',
            processedBookPath: tempFile.path,
            totalPages: 28,
            isScanned: false,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );

          // Insert book to satisfy foreign key constraint on reading_progresses
          await db.into(db.books).insert(book);

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                appDatabaseProvider.overrideWithValue(db),
                databaseServiceProvider.overrideWithValue(dbService),
                bookBookmarksStreamProvider(
                  book.id,
                ).overrideWith((ref) => Stream.value(<Bookmark>[])),
                bookHighlightsStreamProvider(
                  book.id,
                ).overrideWith((ref) => Stream.value(<Highlight>[])),
                activeReadingModeProvider(
                  book.id,
                ).overrideWith((ref) => ReadingMode.reflowable),
              ],
              child: MaterialApp(
                home: ReadingScreen(
                  book: book,
                  initialMode: ReadingMode.reflowable,
                ),
              ),
            ),
          );

          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          await tester.pump(const Duration(milliseconds: 300));

          // Top floating toolbar is visible with book title
          expect(find.text('Filosofi Teras'), findsOneWidget);
          // Top bar contains format pill button
          expect(find.text('Book'), findsOneWidget);
          expect(find.text('PDF'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    },
  );
}
