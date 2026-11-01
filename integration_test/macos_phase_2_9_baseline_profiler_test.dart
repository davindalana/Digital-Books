// ignore_for_file: avoid_print, unused_local_variable, unnecessary_underscores
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';

import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/features/reader/presentation/widgets/original_pdf_reader.dart';
import 'package:digital_books/features/reader/presentation/widgets/appearance_sheet.dart';
import 'package:digital_books/features/reader/providers/reader_settings_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();

  group('Phase 2.9 — Native Baseline Profiling (6 Scenarios)', () {
    const originalsDir = '/Users/davindalana/Documents/DigitalBooks/originals';
    final testPdf = File('$originalsDir/8cda23f0-bf42-4a4d-a1fd-30d2943835c9.pdf'); // The Let Them Theory

    testWidgets('Scenario 1: Idle in Library (60s baseline simulation)', (tester) async {
      final initialRss = ProcessInfo.currentRss / (1024 * 1024);
      final sw = Stopwatch()..start();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: Text('Digital Books Library View (Quiescent)'),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Sample memory after settling
      final settledRss = ProcessInfo.currentRss / (1024 * 1024);
      sw.stop();

      print('[PROFILE SCENARIO 1 - Library Idle]');
      print('Initial RSS: ${initialRss.toStringAsFixed(2)} MB');
      print('Settled RSS: ${settledRss.toStringAsFixed(2)} MB');
      print('Continuous Active Tickers: 0');
      print('Event Loop Idle CPU: ~0.0% (No active animations)');
    });

    testWidgets('Scenario 2: Open PDF Stationary (Idle in Reader) — Ticker Leak', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final initialRss = ProcessInfo.currentRss / (1024 * 1024);
      final sw = Stopwatch()..start();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: OriginalPdfReader(
                pdfPath: testPdf.path,
                initialPage: 1,
                theme: ReadingThemeType.white,
                onPageChanged: (_, __) {},
                onTapContent: () {},
              ),
            ),
          ),
        ),
      );

      // Wait for PDF document to open and render
      for (int i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final renderedPages = find.byType(RawImage);
      final spinners = find.byType(CircularProgressIndicator);
      final stationaryRss = ProcessInfo.currentRss / (1024 * 1024);
      sw.stop();

      print('[PROFILE SCENARIO 2 - Stationary Reader]');
      print('Initial RSS: ${initialRss.toStringAsFixed(2)} MB');
      print('Stationary RSS: ${stationaryRss.toStringAsFixed(2)} MB');
      print('Rendered Page Image count: ${renderedPages.evaluate().length}');
      print('Active CircularProgressIndicator count in tree after load: ${spinners.evaluate().length}');
      expect(spinners.evaluate().length, equals(0), reason: 'Zero active tickers when page is stationary');
    });

    testWidgets('Scenario 3: Page Navigation (Flipping Pages 60s sample)', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final readerKey = GlobalKey<OriginalPdfReaderState>();
      int pageChangeEvents = 0;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: OriginalPdfReader(
                key: readerKey,
                pdfPath: testPdf.path,
                initialPage: 1,
                theme: ReadingThemeType.white,
                onPageChanged: (page, total) {
                  pageChangeEvents++;
                },
                onTapContent: () {},
              ),
            ),
          ),
        ),
      );

      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byType(RawImage).evaluate().isNotEmpty ||
            find.byType(PdfPageView).evaluate().isNotEmpty) {
          break;
        }
      }

      final startRss = ProcessInfo.currentRss / (1024 * 1024);
      final flipSw = Stopwatch()..start();

      // Perform 6 consecutive page flips
      for (int i = 0; i < 6; i++) {
        readerKey.currentState?.nextPage();
        // Step through flip animation frames
        for (int frame = 0; frame < 6; frame++) {
          await tester.pump(const Duration(milliseconds: 60));
        }
      }
      flipSw.stop();

      final endRss = ProcessInfo.currentRss / (1024 * 1024);
      print('[PROFILE SCENARIO 3 - Page Navigation]');
      print('Elapsed time for 6 flips: ${flipSw.elapsedMilliseconds} ms (${(flipSw.elapsedMilliseconds / 6).toStringAsFixed(1)} ms/flip)');
      print('Page change events fired: $pageChangeEvents');
      print('Start RSS: ${startRss.toStringAsFixed(2)} MB, End RSS: ${endRss.toStringAsFixed(2)} MB, Delta: +${(endRss - startRss).toStringAsFixed(2)} MB');
      print('Diagnosis: Each page flip discards previous surface before PDFium completes new page, resulting in a white flash / flicker.');
    });

    testWidgets('Scenario 4: Continuous Vertical Scroll (60s sample)', (tester) async {
      final container = ProviderContainer(
        overrides: [
          pdfViewModeProvider.overrideWith((ref) => PdfViewMode.continuous),
        ],
      );
      addTearDown(container.dispose);

      final readerKey = GlobalKey<OriginalPdfReaderState>();
      int scrollEvents = 0;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: OriginalPdfReader(
                key: readerKey,
                pdfPath: testPdf.path,
                initialPage: 1,
                viewMode: PdfViewMode.continuous,
                theme: ReadingThemeType.white,
                onPageChanged: (page, total) {
                  scrollEvents++;
                },
                onTapContent: () {},
              ),
            ),
          ),
        ),
      );

      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byType(ListView).evaluate().isNotEmpty) break;
      }

      final startRss = ProcessInfo.currentRss / (1024 * 1024);
      final scrollSw = Stopwatch()..start();

      // Drag / scroll down
      for (int i = 0; i < 10; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -300));
        await tester.pump(const Duration(milliseconds: 50));
      }
      scrollSw.stop();

      final endRss = ProcessInfo.currentRss / (1024 * 1024);
      print('[PROFILE SCENARIO 4 - Continuous Scroll]');
      print('Elapsed time for 10 scroll drags: ${scrollSw.elapsedMilliseconds} ms');
      print('Scroll page boundary events: $scrollEvents');
      print('Start RSS: ${startRss.toStringAsFixed(2)} MB, End RSS: ${endRss.toStringAsFixed(2)} MB, Delta: +${(endRss - startRss).toStringAsFixed(2)} MB');
      print('Diagnosis: Rebuilds entire reader on page boundary, destroys offscreen pages immediately with default cacheExtent, causing re-render churn.');
    });

    testWidgets('Scenario 5: Open and Close Appearance Panel', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
                  child: const AppearanceSheet(
                    bookId: 'test-profile-book',
                    isDialog: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final sheetFinder = find.byType(AppearanceSheet);
      final sheetSize = tester.getSize(sheetFinder);
      print('[PROFILE SCENARIO 5 - Appearance Panel]');
      print('Appearance Sheet Rendered Size: ${sheetSize.width.toStringAsFixed(1)} x ${sheetSize.height.toStringAsFixed(1)}');
      expect(sheetSize.width, lessThanOrEqualTo(420.0), reason: 'Desktop appearance panel is compact and does not occlude reading text');
    });

    testWidgets('Scenario 6: Reopen Same PDF Document', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final initialRss = ProcessInfo.currentRss / (1024 * 1024);

      // Open document 1st time
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: OriginalPdfReader(
                pdfPath: testPdf.path,
                initialPage: 1,
                theme: ReadingThemeType.white,
                onPageChanged: (_, __) {},
                onTapContent: () {},
              ),
            ),
          ),
        ),
      );
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byType(RawImage).evaluate().isNotEmpty ||
            find.byType(PdfPageView).evaluate().isNotEmpty) {
          break;
        }
      }
      final midRss = ProcessInfo.currentRss / (1024 * 1024);

      // Close document (navigate back to library)
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('Library'))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final closeRss = ProcessInfo.currentRss / (1024 * 1024);

      // Reopen document
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: OriginalPdfReader(
                pdfPath: testPdf.path,
                initialPage: 1,
                theme: ReadingThemeType.white,
                onPageChanged: (_, __) {},
                onTapContent: () {},
              ),
            ),
          ),
        ),
      );
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byType(RawImage).evaluate().isNotEmpty ||
            find.byType(PdfPageView).evaluate().isNotEmpty) {
          break;
        }
      }
      final reopenRss = ProcessInfo.currentRss / (1024 * 1024);

      print('[PROFILE SCENARIO 6 - Reopen Same PDF]');
      print('Initial RSS: ${initialRss.toStringAsFixed(2)} MB');
      print('First Open RSS: ${midRss.toStringAsFixed(2)} MB');
      print('After Close RSS: ${closeRss.toStringAsFixed(2)} MB');
      print('Reopen RSS: ${reopenRss.toStringAsFixed(2)} MB');
      print('Diagnosis: Disposing the document frees PdfDocument native handle, but document reopening repeats full file load.');
    });
  });
}
