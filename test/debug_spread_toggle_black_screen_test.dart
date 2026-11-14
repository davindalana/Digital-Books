// ignore_for_file: avoid_print

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:drift/native.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/providers/database_providers.dart';
import 'package:digital_books/features/reader/presentation/screens/reading_screen.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/reflowable_page_renderer.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/reflowable_reader_container.dart';
import 'package:digital_books/features/reader/presentation/widgets/original_pdf_reader.dart';
import 'package:digital_books/features/reader/providers/reader_settings_provider.dart';
import 'package:path/path.dart' as p;
import 'helpers/real_book_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bookId = '7b3dcbf3-0f23-4c6d-8044-d525257dac00';
  final jsonPath = p.join(RealBookFixtures.booksDir, '$bookId.json');
  final pdfPath = p.join(RealBookFixtures.originalsDir, '$bookId.pdf');

  setUpAll(() async {
    if (!checkFixtureOrSkip(jsonPath) || !checkFixtureOrSkip(pdfPath)) return;
    GoogleFonts.config.allowRuntimeFetching = false;
    final interFont = File('assets/fonts/Inter-Regular.ttf');
    if (interFont.existsSync()) {
      for (final family in ['Palatino', 'Inter', 'Georgia']) {
        final bytes = interFont.readAsBytesSync();
        final loader = FontLoader(family)
          ..addFont(Future.value(ByteData.view(bytes.buffer)));
        await loader.load();
      }
    }
  });

  setUp(() {
    if (!checkFixtureOrSkip(jsonPath) || !checkFixtureOrSkip(pdfPath)) return;
  });

  late AppDatabase db;
  late DatabaseService dbService;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dbService = DatabaseService(db);

    final testBook = Book(
      id: bookId,
      title: 'Bicara Itu Ada Seninya',
      author: 'Oh Su Hyang',
      originalPdfPath: pdfPath,
      processedBookPath: jsonPath,
      totalPages: 255,
      isScanned: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await db.into(db.books).insert(testBook);
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('ReadingScreen: toggle spread button on and off in Reflowable mode', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(934 * 2.0, 934 * 2.0);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final testBook = Book(
      id: bookId,
      title: 'Bicara Itu Ada Seninya',
      author: 'Oh Su Hyang',
      originalPdfPath: pdfPath,
      processedBookPath: jsonPath,
      totalPages: 255,
      isScanned: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseServiceProvider.overrideWithValue(dbService),
          activeReadingModeProvider(
            bookId,
          ).overrideWith((ref) => ReadingMode.reflowable),
        ],
        child: MaterialApp(
          home: ReadingScreen(
            book: testBook,
            initialMode: ReadingMode.reflowable,
          ),
        ),
      ),
    );

    // Allow async loading of document
    for (int i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    print('Looking for spread toggle button...');
    final spreadBtnFinder = find.byTooltip('Two-page view');
    final singleBtnFinder = find.byTooltip('Single-page view');

    print('Spread button found: ${spreadBtnFinder.evaluate().length}');
    print('Single button found: ${singleBtnFinder.evaluate().length}');
    print(
      'ReflowableReaderContainer count: ${find.byType(ReflowableReaderContainer).evaluate().length}',
    );
    print(
      'OriginalPdfReader count: ${find.byType(OriginalPdfReader).evaluate().length}',
    );
    print(
      'CircularProgressIndicator count: ${find.byType(CircularProgressIndicator).evaluate().length}',
    );
    print(
      'Menyiapkan buku count: ${find.text('Menyiapkan buku...').evaluate().length}',
    );

    final initialRenderers = tester
        .widgetList(find.byType(ReflowablePageRenderer))
        .toList();
    print('Initial ReflowablePageRenderer count: ${initialRenderers.length}');
    expect(initialRenderers.length, inInclusiveRange(1, 2));

    // Tap the button to toggle
    final btnToTap = spreadBtnFinder.evaluate().isNotEmpty
        ? spreadBtnFinder
        : singleBtnFinder;
    expect(btnToTap, findsOneWidget);

    print('Tapping toggle button first time...');
    await tester.tap(btnToTap);
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final afterToggle1 = tester
        .widgetList(find.byType(ReflowablePageRenderer))
        .toList();
    print(
      'ReflowablePageRenderer count after toggle 1: ${afterToggle1.length}',
    );

    // Find button to tap back
    final btnToTap2 = find.byTooltip('Two-page view').evaluate().isNotEmpty
        ? find.byTooltip('Two-page view')
        : find.byTooltip('Single-page view');
    expect(btnToTap2, findsOneWidget);

    print('Tapping toggle button second time (balik lagi)...');
    await tester.tap(btnToTap2);
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final afterToggle2 = tester
        .widgetList(find.byType(ReflowablePageRenderer))
        .toList();
    print(
      'ReflowablePageRenderer count after toggle 2: ${afterToggle2.length}',
    );

    final err = tester.takeException();
    if (err != null) {
      print('EXCEPTION OCCURRED: $err');
    }
    expect(err, isNull);
    expect(afterToggle2.length, 2);

    // Unmount and flush drift stream query timers cleanly
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
  });
}
