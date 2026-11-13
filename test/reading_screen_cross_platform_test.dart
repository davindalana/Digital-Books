import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/core/providers/database_providers.dart';
import 'package:digital_books/features/reader/domain/models/book_annotation.dart';
import 'package:digital_books/features/reader/presentation/screens/reading_screen.dart';
import 'package:digital_books/features/reader/providers/reader_settings_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late DatabaseService dbService;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dbService = DatabaseService(db);
  });

  tearDown(() async {
    await db.close();
  });

  Widget buildTestableReadingScreen(Book book) {
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
      ],
      child: MaterialApp(
        home: ReadingScreen(book: book, initialMode: ReadingMode.originalPdf),
      ),
    );
  }

  group('ReadingScreen Cross-Platform Layout & Interaction Tests', () {
    final testBook = Book(
      id: 'test_book_scanned',
      title: 'The 48 Laws Of Power',
      author: 'Robert Greene',
      originalPdfPath: '/nonexistent/48laws.pdf',
      totalPages: 13,
      isScanned: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    testWidgets(
      'Renders top and bottom floating bars on iPhone (390x844) without overflow',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(buildTestableReadingScreen(testBook));
        await tester.pumpAndSettle();

        // Top bar back button and book title
        expect(
          find.byKey(const ValueKey('reader_top_back_button')),
          findsOneWidget,
        );
        expect(find.text('The 48 Laws Of Power'), findsOneWidget);

        // Bottom bar page indicator
        expect(find.text('Page 1 of 13'), findsOneWidget);

        // Verify no RenderFlex overflow exception
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(milliseconds: 50));
      },
    );

    testWidgets(
      'Renders cleanly on small Android phone (360x780) without overflow',
      (tester) async {
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(buildTestableReadingScreen(testBook));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('reader_top_back_button')),
          findsOneWidget,
        );
        expect(find.text('The 48 Laws Of Power'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(milliseconds: 50));
      },
    );

    testWidgets(
      'Renders full desktop controls on macOS (1280x800) including zoom buttons',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(buildTestableReadingScreen(testBook));
        await tester.pumpAndSettle();

        // Desktop shows Zoom In and Zoom Out tooltips/buttons
        expect(find.byTooltip('Zoom In (Cmd +)'), findsOneWidget);
        expect(find.byTooltip('Zoom Out (Cmd -)'), findsOneWidget);
        expect(find.byTooltip('Continuous scrolling'), findsOneWidget);

        // Tap zoom in without errors
        await tester.tap(find.byTooltip('Zoom In (Cmd +)'));
        await tester.pump();
        expect(tester.takeException(), isNull);

        // Tap view mode toggle
        await tester.tap(find.byTooltip('Continuous scrolling'));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(milliseconds: 50));
      },
    );

    testWidgets(
      'Appearance sheet opens and allows theme change & layout mode selection',
      (tester) async {
        tester.view.physicalSize = const Size(820, 1180);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(buildTestableReadingScreen(testBook));
        await tester.pumpAndSettle();

        // Tap appearance icon
        await tester.tap(find.byTooltip('Appearance & Theme'));
        await tester.pumpAndSettle();

        // Verify layout selector is visible in Appearance sheet
        expect(find.text('TATA LETAK HALAMAN'), findsOneWidget);
        expect(find.text('Pages'), findsWidgets);
        expect(find.text('Gulir Vertikal'), findsOneWidget);

        // Tap Gulir Vertikal
        await tester.tap(find.text('Gulir Vertikal'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(milliseconds: 50));
      },
    );
  });
}
