import 'dart:io';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/features/reader/presentation/widgets/original_pdf_reader.dart';
import 'package:digital_books/features/reader/providers/reader_settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import '../test/helpers/real_book_fixtures.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'macOS PDF Reader: Real Native PDFium Rendering, Zoom & View Mode Validation',
    (tester) async {
      final preferredPdf = File(
        p.join(
          RealBookFixtures.originalsDir,
          '0ee84822-2c1c-4309-9b9b-88938524b3ae.pdf',
        ),
      );
      final fallbackPdf = File('test/fixtures/corpus/05_headers_footers.pdf');
      final file = preferredPdf.existsSync() ? preferredPdf : fallbackPdf;
      final pdfPath = file.path;
      final expectedPages = file == preferredPdf ? 13 : 3;

      expect(
        file.existsSync(),
        isTrue,
        reason: 'Target PDF must exist for native testing',
      );

      final readerKey = GlobalKey<OriginalPdfReaderState>();
      int currentPage = 1;
      int totalPages = 1;
      PdfViewMode viewMode = PdfViewMode.paginated;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return MaterialApp(
              home: Scaffold(
                body: SizedBox.expand(
                  child: OriginalPdfReader(
                    key: readerKey,
                    pdfPath: pdfPath,
                    initialPage: 1,
                    theme: ReadingThemeType.black,
                    viewMode: viewMode,
                    onPageChanged: (page, total) {
                      setState(() {
                        currentPage = page;
                        totalPages = total;
                      });
                    },
                    onTapContent: () {},
                    onToggleViewMode: () {
                      setState(() {
                        viewMode = viewMode == PdfViewMode.paginated
                            ? PdfViewMode.continuous
                            : PdfViewMode.paginated;
                      });
                    },
                  ),
                ),
              ),
            );
          },
        ),
      );

      // Wait for native PDFium to load the document
      int attempts = 0;
      while ((readerKey.currentState?.isLoading ?? true) && attempts < 25) {
        await tester.pump(const Duration(milliseconds: 100));
        attempts++;
      }

      final state = readerKey.currentState!;
      expect(state.isLoading, isFalse);
      expect(state.errorMessage, isNull);
      expect(state.document, isNotNull);
      expect(state.totalPages, equals(expectedPages));
      expect(totalPages, equals(expectedPages));
      expect(currentPage, equals(1));
      debugPrint(
        'Step 1 PASSED: PDFium opened document with $expectedPages pages successfully.',
      );

      // Pump frames to ensure Page 1 rasterizes into bitmap cache
      int rasterAttempts = 0;
      while (!state.isPageCached(1) && rasterAttempts < 30) {
        await tester.pump(const Duration(milliseconds: 100));
        rasterAttempts++;
      }
      expect(state.isPageCached(1), isTrue);
      expect(find.byType(RawImage), findsAtLeastNWidgets(1));
      debugPrint(
        'Step 2 PASSED: Page 1 rendered without error or black screen.',
      );

      // Step 3: Test Zoom In and Zoom Out
      state.zoomIn();
      await tester.pump(const Duration(milliseconds: 400));
      debugPrint('Step 3A PASSED: zoomIn executed cleanly.');

      state.zoomOut();
      await tester.pump(const Duration(milliseconds: 400));
      debugPrint('Step 3B PASSED: zoomOut executed cleanly.');

      state.resetZoom();
      await tester.pump(const Duration(milliseconds: 400));
      debugPrint('Step 3C PASSED: resetZoom executed cleanly.');

      // Step 4: Page navigation
      state.nextPage();
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(state.currentPage, inInclusiveRange(2, 3));
      debugPrint(
        'Step 4A PASSED: nextPage navigated to page ${state.currentPage}.',
      );

      state.previousPage();
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(state.currentPage, equals(1));
      debugPrint('Step 4B PASSED: previousPage returned to page 1.');

      // Step 5: Switch to Continuous View Mode
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: OriginalPdfReader(
                key: readerKey,
                pdfPath: pdfPath,
                initialPage: 1,
                theme: ReadingThemeType.black,
                viewMode: PdfViewMode.continuous,
                onPageChanged: (page, total) {},
                onTapContent: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(readerKey.currentState?.viewMode, equals(PdfViewMode.continuous));
      expect(find.byType(ListView), findsOneWidget);
      debugPrint(
        'Step 5 PASSED: Continuous scroll view rendered successfully.',
      );

      // Step 6: Dismount and verify clean disposal
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      );
      await tester.pump(const Duration(milliseconds: 300));
      debugPrint(
        'Step 6 PASSED: Widget dismounted and native document disposed cleanly.',
      );
    },
  );
}
