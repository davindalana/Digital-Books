// ignore_for_file: avoid_print
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_books/features/reader/presentation/widgets/original_pdf_reader.dart';
import 'package:digital_books/features/reader/providers/reader_settings_provider.dart';
import 'package:digital_books/core/theme/reading_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testPdfPath = 'test/fixtures/corpus/05_headers_footers.pdf';

  setUpAll(() {
    expect(File(testPdfPath).existsSync(), isTrue,
        reason: 'Test corpus PDF must exist');
  });

  group('Phase 2.9.2 — Non-Blocking Navigation & Flash Elimination Tests', () {
    testWidgets(
        '1. Reader opens and initializes with non-white themed background',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));

      int currentPageReported = 1;
      int totalPagesReported = 1;

      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OriginalPdfReader(
                pdfPath: testPdfPath,
                initialPage: 1,
                theme: ReadingThemeType.dark,
                viewMode: PdfViewMode.paginated,
                onPageChanged: (page, total) {
                  currentPageReported = page;
                  totalPagesReported = total;
                },
                onTapContent: () {},
              ),
            ),
          ),
        );

        final state = tester.state<OriginalPdfReaderState>(find.byType(OriginalPdfReader));
        for (var i = 0; i < 30; i++) {
          if (!state.isLoading) break;
          await Future.delayed(const Duration(milliseconds: 100));
          await tester.pump();
        }
      });

      final state =
          tester.state<OriginalPdfReaderState>(find.byType(OriginalPdfReader));
      expect(state.currentPage, equals(1));
      expect(state.isLoading, isFalse);
      expect(currentPageReported, equals(1));
      expect(totalPagesReported, equals(3));

      // Assert that background containers are NOT stark white (#FFFFFF)
      final containers = tester.widgetList<Container>(find.byType(Container));
      for (final c in containers) {
        if (c.color != null) {
          expect(c.color, isNot(equals(Colors.white)),
              reason:
                  'Background must use dark paper tone, never stark white in dark theme');
        }
      }
    });

    testWidgets(
        '2. Non-blocking navigation: rapid nextPage() during flip does not drop input',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));

      final pagesChanged = <int>[];

      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OriginalPdfReader(
                pdfPath: testPdfPath,
                initialPage: 1,
                theme: ReadingThemeType.dark,
                viewMode: PdfViewMode.paginated,
                onPageChanged: (page, total) {
                  pagesChanged.add(page);
                },
                onTapContent: () {},
              ),
            ),
          ),
        );

        final state = tester.state<OriginalPdfReaderState>(find.byType(OriginalPdfReader));
        for (var i = 0; i < 30; i++) {
          if (!state.isLoading) break;
          await Future.delayed(const Duration(milliseconds: 100));
          await tester.pump();
        }
      });

      final state =
          tester.state<OriginalPdfReaderState>(find.byType(OriginalPdfReader));
      expect(state.currentPage, equals(1));
      expect(state.isFlipping, isFalse);

      // Trigger 1st nextPage() -> starts animation toward spread 1
      state.nextPage();
      expect(state.isFlipping, isTrue, reason: 'First nextPage() triggers flip');
      expect(state.targetSpreadIndex, equals(1));

      // Advance partial frame (t ~ 0.25)
      await tester.pump(const Duration(milliseconds: 80));
      expect(state.isFlipping, isTrue);

      // Trigger 2nd nextPage() WHILE flipping is active -> non-blocking fast-forward commit!
      state.nextPage();
      // Since spread 1 is the last spread (pages 2-3 of 3), it immediately commits spread 1
      expect(state.currentSpreadIndex, equals(1));
      expect(state.currentPage, equals(3));
      expect(pagesChanged, contains(3));

      // Let animation settle
      await tester.pumpAndSettle();
      expect(state.isFlipping, isFalse);
    });

    testWidgets(
        '3. Smooth reversal: previousPage() while forward flipping reverses animation',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));

      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OriginalPdfReader(
                pdfPath: testPdfPath,
                initialPage: 1,
                theme: ReadingThemeType.dark,
                viewMode: PdfViewMode.paginated,
                onPageChanged: (p, t) {},
                onTapContent: () {},
              ),
            ),
          ),
        );

        final state = tester.state<OriginalPdfReaderState>(find.byType(OriginalPdfReader));
        for (var i = 0; i < 30; i++) {
          if (!state.isLoading) break;
          await Future.delayed(const Duration(milliseconds: 100));
          await tester.pump();
        }
      });

      final state =
          tester.state<OriginalPdfReaderState>(find.byType(OriginalPdfReader));

      // Trigger forward flip
      state.nextPage();
      expect(state.isFlipping, isTrue);

      // Mid-flip (t ~ 0.3)
      await tester.pump(const Duration(milliseconds: 100));

      // User changes mind and presses previousPage()
      state.previousPage();
      // Animation reverses back
      await tester.pumpAndSettle();

      expect(state.isFlipping, isFalse);
      expect(state.currentPage, equals(1),
          reason:
              'Smooth reversal returns reader to initial spread cleanly without overshoot');
    });

    testWidgets(
        '4. Rapid 10 inputs sequence is non-blocking and handles boundaries safely',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));

      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OriginalPdfReader(
                pdfPath: testPdfPath,
                initialPage: 1,
                theme: ReadingThemeType.sepia,
                viewMode: PdfViewMode.paginated,
                onPageChanged: (p, t) {},
                onTapContent: () {},
              ),
            ),
          ),
        );

        final state = tester.state<OriginalPdfReaderState>(find.byType(OriginalPdfReader));
        for (var i = 0; i < 30; i++) {
          if (!state.isLoading) break;
          await Future.delayed(const Duration(milliseconds: 100));
          await tester.pump();
        }
      });

      final state =
          tester.state<OriginalPdfReaderState>(find.byType(OriginalPdfReader));

      // Fire 10 rapid nextPage() calls
      for (int i = 0; i < 10; i++) {
        state.nextPage();
        await tester.pump(const Duration(milliseconds: 15));
      }

      await tester.pumpAndSettle();
      expect(state.isFlipping, isFalse);
      expect(state.currentPage, lessThanOrEqualTo(state.totalPages));
      expect(state.currentPage, equals(3),
          reason: 'Clamped at last page (page 3) without index overflow');

      // Fire 10 rapid previousPage() calls back to page 1
      for (int i = 0; i < 10; i++) {
        state.previousPage();
        await tester.pump(const Duration(milliseconds: 15));
      }

      await tester.pumpAndSettle();
      expect(state.isFlipping, isFalse);
      expect(state.currentPage, equals(1),
          reason: 'Boundary clamping prevents index underflow below page 1');
    });

    testWidgets(
        '5. Retained bitmap cache double-buffering pre-caches pages and avoids null frame flash',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));

      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OriginalPdfReader(
                pdfPath: testPdfPath,
                initialPage: 1,
                theme: ReadingThemeType.dark,
                viewMode: PdfViewMode.paginated,
                onPageChanged: (p, t) {},
                onTapContent: () {},
              ),
            ),
          ),
        );

        // Allow pre-cache renders to complete
        await Future.delayed(const Duration(milliseconds: 500));
        await tester.pump();
      });

      final state =
          tester.state<OriginalPdfReaderState>(find.byType(OriginalPdfReader));

      // Page 1 is cached
      expect(state.isPageCached(1), isTrue,
          reason: 'Page 1 must be cached in memory');

      // Check that RawImage is rendered for page 1
      expect(find.byType(RawImage), findsWidgets,
          reason:
              'Retained bitmap cache renders RawImage directly, preventing empty white frame');
    });

    testWidgets('6. Drag start during animation does not lock or stutter',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));

      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OriginalPdfReader(
                pdfPath: testPdfPath,
                initialPage: 1,
                theme: ReadingThemeType.dark,
                viewMode: PdfViewMode.paginated,
                onPageChanged: (p, t) {},
                onTapContent: () {},
              ),
            ),
          ),
        );

        final state = tester.state<OriginalPdfReaderState>(find.byType(OriginalPdfReader));
        for (var i = 0; i < 30; i++) {
          if (!state.isLoading) break;
          await Future.delayed(const Duration(milliseconds: 100));
          await tester.pump();
        }
      });

      final state =
          tester.state<OriginalPdfReaderState>(find.byType(OriginalPdfReader));

      // Start flip animation
      state.nextPage();
      await tester.pump(const Duration(milliseconds: 50));
      expect(state.isFlipping, isTrue);

      // Simulate swipe gesture during flip
      final gesture = await tester.startGesture(const Offset(800, 350));
      await gesture.moveBy(const Offset(-100, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(state.isFlipping, isFalse);
    });
  });
}
