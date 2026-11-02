// ignore_for_file: avoid_print, depend_on_referenced_packages

import 'dart:io';
import 'dart:math' as math;
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
import 'package:digital_books/features/reader/presentation/widgets/appearance_sheet.dart';
import 'package:digital_books/features/reader/presentation/widgets/annotations_sheet.dart';
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
    tempDir = Directory.systemTemp.createTempSync('lifecycle_100_stress_test_');
    PathProviderPlatform.instance = MockPathProviderPlatform(tempDir);
    db = AppDatabase(NativeDatabase.memory());
    dbService = DatabaseService(db);

    const mockDoc = ReaderDocument(
      bookId: 'nav_stress_book',
      title: 'Navigation Stress Book',
      author: 'QA Architect',
      totalPages: 10,
      chapters: [
        ReaderChapter(
          id: 'ch_1',
          index: 0,
          title: 'Chapter 1: The Matrix',
          nodes: [
            ContentNode(
              id: 'n_1',
              type: ContentNodeType.paragraph,
              text: 'This is a long test paragraph to verify complete navigation lifecycle stability across 100 cycles without leaks or dangling inherited dependencies.',
              sourcePdfPage: 1,
            ),
          ],
        ),
      ],
    );

    processedFile = File('${tempDir.path}/nav_stress_book.json');
    processedFile.writeAsStringSync(mockDoc.toBookDocument().toJsonString());

    await dbService.insertBook(
      BooksCompanion(
        id: const drift.Value('nav_stress_book'),
        title: const drift.Value('Navigation Stress Book'),
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
    try {
      await db.close().timeout(const Duration(milliseconds: 500));
    } catch (_) {}
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('Phase 3.5 — 100-Cycle Multi-Pathway Navigation & Lifecycle Stress Matrix', () {
    testWidgets('100-Cycle Comprehensive Stress Across 8 Navigation Pathways', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final book = await dbService.getBookById('nav_stress_book');
      expect(book, isNotNull);

      final initialRss = ProcessInfo.currentRss;
      int peakRss = initialRss;
      int totalExceptions = 0;
      int assertionCount = 0;

      final sw = Stopwatch()..start();

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

      // -----------------------------------------------------------------------
      // Pathway 1: Library -> Book Details Dialog -> Read Book -> Escape Pop (25 cycles)
      // -----------------------------------------------------------------------
      for (int i = 0; i < 25; i++) {
        try {
          await tester.longPress(find.byType(BookCard).first);
          await tester.pumpAndSettle();

          expect(find.byType(BookDetailsDialog), findsOneWidget);
          await tester.tap(find.text('Read Book'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 150));
          await tester.pumpAndSettle();

          expect(find.byType(ReadingScreen), findsOneWidget);

          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 150));
          await tester.pumpAndSettle();

          expect(find.byType(ReadingScreen), findsNothing);
          expect(find.byType(LibraryScreen), findsOneWidget);
        } catch (e, st) {
          totalExceptions++;
          print('EXCEPTION in loop: $e\n$st');
          if (e.toString().contains('_dependents.isEmpty')) assertionCount++;
        }
        peakRss = math.max(peakRss, ProcessInfo.currentRss);
      }

      // -----------------------------------------------------------------------
      // Pathway 2: Library -> Direct Tap BookCard -> ReadingScreen -> Escape Pop (25 cycles)
      // -----------------------------------------------------------------------
      for (int i = 0; i < 25; i++) {
        try {
          await tester.tap(find.byType(BookCard).first);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 150));
          await tester.pumpAndSettle();

          expect(find.byType(ReadingScreen), findsOneWidget);

          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 150));
          await tester.pumpAndSettle();

          expect(find.byType(ReadingScreen), findsNothing);
        } catch (e, st) {
          totalExceptions++;
          print('EXCEPTION in loop: $e\n$st');
          if (e.toString().contains('_dependents.isEmpty')) assertionCount++;
        }
        peakRss = math.max(peakRss, ProcessInfo.currentRss);
      }

      // -----------------------------------------------------------------------
      // Pathway 3: Dynamic DB Book Insert -> Reader Launch -> Escape Pop (10 cycles)
      // -----------------------------------------------------------------------
      for (int i = 0; i < 10; i++) {
        try {
          final dynId = 'dynamic_book_$i';
          await dbService.insertBook(
            BooksCompanion(
              id: drift.Value(dynId),
              title: drift.Value('Dynamic Book $i'),
              author: const drift.Value('Import Service'),
              originalPdfPath: drift.Value(processedFile.path),
              processedBookPath: drift.Value(processedFile.path),
              totalPages: const drift.Value(5),
              isScanned: const drift.Value(false),
              createdAt: drift.Value(DateTime.now()),
              updatedAt: drift.Value(DateTime.now()),
            ),
          );
          await tester.pumpAndSettle();

          // Find card with dynamic title
          final dynCard = find.text('Dynamic Book $i');
          if (dynCard.evaluate().isNotEmpty) {
            await tester.tap(dynCard.first);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 150));
            await tester.pumpAndSettle();

            expect(find.byType(ReadingScreen), findsOneWidget);

            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 150));
            await tester.pumpAndSettle();
          }
        } catch (e, st) {
          totalExceptions++;
          print('EXCEPTION in Pathway 3: $e\n$st');
          if (e.toString().contains('_dependents.isEmpty')) assertionCount++;
        }
        peakRss = math.max(peakRss, ProcessInfo.currentRss);
      }

      // Helper to ensure controls are revealed if auto-hide timer hid them
      Future<void> ensureControlsVisible() async {
        final backBtn = find.byKey(const ValueKey('reader_top_back_button'));
        if (backBtn.evaluate().isNotEmpty) {
          final renderBox = tester.renderObject(backBtn) as RenderBox;
          final pos = renderBox.localToGlobal(Offset.zero);
          if (pos.dy < 0) {
            await tester.tapAt(const Offset(600, 400));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 250));
          }
        }
      }

      // -----------------------------------------------------------------------
      // Pathway 4: Inside Reader -> Appearance Sheet Open & Dismiss (15 cycles)
      // -----------------------------------------------------------------------
      // Launch reader first
      await tester.tap(find.byType(BookCard).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(ReadingScreen), findsOneWidget);

      for (int i = 0; i < 15; i++) {
        try {
          await ensureControlsVisible();
          final appearanceBtn = find.byKey(const ValueKey('reader_appearance_button'));
          if (appearanceBtn.evaluate().isNotEmpty) {
            await tester.tap(appearanceBtn);
            await tester.pumpAndSettle();

            expect(find.byType(AppearanceSheet), findsOneWidget);

            // Close sheet via Escape
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();

            expect(find.byType(AppearanceSheet), findsNothing);
            expect(find.byType(ReadingScreen), findsOneWidget);
          }
        } catch (e, st) {
          totalExceptions++;
          print('EXCEPTION in Pathway 4: $e\n$st');
          if (e.toString().contains('_dependents.isEmpty')) assertionCount++;
        }
        peakRss = math.max(peakRss, ProcessInfo.currentRss);
      }

      // -----------------------------------------------------------------------
      // Pathway 5: Inside Reader -> Annotations Sheet Open & Dismiss (15 cycles)
      // -----------------------------------------------------------------------
      for (int i = 0; i < 15; i++) {
        try {
          await ensureControlsVisible();
          final annotBtn = find.byKey(const ValueKey('reader_annotations_button'));
          if (annotBtn.evaluate().isNotEmpty) {
            await tester.tap(annotBtn);
            await tester.pumpAndSettle();

            expect(find.byType(AnnotationsSheet), findsOneWidget);

            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();

            expect(find.byType(AnnotationsSheet), findsNothing);
            expect(find.byType(ReadingScreen), findsOneWidget);
          }
        } catch (e, st) {
          totalExceptions++;
          print('EXCEPTION in Pathway 5: $e\n$st');
          if (e.toString().contains('_dependents.isEmpty')) assertionCount++;
        }
        peakRss = math.max(peakRss, ProcessInfo.currentRss);
      }

      // -----------------------------------------------------------------------
      // Pathway 6: Inside Reader -> Bookmark Add & Remove Toggle (10 cycles)
      // -----------------------------------------------------------------------
      for (int i = 0; i < 10; i++) {
        try {
          await ensureControlsVisible();
          final bmBtn = find.byKey(const ValueKey('reader_bookmark_button'));
          if (bmBtn.evaluate().isNotEmpty) {
            await tester.tap(bmBtn);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 100));

            // Tap again to toggle off
            await tester.tap(bmBtn);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 100));
          }
        } catch (e, st) {
          totalExceptions++;
          print('EXCEPTION in Pathway 6: $e\n$st');
          if (e.toString().contains('_dependents.isEmpty')) assertionCount++;
        }
        peakRss = math.max(peakRss, ProcessInfo.currentRss);
      }

      // -----------------------------------------------------------------------
      // Pathway 7: Inside Reader -> Page Navigation Forward/Back (10 cycles)
      // -----------------------------------------------------------------------
      for (int i = 0; i < 10; i++) {
        try {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));

          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
        } catch (e, st) {
          totalExceptions++;
          print('EXCEPTION in loop: $e\n$st');
          if (e.toString().contains('_dependents.isEmpty')) assertionCount++;
        }
        peakRss = math.max(peakRss, ProcessInfo.currentRss);
      }

      // Close reader back to library
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(find.byType(ReadingScreen), findsNothing);

      // -----------------------------------------------------------------------
      // Pathway 8: Rapid Open & Immediate Abort / Pop while Async Loading (10 cycles)
      // -----------------------------------------------------------------------
      for (int i = 0; i < 10; i++) {
        try {
          await tester.tap(find.byType(BookCard).first);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 150));

          // Pop while async loading is active
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 150));
          await tester.pumpAndSettle();

          expect(find.byType(ReadingScreen), findsNothing);
        } catch (e, st) {
          totalExceptions++;
          print('EXCEPTION in Pathway 8: $e\n$st');
          if (e.toString().contains('_dependents.isEmpty')) assertionCount++;
        }
        peakRss = math.max(peakRss, ProcessInfo.currentRss);
      }

      sw.stop();

      // Clean unmount of widget tree & flush timers
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final finalRss = ProcessInfo.currentRss;
      final netRssDeltaMb = (finalRss - initialRss) / (1024 * 1024);
      final peakRssDeltaMb = (peakRss - initialRss) / (1024 * 1024);

      print('\n===============================================================');
      print('PHASE 3.5: 120-CYCLE MULTI-PATHWAY LIFECYCLE STRESS REPORT');
      print('===============================================================');
      print('Total Navigation Cycles: 120 cycles across 8 pathways');
      print('  - Path 1 (Dialog -> Reader -> Close): 25 cycles');
      print('  - Path 2 (Direct Card -> Reader -> Close): 25 cycles');
      print('  - Path 3 (Dynamic DB Insert -> Reader): 10 cycles');
      print('  - Path 4 (Reader -> Appearance Sheet): 15 cycles');
      print('  - Path 5 (Reader -> Annotations Sheet): 15 cycles');
      print('  - Path 6 (Reader -> Bookmark Toggle): 10 cycles');
      print('  - Path 7 (Reader -> Page Flip Traversal): 10 cycles');
      print('  - Path 8 (Rapid Open & Abort In-Flight): 10 cycles');
      print('Total Execution Duration: ${sw.elapsedMilliseconds} ms (${(sw.elapsedMilliseconds / 120).toStringAsFixed(1)} ms/cycle)');
      print('Unhandled Exceptions: $totalExceptions');
      print('Flutter Assertions (_dependents.isEmpty): $assertionCount');
      print('Initial RSS: ${(initialRss / (1024 * 1024)).toStringAsFixed(2)} MB');
      print('Peak RSS Delta: +${peakRssDeltaMb.toStringAsFixed(2)} MB');
      print('Final RSS Delta: ${netRssDeltaMb >= 0 ? "+" : ""}${netRssDeltaMb.toStringAsFixed(2)} MB');
      print('===============================================================');

      expect(totalExceptions, equals(0), reason: 'All 120 navigation cycles must complete with 0 unhandled exceptions');
      expect(assertionCount, equals(0), reason: 'Zero _dependents.isEmpty assertions must be thrown');
    });
  });
}
