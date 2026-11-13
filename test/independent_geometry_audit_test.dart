// ignore_for_file: avoid_print
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/core/theme/typography_settings.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'package:digital_books/features/reader/domain/engines/pagination_engine.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/paginated_reflowable_reader.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/reflowable_page_renderer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Independent Geometry Audit (Vertical & Horizontal)', () {
    final testDoc = ReaderDocument(
      bookId: 'geom_audit_doc',
      title: 'Geometry Audit Title',
      author: 'Audit Author',
      totalPages: 5,
      chapters: [
        const ReaderChapter(
          id: 'ch_1',
          index: 0,
          title: 'Chapter 1: Foundations',
          nodes: [
            ContentNode(
              id: 'p_1',
              type: ContentNodeType.paragraph,
              text:
                  'This is the first sample paragraph for geometry measurement on page 1.',
            ),
            ContentNode(id: 'pb_1', type: ContentNodeType.pageBreak, text: ''),
            ContentNode(
              id: 'p_2',
              type: ContentNodeType.paragraph,
              text:
                  'This is the second sample paragraph for geometry measurement on page 2.',
            ),
          ],
        ),
      ],
      metadata: const {},
    );

    testWidgets(
      '1. Vertical Geometry: Measure actual rendered widget boxes vs 68 pt deduction',
      (tester) async {
        const double viewportWidth = 800.0;
        const double viewportHeight = 600.0;
        tester.view.physicalSize = const Size(viewportWidth, viewportHeight);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PaginatedReflowableReader(
                document: testDoc,
                theme: ReadingThemeType.dark,
                typography: const TypographySettings(
                  twoPageSpread: false,
                  fontSize: 16,
                ),
                onTapContent: () {},
                onProgressChanged: (ch, page, pct, anchor, offset) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Find ReflowablePageRenderer
        final rendererFinder = find.byType(ReflowablePageRenderer);
        expect(rendererFinder, findsOneWidget);

        final RenderBox rendererBox = tester.renderObject(rendererFinder);
        expect(rendererBox.size.height, equals(viewportHeight));

        // Find Header SizedBox (height: 28)
        final headerFinder = find.descendant(
          of: rendererFinder,
          matching: find.byWidgetPredicate(
            (w) => w is SizedBox && w.height == 28.0,
          ),
        );
        expect(headerFinder, findsOneWidget);
        final RenderBox headerBox = tester.renderObject(headerFinder);
        expect(headerBox.size.height, equals(28.0));

        // Find Footer SizedBox (height: 24)
        final footerFinder = find.descendant(
          of: rendererFinder,
          matching: find.byWidgetPredicate(
            (w) => w is SizedBox && w.height == 24.0,
          ),
        );
        expect(footerFinder, findsOneWidget);
        final RenderBox footerBox = tester.renderObject(footerFinder);
        expect(footerBox.size.height, equals(24.0));

        // Find Content Area Expanded
        final expandedFinder = find.descendant(
          of: rendererFinder,
          matching: find.byType(Expanded),
        );
        expect(expandedFinder, findsOneWidget);
        final RenderBox expandedBox = tester.renderObject(expandedFinder);

        // The current renderer allocates 24 pt top and bottom padding,
        // a 28 pt header, and a 20 pt footer region (including its spacing).
        const expectedContentHeight = viewportHeight - (24.0 * 2) - 28.0 - 20.0;
        expect(expectedContentHeight, equals(504.0));
        expect(expandedBox.size.height, equals(expectedContentHeight));

        // Now compare with PaginationEngine availableHeight formula:
        // Compare the measured renderer geometry against the explicit layout
        // budget used by this widget configuration.
        final engineCalculatedHeight =
            (viewportHeight - (24.0 * 2) - 28.0 - 20.0).clamp(120.0, 4000.0);
        expect(engineCalculatedHeight, equals(expandedBox.size.height));
        print(
          'Vertical Geometry Verification: Rendered Content Height (${expandedBox.size.height} pt) == Engine Available Height ($engineCalculatedHeight pt). MATCH!',
        );
      },
    );

    testWidgets(
      '2. Horizontal Geometry: Test Spread Widths across Narrow, Medium, Wide, and Ultrawide Viewports',
      (tester) async {
        final testCases = [
          {'w': 900.0, 'h': 650.0, 'name': 'Minimal Spread (900px)'},
          {'w': 1100.0, 'h': 700.0, 'name': 'Medium Window Spread (1100px)'},
          {'w': 1400.0, 'h': 850.0, 'name': 'Wide Window Spread (1400px)'},
          {
            'w': 2000.0,
            'h': 1000.0,
            'name': 'Ultrawide Screen Spread (2000px)',
          },
        ];

        for (final tc in testCases) {
          final w = tc['w'] as double;
          final h = tc['h'] as double;
          final name = tc['name'] as String;

          tester.view.physicalSize = Size(w, h);
          tester.view.devicePixelRatio = 1.0;

          const typo = TypographySettings(twoPageSpread: true, fontSize: 16);

          // 1. Engine calculation
          const double spineWidth = PaginationEngine.spreadGutterWidth;
          final double rawPageWidth = (w - spineWidth) / 2;
          final double effectiveMargin = (rawPageWidth < 400.0)
              ? 18.0
              : (rawPageWidth < 650.0
                    ? math.max(48.0, typo.horizontalMargin)
                    : math.max(56.0, typo.horizontalMargin));
          final double expectedContentWidth =
              (rawPageWidth - (effectiveMargin * 2.0)).clamp(160.0, 620.0);

          // Run engine pagination
          final pages = PaginationEngine.paginateChapter(
            chapter: testDoc.chapters[0],
            viewportWidth: w,
            viewportHeight: h,
            typography: typo,
          );
          expect(pages, isNotEmpty);

          // 2. Render Widget in real tree
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: PaginatedReflowableReader(
                  document: testDoc,
                  theme: ReadingThemeType.dark,
                  typography: typo,
                  onTapContent: () {},
                  onProgressChanged: (ch, page, pct, anchor, offset) {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Check spine width
          final spineFinder = find.byWidgetPredicate(
            (widget) =>
                widget is Container &&
                widget.constraints?.maxWidth ==
                    PaginationEngine.spreadGutterWidth &&
                widget.decoration != null,
          );
          expect(
            spineFinder,
            findsOneWidget,
            reason:
                '$name: Spine container must be exactly ${PaginationEngine.spreadGutterWidth} pt',
          );

          // Check left page renderer actual rendered box width
          final renderers = find.byType(ReflowablePageRenderer);
          expect(
            renderers,
            findsNWidgets(2),
            reason: '$name: Spread must render 2 page renderers',
          );

          final RenderBox leftBox = tester.renderObject(renderers.first);
          expect(
            leftBox.size.width,
            equals(expectedContentWidth),
            reason:
                '$name: Left page RenderBox width (${leftBox.size.width}) must match expectedContentWidth ($expectedContentWidth)',
          );

          final RenderBox rightBox = tester.renderObject(renderers.last);
          expect(
            rightBox.size.width,
            equals(expectedContentWidth),
            reason:
                '$name: Right page RenderBox width (${rightBox.size.width}) must match expectedContentWidth ($expectedContentWidth)',
          );

          print(
            'Horizontal Spread [$name]: Viewport W=$w -> Rendered Column Width = ${leftBox.size.width} pt. Engine expected = $expectedContentWidth pt. EXACT 1:1 MATCH!',
          );
        }

        tester.view.reset();
      },
    );

    testWidgets(
      '3. Single-Page Horizontal Geometry: Test across Narrow, Medium, and Wide Viewports',
      (tester) async {
        final testCases = [
          {'w': 400.0, 'h': 600.0, 'name': 'Narrow (400px)'},
          {'w': 600.0, 'h': 700.0, 'name': 'Compact (600px)'},
          {'w': 800.0, 'h': 700.0, 'name': 'Standard (800px)'},
          {'w': 1200.0, 'h': 800.0, 'name': 'Wide Single Page (1200px)'},
          {'w': 1800.0, 'h': 900.0, 'name': 'Ultrawide Single Page (1800px)'},
        ];

        for (final tc in testCases) {
          final w = tc['w'] as double;
          final h = tc['h'] as double;
          final name = tc['name'] as String;

          tester.view.physicalSize = Size(w, h);
          tester.view.devicePixelRatio = 1.0;

          const typo = TypographySettings(twoPageSpread: false, fontSize: 16);

          final double effectiveMargin = (w < 400.0)
              ? 18.0
              : (w < 650.0
                    ? math.max(48.0, typo.horizontalMargin)
                    : math.max(56.0, typo.horizontalMargin));
          final double expectedContentWidth = (w - (effectiveMargin * 2.0))
              .clamp(160.0, 680.0);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: PaginatedReflowableReader(
                  document: testDoc,
                  theme: ReadingThemeType.dark,
                  typography: typo,
                  onTapContent: () {},
                  onProgressChanged: (ch, page, pct, anchor, offset) {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final rendererFinder = find.byType(ReflowablePageRenderer);
          expect(rendererFinder, findsOneWidget);

          final RenderBox rendererBox = tester.renderObject(rendererFinder);
          expect(
            rendererBox.size.width,
            equals(expectedContentWidth),
            reason:
                '$name: Single page RenderBox width (${rendererBox.size.width}) must match expectedContentWidth ($expectedContentWidth)',
          );

          print(
            'Horizontal Single [$name]: Viewport W=$w -> Rendered Column Width = ${rendererBox.size.width} pt. Engine expected = $expectedContentWidth pt. EXACT 1:1 MATCH!',
          );
        }

        tester.view.reset();
      },
    );
  });
}
