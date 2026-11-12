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
    ReadingMode mode = ReadingMode.reflowable,
    ReadingThemeType theme = ReadingThemeType.black,
    TargetPlatform platform = TargetPlatform.macOS,
  }) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        databaseServiceProvider.overrideWithValue(dbService),
        bookBookmarksStreamProvider(
          testBook.id,
        ).overrideWith((ref) => Stream.value(<Bookmark>[])),
        bookAnnotationsStreamProvider(
          testBook.id,
        ).overrideWith((ref) => Stream.value(<BookAnnotation>[])),
        activeReadingModeProvider(testBook.id).overrideWith((ref) => mode),
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
              width: 1200,
              height: 800,
              child: ReadingScreen(book: testBook, initialMode: mode),
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
  });
}
