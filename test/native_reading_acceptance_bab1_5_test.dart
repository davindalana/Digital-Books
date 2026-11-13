// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/core/theme/typography_settings.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'package:digital_books/features/reader/domain/engines/pagination_engine.dart';
import 'package:digital_books/features/reader/domain/engines/reflowable_engine.dart';
import 'package:digital_books/features/reader/domain/models/book_document.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/paginated_reflowable_reader.dart';
import 'helpers/test_evidence_dir.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bookId = '7b3dcbf3-0f23-4c6d-8044-d525257dac00';
  final jsonFile = File(
    '/Users/davindalana/Documents/DigitalBooks/books/$bookId.json',
  );
  final evidenceDir = resolveTestEvidenceDirectory('book_mode_acceptance');

  late ReaderDocument readerDoc;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final family in ['Palatino', 'Inter', 'Georgia']) {
      final fontPath =
          File('/System/Library/Fonts/Supplemental/Georgia.ttf').existsSync()
          ? '/System/Library/Fonts/Supplemental/Georgia.ttf'
          : '/System/Library/Fonts/Supplemental/Arial.ttf';
      final bytes = File(fontPath).readAsBytesSync();
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
    }

    if (!evidenceDir.existsSync()) {
      evidenceDir.createSync(recursive: true);
    }

    expect(jsonFile.existsSync(), isTrue, reason: 'Real book JSON must exist');
    final jsonStr = jsonFile.readAsStringSync();
    final bookDoc = BookDocument.fromJson(
      jsonDecode(jsonStr) as Map<String, dynamic>,
    );
    readerDoc = ReflowableEngine.normalizeDocument(bookDoc);
  });

  group('Native Reading Acceptance BAB I-V & Visual Evidence Capture', () {
    Future<void> renderAndCapture(
      WidgetTester tester, {
      required Widget widget,
      required Size size,
      required String filename,
    }) async {
      final key = GlobalKey();
      tester.view.physicalSize = Size(size.width * 2.0, size.height * 2.0);
      tester.view.devicePixelRatio = 2.0;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: 'Inter', brightness: Brightness.light),
            home: Scaffold(
              backgroundColor: const Color(0xFFF8F9FA),
              body: Center(
                child: RepaintBoundary(
                  key: key,
                  child: SizedBox(
                    width: size.width,
                    height: size.height,
                    child: widget,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2.0);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        final pngBytes = byteData!.buffer.asUint8List();

        final outFile = File('${evidenceDir.path}/$filename');
        outFile.writeAsBytesSync(pngBytes);
        print(
          '  ✓ Captured: ${outFile.path} (${(pngBytes.length / 1024).toStringAsFixed(1)} KB)',
        );
      });
    }

    test('0. Print Chapter Page Boundaries for Manual Verification', () {
      for (final (label, w, h, spread) in [
        ('Desktop Spread (1102x951)', 1102.0, 951.0, true),
        ('Compact Single (600x800)', 600.0, 800.0, false),
      ]) {
        PaginationEngine.clearCache();
        final pages = PaginationEngine.paginateDocument(
          document: readerDoc,
          viewportWidth: w,
          viewportHeight: h,
          typography: TypographySettings(twoPageSpread: spread),
        );
        print('\n=== $label Total Pages: ${pages.length} ===');
        for (final ch in readerDoc.chapters) {
          final chPages = pages
              .where((p) => p.chapterIndex == ch.index)
              .toList();
          if (chPages.isEmpty) continue;
          final start = chPages.first.pageIndexInBook + 1;
          final end = chPages.last.pageIndexInBook + 1;
          print(
            '  ch${ch.index} "${ch.title}": halaman $start – $end (${chPages.length} hal)',
          );
        }
      }
    });

    testWidgets(
      '0b. Render Chapter 0: Front Matter Spread (Cover & Copyright)',
      (tester) async {
        print('\n--- Evaluating Chapter 0: Front Matter Spread ---');
        final ch0 = readerDoc.chapters.firstWhere(
          (c) => c.title.contains('Bagian Awal'),
        );
        expect(ch0.nodes, isNotEmpty);

        await renderAndCapture(
          tester,
          widget: PaginatedReflowableReader(
            document: readerDoc,
            initialAnchorNodeId: ch0.nodes.first.id,
            theme: ReadingThemeType.dark,
            typography: const TypographySettings(twoPageSpread: true),
            onTapContent: () {},
            onProgressChanged: (ch, p, pct, anc, off) {},
          ),
          size: const Size(1102, 951),
          filename: '00_front_matter_spread.png',
        );
      },
    );

    testWidgets('1. Render Chapter 3: Table of Contents (TOC)', (tester) async {
      print('\n--- Evaluating Chapter 3: Table of Contents ---');
      final tocChapter = readerDoc.chapters.firstWhere(
        (c) => c.title.contains('Daftar Isi'),
      );
      expect(tocChapter.nodes, isNotEmpty);
      print(
        '• TOC Title: "${tocChapter.title}" with ${tocChapter.nodes.length} nodes',
      );

      await renderAndCapture(
        tester,
        widget: PaginatedReflowableReader(
          document: readerDoc,
          initialAnchorNodeId: tocChapter.nodes.first.id,
          theme: ReadingThemeType.white,
          typography: const TypographySettings(twoPageSpread: true),
          onTapContent: () {},
          onProgressChanged: (ch, p, pct, anc, off) {},
        ),
        size: const Size(1102, 951),
        filename: '01_toc_spread.png',
      );
    });

    testWidgets('2. Render Chapter 4: BAB I Opener & Spread Flow', (
      tester,
    ) async {
      print('\n--- Evaluating Chapter 4: BAB I ---');
      final bab1 = readerDoc.chapters.firstWhere(
        (c) => c.title.contains('BAB I'),
      );
      expect(bab1.nodes, isNotEmpty);
      print('• BAB I Title: "${bab1.title}" with ${bab1.nodes.length} nodes');

      await renderAndCapture(
        tester,
        widget: PaginatedReflowableReader(
          document: readerDoc,
          initialAnchorNodeId: bab1.nodes.first.id,
          theme: ReadingThemeType.white,
          typography: const TypographySettings(twoPageSpread: true),
          onTapContent: () {},
          onProgressChanged: (ch, p, pct, anc, off) {},
        ),
        size: const Size(1102, 951),
        filename: '02_bab1_opener_spread.png',
      );
    });

    testWidgets(
      '3. Render BAB I Section: Lists & Dialogues (Tema, Konflik, Simpati, Solusi)',
      (tester) async {
        print('\n--- Evaluating BAB I Lists & Dialogues ---');
        final bab1 = readerDoc.chapters.firstWhere(
          (c) => c.title.contains('BAB I'),
        );
        final targetNode = bab1.nodes.firstWhere(
          (n) => n.text.contains('1. Tema'),
        );

        await renderAndCapture(
          tester,
          widget: PaginatedReflowableReader(
            document: readerDoc,
            initialAnchorNodeId: targetNode.id,
            theme: ReadingThemeType.sepia,
            typography: const TypographySettings(twoPageSpread: true),
            onTapContent: () {},
            onProgressChanged: (ch, p, pct, anc, off) {},
          ),
          size: const Size(1102, 951),
          filename: '03_bab1_lists_and_dialogue.png',
        );
      },
    );

    testWidgets(
      '4. Render Chapter 5: BAB II (Pintar Mendengar, Pandai Berbicara)',
      (tester) async {
        print('\n--- Evaluating Chapter 5: BAB II ---');
        final bab2 = readerDoc.chapters.firstWhere(
          (c) => c.title.contains('BAB II'),
        );
        expect(bab2.nodes, isNotEmpty);
        print(
          '• BAB II Title: "${bab2.title}" with ${bab2.nodes.length} nodes',
        );

        await renderAndCapture(
          tester,
          widget: PaginatedReflowableReader(
            document: readerDoc,
            initialAnchorNodeId: bab2.nodes.first.id,
            theme: ReadingThemeType.white,
            typography: const TypographySettings(twoPageSpread: true),
            onTapContent: () {},
            onProgressChanged: (ch, p, pct, anc, off) {},
          ),
          size: const Size(1102, 951),
          filename: '04_bab2_opener_spread.png',
        );
      },
    );

    testWidgets(
      '5. Render Chapter 6: BAB III (Ucapan yang Membuat Lawan Bicara Memihak Kita)',
      (tester) async {
        print('\n--- Evaluating Chapter 6: BAB III (MEMIHAK) ---');
        final bab3 = readerDoc.chapters.firstWhere(
          (c) => c.title.contains('BAB III'),
        );
        expect(bab3.nodes, isNotEmpty);
        expect(bab3.title.toLowerCase(), contains('memihak'));
        print(
          '• BAB III Title: "${bab3.title}" with ${bab3.nodes.length} nodes',
        );

        await renderAndCapture(
          tester,
          widget: PaginatedReflowableReader(
            document: readerDoc,
            initialAnchorNodeId: bab3.nodes.first.id,
            theme: ReadingThemeType.white,
            typography: const TypographySettings(twoPageSpread: true),
            onTapContent: () {},
            onProgressChanged: (ch, p, pct, anc, off) {},
          ),
          size: const Size(1102, 951),
          filename: '05_bab3_memihak_opener.png',
        );
      },
    );

    testWidgets(
      '6. Render Chapter 7: BAB IV (Beratnya Ucapan Ditentukan Oleh Dalamnya Isi & KISS)',
      (tester) async {
        print('\n--- Evaluating Chapter 7: BAB IV ---');
        final bab4 = readerDoc.chapters.firstWhere(
          (c) => c.title.contains('BAB IV'),
        );
        expect(bab4.nodes, isNotEmpty);
        print(
          '• BAB IV Title: "${bab4.title}" with ${bab4.nodes.length} nodes',
        );

        final kissNode = bab4.nodes.firstWhere((n) => n.text.contains('Kiss!'));

        await renderAndCapture(
          tester,
          widget: PaginatedReflowableReader(
            document: readerDoc,
            initialAnchorNodeId: kissNode.id,
            theme: ReadingThemeType.sepia,
            typography: const TypographySettings(twoPageSpread: true),
            onTapContent: () {},
            onProgressChanged: (ch, p, pct, anc, off) {},
          ),
          size: const Size(1102, 951),
          filename: '06_bab4_kiss_principle.png',
        );
      },
    );

    testWidgets(
      '7. Render Chapter 8: BAB V (Suara Bagus Bukan Bawaan Dari Lahir & Vocal Exercises)',
      (tester) async {
        print('\n--- Evaluating Chapter 8: BAB V ---');
        final bab5 = readerDoc.chapters.firstWhere(
          (c) => c.title.contains('BAB V'),
        );
        expect(bab5.nodes, isNotEmpty);
        print('• BAB V Title: "${bab5.title}" with ${bab5.nodes.length} nodes');

        final vocalNode = bab5.nodes.firstWhere(
          (n) => n.text.contains('Bibir: Ma Ba Ta'),
        );

        await renderAndCapture(
          tester,
          widget: PaginatedReflowableReader(
            document: readerDoc,
            initialAnchorNodeId: vocalNode.id,
            theme: ReadingThemeType.white,
            typography: const TypographySettings(twoPageSpread: true),
            onTapContent: () {},
            onProgressChanged: (ch, p, pct, anc, off) {},
          ),
          size: const Size(1102, 951),
          filename: '07_bab5_vocal_exercises.png',
        );
      },
    );

    testWidgets(
      '8. Compact Single-Page Layout (600x800) & Window Resize Anchor Preservation',
      (tester) async {
        print('\n--- Evaluating Compact Single-Page & Resize ---');
        final bab1 = readerDoc.chapters.firstWhere(
          (c) => c.title.contains('BAB I'),
        );
        final anchorNode = bab1.nodes[5];

        await renderAndCapture(
          tester,
          widget: PaginatedReflowableReader(
            document: readerDoc,
            initialAnchorNodeId: anchorNode.id,
            theme: ReadingThemeType.dark,
            typography: const TypographySettings(twoPageSpread: false),
            onTapContent: () {},
            onProgressChanged: (ch, p, pct, anc, off) {},
          ),
          size: const Size(600, 800),
          filename: '08_compact_single_page.png',
        );

        // Verify that after resize from compact (600) to wide spread (1102), anchor is preserved
        PaginationEngine.clearCache();
        final compactPages = PaginationEngine.paginateDocument(
          document: readerDoc,
          viewportWidth: 600,
          viewportHeight: 800,
          typography: const TypographySettings(twoPageSpread: false),
        );
        final compactIndex = PaginationEngine.findPageIndexForAnchor(
          pages: compactPages,
          anchorNodeId: anchorNode.id,
        );

        final spreadPages = PaginationEngine.paginateDocument(
          document: readerDoc,
          viewportWidth: 1102,
          viewportHeight: 951,
          typography: const TypographySettings(twoPageSpread: true),
        );
        final spreadIndex = PaginationEngine.findPageIndexForAnchor(
          pages: spreadPages,
          anchorNodeId: anchorNode.id,
        );

        print(
          '• Anchor ${anchorNode.id} mapped to compact page $compactIndex and spread page $spreadIndex',
        );
        expect(compactIndex, greaterThan(0));
        expect(spreadIndex, greaterThan(0));
        expect(
          spreadPages[spreadIndex].slices.any(
            (s) => s.node.id == anchorNode.id,
          ),
          isTrue,
        );
      },
    );
  });
}
