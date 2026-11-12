import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';

import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/core/providers/database_providers.dart';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/features/reader/domain/models/book_annotation.dart';
import 'package:digital_books/features/reader/presentation/screens/reading_screen.dart';
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

  Book createTestBook({
    String id = 'test-top-bar-book',
    String title = 'The Art of Computer Systems',
    String author = 'Donald E. Knuth',
  }) {
    return Book(
      id: id,
      title: title,
      author: author,
      originalPdfPath: '/nonexistent/systems.pdf',
      totalPages: 350,
      isScanned: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  Widget buildTopBarTestWidget({
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
        theme: ThemeData(
          platform: platform,
          brightness: theme.isDark ? Brightness.dark : Brightness.light,
        ),
        home: ReadingScreen(book: book, initialMode: mode),
      ),
    );
  }

  group('Reader Top Bar Refinement — True Center Alignment & Minimalist macOS UI', () {
    testWidgets(
      '1. Title center strictly equals window center (titleCenter.dx == windowWidth / 2.0)',
      (tester) async {
        const widths = [1200.0, 960.0, 800.0];
        final book = createTestBook();

        for (final width in widths) {
          await tester.binding.setSurfaceSize(Size(width, 700));
          await tester.pumpWidget(
            buildTopBarTestWidget(book: book, mode: ReadingMode.originalPdf),
          );
          await tester.pumpAndSettle();

          final titleFinder = find.text(book.title);
          expect(titleFinder, findsOneWidget);

          final titleCenter = tester.getCenter(titleFinder);
          final expectedCenter = width / 2.0;

          expect(
            (titleCenter.dx - expectedCenter).abs(),
            lessThan(1.0),
            reason:
                'Title at width $width should be centered at $expectedCenter but was at ${titleCenter.dx}',
          );
        }
        await tester.binding.setSurfaceSize(null);
      },
    );

    testWidgets(
      '2. Subtitle center strictly equals window center (subtitleCenter.dx == windowWidth / 2.0)',
      (tester) async {
        const widths = [1200.0, 960.0, 800.0];
        final book = createTestBook(author: 'Prof. Donald E. Knuth');

        for (final width in widths) {
          await tester.binding.setSurfaceSize(Size(width, 700));
          await tester.pumpWidget(
            buildTopBarTestWidget(book: book, mode: ReadingMode.originalPdf),
          );
          await tester.pumpAndSettle();

          final subtitleFinder = find.text('Prof. Donald E. Knuth');
          expect(subtitleFinder, findsOneWidget);

          final subtitleCenter = tester.getCenter(subtitleFinder);
          final expectedCenter = width / 2.0;

          expect(
            (subtitleCenter.dx - expectedCenter).abs(),
            lessThan(1.0),
            reason:
                'Subtitle at width $width should be centered at $expectedCenter but was at ${subtitleCenter.dx}',
          );
        }
        await tester.binding.setSurfaceSize(null);
      },
    );

    testWidgets('3. Unequal side-group widths do not affect title position', (
      tester,
    ) async {
      const width = 1200.0;
      await tester.binding.setSurfaceSize(const Size(width, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final book = createTestBook();

      // Condition A: PDF mode at wide desktop (has Zoom in/out, view mode toggle, enhancement, appearance, annotations, bookmark)
      // Left group has: Back button (~80dp left offset + 36dp width = ~116dp).
      // Right group has: 7 buttons (width ~260dp).
      await tester.pumpWidget(
        buildTopBarTestWidget(book: book, mode: ReadingMode.originalPdf),
      );
      await tester.pumpAndSettle();

      final titleFinderA = find.text(book.title);
      final titleCenterA = tester.getCenter(titleFinderA);
      expect((titleCenterA.dx - (width / 2.0)).abs(), lessThan(1.0));

      // Condition B: Narrow width 850 where Zoom buttons are hidden (isWideDesktop is false)
      // The right group width changes significantly, while left group stays identical.
      await tester.binding.setSurfaceSize(const Size(850.0, 700));
      await tester.pumpWidget(
        buildTopBarTestWidget(book: book, mode: ReadingMode.originalPdf),
      );
      await tester.pumpAndSettle();

      final titleFinderB = find.text(book.title);
      final titleCenterB = tester.getCenter(titleFinderB);
      expect((titleCenterB.dx - (850.0 / 2.0)).abs(), lessThan(1.0));
    });

    testWidgets('4. Long title truncation with ellipsis without overflow', (
      tester,
    ) async {
      const longTitle =
          'A Very Extremely Long Book Title Specifically Designed To Validate That '
          'The Top Bar Architecture Correctly Truncates With Ellipsis When Constrained By Symmetrical Clearance';
      final book = createTestBook(title: longTitle);

      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildTopBarTestWidget(book: book, mode: ReadingMode.originalPdf),
      );
      await tester.pumpAndSettle();

      final titleFinder = find.text(longTitle);
      expect(titleFinder, findsOneWidget);

      final titleWidget = tester.widget<Text>(titleFinder);
      expect(titleWidget.maxLines, equals(1));
      expect(titleWidget.overflow, equals(TextOverflow.ellipsis));

      // Verify title center is still strictly centered
      final titleCenter = tester.getCenter(titleFinder);
      expect((titleCenter.dx - 400.0).abs(), lessThan(1.0));

      // No overflow error occurred during layout
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      '5. Long chapter subtitle truncation with ellipsis without overflow',
      (tester) async {
        const longSubtitle =
            'Professor Bartholomew Alexander Montgomery III, Distinguished Chair of Comparative Typography and Cognitive Ergonomics';
        final book = createTestBook(author: longSubtitle);

        await tester.binding.setSurfaceSize(const Size(800, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          buildTopBarTestWidget(book: book, mode: ReadingMode.originalPdf),
        );
        await tester.pumpAndSettle();

        final subtitleFinder = find.text(longSubtitle);
        expect(subtitleFinder, findsOneWidget);

        final subtitleWidget = tester.widget<Text>(subtitleFinder);
        expect(subtitleWidget.maxLines, equals(1));
        expect(subtitleWidget.overflow, equals(TextOverflow.ellipsis));

        // Verify subtitle center is still strictly centered
        final subtitleCenter = tester.getCenter(subtitleFinder);
        expect((subtitleCenter.dx - 400.0).abs(), lessThan(1.0));

        // No overflow error occurred during layout
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '6. No overlap at wide (1200), medium (800), and narrow (450) widths',
      (tester) async {
        const testWidths = [1200.0, 800.0, 450.0];
        final book = createTestBook(
          title: 'Typography & Readability in Digital Systems',
        );

        for (final width in testWidths) {
          await tester.binding.setSurfaceSize(Size(width, 700));
          await tester.pumpWidget(
            buildTopBarTestWidget(book: book, mode: ReadingMode.originalPdf),
          );
          await tester.pumpAndSettle();

          final titleFinder = find.text(book.title);
          expect(titleFinder, findsOneWidget);
          final titleRect = tester.getRect(titleFinder);

          // Left control: Back button
          final backFinder = find.byKey(
            const ValueKey('reader_top_back_button'),
          );
          expect(backFinder, findsOneWidget);
          final backRect = tester.getRect(backFinder);

          // Title left edge must never overlap with back button right edge
          expect(
            titleRect.left,
            greaterThanOrEqualTo(backRect.right),
            reason: 'Title overlapped back button at width $width',
          );

          // Right control: Appearance button
          final appearanceFinder = find.byKey(
            const ValueKey('reader_appearance_button'),
          );
          expect(appearanceFinder, findsOneWidget);
          final appearanceRect = tester.getRect(appearanceFinder);

          // Title right edge must never overlap with appearance button left edge
          expect(
            titleRect.right,
            lessThanOrEqualTo(appearanceRect.left),
            reason: 'Title overlapped appearance button at width $width',
          );

          expect(tester.takeException(), isNull);
        }
        await tester.binding.setSurfaceSize(null);
      },
    );

    testWidgets(
      '7. Consistent vertical icon alignment (centers aligned to toolbar centerline ~40dp)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final book = createTestBook();
        await tester.pumpWidget(
          buildTopBarTestWidget(book: book, mode: ReadingMode.originalPdf),
        );
        await tester.pumpAndSettle();

        // Toolbar height is 80dp, so centerline is at y = 40.0
        const expectedCenterY = 40.0;
        const tolerance = 1.0;

        final buttonKeys = [
          'reader_top_back_button',
          'reader_appearance_button',
          'reader_annotations_button',
          'reader_bookmark_button',
        ];

        for (final keyName in buttonKeys) {
          final buttonFinder = find.byKey(ValueKey(keyName));
          expect(buttonFinder, findsOneWidget);

          final center = tester.getCenter(buttonFinder);
          expect(
            (center.dy - expectedCenterY).abs(),
            lessThanOrEqualTo(tolerance),
            reason:
                'Button $keyName vertical center was ${center.dy}, expected $expectedCenterY',
          );
        }
      },
    );

    testWidgets(
      '8. Book and PDF modes share the exact same center alignment behavior',
      (tester) async {
        const width = 1100.0;
        await tester.binding.setSurfaceSize(const Size(width, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final book = createTestBook();

        // 1. PDF Mode
        await tester.pumpWidget(
          buildTopBarTestWidget(book: book, mode: ReadingMode.originalPdf),
        );
        await tester.pumpAndSettle();

        final pdfTitleFinder = find.text(book.title);
        final pdfTitleCenter = tester.getCenter(pdfTitleFinder);

        // 2. Book (Reflowable) Mode
        await tester.pumpWidget(
          buildTopBarTestWidget(book: book, mode: ReadingMode.reflowable),
        );
        await tester.pumpAndSettle();

        final bookTitleFinder = find.text(book.title);
        final bookTitleCenter = tester.getCenter(bookTitleFinder);

        // Both must be strictly centered at width / 2.0
        expect((pdfTitleCenter.dx - (width / 2.0)).abs(), lessThan(1.0));
        expect((bookTitleCenter.dx - (width / 2.0)).abs(), lessThan(1.0));
        expect((pdfTitleCenter.dx - bookTitleCenter.dx).abs(), lessThan(0.1));
      },
    );

    testWidgets(
      '9. All themes (White, Sepia, Black) preserve visual contrast and typography hierarchy',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final book = createTestBook(author: 'Donald E. Knuth');

        final themes = [
          ReadingThemeType.white,
          ReadingThemeType.sepia,
          ReadingThemeType.black,
        ];

        for (final theme in themes) {
          await tester.pumpWidget(
            KeyedSubtree(
              key: ValueKey(theme),
              child: buildTopBarTestWidget(
                book: book,
                theme: theme,
                mode: ReadingMode.originalPdf,
              ),
            ),
          );
          await tester.pumpAndSettle();

          final titleText = tester.widget<Text>(find.text(book.title));
          expect(titleText.style?.color, equals(theme.textColor));
          expect(titleText.style?.fontSize, equals(18.0));
          expect(titleText.style?.fontWeight, equals(FontWeight.w600));

          final subtitleText = tester.widget<Text>(
            find.text('Donald E. Knuth'),
          );
          expect(subtitleText.style?.color, equals(theme.secondaryTextColor));
          expect(subtitleText.style?.fontSize, equals(13.0));
          expect(subtitleText.style?.fontWeight, equals(FontWeight.w400));
        }
      },
    );

    testWidgets(
      '10. macOS unified window controls integration: traffic light clearance and shared vertical centerline',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final book = createTestBook();
        await tester.pumpWidget(
          buildTopBarTestWidget(
            book: book,
            mode: ReadingMode.originalPdf,
            platform: TargetPlatform.macOS,
          ),
        );
        await tester.pumpAndSettle();

        // 1. Back button starts at exactly 104dp on macOS
        final backButton = find.byKey(const ValueKey('reader_top_back_button'));
        expect(backButton, findsOneWidget);
        final backRect = tester.getRect(backButton);
        expect(backRect.left, equals(104.0));

        // 2. Traffic light cluster right edge is at 78.0dp in native AppKit
        // Clearance between native zoom button and Flutter back button must be 26dp (within 24-32dp)
        const nativeTrafficLightRightEdge = 78.0;
        final clearance = backRect.left - nativeTrafficLightRightEdge;
        expect(clearance, inInclusiveRange(24.0, 32.0));

        // 3. Shared vertical centerline:
        // Native traffic lights are centered at Y = 40.0dp
        // Back button, mode pill, and right controls are centered at Y = 40.0dp
        const nativeTrafficLightCenterY = 40.0;
        final backCenter = tester.getCenter(backButton);
        expect(
          (backCenter.dy - nativeTrafficLightCenterY).abs(),
          lessThanOrEqualTo(1.0),
        );

        // 4. Title and subtitle form a vertically centered group with center Y = 40.0dp
        final titleFinder = find.text(book.title);
        final subtitleFinder = find.text(book.author);
        final titleRect = tester.getRect(titleFinder);
        final subtitleRect = tester.getRect(subtitleFinder);
        final groupMidY = (titleRect.top + subtitleRect.bottom) / 2.0;
        expect(
          (groupMidY - nativeTrafficLightCenterY).abs(),
          lessThanOrEqualTo(2.0),
        );
      },
    );
  });
}
