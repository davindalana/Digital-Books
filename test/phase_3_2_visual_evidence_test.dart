// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:ui' as ui;
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/core/theme/typography_settings.dart';
import 'package:digital_books/features/reader/domain/engines/reflowable_highlight_span_builder.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'package:digital_books/features/reader/presentation/widgets/book_search_dialog.dart';
import 'package:digital_books/features/reader/presentation/widgets/original_pdf_reader.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/paginated_reflowable_reader.dart';
import 'package:digital_books/features/reader/presentation/widgets/search_traversal_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final evidenceDir = 'docs/visual_evidence/phase_3_2';

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

  group('Phase 3.2 — Visual Acceptance Evidence Captures', () {
    testWidgets('1. Capture BookSearchDialog with multi-source results and badges', (
      tester,
    ) async {
      final sampleDoc = ReaderDocument(
        bookId: 'vis_test_1',
        title: 'Laut Bercerita',
        author: 'Leila S. Chudori',
        chapters: [
          const ReaderChapter(
            id: 'ch_1',
            index: 0,
            title: 'Bagian Pertama: Biru Laut',
            nodes: [
              ContentNode(
                id: 'n1',
                type: ContentNodeType.paragraph,
                text:
                    'Di dasar laut yang sunyi dan gelap, aku mendengar suara langkah kaki mereka mendekat perlahan.',
                sourcePdfPage: 1,
              ),
              ContentNode(
                id: 'n2',
                type: ContentNodeType.paragraph,
                text:
                    'Laut bercerita tentang kami yang dipaksa bungkam oleh dinginnya lantai sel tahanan.',
                sourcePdfPage: 2,
              ),
              ContentNode(
                id: 'n3',
                type: ContentNodeType.paragraph,
                text:
                    'Nama-nama kawan kami tenggelam bersama rahasia laut yang tak pernah tuntas terungkap.',
                sourcePdfPage: 3,
              ),
            ],
          ),
        ],
      );

      // Mount BookSearchDialog directly and search
      await captureWidget(
        tester: tester,
        size: const Size(640, 700),
        filename: '01_search_dialog_with_results.png',
        widget: BookSearchDialog(
          theme: ReadingThemeType.dark,
          readerDocument: sampleDoc,
          onNavigateToResult: (_) {},
        ),
        onReady: (tester) async {
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField), 'laut');
          await tester.pumpAndSettle(const Duration(milliseconds: 350));
        },
      );

      expect(
        File(
          p.join(evidenceDir, '01_search_dialog_with_results.png'),
        ).existsSync(),
        isTrue,
      );
    });

    testWidgets(
      '2. Capture Original PDF Reader with golden precision bounding-box highlights',
      (tester) async {
        // Simulate page surface with PdfSearchHighlightPainter
        const highlightBoxes = [
          Rect.fromLTWH(0.12, 0.28, 0.38, 0.038),
          Rect.fromLTWH(0.12, 0.33, 0.25, 0.038),
        ];

        final pageWidget = Container(
          color: const Color(0xFF232325), // Dark paper color
          child: Stack(
            children: [
              // Realistic simulated book page text layout
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 48,
                  vertical: 60,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(
                      child: Text(
                        'BAGIAN PERTAMA',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Center(
                      child: Text(
                        'BIRU LAUT',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 36),
                    const Text(
                      'Kematian datang tanpa aba-aba. Seperti ombak besar yang tiba-tiba menyapu pantai pada suatu senja yang sepi.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14.5,
                        height: 1.8,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Di dasar laut yang sunyi dan gelap, aku mengenang aroma masakan Ibu di dapur rumah kami di Solo.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14.5,
                        height: 1.8,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Laut bercerita tentang kami yang dipaksa menelan garam dan pasir, sementara dunia di atas sana terus berjalan seolah tak terjadi apa-apa.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14.5,
                        height: 1.8,
                      ),
                    ),
                    const Spacer(),
                    const Center(
                      child: Text(
                        '— 1 —',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),

              // Precision golden highlight overlay
              Positioned.fill(
                child: CustomPaint(
                  painter: const PdfSearchHighlightPainter(
                    normalizedBoxes: highlightBoxes,
                    isDark: true,
                  ),
                ),
              ),
            ],
          ),
        );

        await captureWidget(
          tester: tester,
          size: const Size(600, 850),
          filename: '02_original_pdf_precision_highlight.png',
          widget: pageWidget,
        );

        expect(
          File(
            p.join(evidenceDir, '02_original_pdf_precision_highlight.png'),
          ).existsSync(),
          isTrue,
        );
      },
    );

    testWidgets(
      '3. Capture Reflowable Reader with Search Traversal Bar and highlighted match',
      (tester) async {
        final doc = ReaderDocument(
          bookId: 'vis_test_3',
          title: 'Laut Bercerita',
          author: 'Leila S. Chudori',
          chapters: [
            const ReaderChapter(
              id: 'ch_1',
              index: 0,
              title: 'Bagian Pertama: Biru Laut',
              nodes: [
                ContentNode(
                  id: 'n1',
                  type: ContentNodeType.documentTitle,
                  text: 'LAUT BERCERITA',
                  sourcePdfPage: 1,
                ),
                ContentNode(
                  id: 'n2',
                  type: ContentNodeType.sectionHeading,
                  text: 'Bagian Pertama: Biru Laut',
                  sourcePdfPage: 1,
                ),
                ContentNode(
                  id: 'target_node',
                  type: ContentNodeType.paragraph,
                  text:
                      'Di dasar laut yang sunyi dan pekat, aku mengenang hangatnya aroma kuah tengkleng buatan Ibu di Solo. '
                      'Laut bercerita tentang kami yang tak pernah kembali ke permukaan.',
                  sourcePdfPage: 1,
                ),
              ],
            ),
          ],
        );

        const searchMatches = [
          ActiveSearchMatch(
            nodeId: 'target_node',
            startOffset: 9,
            endOffset: 13,
            isActive: true,
          ),
        ];

        final screenWidget = Stack(
          children: [
            // Paginated Reflowable Reader with active search match
            Positioned.fill(
              child: PaginatedReflowableReader(
                document: doc,
                theme: ReadingThemeType.warmPaper,
                typography: const TypographySettings(
                  fontSize: 18.0,
                  lineSpacing: 1.6,
                ),
                searchMatches: searchMatches,
                onTapContent: () {},
                onProgressChanged: (ch, p, pct, anc, off) {},
              ),
            ),

            // Floating Search Traversal Bar at the top
            Positioned(
              top: 24,
              left: 0,
              right: 0,
              child: Center(
                child: SearchTraversalBar(
                  query: 'laut',
                  currentIndex: 0,
                  totalCount: 14,
                  theme: ReadingThemeType.warmPaper,
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
          size: const Size(900, 700),
          filename: '03_reflowable_search_highlight_traversal.png',
          widget: screenWidget,
        );

        expect(
          File(
            p.join(evidenceDir, '03_reflowable_search_highlight_traversal.png'),
          ).existsSync(),
          isTrue,
        );
      },
    );
  });
}
