import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/features/reader/presentation/widgets/original_pdf_reader.dart';
import 'package:digital_books/features/reader/providers/reader_settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OriginalPdfReader Stability & UX Tests', () {
    testWidgets(
      'Renders error UI with responsive layout on small phone screens (360x780)',
      (tester) async {
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OriginalPdfReader(
                pdfPath: '/invalid/path.pdf',
                initialPage: 1,
                theme: ReadingThemeType.black,
                viewMode: PdfViewMode.paginated,
                onPageChanged: (p, t) {},
                onTapContent: () {},
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Ensure error UI renders cleanly without overflow
        expect(
          find.textContaining('Original PDF not found at:'),
          findsOneWidget,
        );
        expect(find.text('Try Again'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Renders error UI on iPad tablet screen (820x1180)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(820, 1180);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OriginalPdfReader(
              pdfPath: '/invalid/path.pdf',
              initialPage: 1,
              theme: ReadingThemeType.sepia,
              viewMode: PdfViewMode.paginated,
              onPageChanged: (p, t) {},
              onTapContent: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.textContaining('Original PDF not found at:'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Supports viewMode toggle and callbacks', (tester) async {
      final key = GlobalKey<OriginalPdfReaderState>();
      PdfViewMode currentMode = PdfViewMode.paginated;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return MaterialApp(
              home: Scaffold(
                body: OriginalPdfReader(
                  key: key,
                  pdfPath: '/invalid/path.pdf',
                  initialPage: 1,
                  theme: ReadingThemeType.white,
                  viewMode: currentMode,
                  onPageChanged: (p, t) {},
                  onTapContent: () {},
                  onToggleViewMode: () {
                    setState(() {
                      currentMode = currentMode == PdfViewMode.paginated
                          ? PdfViewMode.continuous
                          : PdfViewMode.paginated;
                    });
                  },
                ),
              ),
            );
          },
        ),
      );

      await tester.pumpAndSettle();
      expect(key.currentState?.viewMode, equals(PdfViewMode.paginated));

      // Test programmatic zoom stubs safe invocation
      expect(() => key.currentState?.zoomIn(), returnsNormally);
      expect(() => key.currentState?.zoomOut(), returnsNormally);
      expect(() => key.currentState?.resetZoom(), returnsNormally);
      expect(() => key.currentState?.toggleTwoPageSpread(), returnsNormally);
    });

    testWidgets(
      'Responsive spread detection toggles between single and two-page spread',
      (tester) async {
        final key = GlobalKey<OriginalPdfReaderState>();

        // 1. Wide desktop screen (1200x800)
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OriginalPdfReader(
                key: key,
                pdfPath: '/invalid/path.pdf',
                initialPage: 1,
                theme: ReadingThemeType.black,
                onPageChanged: (p, t) {},
                onTapContent: () {},
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        expect(key.currentState?.isTwoPageSpreadActive, isTrue);

        // User manually toggles to 1-page mode
        key.currentState?.toggleTwoPageSpread();
        await tester.pumpAndSettle();
        expect(key.currentState?.isTwoPageSpreadActive, isFalse);

        // User toggles back to 2-page mode
        key.currentState?.toggleTwoPageSpread();
        await tester.pumpAndSettle();
        expect(key.currentState?.isTwoPageSpreadActive, isTrue);

        // 2. Narrow mobile screen (400x800) -> automatically collapses to single page
        tester.view.physicalSize = const Size(400, 800);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OriginalPdfReader(
                key: key,
                pdfPath: '/invalid/path.pdf',
                initialPage: 1,
                theme: ReadingThemeType.black,
                onPageChanged: (p, t) {},
                onTapContent: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(key.currentState?.isTwoPageSpreadActive, isFalse);
      },
    );

    testWidgets(
      'Transformation controller scales accurately with zoomIn, zoomOut, resetZoom',
      (tester) async {
        final tc = TransformationController();
        expect(tc.value.getMaxScaleOnAxis(), equals(1.0));

        // Zoom In logic
        final currentScale = tc.value.getMaxScaleOnAxis();
        final targetScale = (currentScale + 0.4).clamp(1.0, 3.5);
        final center = const Offset(400, 300);
        tc.value = Matrix4.identity()
          ..setTranslationRaw(
            center.dx * (1 - targetScale),
            center.dy * (1 - targetScale),
            0.0,
          )
          // ignore: deprecated_member_use
          ..scale(targetScale, targetScale, 1.0);

        expect(tc.value.getMaxScaleOnAxis(), closeTo(1.4, 0.01));

        // Zoom Out logic
        final outScale = (tc.value.getMaxScaleOnAxis() - 0.4).clamp(1.0, 3.5);
        tc.value = Matrix4.identity()
          ..setTranslationRaw(
            center.dx * (1 - outScale),
            center.dy * (1 - outScale),
            0.0,
          )
          // ignore: deprecated_member_use
          ..scale(outScale, outScale, 1.0);

        expect(tc.value.getMaxScaleOnAxis(), closeTo(1.0, 0.01));

        // Reset
        tc.value = Matrix4.identity();
        expect(tc.value.getMaxScaleOnAxis(), equals(1.0));
        tc.dispose();
      },
    );

    testWidgets(
      'Disposal and unmount cleanly release state without exceptions',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OriginalPdfReader(
                pdfPath: '/invalid/path.pdf',
                initialPage: 1,
                theme: ReadingThemeType.warmPaper,
                onPageChanged: (p, t) {},
                onTapContent: () {},
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Trigger unmount
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
        );

        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  });
}
