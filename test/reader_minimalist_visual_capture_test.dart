// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
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

  final evidenceDir = Directory('docs/visual_evidence/minimalist_ui');
  const processedDocPath =
      '/Users/davindalana/Documents/DigitalBooks/books/7b3dcbf3-0f23-4c6d-8044-d525257dac00.json';
  const pdfFixturePath = 'test/fixtures/corpus/01_single_column_novel.pdf';

  late AppDatabase db;
  late DatabaseService dbService;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final family in ['Literata', 'Palatino', 'Inter', 'Georgia']) {
      final fontPath =
          File('/System/Library/Fonts/Supplemental/Georgia.ttf').existsSync()
          ? '/System/Library/Fonts/Supplemental/Georgia.ttf'
          : '/System/Library/Fonts/Supplemental/Arial.ttf';
      if (File(fontPath).existsSync()) {
        final bytes = File(fontPath).readAsBytesSync();
        final loader = FontLoader(family)
          ..addFont(Future.value(ByteData.view(bytes.buffer)));
        await loader.load();
      }
    }
    if (!evidenceDir.existsSync()) {
      evidenceDir.createSync(recursive: true);
    }
  });

  final testBook = Book(
    id: 'test-minimalist-capture-book',
    title: 'The Let Them Theory',
    author: 'Mel Robbins',
    originalPdfPath: pdfFixturePath,
    processedBookPath: processedDocPath,
    totalPages: 272,
    isScanned: false,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dbService = DatabaseService(db);
    await db.into(db.books).insert(testBook);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> captureScreen(
    WidgetTester tester, {
    required GlobalKey key,
    required String filename,
  }) async {
    await tester.runAsync(() async {
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null) {
        final img = await boundary.toImage(pixelRatio: 2.0);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        if (bytes != null) {
          final file = File('${evidenceDir.path}/$filename');
          file.writeAsBytesSync(bytes.buffer.asUint8List());
          print('Captured: ${file.path} (${file.lengthSync()} bytes)');
        }
      }
    });
  }

  Future<void> teardownWidget(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  }

  Widget buildTestApp({
    required GlobalKey key,
    Book? book,
    double width = 1200,
    double height = 800,
    ReadingMode mode = ReadingMode.reflowable,
    ReadingThemeType theme = ReadingThemeType.black,
    TargetPlatform platform = TargetPlatform.macOS,
  }) {
    final activeBook = book ?? testBook;
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        databaseServiceProvider.overrideWithValue(dbService),
        bookBookmarksStreamProvider(
          activeBook.id,
        ).overrideWith((ref) => Stream.value(<Bookmark>[])),
        bookAnnotationsStreamProvider(
          activeBook.id,
        ).overrideWith((ref) => Stream.value(<BookAnnotation>[])),
        activeReadingModeProvider(activeBook.id).overrideWith((ref) => mode),
        readingThemeStateProvider.overrideWith((ref) => theme),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          platform: platform,
          brightness: theme.isDark ? Brightness.dark : Brightness.light,
        ),
        home: Scaffold(
          body: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: width,
              height: height,
              child: ReadingScreen(book: activeBook, initialMode: mode),
            ),
          ),
        ),
      ),
    );
  }

  group('Minimalist UI Visual Evidence Capture Suite', () {
    testWidgets('Capture 1: Book Mode with Controls Visible', (tester) async {
      final key = GlobalKey();
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      tester.view.physicalSize = const Size(2400, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildTestApp(
          key: key,
          mode: ReadingMode.reflowable,
          theme: ReadingThemeType.black,
        ),
      );
      await tester.pumpAndSettle();

      await captureScreen(
        tester,
        key: key,
        filename: '01_book_mode_controls_visible.png',
      );
      await teardownWidget(tester);
    });

    testWidgets('Capture 2: Book Mode After Auto-Hide', (tester) async {
      final key = GlobalKey();
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      tester.view.physicalSize = const Size(2400, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildTestApp(
          key: key,
          mode: ReadingMode.reflowable,
          theme: ReadingThemeType.black,
        ),
      );
      await tester.pumpAndSettle();

      // Trigger 3.2s inactivity auto-hide
      await tester.pump(const Duration(milliseconds: 3300));
      await tester.pumpAndSettle();

      await captureScreen(
        tester,
        key: key,
        filename: '02_book_mode_auto_hidden.png',
      );
      await teardownWidget(tester);
    });

    testWidgets('Capture 3: Top Edge Hover (Revealed Top Chrome)', (
      tester,
    ) async {
      final key = GlobalKey();
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      tester.view.physicalSize = const Size(2400, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildTestApp(
          key: key,
          mode: ReadingMode.reflowable,
          theme: ReadingThemeType.black,
        ),
      );
      await tester.pumpAndSettle();

      // Wait for auto-hide
      await tester.pump(const Duration(milliseconds: 3300));
      await tester.pumpAndSettle();

      // Hover at top edge (y = 25 <= 56)
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(600, 400));
      await mouse.moveTo(const Offset(600, 25));
      await tester.pump();
      await tester.pumpAndSettle();

      await captureScreen(
        tester,
        key: key,
        filename: '03_book_mode_top_edge_hover.png',
      );
      await teardownWidget(tester);
    });

    testWidgets('Capture 4: Bottom Edge Hover (Revealed Bottom Chrome)', (
      tester,
    ) async {
      final key = GlobalKey();
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      tester.view.physicalSize = const Size(2400, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildTestApp(
          key: key,
          mode: ReadingMode.reflowable,
          theme: ReadingThemeType.black,
        ),
      );
      await tester.pumpAndSettle();

      // Wait for auto-hide
      await tester.pump(const Duration(milliseconds: 3300));
      await tester.pumpAndSettle();

      // Hover at bottom edge (y = 780 >= 752)
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(600, 400));
      await mouse.moveTo(const Offset(600, 780));
      await tester.pump();
      await tester.pumpAndSettle();

      await captureScreen(
        tester,
        key: key,
        filename: '04_book_mode_bottom_edge_hover.png',
      );
      await teardownWidget(tester);
    });

    testWidgets('Capture 5: Light Theme (Theme White)', (tester) async {
      final key = GlobalKey();
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      tester.view.physicalSize = const Size(2400, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildTestApp(
          key: key,
          mode: ReadingMode.reflowable,
          theme: ReadingThemeType.white,
        ),
      );
      await tester.pumpAndSettle();

      await captureScreen(
        tester,
        key: key,
        filename: '05_book_mode_light_theme.png',
      );
      await teardownWidget(tester);
    });

    testWidgets('Capture 6: Dark Theme (Theme Black)', (tester) async {
      final key = GlobalKey();
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      tester.view.physicalSize = const Size(2400, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildTestApp(
          key: key,
          mode: ReadingMode.reflowable,
          theme: ReadingThemeType.black,
        ),
      );
      await tester.pumpAndSettle();

      await captureScreen(
        tester,
        key: key,
        filename: '06_book_mode_dark_theme.png',
      );
      await teardownWidget(tester);
    });

    testWidgets('Capture 7: Sepia Theme (Theme Sepia)', (tester) async {
      final key = GlobalKey();
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      tester.view.physicalSize = const Size(2400, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildTestApp(
          key: key,
          mode: ReadingMode.reflowable,
          theme: ReadingThemeType.sepia,
        ),
      );
      await tester.pumpAndSettle();

      await captureScreen(
        tester,
        key: key,
        filename: '07_book_mode_sepia_theme.png',
      );
      await teardownWidget(tester);
    });

    testWidgets('Capture 8: PDF Mode with Minimal Controls', (tester) async {
      final key = GlobalKey();
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      tester.view.physicalSize = const Size(2400, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildTestApp(
          key: key,
          mode: ReadingMode.originalPdf,
          theme: ReadingThemeType.black,
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      await captureScreen(
        tester,
        key: key,
        filename: '08_pdf_mode_controls_visible.png',
      );
      await teardownWidget(tester);
    });

    testWidgets('Capture 9: Long Title Truncation with Ellipsis', (tester) async {
      final key = GlobalKey();
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      tester.view.physicalSize = const Size(2400, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final longTitleBook = testBook.copyWith(
        id: 'test-long-title-book',
        title:
            'A Very Extremely Long Book Title Specifically Designed To Validate That The Top Bar Architecture Correctly Truncates With Ellipsis When Constrained By Symmetrical Clearance',
      );
      await db.into(db.books).insert(longTitleBook);

      await tester.pumpWidget(
        buildTestApp(
          key: key,
          book: longTitleBook,
          mode: ReadingMode.reflowable,
          theme: ReadingThemeType.black,
        ),
      );
      await tester.pumpAndSettle();

      await captureScreen(
        tester,
        key: key,
        filename: '09_long_title_truncation.png',
      );
      await teardownWidget(tester);
    });

    testWidgets('Capture 10: Long Chapter Subtitle Truncation with Ellipsis', (tester) async {
      final key = GlobalKey();
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      tester.view.physicalSize = const Size(2400, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final longSubtitleBook = testBook.copyWith(
        id: 'test-long-subtitle-book',
        author:
            'Professor Bartholomew Alexander Montgomery III, Distinguished Chair of Comparative Typography and Cognitive Ergonomics',
      );
      await db.into(db.books).insert(longSubtitleBook);

      await tester.pumpWidget(
        buildTestApp(
          key: key,
          book: longSubtitleBook,
          mode: ReadingMode.reflowable,
          theme: ReadingThemeType.black,
        ),
      );
      await tester.pumpAndSettle();

      await captureScreen(
        tester,
        key: key,
        filename: '10_long_subtitle_truncation.png',
      );
      await teardownWidget(tester);
    });

    testWidgets('Capture 11: Medium Window Responsive Top Bar (800dp)', (tester) async {
      final key = GlobalKey();
      await tester.binding.setSurfaceSize(const Size(800, 700));
      tester.view.physicalSize = const Size(1600, 1400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildTestApp(
          key: key,
          width: 800,
          height: 700,
          mode: ReadingMode.reflowable,
          theme: ReadingThemeType.black,
        ),
      );
      await tester.pumpAndSettle();

      await captureScreen(
        tester,
        key: key,
        filename: '11_medium_window_800dp.png',
      );
      await teardownWidget(tester);
    });

    testWidgets('Capture 12: Narrow Window Responsive Top Bar (450dp)', (tester) async {
      final key = GlobalKey();
      await tester.binding.setSurfaceSize(const Size(450, 700));
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildTestApp(
          key: key,
          width: 450,
          height: 700,
          mode: ReadingMode.reflowable,
          theme: ReadingThemeType.black,
        ),
      );
      await tester.pumpAndSettle();

      await captureScreen(
        tester,
        key: key,
        filename: '12_narrow_window_450dp.png',
      );
      await teardownWidget(tester);
    });

    testWidgets('Capture 13: Traffic Lights and Toolbar in Same Horizontal Band', (
      tester,
    ) async {
      final key = GlobalKey();
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      tester.view.physicalSize = const Size(2400, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            databaseServiceProvider.overrideWithValue(dbService),
            bookBookmarksStreamProvider(
              testBook.id,
            ).overrideWith((ref) => Stream.value(<Bookmark>[])),
            bookAnnotationsStreamProvider(
              testBook.id,
            ).overrideWith((ref) => Stream.value(<BookAnnotation>[])),
            activeReadingModeProvider(
              testBook.id,
            ).overrideWith((ref) => ReadingMode.reflowable),
            readingThemeStateProvider.overrideWith(
              (ref) => ReadingThemeType.black,
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              platform: TargetPlatform.macOS,
              brightness: Brightness.dark,
            ),
            home: Scaffold(
              body: RepaintBoundary(
                key: key,
                child: SizedBox(
                  width: 1200,
                  height: 800,
                  child: Stack(
                    children: [
                      ReadingScreen(
                        book: testBook,
                        initialMode: ReadingMode.reflowable,
                      ),
                      Positioned(
                        left: 20,
                        top: 33,
                        width: 14,
                        height: 14,
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Color(0xFFFF5F56),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 42,
                        top: 33,
                        width: 14,
                        height: 14,
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Color(0xFFFFBD2E),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 64,
                        top: 33,
                        width: 14,
                        height: 14,
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Color(0xFF27C93F),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await captureScreen(
        tester,
        key: key,
        filename: '13_macos_unified_traffic_lights_band.png',
      );
      await teardownWidget(tester);
    });
  });
}
