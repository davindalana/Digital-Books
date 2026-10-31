import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/features/reader/presentation/widgets/original_pdf_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('OriginalPdfReader displays error state and retry button for invalid path',
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
    expect(find.text('Berkas PDF Tidak Ditemukan'), findsOneWidget);
    expect(find.text('Coba Lagi'), findsOneWidget);
    expect(find.text('Buka Versi Teks'), findsOneWidget);
    expect(find.text('Kembali ke Library'), findsOneWidget);

    // Test switch button
    await tester.tap(find.text('Buka Versi Teks'));
    expect(switchCalled, isTrue);

    // Test back button
    await tester.tap(find.text('Kembali ke Library'));
    expect(backCalled, isTrue);

    // Test retry button
    await tester.tap(find.text('Coba Lagi'));
    await tester.pump();
    expect(find.text('Berkas PDF Tidak Ditemukan'), findsOneWidget);
  });
}
