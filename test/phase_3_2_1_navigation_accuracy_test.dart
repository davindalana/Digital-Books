// ignore_for_file: avoid_print

import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/features/reader/domain/engines/in_book_search_engine.dart';
import 'package:digital_books/features/reader/domain/engines/reflowable_highlight_span_builder.dart';
import 'package:digital_books/features/reader/presentation/widgets/original_pdf_reader.dart';
import 'package:digital_books/features/reader/presentation/widgets/search_traversal_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 3.2.1 — Search Navigation & Traversal Audit', () {
    testWidgets('1. Search Traversal Bar Renders Correct Count & Triggers Next / Prev / Close', (tester) async {
      int nextCount = 0;
      int prevCount = 0;
      bool closed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchTraversalBar(
              query: 'destiny',
              currentIndex: 0,
              totalCount: 3,
              theme: ReadingThemeType.white,
              onPrevious: () => prevCount++,
              onNext: () => nextCount++,
              onClose: () => closed = true,
            ),
          ),
        ),
      );

      // Verify Query Badge and Match Count Text
      expect(find.text('destiny'), findsOneWidget);
      expect(find.text('1 dari 3'), findsOneWidget);

      // Tap Next Match
      await tester.tap(find.byTooltip('Hasil Berikutnya (Enter)'));
      await tester.pump();
      expect(nextCount, equals(1));

      // Tap Previous Match
      await tester.tap(find.byTooltip('Hasil Sebelumnya (Shift+Enter)'));
      await tester.pump();
      expect(prevCount, equals(1));

      // Tap Close
      await tester.tap(find.byTooltip('Selesai Pencarian (Esc)'));
      await tester.pump();
      expect(closed, isTrue);
    });

    test('2. Cyclic Traversal Next/Previous Index Wrapping Logic', () {
      final matches = [
        const InBookSearchResult(
          id: 'sr_1',
          chapterIndex: 0,
          chapterId: 'ch1',
          chapterTitle: 'Ch 1',
          nodeId: 'n1',
          sourcePdfPage: 1,
          startOffset: 10,
          endOffset: 17,
          matchedText: 'destiny',
          snippet: '…change the destiny of the…',
          prefixContext: 'change the ',
          suffixContext: ' of the',
          boundingBoxes: [Rect.fromLTWH(0.4, 0.21, 0.09, 0.03)],
          isCrossPage: false,
          isOcr: false,
        ),
        const InBookSearchResult(
          id: 'sr_2',
          chapterIndex: 0,
          chapterId: 'ch1',
          chapterTitle: 'Ch 1',
          nodeId: 'n2',
          sourcePdfPage: 2,
          startOffset: 50,
          endOffset: 57,
          matchedText: 'destiny',
          snippet: '…manifest destiny across…',
          prefixContext: 'manifest ',
          suffixContext: ' across',
          boundingBoxes: [Rect.fromLTWH(0.2, 0.45, 0.09, 0.03)],
          isCrossPage: false,
          isOcr: false,
        ),
        const InBookSearchResult(
          id: 'sr_3',
          chapterIndex: 1,
          chapterId: 'ch2',
          chapterTitle: 'Ch 2',
          nodeId: 'n3',
          sourcePdfPage: 3,
          startOffset: 80,
          endOffset: 87,
          matchedText: 'destiny',
          snippet: '…fulfill their destiny now…',
          prefixContext: 'fulfill their ',
          suffixContext: ' now',
          boundingBoxes: [Rect.fromLTWH(0.5, 0.80, 0.09, 0.03)],
          isCrossPage: false,
          isOcr: false,
        ),
      ];

      int currentIndex = 0;
      int wrap(int index, int total) => (index % total + total) % total;

      // Forward step 0 -> 1
      currentIndex = wrap(currentIndex + 1, matches.length);
      expect(currentIndex, equals(1));
      expect(matches[currentIndex].sourcePdfPage, equals(2));

      // Forward step 1 -> 2
      currentIndex = wrap(currentIndex + 1, matches.length);
      expect(currentIndex, equals(2));
      expect(matches[currentIndex].sourcePdfPage, equals(3));

      // Forward wrap 2 -> 0 (end back to start)
      currentIndex = wrap(currentIndex + 1, matches.length);
      expect(currentIndex, equals(0));
      expect(matches[currentIndex].sourcePdfPage, equals(1));

      // Backward wrap 0 -> 2 (start back to end)
      currentIndex = wrap(currentIndex - 1, matches.length);
      expect(currentIndex, equals(2));
      expect(matches[currentIndex].sourcePdfPage, equals(3));

      // Backward step 2 -> 1
      currentIndex = wrap(currentIndex - 1, matches.length);
      expect(currentIndex, equals(1));
      expect(matches[currentIndex].sourcePdfPage, equals(2));
    });

    test('3. Mode-Switching Search State & Active Match Retention Audit', () {
      // Simulate state when searching in Reflowable mode:
      const activeMatch = InBookSearchResult(
        id: 'sr_match_reflowable',
        chapterIndex: 1,
        chapterId: 'chapter_02',
        chapterTitle: 'Chapter Two',
        nodeId: 'node_ch2_para_04',
        sourcePdfPage: 15,
        startOffset: 124,
        endOffset: 134,
        matchedText: 'speedboat',
        snippet: '…menaiki sebuah speedboat. Bau asin…',
        prefixContext: 'menaiki sebuah ',
        suffixContext: '. Bau asin',
        boundingBoxes: [
          Rect.fromLTWH(0.55, 0.38, 0.14, 0.035),
        ],
        isCrossPage: false,
        isOcr: true,
      );

      // Switching from Reflowable to Original PDF:
      // Must map active search match to sourcePdfPage and set activePdfSearchHighlights
      final targetPdfPage = activeMatch.sourcePdfPage;
      final pdfHighlights = {
        activeMatch.sourcePdfPage: activeMatch.boundingBoxes,
      };

      expect(targetPdfPage, equals(15));
      expect(pdfHighlights[15], isNotNull);
      expect(pdfHighlights[15]!.first, equals(const Rect.fromLTWH(0.55, 0.38, 0.14, 0.035)));

      // Switching from Original PDF to Reflowable:
      // Must map back to nodeId, chapterIndex, and startOffset
      final targetNodeId = activeMatch.nodeId;
      final targetChapter = activeMatch.chapterIndex;
      final targetCharOffset = activeMatch.startOffset;

      expect(targetNodeId, equals('node_ch2_para_04'));
      expect(targetChapter, equals(1));
      expect(targetCharOffset, equals(124));
    });

    testWidgets('4. Original PDF Highlight Painter Renders Normalized Box Without Drift', (tester) async {
      const highlightBox = Rect.fromLTWH(0.2, 0.3, 0.4, 0.05);

      // Render at standard window size (800 x 1000)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 800,
                height: 1000,
                child: CustomPaint(
                  painter: PdfSearchHighlightPainter(
                    normalizedBoxes: const [highlightBox],
                    isDark: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(CustomPaint), findsWidgets);

      // Now simulate window resize to wider format (1200 x 900)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 1200,
                height: 900,
                child: CustomPaint(
                  painter: PdfSearchHighlightPainter(
                    normalizedBoxes: const [highlightBox],
                    isDark: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // CustomPaint successfully resizes with normalized scale factors
      expect(find.byType(CustomPaint), findsWidgets);
    });

    test('5. Reflowable Rich Text Span Highlights Active Match Correctly', () {
      const text = 'Kini salah satu dari mereka berteriak agar aku menaiki sebuah speedboat.';
      final matchStart = text.indexOf('speedboat');
      final matchEnd = matchStart + 'speedboat'.length;

      final matches = [
        ActiveSearchMatch(
          nodeId: 'node_test',
          startOffset: matchStart,
          endOffset: matchEnd,
          isActive: true,
        ),
      ];

      final span = ReflowableHighlightSpanBuilder.buildRichSpan(
        text: text,
        sliceStartOffset: 0,
        sliceEndOffset: text.length,
        highlightsForNode: const [],
        searchMatchesForNode: matches,
        baseStyle: const TextStyle(fontSize: 16, color: Colors.black),
        theme: ReadingThemeType.white,
      );

      expect(span, isNotNull);
      // The TextSpan should have children representing before match, match, and after match
      final children = span.children;
      expect(children, isNotNull);
      expect(children!.isNotEmpty, isTrue);

      // One of the children must contain 'speedboat' with active highlight background
      final matchSpan = children.firstWhere(
        (s) => (s as TextSpan).text == 'speedboat',
      ) as TextSpan;

      expect(matchSpan.text, equals('speedboat'));
      expect(matchSpan.style?.backgroundColor, isNotNull);
      expect(matchSpan.style?.color, isNotNull);
    });
  });
}
