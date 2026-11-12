import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';

import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/core/providers/database_providers.dart';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/core/typography/typography_settings.dart';
import 'package:digital_books/features/reader/domain/models/book_annotation.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'package:digital_books/features/reader/presentation/screens/reading_screen.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/paginated_reflowable_reader.dart';
import 'package:digital_books/features/reader/providers/reader_settings_provider.dart';

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

  final testBook = Book(
    id: 'test-minimalist-book',
    title: 'The Principles of Aesthetic Typography',
    author: 'Elena Vance',
    originalPdfPath: '/nonexistent/aesthetic_typography.pdf',
    totalPages: 180,
    isScanned: false,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  Widget createTestWidget({
    required Book book,
    ReadingThemeType theme = ReadingThemeType.black,
    ReadingMode mode = ReadingMode.originalPdf,
    TargetPlatform platform = TargetPlatform.macOS,
  }) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        databaseServiceProvider.overrideWithValue(dbService),
        bookBookmarksStreamProvider(
          book.id,
        ).overrideWith((ref) => Stream.value(<Bookmark>[])),
        bookAnnotationsStreamProvider(
          book.id,
        ).overrideWith((ref) => Stream.value(<BookAnnotation>[])),
        activeReadingModeProvider(book.id).overrideWith((ref) => mode),
        readingThemeStateProvider.overrideWith((ref) => theme),
      ],
      child: MaterialApp(
        theme: ThemeData(platform: platform),
        home: ReadingScreen(book: book, initialMode: mode),
      ),
    );
  }

  group('Reader Minimalist Apple Books UI & Interaction Tests', () {
    testWidgets(
      '1. Unified Top Bar spans full width with macOS traffic light clearance',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          createTestWidget(book: testBook, platform: TargetPlatform.macOS),
        );
        await tester.pumpAndSettle();

        // Top bar is visible
        final backButton = find.byKey(const ValueKey('reader_top_back_button'));
        expect(backButton, findsOneWidget);

        // Verify traffic-light clearance: Back button x-coordinate must be >= 80dp on macOS
        final backTopLeft = tester.getTopLeft(backButton);
        expect(backTopLeft.dx, greaterThanOrEqualTo(80.0));

        // Title is centered in the title bar
        final titleFinder = find.text('The Principles of Aesthetic Typography');
        expect(titleFinder, findsOneWidget);

        final titleCenter = tester.getCenter(titleFinder);
        // Center of 1200 width is 600. Title should be centered horizontally within +-80dp
        expect((titleCenter.dx - 600.0).abs(), lessThan(80.0));

        // Essential control buttons present
        expect(
          find.byKey(const ValueKey('reader_appearance_button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('reader_bookmark_button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('reader_annotations_button')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '2. Slim Bottom Bar sits flush at window bottom with 32dp height',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1000, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(createTestWidget(book: testBook));
        await tester.pumpAndSettle();

        // Page label exists in bottom bar
        final pageLabelFinder = find.textContaining('Hal. 1 dari');
        expect(pageLabelFinder, findsOneWidget);

        // Verify bottom bar container sits at the very bottom edge (y=700 - 32 = 668)
        final bottomBarContainerFinder = find
            .ancestor(of: pageLabelFinder, matching: find.byType(Container))
            .first;
        final bottomBarSize = tester.getSize(bottomBarContainerFinder);
        expect(bottomBarSize.height, equals(32.0));

        final bottomBarTopLeft = tester.getTopLeft(bottomBarContainerFinder);
        expect(bottomBarTopLeft.dy, equals(700.0 - 32.0));

        // Scrubbing slider exists and is configured with compact track height
        final sliderFinder = find.byType(Slider);
        expect(sliderFinder, findsOneWidget);

        final sliderTheme = tester.widget<SliderTheme>(
          find.ancestor(of: sliderFinder, matching: find.byType(SliderTheme)),
        );
        expect(sliderTheme.data.trackHeight, equals(2.5));
        expect(
          sliderTheme.data.activeTrackColor,
          equals(const Color(0xFF007AFF)),
        );
      },
    );

    testWidgets(
      '3. Auto-Hide Timer smoothly hides controls after 3.2s of inactivity',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1000, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(createTestWidget(book: testBook));
        await tester.pumpAndSettle();

        // Initially visible (top: 0.0, bottom: 0.0)
        final animatedPositioneds = tester
            .widgetList<AnimatedPositioned>(find.byType(AnimatedPositioned))
            .toList();
        final topBarPos = animatedPositioneds.firstWhere((w) => w.top != null);
        final bottomBarPos = animatedPositioneds.firstWhere(
          (w) => w.bottom != null,
        );
        expect(topBarPos.top, equals(0.0));
        expect(bottomBarPos.bottom, equals(0.0));

        // Fast-forward past the 3.2s inactivity timer
        await tester.pump(const Duration(milliseconds: 3300));
        await tester.pumpAndSettle();

        // Controls smoothly animated offscreen (top: -100, bottom: -100)
        final hiddenPositioneds = tester
            .widgetList<AnimatedPositioned>(find.byType(AnimatedPositioned))
            .toList();
        final hiddenTopPos = hiddenPositioneds.firstWhere((w) => w.top != null);
        final hiddenBottomPos = hiddenPositioneds.firstWhere(
          (w) => w.bottom != null,
        );
        expect(hiddenTopPos.top, equals(-100.0));
        expect(hiddenBottomPos.bottom, equals(-100.0));

        // Verify the top bar AnimatedOpacity is 0.0 and IgnorePointer is ignoring
        final topOpacity = tester.widget<AnimatedOpacity>(
          find
              .descendant(
                of: find.byWidget(hiddenTopPos),
                matching: find.byType(AnimatedOpacity),
              )
              .first,
        );
        expect(topOpacity.opacity, equals(0.0));

        final topIgnore = tester.widget<IgnorePointer>(
          find
              .descendant(
                of: find.byWidget(hiddenTopPos),
                matching: find.byType(IgnorePointer),
              )
              .first,
        );
        expect(topIgnore.ignoring, isTrue);
      },
    );

    testWidgets(
      '4. Edge hover smoothly reveals respective controls when hidden',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1000, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(createTestWidget(book: testBook));
        await tester.pumpAndSettle();

        // Let controls auto-hide
        await tester.pump(const Duration(milliseconds: 3300));
        await tester.pumpAndSettle();

        // Move mouse near top edge (y = 25 <= 56)
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await gesture.addPointer(location: const Offset(500, 300));
        await gesture.moveTo(const Offset(500, 25));
        await tester.pump();
        await tester.pumpAndSettle();

        // Top bar and controls are restored to top: 0.0
        final restoredPositioneds = tester
            .widgetList<AnimatedPositioned>(find.byType(AnimatedPositioned))
            .toList();
        final restoredTop = restoredPositioneds.firstWhere(
          (w) => w.top != null,
        );
        expect(restoredTop.top, equals(0.0));
      },
    );

    testWidgets('5. Tapping reading canvas toggles controls visibility', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      bool toggled = false;

      final doc = ReaderDocument(
        bookId: 'doc_toggle_test',
        title: 'Buku Uji',
        author: 'Pengarang',
        chapters: [
          const ReaderChapter(
            id: 'ch1',
            title: 'BAB I',
            index: 0,
            nodes: [
              ContentNode(
                id: 'p1',
                type: ContentNodeType.paragraph,
                text: 'Paragraf pengujian ketukan layar.',
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaginatedReflowableReader(
              document: doc,
              theme: ReadingThemeType.black,
              typography: const TypographySettings(),
              onTapContent: () => toggled = true,
              onProgressChanged: (_, _, _, _, _) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap center of canvas (x=500, y=350)
      await tester.tapAt(const Offset(500, 350));
      await tester.pumpAndSettle();

      expect(toggled, isTrue);
    });

    testWidgets(
      '6. Paginated Reflowable Reader chevrons are invisible until edge hover',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1000, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final doc = ReaderDocument(
          bookId: 'doc_chevron_test',
          title: 'Buku Navigasi',
          author: 'Pengarang',
          chapters: [
            ReaderChapter(
              id: 'ch1',
              title: 'BAB I',
              index: 0,
              nodes: List.generate(
                100,
                (i) => ContentNode(
                  id: 'p_$i',
                  type: ContentNodeType.paragraph,
                  text:
                      'Paragraf ke-$i yang sangat panjang dan memiliki banyak kata untuk menghasilkan banyak halaman dalam paginated reader sehingga tombol navigasi aktif di halaman tengah.',
                ),
              ),
            ),
          ],
        );

        const typo = TypographySettings(twoPageSpread: false);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PaginatedReflowableReader(
                document: doc,
                theme: ReadingThemeType.black,
                typography: typo,
                initialPageIndex: 5, // Page 6 (both previous and next exist)
                onTapContent: () {},
                onProgressChanged: (_, _, _, _, _) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Find the chevron icons
        final leftChevronIcon = find.byIcon(Icons.chevron_left_rounded);
        final rightChevronIcon = find.byIcon(Icons.chevron_right_rounded);
        expect(leftChevronIcon, findsOneWidget);
        expect(rightChevronIcon, findsOneWidget);

        // Verify resting opacity of both chevron containers is 0.0
        final leftOpacityWidget = tester.widget<AnimatedOpacity>(
          find
              .ancestor(
                of: leftChevronIcon,
                matching: find.byType(AnimatedOpacity),
              )
              .first,
        );
        final rightOpacityWidget = tester.widget<AnimatedOpacity>(
          find
              .ancestor(
                of: rightChevronIcon,
                matching: find.byType(AnimatedOpacity),
              )
              .first,
        );
        expect(leftOpacityWidget.opacity, equals(0.0));
        expect(rightOpacityWidget.opacity, equals(0.0));

        // Hover over left margin (x=30, y=350)
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(30, 350));
        await tester.pump();
        await tester.pumpAndSettle();

        // Left chevron fades in (opacity: 1.0)
        final leftHoveredOpacity = tester.widget<AnimatedOpacity>(
          find
              .ancestor(
                of: leftChevronIcon,
                matching: find.byType(AnimatedOpacity),
              )
              .first,
        );
        expect(leftHoveredOpacity.opacity, equals(1.0));

        // Move mouse away into center (x=500, y=350)
        await mouse.moveTo(const Offset(500, 350));
        await tester.pump();
        await tester.pumpAndSettle();

        // Left chevron fades back out to 0.0
        final leftExitedOpacity = tester.widget<AnimatedOpacity>(
          find
              .ancestor(
                of: leftChevronIcon,
                matching: find.byType(AnimatedOpacity),
              )
              .first,
        );
        expect(leftExitedOpacity.opacity, equals(0.0));
      },
    );

    testWidgets(
      '7. Unified Top & Bottom Bar styling across Light, Sepia, and Dark themes',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        for (final theme in [
          ReadingThemeType.white,
          ReadingThemeType.sepia,
          ReadingThemeType.black,
        ]) {
          await tester.pumpWidget(
            KeyedSubtree(
              key: ValueKey(theme),
              child: createTestWidget(book: testBook, theme: theme),
            ),
          );
          await tester.pumpAndSettle();

          // Top bar renders cleanly with theme
          final title = find.text('The Principles of Aesthetic Typography');
          expect(title, findsOneWidget);

          final titleWidget = tester.widget<Text>(title);
          expect(titleWidget.style?.color, equals(theme.textColor));

          // Bottom bar renders cleanly with theme
          final percentFinder = find.textContaining('%');
          expect(percentFinder, findsOneWidget);

          final percentWidget = tester.widget<Text>(percentFinder);
          expect(percentWidget.style?.color, equals(theme.textColor));
        }
      },
    );
  });
}
