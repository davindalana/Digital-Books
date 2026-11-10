// ignore_for_file: avoid_print
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_books/features/reader/presentation/widgets/appearance_sheet.dart';
import 'package:digital_books/features/reader/providers/reader_settings_provider.dart';
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/features/reader/presentation/screens/reading_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 2.9 — Reader UX & Toolbar Stabilization Tests', () {
    final testBook = Book(
      id: 'test-ux-book',
      title: 'UX Test Book',
      author: 'Author',
      originalPdfPath: 'test/fixtures/corpus/01_single_column_novel.pdf',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      isScanned: false,
      totalPages: 10,
    );

    testWidgets(
      '1. Compact Appearance Sheet on Desktop constrains width to <= 420 pt',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 800));

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 420,
                      maxHeight: 560,
                    ),
                    child: const AppearanceSheet(
                      bookId: 'test-ux-book',
                      isDialog: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        final sheetFinder = find.byType(AppearanceSheet);
        expect(sheetFinder, findsOneWidget);
        final size = tester.getSize(sheetFinder);
        expect(size.width, lessThanOrEqualTo(420.0));
        expect(find.text('Pengaturan Tampilan'), findsOneWidget);
      },
    );

    testWidgets(
      '2. Appearance Sheet in PDF Mode hides font size and typography controls',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            activeReadingModeProvider(
              'test-ux-book',
            ).overrideWith((ref) => ReadingMode.originalPdf),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: Scaffold(
                body: AppearanceSheet(bookId: 'test-ux-book', isDialog: true),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // In PDF mode, font family selector should be hidden
        expect(find.text('FONT'), findsNothing);
        expect(
          find.text(
            'Pengaturan ukuran font dan tipografi teks berlaku dalam mode Buku (Reflowable).',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '3. Appearance Sheet in Reflowable Mode displays full typography controls',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            activeReadingModeProvider(
              'test-ux-book',
            ).overrideWith((ref) => ReadingMode.reflowable),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: Scaffold(
                body: AppearanceSheet(bookId: 'test-ux-book', isDialog: true),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // In Reflowable mode, font family and typography selectors are visible
        expect(find.text('FONT'), findsOneWidget);
        expect(find.text('Georgia'), findsOneWidget);
        expect(find.text('Palatino'), findsOneWidget);
      },
    );

    testWidgets(
      '4. Spread toggle is gated and shows explanation tooltip in Continuous Scrolling',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            pdfViewModeProvider.overrideWith((ref) => PdfViewMode.continuous),
            activeReadingModeProvider(
              'test-ux-book',
            ).overrideWith((ref) => ReadingMode.originalPdf),
          ],
        );
        addTearDown(container.dispose);

        await tester.binding.setSurfaceSize(const Size(1000, 700));

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: ReadingScreen(
                book: testBook,
                initialMode: ReadingMode.originalPdf,
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // In continuous mode, the spread toggle button exists but has the explanatory tooltip
        final disabledSpreadFinder = find.byTooltip(
          'Tampilan 2 halaman hanya tersedia dalam mode Halaman (Paginasi)',
        );
        expect(disabledSpreadFinder, findsOneWidget);

        // Tapping it shows the floating snackbar explanation
        await tester.tap(disabledSpreadFinder);
        await tester.pump();
        expect(find.byType(SnackBar), findsOneWidget);
        expect(
          find.text(
            'Tampilan 2 halaman hanya tersedia dalam mode Halaman (Paginasi). Silakan beralih dari Gulir Vertikal.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '5. Auto-Hide Toolbar fades out after 3.5s of inactivity and reappears on pointer movement',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            activeReadingModeProvider(
              'test-ux-book',
            ).overrideWith((ref) => ReadingMode.originalPdf),
          ],
        );
        addTearDown(container.dispose);

        await tester.binding.setSurfaceSize(const Size(1000, 700));

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: ReadingScreen(
                book: testBook,
                initialMode: ReadingMode.originalPdf,
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Controls initially visible
        final topBarFinder = find.byKey(const ValueKey('reader_toc_button'));
        expect(topBarFinder, findsOneWidget);

        // Advance past the 3.5 second inactivity timer
        await tester.pump(const Duration(milliseconds: 3600));

        // Controls animated off-screen
        final animatedPositioneds = tester
            .widgetList<AnimatedPositioned>(find.byType(AnimatedPositioned))
            .toList();
        final topBarPositioned = animatedPositioneds.firstWhere(
          (w) => w.top != null,
        );
        expect(
          topBarPositioned.top,
          equals(-100.0),
          reason: 'Top bar auto-hides offscreen after inactivity',
        );

        // Pointer movement over the reading surface restores controls
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await gesture.addPointer(location: const Offset(500, 350));
        await gesture.moveTo(const Offset(510, 360));
        await tester.pump();

        final restoredTopBar = tester
            .widgetList<AnimatedPositioned>(find.byType(AnimatedPositioned))
            .firstWhere((w) => w.top != null);
        expect(
          restoredTopBar.top,
          equals(0.0),
          reason: 'Pointer movement wakes up controls immediately',
        );
      },
    );
  });
}
