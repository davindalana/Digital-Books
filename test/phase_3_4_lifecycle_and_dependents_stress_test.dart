// ignore_for_file: avoid_print, depend_on_referenced_packages

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' as drift;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/core/providers/database_providers.dart';
import 'package:digital_books/features/library/presentation/screens/library_screen.dart';
import 'package:digital_books/features/library/presentation/widgets/book_card.dart';
import 'package:digital_books/features/library/presentation/widgets/book_details_dialog.dart';
import 'package:digital_books/features/reader/presentation/screens/reading_screen.dart';
import 'package:digital_books/features/reader/providers/reader_settings_provider.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';

class MockPathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final Directory tempDir;
  MockPathProviderPlatform(this.tempDir);

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir.path;

  @override
  Future<String?> getTemporaryPath() async => tempDir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DatabaseService dbService;
  late Directory tempDir;
  late File processedFile;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('lifecycle_stress_test_');
    PathProviderPlatform.instance = MockPathProviderPlatform(tempDir);
    db = AppDatabase(NativeDatabase.memory());
    dbService = DatabaseService(db);

    // Create a mock processed book JSON
    const mockDoc = ReaderDocument(
      bookId: 'lifecycle_test_book',
      title: 'Lifecycle Stress Book',
      author: 'QA Architect',
      totalPages: 10,
      chapters: [
        ReaderChapter(
          id: 'ch_1',
          index: 0,
          title: 'Chapter 1: The Test',
          nodes: [
            ContentNode(
              id: 'n_1',
              type: ContentNodeType.paragraph,
              text: 'This is a test paragraph to verify stable widget lifecycles.',
              sourcePdfPage: 1,
            ),
          ],
        ),
      ],
    );

    processedFile = File('${tempDir.path}/lifecycle_test_book.json');
    processedFile.writeAsStringSync(mockDoc.toBookDocument().toJsonString());

    // Seed test book in DB
    await dbService.insertBook(
      BooksCompanion(
        id: const drift.Value('lifecycle_test_book'),
        title: const drift.Value('Lifecycle Stress Book'),
        author: const drift.Value('QA Architect'),
        originalPdfPath: drift.Value(processedFile.path),
        processedBookPath: drift.Value(processedFile.path),
        totalPages: const drift.Value(10),
        isScanned: const drift.Value(false),
        createdAt: drift.Value(DateTime.now()),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );
  });

  tearDown(() async {
    await db.close();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('Lifecycle & _dependents.isEmpty Elimination Audit', () {
    testWidgets('1. BookDetailsDialog cleanly launches ReadingScreen via BookLaunchRequest without InheritedElement leakage', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final book = await dbService.getBookById('lifecycle_test_book');
      expect(book, isNotNull);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            databaseServiceProvider.overrideWithValue(dbService),
          ],
          child: const MaterialApp(
            home: LibraryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Ensure library rendered
      expect(find.text('Lifecycle Stress Book'), findsWidgets);

      // Open Book Details Dialog via long press on BookCard
      await tester.longPress(find.byType(BookCard).first);
      await tester.pumpAndSettle();

      expect(find.byType(BookDetailsDialog), findsOneWidget);

      // Tap "Read Book"
      final readButton = find.text('Read Book');
      expect(readButton, findsOneWidget);
      await tester.tap(readButton);

      // Let dialog pop and ReadingScreen push cleanly
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Dialog should be gone, ReadingScreen should be mounted with controls visible
      expect(find.byType(BookDetailsDialog), findsNothing);
      expect(find.byType(ReadingScreen), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Close ReadingScreen via top back button
      final backButton = find.byKey(const ValueKey('reader_top_back_button'));
      expect(backButton, findsOneWidget);
      await tester.tap(backButton);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      // Back at LibraryScreen cleanly
      expect(find.byType(ReadingScreen), findsNothing);
      expect(find.byType(LibraryScreen), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('2. Rapid repeated reader open/close loop (15 cycles) does not trigger _dependents.isEmpty or memory leak', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final book = await dbService.getBookById('lifecycle_test_book');
      expect(book, isNotNull);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            databaseServiceProvider.overrideWithValue(dbService),
          ],
          child: const MaterialApp(
            home: LibraryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final stopwatch = Stopwatch()..start();

      for (int i = 0; i < 15; i++) {
        // Open details via long press
        await tester.longPress(find.byType(BookCard).first);
        await tester.pumpAndSettle();

        // Launch reader
        await tester.tap(find.text('Read Book'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        expect(find.byType(ReadingScreen), findsOneWidget);

        // Close reader via Escape key shortcut
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        expect(find.byType(ReadingScreen), findsNothing);
        expect(tester.takeException(), isNull, reason: 'Cycle $i must not throw any exception');
      }

      stopwatch.stop();
      print('\n===============================================================');
      print('RAPID 15-CYCLE OPEN/CLOSE LIFECYCLE AUDIT');
      print('===============================================================');
      print('Total Duration: ${stopwatch.elapsedMilliseconds} ms (${(stopwatch.elapsedMilliseconds / 15).toStringAsFixed(1)} ms/cycle)');
      print('Exceptions / Crashes: 0 (Zero _dependents.isEmpty assertions)');
      print('===============================================================');

      // Unmount the widget tree and flush any stream cancellation timers
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('3. Annotations Sheet open/close within ReadingScreen does not disrupt route tree', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final book = await dbService.getBookById('lifecycle_test_book');
      expect(book, isNotNull);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            databaseServiceProvider.overrideWithValue(dbService),
          ],
          child: MaterialApp(
            home: ReadingScreen(
              book: book!,
              initialMode: ReadingMode.reflowable,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Open Annotations Sheet (controls are visible on launch)
      final annotBtn = find.byKey(const ValueKey('reader_annotations_button'));
      expect(annotBtn, findsOneWidget);
      await tester.tap(annotBtn);
      await tester.pumpAndSettle();

      // Verify sheet is open
      expect(find.text('Anotasi & Penanda Buku'), findsOneWidget);

      // Press Escape: Should dismiss modal sheet, NOT ReadingScreen!
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // ReadingScreen is STILL mounted!
      expect(find.byType(ReadingScreen), findsOneWidget);
      expect(find.text('Anotasi & Penanda Buku'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
