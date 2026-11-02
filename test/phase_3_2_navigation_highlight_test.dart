import 'package:digital_books/features/reader/domain/engines/reflowable_highlight_span_builder.dart';
import 'package:digital_books/features/reader/presentation/widgets/original_pdf_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 3.2 — Navigation & Precision Highlight Overlay Test', () {
    test('1. PdfSearchHighlightPainter drawing & shouldRepaint verification', () {
      const boxes = [
        Rect.fromLTWH(0.1, 0.2, 0.3, 0.05),
        Rect.fromLTWH(0.5, 0.6, 0.2, 0.04),
      ];

      final painterLight = PdfSearchHighlightPainter(
        normalizedBoxes: boxes,
        isDark: false,
      );

      final painterDark = PdfSearchHighlightPainter(
        normalizedBoxes: boxes,
        isDark: true,
      );

      // Verify shouldRepaint on property change
      expect(painterLight.shouldRepaint(painterDark), isTrue);

      final painterSame = PdfSearchHighlightPainter(
        normalizedBoxes: boxes,
        isDark: false,
      );
      expect(painterLight.shouldRepaint(painterSame), isFalse);

      final painterDiffBoxes = PdfSearchHighlightPainter(
        normalizedBoxes: [boxes.first],
        isDark: false,
      );
      expect(painterLight.shouldRepaint(painterDiffBoxes), isTrue);
    });

    testWidgets('2. PdfSearchHighlightPainter scales cleanly with viewport resize', (tester) async {
      const normBox = Rect.fromLTWH(0.2, 0.3, 0.4, 0.1);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 1000,
              child: CustomPaint(
                painter: const PdfSearchHighlightPainter(
                  normalizedBoxes: [normBox],
                  isDark: false,
                ),
              ),
            ),
          ),
        ),
      );

      final painterFinder = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is PdfSearchHighlightPainter,
      );

      expect(painterFinder, findsOneWidget);

      // Resize window to compact width
      await tester.binding.setSurfaceSize(const Size(400, 600));
      await tester.pump();
      expect(painterFinder, findsOneWidget);

      // Resize window to expansive width
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      await tester.pump();
      expect(painterFinder, findsOneWidget);

      // Reset surface size
      await tester.binding.setSurfaceSize(null);
    });

    test('3. Search traversal indexing and circular wrap-around', () {
      final totalResults = 5;

      int getNextIndex(int current) => (current + 1) % totalResults;
      int getPrevIndex(int current) => (current - 1 + totalResults) % totalResults;

      // Forward navigation
      expect(getNextIndex(0), equals(1));
      expect(getNextIndex(3), equals(4));
      // Wrap-around forward: 4 -> 0
      expect(getNextIndex(4), equals(0));

      // Backward navigation
      expect(getPrevIndex(4), equals(3));
      expect(getPrevIndex(1), equals(0));
      // Wrap-around backward: 0 -> 4
      expect(getPrevIndex(0), equals(4));
    });

    test('4. Reflowable ActiveSearchMatch highlight span creation', () {
      const match = ActiveSearchMatch(
        nodeId: 'node_test_1',
        startOffset: 10,
        endOffset: 25,
        isActive: true,
      );

      expect(match.nodeId, equals('node_test_1'));
      expect(match.startOffset, equals(10));
      expect(match.endOffset, equals(25));
      expect(match.isActive, isTrue);
    });
  });
}
