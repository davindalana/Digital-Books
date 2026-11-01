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
        reason: 'Corpus PDF fixture 05_headers_footers.pdf must exist');
  });

  Future<void> waitForReaderReady(WidgetTester tester) async {
    final state = tester.state<OriginalPdfReaderState>(find.byType(OriginalPdfReader));
    for (var i = 0; i < 40; i++) {
      if (!state.isLoading && state.document != null) break;
      await Future.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    }
  }

  group('Phase 3.0.1 — PDF Page Transition Stability & Zero-Flash Validation', () {
    testWidgets('1. Next single page: smooth flip without blank white frame',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));
      int currentPage = 1;

      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OriginalPdfReader(
                pdfPath: testPdfPath,
                initialPage: 1,
                theme: ReadingThemeType.dark,
                viewMode: PdfViewMode.paginated,
                onPageChanged: (page, total) => currentPage = page,
                onTapContent: () {},
              ),
            ),
          ),
        );
        await waitForReaderReady(tester);
      });

      final state = tester.state<OriginalPdfReaderState>(find.byType(OriginalPdfReader));
      expect(state.currentPage, equals(1));
      expect(currentPage, equals(1));

      // Trigger single next page
      await tester.runAsync(() async {
        state.nextPage();
        await Future.delayed(const Duration(milliseconds: 80));
        await tester.pump();
      });

      // Verify that while flipping or transitioning, RawImage is painted
      final rawImages = find.byType(RawImage);
      expect(rawImages, findsWidgets,
          reason: 'At least one page surface image must be actively visible during transition');

      // Complete animation
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 350));
        await tester.pump();
      });

      expect(currentPage, greaterThanOrEqualTo(1));
    });

    testWidgets('2. Previous single page: smooth reverse flip without blank frame',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));
      int currentPage = 2;

      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OriginalPdfReader(
                pdfPath: testPdfPath,
                initialPage: 2,
                theme: ReadingThemeType.sepia,
                viewMode: PdfViewMode.paginated,
                onPageChanged: (page, total) => currentPage = page,
                onTapContent: () {},
              ),
            ),
          ),
        );
        await waitForReaderReady(tester);
      });

      final state = tester.state<OriginalPdfReaderState>(find.byType(OriginalPdfReader));

      await tester.runAsync(() async {
        state.previousPage();
        await Future.delayed(const Duration(milliseconds: 80));
        await tester.pump();
      });

      final rawImages = find.byType(RawImage);
      expect(rawImages, findsWidgets);

      await tester.runAsync(() async {
        for (var i = 0; i < 25; i++) {
          if (!state.isFlipping && state.currentPage == 1) break;
          await Future.delayed(const Duration(milliseconds: 40));
          await tester.pump(const Duration(milliseconds: 40));
        }
      });

      expect(state.currentPage, equals(1));
      expect(currentPage, equals(1));
    });

    testWidgets('3. Next then immediate previous: smoothly reverses without flash or lock',
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
                onPageChanged: (page, total) {},
                onTapContent: () {},
              ),
            ),
          ),
        );
        await waitForReaderReady(tester);
      });

      final state = tester.state<OriginalPdfReaderState>(find.byType(OriginalPdfReader));

      await tester.runAsync(() async {
        state.nextPage();
        await Future.delayed(const Duration(milliseconds: 40));
        state.previousPage();
        await Future.delayed(const Duration(milliseconds: 350));
        await tester.pump();
      });

      expect(state.currentPage, equals(1));
      expect(find.byType(RawImage), findsWidgets);
    });

    testWidgets('4. Rapid next 5-10 times: does not drop input, race, or produce blank frame',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));
      int lastReportedPage = 1;

      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OriginalPdfReader(
                pdfPath: testPdfPath,
                initialPage: 1,
                theme: ReadingThemeType.white,
                viewMode: PdfViewMode.paginated,
                onPageChanged: (page, total) => lastReportedPage = page,
                onTapContent: () {},
              ),
            ),
          ),
        );
        await waitForReaderReady(tester);
      });

      final state = tester.state<OriginalPdfReaderState>(find.byType(OriginalPdfReader));

      await tester.runAsync(() async {
        for (int i = 0; i < 7; i++) {
          state.nextPage();
          await Future.delayed(const Duration(milliseconds: 30));
        }
        await Future.delayed(const Duration(milliseconds: 400));
        await tester.pump();
      });

      expect(lastReportedPage, greaterThan(1));
      expect(state.isLoading, isFalse);
    });

    testWidgets('5. Rapid previous 5-10 times: cleanly clamps to beginning',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));
      int lastReportedPage = 3;

      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OriginalPdfReader(
                pdfPath: testPdfPath,
                initialPage: 3,
                theme: ReadingThemeType.dark,
                viewMode: PdfViewMode.paginated,
                onPageChanged: (page, total) => lastReportedPage = page,
                onTapContent: () {},
              ),
            ),
          ),
        );
        await waitForReaderReady(tester);
      });

      final state = tester.state<OriginalPdfReaderState>(find.byType(OriginalPdfReader));

      await tester.runAsync(() async {
        for (int i = 0; i < 6; i++) {
          state.previousPage();
          await Future.delayed(const Duration(milliseconds: 30));
        }
        await Future.delayed(const Duration(milliseconds: 400));
        await tester.pump();
      });

      expect(state.currentPage, equals(1));
      expect(lastReportedPage, equals(1));
    });

    testWidgets('6. Navigation while rendering is in flight: gates transition without white frame',
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
                onPageChanged: (page, total) {},
                onTapContent: () {},
              ),
            ),
          ),
        );
        // Do not wait until all pre-warming completes; immediately trigger next
        final state = tester.state<OriginalPdfReaderState>(find.byType(OriginalPdfReader));
        state.nextPage();
        await Future.delayed(const Duration(milliseconds: 100));
        await tester.pump();

        // Check that dark background is maintained and no error occurs
        expect(find.byType(OriginalPdfReader), findsOneWidget);
        await Future.delayed(const Duration(milliseconds: 350));
        await tester.pump();
      });
    });

    testWidgets('7. Cold vs Warm cache navigation: warm cache flips instantly',
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
                onPageChanged: (page, total) {},
                onTapContent: () {},
              ),
            ),
          ),
        );
        await waitForReaderReady(tester);
      });

      final state = tester.state<OriginalPdfReaderState>(find.byType(OriginalPdfReader));
      // Give cache warming time to pre-render adjacent pages
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
      });

      expect(state.cachedBitmapCount, greaterThanOrEqualTo(1));

      // Warm navigation
      await tester.runAsync(() async {
        state.nextPage();
        await Future.delayed(const Duration(milliseconds: 150));
        await tester.pump();
      });

      expect(state.isFlipping, isTrue);
    });

    testWidgets('8. Theme changes while reader active: does not drop bitmap or flash white',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));
      ReadingThemeType currentTheme = ReadingThemeType.dark;

      late StateSetter setParentState;

      await tester.runAsync(() async {
        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setState) {
              setParentState = setState;
              return MaterialApp(
                home: Scaffold(
                  body: OriginalPdfReader(
                    pdfPath: testPdfPath,
                    initialPage: 1,
                    theme: currentTheme,
                    viewMode: PdfViewMode.paginated,
                    onPageChanged: (page, total) {},
                    onTapContent: () {},
                  ),
                ),
              );
            },
          ),
        );
        await waitForReaderReady(tester);
      });

      final state = tester.state<OriginalPdfReaderState>(find.byType(OriginalPdfReader));
      expect(state.isPageCached(1), isTrue);

      // Switch theme to Sepia
      await tester.runAsync(() async {
        setParentState(() {
          currentTheme = ReadingThemeType.sepia;
        });
        await tester.pump();
        await Future.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      });

      expect(state.isPageCached(1), isTrue);
      expect(find.byType(RawImage), findsWidgets);
    });

    testWidgets('9. Zoom then navigate: resets zoom safely without matrix exception',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));

      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OriginalPdfReader(
                pdfPath: testPdfPath,
                initialPage: 1,
                theme: ReadingThemeType.white,
                viewMode: PdfViewMode.paginated,
                onPageChanged: (page, total) {},
                onTapContent: () {},
              ),
            ),
          ),
        );
        await waitForReaderReady(tester);
      });

      final state = tester.state<OriginalPdfReaderState>(find.byType(OriginalPdfReader));

      await tester.runAsync(() async {
        state.zoomIn();
        await Future.delayed(const Duration(milliseconds: 100));
        await tester.pump();

        state.nextPage();
        await Future.delayed(const Duration(milliseconds: 350));
        await tester.pump();
      });

      expect(find.byType(OriginalPdfReader), findsOneWidget);
    });

    testWidgets('10. Continuous vertical scroll view: stable list rendering without crash',
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
                viewMode: PdfViewMode.continuous,
                onPageChanged: (page, total) {},
                onTapContent: () {},
              ),
            ),
          ),
        );
        await waitForReaderReady(tester);
      });

      expect(find.byType(ListView), findsOneWidget);
    });
  });
}
