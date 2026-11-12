import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/features/reader/presentation/widgets/original_pdf_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'OriginalPdfReader displays error state and retry button for invalid path',
    (tester) async {
      bool switchCalled = false;
      bool backCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OriginalPdfReader(
              pdfPath: '/invalid/path/to/nonexistent.pdf',
              initialPage: 1,
              theme: ReadingThemeType.black,
              onPageChanged: (page, total) {},
              onTapContent: () {},
              onSwitchToReflowable: () {
                switchCalled = true;
              },
              onBack: () {
                backCalled = true;
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify error card is displayed instead of a black screen
      expect(find.text('PDF File Not Found'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
      expect(find.text('Open Text Version'), findsOneWidget);
      expect(find.text('Back to Library'), findsOneWidget);

      // Test switch button
      await tester.tap(find.text('Open Text Version'));
      expect(switchCalled, isTrue);

      // Test back button
      await tester.tap(find.text('Back to Library'));
      expect(backCalled, isTrue);

      // Test retry button
      await tester.tap(find.text('Try Again'));
      await tester.pump();
      expect(find.text('PDF File Not Found'), findsOneWidget);
    },
  );
}
