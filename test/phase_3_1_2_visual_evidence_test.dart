// ignore_for_file: avoid_print, depend_on_referenced_packages

import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/core/typography/typography_settings.dart';
import 'package:digital_books/features/processing/services/apple_vision_ocr_service.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/paginated_reflowable_reader.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/scrolling_reflowable_reader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final ocrService = AppleVisionOcrService();
  late Directory tempDir;
  final evidenceDir = 'docs/visual_evidence/phase_3_1_2';

  final bicaraSeninyaPath =
      '/Users/davindalana/Downloads/Bicara Itu Ada Seninya (Oh Su Hyang).pdf';

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('db_vis_312_');
    Directory(evidenceDir).createSync(recursive: true);
    await ocrService.ensureBinaryAvailable();
  });

  tearDownAll(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Future<ReaderDocument> getSampleStructuredDoc() async {
    // Generate a rich structured ReaderDocument using actual book text
    final nodes = [
      const ContentNode(
        id: 'doc_title',
        type: ContentNodeType.documentTitle,
        text: 'BICARA ITU ADA SENINYA',
        level: 1,
        sourcePdfPage: 1,
      ),
      const ContentNode(
        id: 'sec_1',
        type: ContentNodeType.sectionHeading,
        text: 'Rahasia Komunikasi Yang Efektif dan Berkesan',
        level: 2,
        sourcePdfPage: 1,
      ),
      const ContentNode(
        id: 'copy_1',
        type: ContentNodeType.copyrightBlock,
        text: 'Hak Cipta Dilindungi Undang-Undang\n'
            'Diterbitkan oleh Penerbit Bhuana Ilmu Populer, Kelompok Gramedia\n'
            'ISBN: 978-602-455-392-0 | Cetakan ke-1: Januari 2018',
        sourcePdfPage: 4,
      ),
      const ContentNode(
        id: 'p_1',
        type: ContentNodeType.paragraph,
        text: 'Bicara bukan sekadar mengeluarkan bunyi kata dari mulut, melainkan menyalurkan '
            'perasaan, keyakinan, dan empati kepada lawan bicara. Ketika Anda mendengarkan '
            'dengan tulus, orang lain akan membuka hatinya untuk mendengarkan pandangan Anda.',
        sourcePdfPage: 4,
      ),
      const ContentNode(
        id: 'list_1',
        type: ContentNodeType.orderedList,
        text: '1. Dengarkan dengan penuh empati sebelum mulai mengemukakan pendapat pribadi.',
        sourcePdfPage: 4,
      ),
      const ContentNode(
        id: 'list_2',
        type: ContentNodeType.orderedList,
        text: '2. Sesuaikan tempo dan intonasi suara dengan konteks dan suasana pembicaraan.',
        sourcePdfPage: 4,
      ),
      const ContentNode(
        id: 'list_3',
        type: ContentNodeType.orderedList,
        text: '3. Gunakan analogi konkret yang relevan dengan pengalaman nyata pendengar.',
        sourcePdfPage: 4,
      ),
      const ContentNode(
        id: 'quote_1',
        type: ContentNodeType.quote,
        text: '"Kata-kata yang tepat pada waktu yang tepat mampu mengubah takdir seseorang."',
        sourcePdfPage: 8,
      ),
      const ContentNode(
        id: 'p_2',
        type: ContentNodeType.paragraph,
        text: 'Melalui latihan yang konsisten dan pemahaman mendalam atas seni berbicara, siapa pun dapat '
            'menjadi komunikator yang disegani dan memberi dampak positif bagi lingkungannya.',
        sourcePdfPage: 9,
      ),
    ];

    return ReaderDocument(
      bookId: 'bicara_structured',
      title: 'Bicara Itu Ada Seninya',
      author: 'Oh Su Hyang',
      totalPages: 10,
      chapters: [
        ReaderChapter(
          id: 'ch_intro',
          index: 0,
          title: 'Pengantar',
          nodes: nodes,
        ),
      ],
    );
  }

  Future<void> captureWidget({
    required WidgetTester tester,
    required Widget widget,
    required Size size,
    required String filename,
  }) async {
    final key = GlobalKey();
    await tester.binding.setSurfaceSize(size);
    tester.view.physicalSize = Size(size.width * 2.0, size.height * 2.0);
    tester.view.devicePixelRatio = 2.0;

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: widget,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null) {
        final img = await boundary.toImage(pixelRatio: 2.0);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        if (bytes != null) {
          final file = File(p.join(evidenceDir, filename));
          file.writeAsBytesSync(bytes.buffer.asUint8List());
          print('  ✓ Captured: ${file.path} (${(file.lengthSync() / 1024).toStringAsFixed(1)} KB)');
        }
      }
    });

    tester.view.resetPhysicalSize();
  }

  group('Phase 3.1.2 — Native Visual Evidence Capture Suite', () {
    testWidgets('1. Capture Original Scanned PDF Page', (tester) async {
      final outPath = p.join(evidenceDir, 'mode_original_pdf.png');

      await tester.runAsync(() async {
        final pdfDoc = await PdfDocument.openFile(bicaraSeninyaPath);
        final page = pdfDoc.pages[3]; // P.4 (Copyright & Lists page)
        final img = await page.render(
          width: (page.width * 1.5).round(),
          height: (page.height * 1.5).round(),
        );
        final uiImg = await img?.createImage();
        final byteData = await uiImg?.toByteData(format: ui.ImageByteFormat.png);
        File(outPath).writeAsBytesSync(byteData!.buffer.asUint8List());
        await pdfDoc.dispose();
      });

      print('  ✓ Captured: $outPath (${(File(outPath).lengthSync() / 1024).toStringAsFixed(1)} KB)');
      expect(File(outPath).existsSync(), isTrue);
    });

    testWidgets('2. Capture Reflowable Modes: Paginated vs Scrolling', (tester) async {
      final doc = await getSampleStructuredDoc();

      // Paginated
      await captureWidget(
        tester: tester,
        widget: PaginatedReflowableReader(
          document: doc,
          theme: ReadingThemeType.warmPaper,
          typography: const TypographySettings(fontSize: 18.0, lineSpacing: 1.6),
          onTapContent: () {},
          onProgressChanged: (ch, p, pct, anc, off) {},
        ),
        size: const Size(1000, 750),
        filename: 'mode_reflowable_paginated.png',
      );
      expect(File(p.join(evidenceDir, 'mode_reflowable_paginated.png')).existsSync(), isTrue);

      // Scrolling
      await captureWidget(
        tester: tester,
        widget: ScrollingReflowableReader(
          document: doc,
          theme: ReadingThemeType.warmPaper,
          typography: const TypographySettings(fontSize: 18.0, lineSpacing: 1.6),
          onTapContent: () {},
          onProgressChanged: (ch, p, pct, anc, off) {},
        ),
        size: const Size(1000, 750),
        filename: 'mode_reflowable_scrolling.png',
      );
      expect(File(p.join(evidenceDir, 'mode_reflowable_scrolling.png')).existsSync(), isTrue);
    });

    testWidgets('3. Capture Typography Scaling: 14pt, 18pt, 24pt', (tester) async {
      final doc = await getSampleStructuredDoc();

      // Small (14pt)
      await captureWidget(
        tester: tester,
        widget: PaginatedReflowableReader(
          document: doc,
          theme: ReadingThemeType.warmPaper,
          typography: const TypographySettings(fontSize: 14.0, lineSpacing: 1.4),
          onTapContent: () {},
          onProgressChanged: (ch, p, pct, anc, off) {},
        ),
        size: const Size(900, 700),
        filename: 'typography_small_14pt.png',
      );
      expect(File(p.join(evidenceDir, 'typography_small_14pt.png')).existsSync(), isTrue);

      // Normal (18pt)
      await captureWidget(
        tester: tester,
        widget: PaginatedReflowableReader(
          document: doc,
          theme: ReadingThemeType.warmPaper,
          typography: const TypographySettings(fontSize: 18.0, lineSpacing: 1.6),
          onTapContent: () {},
          onProgressChanged: (ch, p, pct, anc, off) {},
        ),
        size: const Size(900, 700),
        filename: 'typography_normal_18pt.png',
      );
      expect(File(p.join(evidenceDir, 'typography_normal_18pt.png')).existsSync(), isTrue);

      // Large (24pt)
      await captureWidget(
        tester: tester,
        widget: PaginatedReflowableReader(
          document: doc,
          theme: ReadingThemeType.warmPaper,
          typography: const TypographySettings(fontSize: 24.0, lineSpacing: 1.8),
          onTapContent: () {},
          onProgressChanged: (ch, p, pct, anc, off) {},
        ),
        size: const Size(900, 700),
        filename: 'typography_large_24pt.png',
      );
      expect(File(p.join(evidenceDir, 'typography_large_24pt.png')).existsSync(), isTrue);
    });

    testWidgets('4. Capture Reading Themes: White, Sepia, Dark', (tester) async {
      final doc = await getSampleStructuredDoc();

      // White
      await captureWidget(
        tester: tester,
        widget: PaginatedReflowableReader(
          document: doc,
          theme: ReadingThemeType.white,
          typography: const TypographySettings(fontSize: 18.0, lineSpacing: 1.6),
          onTapContent: () {},
          onProgressChanged: (ch, p, pct, anc, off) {},
        ),
        size: const Size(900, 700),
        filename: 'theme_white.png',
      );
      expect(File(p.join(evidenceDir, 'theme_white.png')).existsSync(), isTrue);

      // Sepia
      await captureWidget(
        tester: tester,
        widget: PaginatedReflowableReader(
          document: doc,
          theme: ReadingThemeType.sepia,
          typography: const TypographySettings(fontSize: 18.0, lineSpacing: 1.6),
          onTapContent: () {},
          onProgressChanged: (ch, p, pct, anc, off) {},
        ),
        size: const Size(900, 700),
        filename: 'theme_sepia.png',
      );
      expect(File(p.join(evidenceDir, 'theme_sepia.png')).existsSync(), isTrue);

      // Dark
      await captureWidget(
        tester: tester,
        widget: PaginatedReflowableReader(
          document: doc,
          theme: ReadingThemeType.dark,
          typography: const TypographySettings(fontSize: 18.0, lineSpacing: 1.6),
          onTapContent: () {},
          onProgressChanged: (ch, p, pct, anc, off) {},
        ),
        size: const Size(900, 700),
        filename: 'theme_dark.png',
      );
      expect(File(p.join(evidenceDir, 'theme_dark.png')).existsSync(), isTrue);
    });

    testWidgets('5. Capture Layouts: Single Page vs Two-Page Spread', (tester) async {
      final doc = await getSampleStructuredDoc();

      // Single Page (Standard Desktop: 900x700)
      await captureWidget(
        tester: tester,
        widget: PaginatedReflowableReader(
          document: doc,
          theme: ReadingThemeType.warmPaper,
          typography: const TypographySettings(fontSize: 18.0, lineSpacing: 1.6, twoPageSpread: false),
          onTapContent: () {},
          onProgressChanged: (ch, p, pct, anc, off) {},
        ),
        size: const Size(900, 700),
        filename: 'layout_single_page.png',
      );
      expect(File(p.join(evidenceDir, 'layout_single_page.png')).existsSync(), isTrue);

      // Two-Page Spread (Expansive Desktop: 1400x850)
      await captureWidget(
        tester: tester,
        widget: PaginatedReflowableReader(
          document: doc,
          theme: ReadingThemeType.warmPaper,
          typography: const TypographySettings(fontSize: 18.0, lineSpacing: 1.6, twoPageSpread: true),
          onTapContent: () {},
          onProgressChanged: (ch, p, pct, anc, off) {},
        ),
        size: const Size(1400, 850),
        filename: 'layout_two_page_spread.png',
      );
      expect(File(p.join(evidenceDir, 'layout_two_page_spread.png')).existsSync(), isTrue);
    });
  });
}
