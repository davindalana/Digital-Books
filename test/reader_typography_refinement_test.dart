import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/core/theme/typography_settings.dart';
import 'package:digital_books/features/reader/domain/engines/pagination_engine.dart';
import 'package:digital_books/features/reader/domain/engines/reflowable_highlight_span_builder.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/paginated_reflowable_reader.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/reflowable_page_renderer.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/scrolling_reflowable_reader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Reader Typography & Spread Refinement Suite', () {
    test('1. TypographySettings Source-of-Truth Defaults', () {
      const settings = TypographySettings();

      // Source-of-truth default font size is 18.0
      expect(settings.fontSize, equals(18.0));

      // Default paragraph alignment is TextAlign.justify
      expect(settings.textAlign, equals(TextAlign.justify));

      // First-line indent multiplier is approximately 1.25em (1.0em - 1.5em)
      expect(settings.firstLineIndentMultiplier, equals(1.25));
      expect(settings.firstLineIndent, equals(18.0 * 1.25)); // 22.5 dp

      // User customization preservation: font size scales indent proportionally
      final customizedSize = settings.copyWith(fontSize: 24.0);
      expect(customizedSize.fontSize, equals(24.0));
      expect(customizedSize.firstLineIndent, equals(24.0 * 1.25)); // 30.0 dp

      // User customization preservation: user can still choose left alignment
      final leftAligned = settings.copyWith(textAlign: TextAlign.left);
      expect(leftAligned.textAlign, equals(TextAlign.left));
      expect(leftAligned.firstLineIndent, equals(22.5));
    });

    test('2. ReflowableHighlightSpanBuilder First-Line Indent Span', () {
      const text = 'Ini adalah kalimat pembuka paragraf pertama.';
      const baseStyle = TextStyle(fontSize: 18.0);

      // Without indent
      final spanNoIndent = ReflowableHighlightSpanBuilder.buildRichSpan(
        text: text,
        sliceStartOffset: 0,
        sliceEndOffset: text.length,
        highlightsForNode: const [],
        baseStyle: baseStyle,
        theme: ReadingThemeType.black,
        firstLineIndent: 0.0,
      );
      expect(spanNoIndent.children, isNull);
      expect(spanNoIndent.text, equals(text));

      // With first-line indent
      final spanWithIndent = ReflowableHighlightSpanBuilder.buildRichSpan(
        text: text,
        sliceStartOffset: 0,
        sliceEndOffset: text.length,
        highlightsForNode: const [],
        baseStyle: baseStyle,
        theme: ReadingThemeType.black,
        firstLineIndent: 22.5,
      );
      expect(spanWithIndent.children, isNotNull);
      expect(spanWithIndent.children!.length, equals(2));
      expect(spanWithIndent.children!.first, isA<WidgetSpan>());
      final widgetSpan = spanWithIndent.children!.first as WidgetSpan;
      expect(widgetSpan.child, isA<SizedBox>());
      final sizedBox = widgetSpan.child as SizedBox;
      expect(sizedBox.width, equals(22.5));
      expect((spanWithIndent.children![1] as TextSpan).text, equals(text));
    });

    test('3. Two-Page Spread Gutter Geometry & Responsiveness', () {
      const typoSpread = TypographySettings(twoPageSpread: true);
      const typoNoSpread = TypographySettings(twoPageSpread: false);

      // Spread gutter is 48.0 dp (increased from 24.0 dp)
      expect(PaginationEngine.spreadGutterWidth, equals(48.0));

      // Two-page spread enabled on wide screens (>= 850 dp)
      const wideViewport = 1000.0;
      final wideContentWidth = PaginationEngine.contentWidthFor(
        viewportWidth: wideViewport,
        typography: typoSpread,
      );
      // Half width is (1000 - 48) / 2 = 476.0; a 476 pt page uses the 48 pt
      // reading inset, so contentWidth = 476 - 96 = 380.0.
      expect(wideContentWidth, equals(380.0));

      // Two-page spread disabled on narrow screens (< 850 dp)
      const narrowViewport = 800.0;
      final narrowContentWidth = PaginationEngine.contentWidthFor(
        viewportWidth: narrowViewport,
        typography: typoSpread,
      );
      // Single page: 800.0; margin = math.max(32.0, 32.0) = 32.0; contentWidth = (800 - 64) clamped to 680 = 680.0
      expect(narrowContentWidth, equals(680.0));

      // Explicit twoPageSpread: false on wide screen returns single page
      final singleWideWidth = PaginationEngine.contentWidthFor(
        viewportWidth: wideViewport,
        typography: typoNoSpread,
      );
      expect(singleWideWidth, equals(680.0));
    });

    testWidgets('4. Paginated Reflowable Page Renderer Typography & Alignment', (
      tester,
    ) async {
      const normalParaNode = ContentNode(
        id: 'p1',
        type: ContentNodeType.paragraph,
        text:
            'Ini adalah paragraf naratif yang panjang untuk menguji apakah perataan justified dan lekukan baris pertama berjalan dengan benar tanpa kesalahan tata letak.',
      );

      const headingNode = ContentNode(
        id: 'h1',
        type: ContentNodeType.heading,
        level: 1,
        text: 'BAB I: PERJALANAN DIMULAI',
      );

      final page = PaginatedPage(
        pageIndexInChapter: 0,
        pageIndexInBook: 0,
        chapterIndex: 0,
        chapterTitle: 'Bab 1',
        slices: [
          PaginatedNodeSlice(
            node: headingNode,
            textSlice: headingNode.text,
            startCharOffset: 0,
            endCharOffset: headingNode.text.length,
          ),
          PaginatedNodeSlice(
            node: normalParaNode,
            textSlice: normalParaNode.text,
            startCharOffset: 0,
            endCharOffset: normalParaNode.text.length,
            isContinuation: false,
          ),
        ],
        firstAnchorNodeId: 'h1',
        lastAnchorNodeId: 'p1',
      );

      const typo = TypographySettings();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReflowablePageRenderer(
              page: page,
              totalPagesInBook: 1,
              theme: ReadingThemeType.black,
              typography: typo,
              contentWidth: 400.0,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final selectables = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .toList();
      expect(selectables.length, greaterThanOrEqualTo(2));

      // First selectable is chapter heading (left-aligned, unindented)
      final headingSelectable = selectables.first;
      expect(headingSelectable.textAlign, equals(TextAlign.left));
      expect(headingSelectable.textSpan?.children, isNull);

      // Second selectable is body paragraph (justified, first-line indent)
      final bodySelectable = selectables.last;
      expect(bodySelectable.textAlign, equals(TextAlign.justify));
      final bodyChildren = bodySelectable.textSpan?.children;
      expect(bodyChildren, isNotNull);
      expect(bodyChildren!.first, isA<WidgetSpan>());
      final indentBox = (bodyChildren.first as WidgetSpan).child as SizedBox;
      expect(indentBox.width, equals(22.5));
    });

    testWidgets('5. Continuation Slices Do NOT Repeat First-Line Indent', (
      tester,
    ) async {
      const longParaNode = ContentNode(
        id: 'p2',
        type: ContentNodeType.paragraph,
        text:
            'Bagian kedua dari paragraf yang terbelah ke halaman berikutnya tidak boleh memiliki indentasi baris pertama.',
      );

      final continuationPage = PaginatedPage(
        pageIndexInChapter: 1,
        pageIndexInBook: 1,
        chapterIndex: 0,
        chapterTitle: 'Bab 1',
        slices: [
          PaginatedNodeSlice(
            node: longParaNode,
            textSlice: longParaNode.text,
            startCharOffset: 120,
            endCharOffset: 120 + longParaNode.text.length,
            isContinuation: true, // continuation of previous page
          ),
        ],
        firstAnchorNodeId: 'p2',
        lastAnchorNodeId: 'p2',
      );

      const typo = TypographySettings();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReflowablePageRenderer(
              page: continuationPage,
              totalPagesInBook: 2,
              theme: ReadingThemeType.black,
              typography: typo,
              contentWidth: 400.0,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final bodySelectable = tester.widget<SelectableText>(
        find.byType(SelectableText),
      );
      expect(bodySelectable.textAlign, equals(TextAlign.justify));

      // Continuation slice must not have WidgetSpan indent
      expect(bodySelectable.textSpan?.children, isNull);
      expect(bodySelectable.textSpan?.text, equals(longParaNode.text));
    });

    testWidgets(
      '6. Continuous Scrolling Reader Applies Justify & Indent to Prose',
      (tester) async {
        final doc = ReaderDocument(
          bookId: 'doc1',
          title: 'Buku Pengujian',
          author: 'Penulis Uji',
          chapters: [
            ReaderChapter(
              id: 'ch1',
              title: 'BAB I: PENDAHULUAN',
              index: 0,
              nodes: [
                const ContentNode(
                  id: 'sec1',
                  type: ContentNodeType.sectionHeading,
                  text: 'Bagian 1: Latar Belakang',
                ),
                const ContentNode(
                  id: 'p_scroll',
                  type: ContentNodeType.paragraph,
                  text:
                      'Paragraf pertama dalam continuous scrolling reader yang harus terformat justified dengan lekukan awal baris.',
                ),
              ],
            ),
          ],
        );

        const typo = TypographySettings();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ScrollingReflowableReader(
                document: doc,
                theme: ReadingThemeType.black,
                typography: typo,
                onTapContent: () {},
                onProgressChanged: (ch, p, pct, a, o) {},
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        final selectables = tester
            .widgetList<SelectableText>(find.byType(SelectableText))
            .toList();

        // Section heading is left-aligned and unindented
        final secHeading = selectables.firstWhere(
          (s) => s.textSpan?.toPlainText().contains('Latar Belakang') == true,
        );
        expect(secHeading.textAlign, equals(TextAlign.left));
        expect(secHeading.textSpan?.children, isNull);

        // Body paragraph is justified with first-line indent
        final bodyParagraph = selectables.firstWhere(
          (s) =>
              s.textSpan?.toPlainText().contains('continuous scrolling') ==
              true,
        );
        expect(bodyParagraph.textAlign, equals(TextAlign.justify));
        final bodyChildren = bodyParagraph.textSpan?.children;
        expect(bodyChildren, isNotNull);
        expect(bodyChildren!.first, isA<WidgetSpan>());
        final indentBox = (bodyChildren.first as WidgetSpan).child as SizedBox;
        expect(indentBox.width, equals(22.5));
      },
    );

    testWidgets('7. Two-Page Spread Layout Center Spine & Gutter Verification', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final doc = ReaderDocument(
        bookId: 'doc_spread',
        title: 'Buku Dua Halaman',
        author: 'Penulis Uji',
        chapters: [
          ReaderChapter(
            id: 'ch_spread',
            title: 'Bab Uji Spread',
            index: 0,
            nodes: [
              const ContentNode(
                id: 'p_left',
                type: ContentNodeType.paragraph,
                text: 'Halaman kiri dengan teks narasi yang cukup panjang.',
              ),
              const ContentNode(
                id: 'pb1',
                type: ContentNodeType.pageBreak,
                text: '',
              ),
              const ContentNode(
                id: 'p_right',
                type: ContentNodeType.paragraph,
                text:
                    'Halaman kanan dengan teks narasi lanjutan di sebelah kanan.',
              ),
            ],
          ),
        ],
      );

      const typo = TypographySettings(twoPageSpread: true);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000.0,
              height: 700.0,
              child: PaginatedReflowableReader(
                document: doc,
                theme: ReadingThemeType.black,
                typography: typo,
                onTapContent: () {},
                onProgressChanged: (ch, p, pct, a, o) {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify two-page spread key exists
      expect(find.byKey(const ValueKey('page_0_spread_true')), findsOneWidget);

      // Verify two ReflowablePageRenderer instances (Left and Right)
      final renderers = tester
          .widgetList<ReflowablePageRenderer>(
            find.byType(ReflowablePageRenderer),
          )
          .toList();
      expect(renderers.length, equals(2));
      expect(renderers[0].isLeftPage, isTrue);
      expect(renderers[1].isLeftPage, isFalse);
      expect(renderers[0].contentWidth, equals(380.0));
      expect(renderers[1].contentWidth, equals(380.0));

      // Verify physical center spine crease container exists with spreadGutterWidth (48.0)
      final containers = tester.widgetList<Container>(find.byType(Container));
      final spineContainer = containers.firstWhere(
        (c) =>
            c.constraints?.minWidth == 48.0 && c.constraints?.maxWidth == 48.0,
      );
      expect(spineContainer.decoration, isA<BoxDecoration>());
      final boxDec = spineContainer.decoration as BoxDecoration;
      expect(boxDec.gradient, isA<LinearGradient>());
      final gradient = boxDec.gradient as LinearGradient;
      expect(gradient.stops, equals(const [0.0, 0.35, 0.5, 0.65, 1.0]));
    });

    testWidgets('8. Highlight Creation & Selection Offset Accuracy with Indent', (
      tester,
    ) async {
      String? savedText;
      String? savedColor;
      int? savedStart;
      int? savedEnd;

      const paraNode = ContentNode(
        id: 'node_sel',
        type: ContentNodeType.paragraph,
        text: 'Buku ini adalah kisah tentang laut dan cerita.',
      );

      final page = PaginatedPage(
        pageIndexInChapter: 0,
        pageIndexInBook: 0,
        chapterIndex: 0,
        chapterTitle: 'Bab 1',
        slices: [
          PaginatedNodeSlice(
            node: paraNode,
            textSlice: paraNode.text,
            startCharOffset: 0,
            endCharOffset: paraNode.text.length,
            isContinuation: false,
          ),
        ],
        firstAnchorNodeId: 'node_sel',
        lastAnchorNodeId: 'node_sel',
      );

      const typo = TypographySettings();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReflowablePageRenderer(
              page: page,
              totalPagesInBook: 1,
              theme: ReadingThemeType.black,
              typography: typo,
              contentWidth: 400.0,
              onHighlightCreated:
                  ({
                    required text,
                    required color,
                    note,
                    required anchorNodeId,
                    required startOffset,
                    required endOffset,
                    prefixContext,
                    suffixContext,
                    required pageNumber,
                  }) {
                    savedText = text;
                    savedColor = color;
                    savedStart = startOffset;
                    savedEnd = endOffset;
                  },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Trigger text selection and context menu on 'Buku'
      // Double tap on the paragraph text (accounting for indent)
      final bodyFinder = find.byType(SelectableText);
      expect(bodyFinder, findsOneWidget);

      final selectableTopLeft = tester.getTopLeft(bodyFinder);
      // Tap past the indent (indent width is 22.5dp) inside the word 'Buku'
      final tapTarget = Offset(
        selectableTopLeft.dx + 40.0,
        selectableTopLeft.dy + 10.0,
      );
      await tester.tapAt(tapTarget);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(tapTarget); // Double tap selects word
      await tester.pumpAndSettle();

      // Verify context menu is visible and tap yellow highlight button
      final yellowButton = find.text('🟡 Kuning');
      expect(yellowButton, findsOneWidget);
      await tester.tap(yellowButton);
      await tester.pumpAndSettle();

      // Verify highlight callback received clean text and exact character offsets
      expect(savedText, equals('Buku'));
      expect(savedColor, equals('yellow'));
      expect(savedStart, equals(0));
      expect(savedEnd, equals(4));
      expect(paraNode.text.substring(savedStart!, savedEnd!), equals('Buku'));
    });
  });
}
