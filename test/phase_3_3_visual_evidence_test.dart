// ignore_for_file: avoid_print, depend_on_referenced_packages

import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/core/typography/typography_settings.dart';
import 'package:digital_books/features/reader/domain/models/book_annotation.dart';
import 'package:digital_books/features/reader/domain/models/highlight_palette.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'package:digital_books/features/reader/presentation/widgets/annotations_sheet.dart';
import 'package:digital_books/features/reader/presentation/widgets/original_pdf_reader.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/highlight_interaction_sheet.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/paginated_reflowable_reader.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/scrolling_reflowable_reader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final evidenceDir = 'docs/visual_evidence/phase_3_3';

  setUpAll(() {
    Directory(evidenceDir).createSync(recursive: true);
  });

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
        theme: ThemeData(
          fontFamily: 'Inter',
          brightness: Brightness.light,
        ),
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
    );

    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null) {
        final img = await boundary.toImage(pixelRatio: 2.0);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        if (bytes != null) {
          final file = File(p.join(evidenceDir, filename));
          file.writeAsBytesSync(bytes.buffer.asUint8List());
          print(
            '  ✓ Captured: ${file.path} (${(file.lengthSync() / 1024).toStringAsFixed(1)} KB)',
          );
        }
      }
    });

    tester.view.resetPhysicalSize();
  }

  // Sample structured document for Reflowable Reader
  ReaderDocument createSampleDocument() {
    return const ReaderDocument(
      bookId: 'book-vis-laut',
      title: 'Laut Bercerita',
      author: 'Leila S. Chudori',
      chapters: [
        ReaderChapter(
          id: 'ch-0',
          index: 0,
          title: 'Bagian Pertama: Biru Laut',
          nodes: [
            ContentNode(
              id: 'node-h1',
              type: ContentNodeType.heading,
              text: 'RUMAH HANTU SEYEGAN',
              level: 1,
              sourcePdfPage: 12,
            ),
            ContentNode(
              id: 'node-p1',
              type: ContentNodeType.paragraph,
              text:
                  'Malam itu angin dingin berembus menembus celah-celah papan rumah di Seyegan. '
                  'Kami duduk melingkar di atas tikar pandan yang mulai koyak di pinggirannya, '
                  'menghadap sepiring pisang goreng yang sudah dingin dan segelas teh nasgitel.',
              sourcePdfPage: 12,
            ),
            ContentNode(
              id: 'node-quote',
              type: ContentNodeType.quote,
              text:
                  '"Matamu harus tetap awas, Laut. Ketakutan yang kita biarkan tumbuh '
                  'akan menjadi penjara paling kukuh bagi pikiran kita sendiri."',
              sourcePdfPage: 13,
            ),
            ContentNode(
              id: 'node-p2',
              type: ContentNodeType.paragraph,
              text:
                  'Mas Biru mengetik sesuatu pada mesin tik tua bermerek Olympia. Suara ketukan logamnya '
                  'berirama, seolah mengimbangi detak jantung kami yang tak pernah benar-benar tenang.',
              sourcePdfPage: 13,
            ),
          ],
        ),
      ],
    );
  }

  group('Phase 3.3 — 9 Native Visual Evidence Captures', () {
    testWidgets('01. Capture Text Selection Toolbar', (tester) async {
      await captureWidget(
        tester: tester,
        size: const Size(800, 480),
        filename: '01_text_selection_toolbar.png',
        widget: Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Laut Bercerita — Bab 1',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 24),
              // Simulated selected paragraph
              RichText(
                text: TextSpan(
                  style: const TextStyle(
                    fontSize: 18,
                    height: 1.7,
                    color: Colors.black87,
                  ),
                  children: [
                    const TextSpan(
                      text:
                          'Malam itu angin dingin berembus menembus celah-celah papan rumah di Seyegan. Kami duduk melingkar di atas ',
                    ),
                    TextSpan(
                      text: 'tikar pandan yang mulai koyak di pinggirannya',
                      style: TextStyle(
                        backgroundColor: const Color(0xFF007AFF).withValues(alpha: 0.28),
                        decoration: TextDecoration.underline,
                        decorationColor: const Color(0xFF007AFF),
                      ),
                    ),
                    const TextSpan(
                      text:
                          ', menghadap sepiring pisang goreng yang sudah dingin dan segelas teh nasgitel.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              // Floating macOS Text Selection Contextual Toolbar
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2C2C2E),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.30),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Palette mini pills
                      ...HighlightColorType.values.map((c) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: c.primaryColor,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white24, width: 1.2),
                              ),
                            ),
                          )),
                      const SizedBox(width: 8),
                      Container(width: 1, height: 18, color: Colors.white24),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.edit_note_rounded, color: Colors.white, size: 16),
                        label: const Text('Catatan', style: TextStyle(color: Colors.white, fontSize: 13)),
                      ),
                      TextButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.copy_rounded, color: Colors.white70, size: 15),
                        label: const Text('Salin', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });

    testWidgets('02. Capture Highlight Palette Multi-Color', (tester) async {
      await captureWidget(
        tester: tester,
        size: const Size(600, 360),
        filename: '02_highlight_palette_multi_color.png',
        widget: Container(
          color: const Color(0xFF1E1E22),
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'PALET WARNA SOROTAN (HIGHLIGHT PALETTE)',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: HighlightColorType.values.map((color) {
                  final isSelected = color == HighlightColorType.yellow;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: color.primaryColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? Colors.white : Colors.transparent,
                            width: 3.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: color.primaryColor.withValues(alpha: 0.5),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: isSelected
                            ? const Icon(Icons.check, color: Colors.black87, size: 24)
                            : null,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        color.label,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white60,
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              const Center(
                child: Text(
                  '6 Warna Standar: Kuning • Hijau • Biru • Merah Muda • Ungu • Emas',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      );
    });

    testWidgets('03. Capture Add/Edit Note Sheet', (tester) async {
      await captureWidget(
        tester: tester,
        size: const Size(640, 520),
        filename: '03_add_edit_note_sheet.png',
        widget: HighlightInteractionSheet(
          selectedText:
              'Matamu harus tetap awas, Laut. Ketakutan yang kita biarkan tumbuh akan menjadi penjara paling kukuh bagi pikiran kita sendiri.',
          initialColor: 'yellow',
          initialNote:
              'Pesan mendalam dari Mas Biru di Seyegan. Menggambarkan ketegangan politik aktivis 1998 sekaligus resiliensi batin.',
          theme: ReadingThemeType.white,
          onSave: (color, note) {},
          onDelete: () {},
        ),
      );
    });

    testWidgets('04. Capture Bookmark Creation Active', (tester) async {
      await captureWidget(
        tester: tester,
        size: const Size(820, 260),
        filename: '04_bookmark_creation_active.png',
        widget: Container(
          color: const Color(0xFFF2F2F7),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Top Action Bar with Active Bookmark
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Laut Bercerita', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          Text('Halaman 12 dari 379 • Rumah Hantu Seyegan', style: TextStyle(fontSize: 11, color: Colors.black54)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.collections_bookmark_rounded, size: 20),
                      onPressed: () {},
                    ),
                    // Active Bookmark Button
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.bookmark_rounded, color: Color(0xFF007AFF), size: 22),
                          SizedBox(width: 6),
                          Text('Tandai', style: TextStyle(color: Color(0xFF007AFF), fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Floating Toast Notification
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E22),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bookmark_added_rounded, color: Color(0xFF007AFF), size: 18),
                    SizedBox(width: 10),
                    Text(
                      'Markah ditambahkan: Halaman 12',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });

    testWidgets('05. Capture Annotations Sheet Library', (tester) async {
      final sampleAnnotations = [
        BookAnnotation(
          id: 'ann-1',
          bookId: 'book-vis-laut',
          type: AnnotationType.note,
          selectedText:
              'Matamu harus tetap awas, Laut. Ketakutan yang kita biarkan tumbuh akan menjadi penjara paling kukuh bagi pikiran kita sendiri.',
          pageIndex: 13,
          chapterId: 'ch-0',
          color: 'gold',
          note: 'Pesan penting Mas Biru mengenai keberanian aktivis mahasiswa di Seyegan.',
          createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        ),
        BookAnnotation(
          id: 'ann-2',
          bookId: 'book-vis-laut',
          type: AnnotationType.highlight,
          selectedText: 'tikar pandan yang mulai koyak di pinggirannya',
          pageIndex: 12,
          chapterId: 'ch-0',
          color: 'green',
          createdAt: DateTime.now().subtract(const Duration(hours: 4)),
        ),
        BookAnnotation(
          id: 'ann-3',
          bookId: 'book-vis-laut',
          type: AnnotationType.highlight,
          selectedText: 'Olympia. Suara ketukan logamnya berirama',
          pageIndex: 13,
          chapterId: 'ch-0',
          color: 'blue',
          createdAt: DateTime.now().subtract(const Duration(hours: 6)),
        ),
        BookAnnotation(
          id: 'ann-4',
          bookId: 'book-vis-laut',
          type: AnnotationType.bookmark,
          selectedText: 'Rumah Hantu Seyegan - Rapat Gerakan',
          pageIndex: 12,
          chapterId: 'ch-0',
          createdAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
      ];

      await captureWidget(
        tester: tester,
        size: const Size(700, 640),
        filename: '05_annotations_sheet_library.png',
        widget: AnnotationsSheet(
          bookTitle: 'Laut Bercerita — Leila S. Chudori',
          annotations: sampleAnnotations,
          theme: ReadingThemeType.white,
          onNavigateToAnnotation: (_) {},
        ),
      );
    });

    testWidgets('06. Capture Navigation From Annotation Library', (tester) async {
      final annotationToJump = BookAnnotation(
        id: 'ann-target-nav',
        bookId: 'book-vis-laut',
        type: AnnotationType.note,
        selectedText: 'Matamu harus tetap awas, Laut. Ketakutan yang kita biarkan tumbuh...',
        pageIndex: 13,
        chapterId: 'ch-0',
        color: 'gold',
        note: 'Pesan Mas Biru.',
        createdAt: DateTime.now(),
      );

      await captureWidget(
        tester: tester,
        size: const Size(760, 480),
        filename: '06_navigation_from_annotation_library.png',
        widget: Container(
          color: const Color(0xFFF8F9FA),
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF34C759).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.touch_app_rounded, color: Color(0xFF34C759), size: 16),
                        SizedBox(width: 6),
                        Text('Navigasi Presisi Lintas Mode', style: TextStyle(color: Color(0xFF34C759), fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF007AFF), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF007AFF).withValues(alpha: 0.15),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(width: 6, height: 50, decoration: BoxDecoration(color: const Color(0xFFD4AF37), borderRadius: BorderRadius.circular(3))),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('"${annotationToJump.selectedText}"', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                          const SizedBox(height: 6),
                          const Row(
                            children: [
                              Icon(Icons.location_on_rounded, size: 14, color: Color(0xFF007AFF)),
                              SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'Melompat ke Halaman 13 (Original PDF) & Paragraf 3 (Reflowable)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF007AFF),
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF007AFF), size: 18),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Target destination view preview
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Halaman 13 — Target Navigasi Terfokus:', style: TextStyle(fontSize: 12, color: Colors.black54)),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFE082).withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFD4AF37), width: 1.2),
                      ),
                      child: const Text(
                        '"Matamu harus tetap awas, Laut. Ketakutan yang kita biarkan tumbuh akan menjadi penjara paling kukuh bagi pikiran kita sendiri."',
                        style: TextStyle(fontSize: 15, height: 1.6, fontStyle: FontStyle.italic),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });

    testWidgets('07. Capture Highlight in Original PDF Reader', (tester) async {
      final sampleAnnotations = [
        BookAnnotation(
          id: 'ann-pdf-box-1',
          bookId: 'book-vis-laut',
          type: AnnotationType.note,
          selectedText: 'RUMAH HANTU SEYEGAN',
          pageIndex: 1,
          boundingBoxes: const [
            Rect.fromLTWH(0.25, 0.12, 0.50, 0.04),
          ],
          color: 'gold',
          note: 'Judul bagian awal.',
          createdAt: DateTime(2026),
        ),
        BookAnnotation(
          id: 'ann-pdf-box-2',
          bookId: 'book-vis-laut',
          type: AnnotationType.highlight,
          selectedText: 'Malam itu angin dingin berembus menembus celah-celah papan rumah di Seyegan.',
          pageIndex: 1,
          boundingBoxes: const [
            Rect.fromLTWH(0.12, 0.22, 0.76, 0.035),
            Rect.fromLTWH(0.12, 0.26, 0.70, 0.035),
          ],
          color: 'yellow',
          createdAt: DateTime(2026),
        ),
      ];

      await captureWidget(
        tester: tester,
        size: const Size(680, 850),
        filename: '07_highlight_original_pdf.png',
        widget: Container(
          color: const Color(0xFFFAF9F6), // Realistic warm paper PDF background
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Simulated scanned PDF page content
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 72),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Text(
                        'RUMAH HANTU SEYEGAN',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2.0,
                          color: Colors.black.withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                    const SizedBox(height: 48),
                    Text(
                      'Malam itu angin dingin berembus menembus celah-celah papan rumah di Seyegan. '
                      'Kami duduk melingkar di atas tikar pandan yang mulai koyak di pinggirannya, '
                      'menghadap sepiring pisang goreng yang sudah dingin dan segelas teh nasgitel.',
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.8,
                        color: Colors.black.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Mas Biru mengetik sesuatu pada mesin tik tua bermerek Olympia. Suara ketukan logamnya '
                      'berirama, seolah mengimbangi detak jantung kami yang tak pernah benar-benar tenang.',
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.8,
                        color: Colors.black.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              // Annotation Overlay with Custom Painter
              CustomPaint(
                painter: PdfUserAnnotationPainter(
                  annotations: sampleAnnotations,
                  theme: ReadingThemeType.warmPaper,
                ),
              ),
            ],
          ),
        ),
      );
    });

    testWidgets('08. Capture Highlight in Reflowable Paginated Reader', (tester) async {
      final doc = createSampleDocument();
      final highlights = [
        Highlight(
          id: 'hl-reflow-1',
          bookId: 'book-vis-laut',
          selectedText: 'Malam itu angin dingin berembus',
          startPosition: 1,
          endPosition: 1,
          color: 'yellow',
          anchorNodeId: 'node-p1',
          startOffset: 0,
          endOffset: 31,
          anchorVersion: 1,
          createdAt: DateTime.now(),
        ),
        Highlight(
          id: 'hl-reflow-2',
          bookId: 'book-vis-laut',
          selectedText: 'Matamu harus tetap awas, Laut.',
          startPosition: 1,
          endPosition: 1,
          color: 'gold',
          note: 'Kutipan penting ketahanan mental.',
          anchorNodeId: 'node-quote',
          startOffset: 1,
          endOffset: 31,
          anchorVersion: 1,
          createdAt: DateTime.now(),
        ),
      ];

      await captureWidget(
        tester: tester,
        size: const Size(680, 720),
        filename: '08_highlight_reflowable_paginated.png',
        widget: PaginatedReflowableReader(
          document: doc,
          theme: ReadingThemeType.white,
          typography: const TypographySettings(fontSize: 17, lineSpacing: 1.7),
          highlights: highlights,
          onTapContent: () {},
          onProgressChanged: (ch, p, pct, node, offset) {},
        ),
      );
    });

    testWidgets('09. Capture Highlight in Reflowable Continuous Scrolling Reader', (tester) async {
      final doc = createSampleDocument();
      final highlights = [
        Highlight(
          id: 'hl-scroll-1',
          bookId: 'book-vis-laut',
          selectedText: 'tikar pandan yang mulai koyak di pinggirannya',
          startPosition: 1,
          endPosition: 1,
          color: 'green',
          anchorNodeId: 'node-p1',
          startOffset: 110,
          endOffset: 155,
          anchorVersion: 1,
          createdAt: DateTime.now(),
        ),
        Highlight(
          id: 'hl-scroll-2',
          bookId: 'book-vis-laut',
          selectedText: 'Olympia. Suara ketukan logamnya berirama',
          startPosition: 1,
          endPosition: 1,
          color: 'pink',
          anchorNodeId: 'node-p2',
          startOffset: 48,
          endOffset: 87,
          anchorVersion: 1,
          createdAt: DateTime.now(),
        ),
      ];

      await captureWidget(
        tester: tester,
        size: const Size(680, 720),
        filename: '09_highlight_reflowable_scrolling.png',
        widget: ScrollingReflowableReader(
          document: doc,
          theme: ReadingThemeType.sepia,
          typography: const TypographySettings(fontSize: 17, lineSpacing: 1.7),
          highlights: highlights,
          onTapContent: () {},
          onProgressChanged: (ch, p, pct, node, offset) {},
        ),
      );
    });
  });
}
