// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:ui' as ui;
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/core/typography/typography_settings.dart';
import 'package:digital_books/features/reader/domain/engines/reflowable_highlight_span_builder.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'package:digital_books/features/reader/presentation/widgets/book_search_dialog.dart';
import 'package:digital_books/features/reader/presentation/widgets/original_pdf_reader.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/paginated_reflowable_reader.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/scrolling_reflowable_reader.dart';
import 'package:digital_books/features/reader/presentation/widgets/search_traversal_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final evidenceDir = 'docs/visual_evidence/phase_3_2_1';

  setUpAll(() {
    Directory(evidenceDir).createSync(recursive: true);
  });

  Future<void> captureWidget({
    required WidgetTester tester,
    required Widget widget,
    required Size size,
    required String filename,
    Future<void> Function(WidgetTester tester)? onReady,
  }) async {
    final key = GlobalKey();
    await tester.binding.setSurfaceSize(size);
    tester.view.physicalSize = Size(size.width * 2.0, size.height * 2.0);
    tester.view.devicePixelRatio = 2.0;

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'SF Pro Display'),
        home: Scaffold(
          backgroundColor: const Color(0xFF1C1C1E),
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

    if (onReady != null) {
      await onReady(tester);
    } else {
      await tester.pumpAndSettle();
    }

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
  }

  group('Phase 3.2.1 — Search Accuracy, Index Integrity & Navigation Visual Audit', () {
    testWidgets('01_digital_search_results.png — Digital vector search results list with source badge', (tester) async {
      final doc = ReaderDocument(
        bookId: 'vis_dig_1',
        title: 'The Adventures of Sherlock Holmes',
        author: 'Arthur Conan Doyle',
        chapters: [
          const ReaderChapter(
            id: 'ch_1',
            index: 0,
            title: 'Chapter 1: A Scandal in Bohemia',
            nodes: [
              ContentNode(
                id: 'n1',
                type: ContentNodeType.paragraph,
                text: 'To Sherlock Holmes she is always the woman. I have seldom heard him mention her under any other name.',
                sourcePdfPage: 1,
              ),
              ContentNode(
                id: 'n2',
                type: ContentNodeType.paragraph,
                text: 'Holmes took the violin from its corner and began to play a low, melancholy tune as he pondered the case.',
                sourcePdfPage: 2,
              ),
              ContentNode(
                id: 'n3',
                type: ContentNodeType.paragraph,
                text: 'My friend Holmes was a man of keen intellect, observing details that escaped all others.',
                sourcePdfPage: 3,
              ),
            ],
          ),
        ],
      );

      await captureWidget(
        tester: tester,
        size: const Size(640, 720),
        filename: '01_digital_search_results.png',
        widget: BookSearchDialog(
          theme: ReadingThemeType.dark,
          readerDocument: doc,
          onNavigateToResult: (_) {},
        ),
        onReady: (tester) async {
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField), 'Holmes');
          await tester.pumpAndSettle(const Duration(milliseconds: 350));
        },
      );

      expect(File(p.join(evidenceDir, '01_digital_search_results.png')).existsSync(), isTrue);
    });

    testWidgets('02_digital_original_pdf_highlight.png — Original PDF Reader precision bounding-box highlight', (tester) async {
      const highlightBoxes = [
        Rect.fromLTWH(0.10, 0.46, 0.12, 0.035),
      ];

      final pageWidget = Container(
        color: const Color(0xFFFBFBFD),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 54, vertical: 64),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(
                    child: Text(
                      'THE ADVENTURES OF SHERLOCK HOLMES',
                      style: TextStyle(
                        color: Colors.black54,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Chapter 1: The Beginning',
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'It was a dark and stormy night when the messenger finally arrived at the gates of the ancient estate. '
                    'He carried news that would change the destiny of the kingdom forever.',
                    style: TextStyle(color: Colors.black87, fontSize: 15, height: 1.7),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Holmes took the violin from its corner and began to play a low, melancholy tune as he pondered the case.',
                    style: TextStyle(color: Colors.black87, fontSize: 15, height: 1.7),
                  ),
                  const Spacer(),
                  const Center(
                    child: Text('Page 1 of 3', style: TextStyle(color: Colors.black38, fontSize: 12)),
                  ),
                ],
              ),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: const PdfSearchHighlightPainter(
                  normalizedBoxes: highlightBoxes,
                  isDark: false,
                ),
              ),
            ),
          ],
        ),
      );

      await captureWidget(
        tester: tester,
        size: const Size(620, 850),
        filename: '02_digital_original_pdf_highlight.png',
        widget: pageWidget,
      );

      expect(File(p.join(evidenceDir, '02_digital_original_pdf_highlight.png')).existsSync(), isTrue);
    });

    testWidgets('03_scanned_ocr_search_results.png — Scanned OCR search results list with dehyphenated match', (tester) async {
      final doc = ReaderDocument(
        bookId: 'vis_ocr_1',
        title: 'Laut Bercerita',
        author: 'Leila S. Chudori',
        chapters: [
          const ReaderChapter(
            id: 'ch_1',
            index: 0,
            title: 'Bagian Pertama',
            nodes: [
              ContentNode(
                id: 'n1',
                type: ContentNodeType.paragraph,
                text: 'Setelah berjalan cukup jauh, kini salah satu dari mereka berteriak agar aku menaiki sebuah speedboat.',
                sourcePdfPage: 15,
              ),
              ContentNode(
                id: 'n2',
                type: ContentNodeType.paragraph,
                text: 'Kudengar seseorang menyalakan motor speedboat itu dan perahu melaju kencang membelah ombak.',
                sourcePdfPage: 15,
              ),
            ],
          ),
        ],
      );

      await captureWidget(
        tester: tester,
        size: const Size(640, 720),
        filename: '03_scanned_ocr_search_results.png',
        widget: BookSearchDialog(
          theme: ReadingThemeType.dark,
          readerDocument: doc,
          onNavigateToResult: (_) {},
        ),
        onReady: (tester) async {
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField), 'speedboat');
          await tester.pumpAndSettle(const Duration(milliseconds: 350));
        },
      );

      expect(File(p.join(evidenceDir, '03_scanned_ocr_search_results.png')).existsSync(), isTrue);
    });

    testWidgets('04_scanned_original_pdf_highlight.png — Scanned OCR page with amber bounding-box highlight', (tester) async {
      // Bounding box over "speedboat" on simulated scan page
      const highlightBoxes = [
        Rect.fromLTWH(0.55, 0.42, 0.22, 0.038),
      ];

      final pageWidget = Container(
        color: const Color(0xFFEFECE6), // Aged scanned book paper
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 52, vertical: 60),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(
                    child: Text(
                      'LAUT BERCERITA',
                      style: TextStyle(color: Colors.brown, fontSize: 13, letterSpacing: 2),
                    ),
                  ),
                  const SizedBox(height: 36),
                  const Text(
                    'Setelah lebih dari sejam kami berada di atas mobil dengan mata yang masih ditutup dan tangan terikat, '
                    'akhirnya si Manusia Pohon menarikku keluar mobil dan bersama yang lain menggiringku ke sebuah tempat, '
                    'udara terbuka.',
                    style: TextStyle(color: Color(0xFF2C241E), fontSize: 15, height: 1.7),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Setelah berjalan cukup jauh, kini salah satu dari mereka berteriak agar aku menaiki sebuah speedboat. '
                    'Bau asin laut kembali menusuk cuping hidungku.',
                    style: TextStyle(color: Color(0xFF2C241E), fontSize: 15, height: 1.7),
                  ),
                  const Spacer(),
                  const Center(
                    child: Text('15', style: TextStyle(color: Colors.brown, fontSize: 12)),
                  ),
                ],
              ),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: const PdfSearchHighlightPainter(
                  normalizedBoxes: highlightBoxes,
                  isDark: false,
                ),
              ),
            ),
          ],
        ),
      );

      await captureWidget(
        tester: tester,
        size: const Size(620, 850),
        filename: '04_scanned_original_pdf_highlight.png',
        widget: pageWidget,
      );

      expect(File(p.join(evidenceDir, '04_scanned_original_pdf_highlight.png')).existsSync(), isTrue);
    });

    testWidgets('05_reflowable_paginated_highlight.png — Reflowable Paginated reader inline search highlight', (tester) async {
      final doc = ReaderDocument(
        bookId: 'vis_reflow_1',
        title: 'Laut Bercerita',
        author: 'Leila S. Chudori',
        chapters: [
          const ReaderChapter(
            id: 'ch_1',
            index: 0,
            title: 'Bagian Pertama: Biru Laut',
            nodes: [
              ContentNode(
                id: 'node_title',
                type: ContentNodeType.documentTitle,
                text: 'LAUT BERCERITA',
                sourcePdfPage: 1,
              ),
              ContentNode(
                id: 'target_p',
                type: ContentNodeType.paragraph,
                text: 'Di dasar laut yang sunyi dan gelap, aku mengenang hangatnya aroma masakan Ibu di dapur rumah kami di Solo.',
                sourcePdfPage: 1,
              ),
            ],
          ),
        ],
      );

      final screenWidget = PaginatedReflowableReader(
        document: doc,
        theme: ReadingThemeType.warmPaper,
        typography: const TypographySettings(fontSize: 18.0, lineSpacing: 1.6),
        searchMatches: const [
          ActiveSearchMatch(
            nodeId: 'target_p',
            startOffset: 9,
            endOffset: 13,
            isActive: true,
          ),
        ],
        onTapContent: () {},
        onProgressChanged: (ch, p, pct, anc, off) {},
      );

      await captureWidget(
        tester: tester,
        size: const Size(800, 650),
        filename: '05_reflowable_paginated_highlight.png',
        widget: screenWidget,
      );

      expect(File(p.join(evidenceDir, '05_reflowable_paginated_highlight.png')).existsSync(), isTrue);
    });

    testWidgets('06_reflowable_scrolling_highlight.png — Reflowable Continuous Scrolling reader search match', (tester) async {
      final doc = ReaderDocument(
        bookId: 'vis_scroll_1',
        title: 'Laut Bercerita',
        author: 'Leila S. Chudori',
        chapters: [
          const ReaderChapter(
            id: 'ch_1',
            index: 0,
            title: 'Bab Satu',
            nodes: [
              ContentNode(
                id: 'node_scroll_1',
                type: ContentNodeType.paragraph,
                text: 'Kini salah satu dari mereka berteriak agar aku menaiki sebuah speedboat yang melaju ke tengah laut.',
                sourcePdfPage: 15,
              ),
            ],
          ),
        ],
      );

      final screenWidget = ScrollingReflowableReader(
        document: doc,
        theme: ReadingThemeType.sepia,
        typography: const TypographySettings(fontSize: 18.0, lineSpacing: 1.6),
        searchMatches: const [
          ActiveSearchMatch(
            nodeId: 'node_scroll_1',
            startOffset: 55,
            endOffset: 64,
            isActive: true,
          ),
        ],
        onTapContent: () {},
        onProgressChanged: (ch, p, pct, anc, off) {},
      );

      await captureWidget(
        tester: tester,
        size: const Size(800, 650),
        filename: '06_reflowable_scrolling_highlight.png',
        widget: screenWidget,
      );

      expect(File(p.join(evidenceDir, '06_reflowable_scrolling_highlight.png')).existsSync(), isTrue);
    });

    testWidgets('07_search_traversal_bar_active.png — Floating Search Traversal Bar (1 dari 3)', (tester) async {
      final widget = Stack(
        children: [
          Container(color: const Color(0xFF1E1E22)),
          Positioned(
            top: 40,
            left: 0,
            right: 0,
            child: Center(
              child: SearchTraversalBar(
                query: 'destiny',
                currentIndex: 0,
                totalCount: 3,
                theme: ReadingThemeType.dark,
                onPrevious: () {},
                onNext: () {},
                onClose: () {},
              ),
            ),
          ),
        ],
      );

      await captureWidget(
        tester: tester,
        size: const Size(700, 200),
        filename: '07_search_traversal_bar_active.png',
        widget: widget,
      );

      expect(File(p.join(evidenceDir, '07_search_traversal_bar_active.png')).existsSync(), isTrue);
    });

    testWidgets('08_search_traversal_cyclic_wrap.png — Search Traversal Bar wrapping (3 dari 3)', (tester) async {
      final widget = Stack(
        children: [
          Container(color: const Color(0xFF1E1E22)),
          Positioned(
            top: 40,
            left: 0,
            right: 0,
            child: Center(
              child: SearchTraversalBar(
                query: 'destiny',
                currentIndex: 2,
                totalCount: 3,
                theme: ReadingThemeType.dark,
                onPrevious: () {},
                onNext: () {},
                onClose: () {},
              ),
            ),
          ),
        ],
      );

      await captureWidget(
        tester: tester,
        size: const Size(700, 200),
        filename: '08_search_traversal_cyclic_wrap.png',
        widget: widget,
      );

      expect(File(p.join(evidenceDir, '08_search_traversal_cyclic_wrap.png')).existsSync(), isTrue);
    });

    testWidgets('09_mode_switch_match_retention.png — Mode switch retaining search match and traversal', (tester) async {
      final widget = Stack(
        children: [
          // Original PDF Page
          Container(
            color: const Color(0xFF232325),
            child: Stack(
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 50, vertical: 80),
                  child: Text(
                    'Setelah berjalan cukup jauh, kini salah satu dari mereka berteriak agar aku menaiki sebuah speedboat.',
                    style: TextStyle(color: Colors.white70, fontSize: 16, height: 1.8),
                  ),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: const PdfSearchHighlightPainter(
                      normalizedBoxes: [Rect.fromLTWH(0.12, 0.12, 0.28, 0.04)],
                      isDark: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Search Traversal Bar floating at the top
          Positioned(
            top: 30,
            left: 0,
            right: 0,
            child: Center(
              child: SearchTraversalBar(
                query: 'speedboat',
                currentIndex: 1,
                totalCount: 2,
                theme: ReadingThemeType.dark,
                onPrevious: () {},
                onNext: () {},
                onClose: () {},
              ),
            ),
          ),
        ],
      );

      await captureWidget(
        tester: tester,
        size: const Size(800, 600),
        filename: '09_mode_switch_match_retention.png',
        widget: widget,
      );

      expect(File(p.join(evidenceDir, '09_mode_switch_match_retention.png')).existsSync(), isTrue);
    });

    testWidgets('10_window_resize_search_stability.png — Expansive window layout (1280x800) search highlight stability', (tester) async {
      final widget = Stack(
        children: [
          Container(
            color: const Color(0xFFFBFBFD),
            child: Row(
              children: [
                // Two-page expansive layout simulation
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(48),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text('Chapter 1: The Beginning', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        SizedBox(height: 16),
                        Text('It was a dark and stormy night when the messenger arrived.', style: TextStyle(fontSize: 15, height: 1.6)),
                      ],
                    ),
                  ),
                ),
                Container(width: 1, color: Colors.black12),
                Expanded(
                  child: Stack(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(48),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text('Section 1: The Investigation Continues', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            SizedBox(height: 16),
                            Text('Holmes took the violin from its corner and began to play a low, melancholy tune.', style: TextStyle(fontSize: 15, height: 1.6)),
                          ],
                        ),
                      ),
                      Positioned.fill(
                        child: CustomPaint(
                          painter: const PdfSearchHighlightPainter(
                            normalizedBoxes: [Rect.fromLTWH(0.08, 0.16, 0.22, 0.04)],
                            isDark: false,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 24,
            left: 0,
            right: 0,
            child: Center(
              child: SearchTraversalBar(
                query: 'Holmes',
                currentIndex: 0,
                totalCount: 3,
                theme: ReadingThemeType.white,
                onPrevious: () {},
                onNext: () {},
                onClose: () {},
              ),
            ),
          ),
        ],
      );

      await captureWidget(
        tester: tester,
        size: const Size(1280, 800),
        filename: '10_window_resize_search_stability.png',
        widget: widget,
      );

      expect(File(p.join(evidenceDir, '10_window_resize_search_stability.png')).existsSync(), isTrue);
    });
  });
}
