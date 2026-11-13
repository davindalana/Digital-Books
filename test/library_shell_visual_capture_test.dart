// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:digital_books/core/constants/app_strings.dart';
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/core/providers/database_providers.dart';
import 'package:digital_books/core/theme/app_theme_tokens.dart';
import 'package:digital_books/features/library/presentation/screens/library_screen.dart';
import 'helpers/test_evidence_dir.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final evidenceDir = resolveTestEvidenceDirectory('phase_2_shell');

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

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dbService = DatabaseService(db);
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

  final sampleBooks = [
    Book(
      id: 'book-1',
      title: 'Bicara Itu Ada Seninya',
      author: 'Oh Su Hyang',
      originalPdfPath: '/path/bicara.pdf',
      totalPages: 255,
      isScanned: true,
      createdAt: DateTime.now().subtract(const Duration(days: 5)),
      updatedAt: DateTime.now(),
    ),
    Book(
      id: 'book-2',
      title: 'Laut Bercerita',
      author: 'Leila S. Chudori',
      originalPdfPath: '/path/laut.pdf',
      totalPages: 379,
      isScanned: false,
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
      updatedAt: DateTime.now(),
    ),
    Book(
      id: 'book-3',
      title: 'The Devotion of Suspect X',
      author: 'Keigo Higashino',
      originalPdfPath: '/path/suspect.pdf',
      totalPages: 320,
      isScanned: false,
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      updatedAt: DateTime.now(),
    ),
  ];

  Widget buildCaptureApp({
    required GlobalKey key,
    required double width,
    required double height,
  }) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        databaseServiceProvider.overrideWithValue(dbService),
        allBooksStreamProvider.overrideWith((ref) => Stream.value(sampleBooks)),
        recentlyAddedStreamProvider.overrideWith(
          (ref) => Stream.value(sampleBooks),
        ),
        currentlyReadingStreamProvider.overrideWith(
          (ref) => Stream.value([
            BookWithProgress(
              book: sampleBooks[0],
              progress: ReadingProgress(
                id: 'prog-1',
                bookId: sampleBooks[0].id,
                currentChapter: 1,
                currentPosition: 20,
                progressPercentage: 0.0784,
                lastReadAt: DateTime.now(),
              ),
            ),
          ]),
        ),
        unstartedBooksStreamProvider.overrideWith(
          (ref) => Stream.value(
            sampleBooks.length > 1 ? sampleBooks.sublist(1) : <Book>[],
          ),
        ),
        finishedBooksStreamProvider.overrideWith(
          (ref) => Stream.value(<BookWithProgress>[]),
        ),
        collectionsStreamProvider.overrideWith(
          (ref) => Stream.value([
            Collection(
              id: 'col-1',
              name: 'Filsafat & Psikologi',
              description: 'Koleksi pengembangan diri',
              createdAt: DateTime.now(),
            ),
          ]),
        ),
        collectionBookCountsStreamProvider.overrideWith(
          (ref) => Stream.value({'col-1': 2}),
        ),
        searchBooksStreamProvider.overrideWith(
          (ref) => Stream.value(sampleBooks),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          platform: TargetPlatform.macOS,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: AppThemeTokens.darkBackground,
        ),
        home: Scaffold(
          backgroundColor: AppThemeTokens.darkBackground,
          body: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: width,
              height: height,
              child: const LibraryScreen(),
            ),
          ),
        ),
      ),
    );
  }

  group('Phase 2 — Visual Evidence Capture across 3 macOS Breakpoints', () {
    testWidgets(
      'Capture 1 & 2: Compact Window (700x650pt) — Sedang Dibaca & Semua Buku',
      (tester) async {
        final key = GlobalKey();
        await tester.binding.setSurfaceSize(const Size(700, 650));
        tester.view.physicalSize = const Size(1400, 1300);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          buildCaptureApp(key: key, width: 700, height: 650),
        );
        await tester.pumpAndSettle();

        await captureScreen(
          tester,
          key: key,
          filename: '01_compact_700_sedang_dibaca.png',
        );

        // Tap 'Semua Buku' in rail
        await tester.tap(find.byTooltip(AppStrings.navSemuaBuku));
        await tester.pumpAndSettle();

        await captureScreen(
          tester,
          key: key,
          filename: '02_compact_700_semua_buku.png',
        );
        await teardownWidget(tester);
      },
    );

    testWidgets(
      'Capture 3 & 4: Standard Window (900x700pt) — Sedang Dibaca & Semua Buku',
      (tester) async {
        final key = GlobalKey();
        await tester.binding.setSurfaceSize(const Size(900, 700));
        tester.view.physicalSize = const Size(1800, 1400);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          buildCaptureApp(key: key, width: 900, height: 700),
        );
        await tester.pumpAndSettle();

        await captureScreen(
          tester,
          key: key,
          filename: '03_standard_900_sedang_dibaca.png',
        );

        // Tap 'Semua Buku' in sidebar
        await tester.tap(find.text(AppStrings.navSemuaBuku));
        await tester.pumpAndSettle();

        await captureScreen(
          tester,
          key: key,
          filename: '04_standard_900_semua_buku.png',
        );
        await teardownWidget(tester);
      },
    );

    testWidgets(
      'Capture 5 & 6: Expansive Window (1280x800pt) — Sedang Dibaca & Semua Buku',
      (tester) async {
        final key = GlobalKey();
        await tester.binding.setSurfaceSize(const Size(1280, 800));
        tester.view.physicalSize = const Size(2560, 1600);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          buildCaptureApp(key: key, width: 1280, height: 800),
        );
        await tester.pumpAndSettle();

        await captureScreen(
          tester,
          key: key,
          filename: '05_expansive_1280_sedang_dibaca.png',
        );

        // Tap 'Semua Buku' in sidebar
        await tester.tap(find.text(AppStrings.navSemuaBuku));
        await tester.pumpAndSettle();

        await captureScreen(
          tester,
          key: key,
          filename: '06_expansive_1280_semua_buku.png',
        );
        await teardownWidget(tester);
      },
    );
  });
}
