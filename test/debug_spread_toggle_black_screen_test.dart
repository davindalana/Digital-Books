// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/core/typography/typography_settings.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'package:digital_books/features/reader/domain/engines/reflowable_engine.dart';
import 'package:digital_books/features/reader/models/book_document.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/paginated_reflowable_reader.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/reflowable_page_renderer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bookId = '7b3dcbf3-0f23-4c6d-8044-d525257dac00';
  final jsonFile = File('/Users/davindalana/Documents/DigitalBooks/books/$bookId.json');

  late ReaderDocument readerDoc;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final family in ['Palatino', 'Inter', 'Georgia']) {
      final fontPath = File('/System/Library/Fonts/Supplemental/Georgia.ttf').existsSync()
          ? '/System/Library/Fonts/Supplemental/Georgia.ttf'
          : '/System/Library/Fonts/Supplemental/Arial.ttf';
      final bytes = File(fontPath).readAsBytesSync();
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
    }

    expect(jsonFile.existsSync(), isTrue, reason: 'Real book JSON must exist');
    final jsonStr = jsonFile.readAsStringSync();
    final bookDoc = BookDocument.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
    readerDoc = ReflowableEngine.normalizeDocument(bookDoc);
  });

  testWidgets('Reproduce black screen when toggling twoPageSpread back and forth', (tester) async {
    tester.view.physicalSize = const Size(934 * 2.0, 934 * 2.0);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final typoNotifier = ValueNotifier<TypographySettings>(
      const TypographySettings(twoPageSpread: true),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<TypographySettings>(
            valueListenable: typoNotifier,
            builder: (context, typo, _) {
              return PaginatedReflowableReader(
                document: readerDoc,
                theme: ReadingThemeType.black,
                typography: typo,
                initialPageIndex: 0,
                onTapContent: () {},
                onProgressChanged: (ch, page, pct, anchor, offset) {},
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify initial render (spread mode)
    final renderersSpread1 = tester.widgetList(find.byType(ReflowablePageRenderer)).toList();
    print('Initial spread mode: found ${renderersSpread1.length} page renderers');
    expect(renderersSpread1.length, inInclusiveRange(1, 2));

    // Toggle 1: twoPageSpread -> false
    print('Toggling to single page (twoPageSpread = false)...');
    typoNotifier.value = typoNotifier.value.copyWith(twoPageSpread: false);
    await tester.pumpAndSettle();

    final renderersSingle = tester.widgetList(find.byType(ReflowablePageRenderer)).toList();
    print('Single page mode: found ${renderersSingle.length} page renderers');
    expect(renderersSingle.length, 1);

    // Toggle 2: twoPageSpread -> true (balik lagi)
    print('Toggling back to spread (twoPageSpread = true)...');
    typoNotifier.value = typoNotifier.value.copyWith(twoPageSpread: true);
    await tester.pumpAndSettle();

    final renderersSpread2 = tester.widgetList(find.byType(ReflowablePageRenderer)).toList();
    print('Spread mode after toggle back: found ${renderersSpread2.length} page renderers');
    expect(renderersSpread2.length, inInclusiveRange(1, 2));
  });
}
