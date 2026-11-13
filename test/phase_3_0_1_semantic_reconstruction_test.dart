import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' show PdfFontStyle;
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/core/theme/typography_settings.dart';
import 'package:digital_books/features/processing/models/extracted_page_geometry.dart';
import 'package:digital_books/features/processing/models/semantic_reconstruction_models.dart';
import 'package:digital_books/features/processing/services/paragraph_reconstructor.dart';
import 'package:digital_books/features/processing/services/reading_order_resolver.dart';
import 'package:digital_books/features/processing/services/semantic_classifier.dart';
import 'package:digital_books/features/processing/services/semantic_document_reconstructor.dart';
import 'package:digital_books/features/reader/domain/models/book_document.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable_book_reader.dart';
import 'package:digital_books/features/reader/services/book_text_normalizer.dart';

void main() {
  group('Phase 3.0.1 — Priority 2: Semantic Document Structure & Reading Quality', () {
    const pageWidth = 595.0;
    const pageHeight = 842.0;

    test(
      '1. Laut Bercerita scanned page reconstructs distinct paragraphs, strips chrome, preserves dialogue',
      () async {
        final ocrLines = [
          // Running Header (top of page)
          (text: '4', x: 0.13, y: 0.94, w: 0.02, h: 0.01),
          (text: 'LAUT BERCERITA', x: 0.43, y: 0.94, w: 0.13, h: 0.01),
          // Paragraph 1
          (
            text:
                'kaki telanjang sementara aku bisa mendengar suara ombak dari',
            x: 0.13,
            y: 0.86,
            w: 0.72,
            h: 0.02,
          ),
          (
            text:
                'bawah sana. Sepasang kaki ini hanya setengah berfungsi karena',
            x: 0.13,
            y: 0.84,
            w: 0.72,
            h: 0.02,
          ),
          (
            text:
                'selalu menjadi sasaran ditindas kaki meja atau ditendang hingga',
            x: 0.13,
            y: 0.81,
            w: 0.72,
            h: 0.02,
          ),
          (
            text:
                'retak. Si Perokok berteriak dengan suara parau agar aku berjalan',
            x: 0.13,
            y: 0.79,
            w: 0.72,
            h: 0.02,
          ),
          (text: 'dengan cepat.', x: 0.13, y: 0.76, w: 0.16, h: 0.02),
          // Paragraph 2 (indented x=0.18)
          (
            text: 'Perjalanan semakin menanjak. Rasanya kami menaiki sebuah',
            x: 0.18,
            y: 0.70,
            w: 0.67,
            h: 0.02,
          ),
          (
            text:
                'bukit karang yang tak terlalu tinggi. Aku masih bisa mendengar',
            x: 0.13,
            y: 0.67,
            w: 0.72,
            h: 0.02,
          ),
          (
            text: 'bunyi ombak yang datang dan pergi.',
            x: 0.13,
            y: 0.64,
            w: 0.42,
            h: 0.02,
          ),
          // Dialogue (separate line, indented)
          (
            text: '"Matilah engkau mati..."',
            x: 0.18,
            y: 0.58,
            w: 0.25,
            h: 0.02,
          ),
          (
            text: 'Kini mereka mengikat tanganku dengan besi pemberat.',
            x: 0.18,
            y: 0.52,
            w: 0.68,
            h: 0.02,
          ),
        ];

        var lineIdx = 0;
        final textLines = ocrLines.map((item) {
          final top = (1.0 - (item.y + item.h)) * pageHeight;
          final left = item.x * pageWidth;
          final width = item.w * pageWidth;
          final height = item.h * pageHeight;
          return ExtractedTextLine(
            bounds: Rect.fromLTWH(left, top, width, height),
            text: item.text,
            fontSize: 11.0,
            fontName: 'VisionOCR',
            lineIndex: lineIdx++,
            pageIndex: 14,
          );
        }).toList();

        final page = ExtractedPageGeometry(
          pageIndex: 14,
          pageSize: const Size(pageWidth, pageHeight),
          lines: textLines,
          images: const [],
          layerType: PageLayerType.nativeText,
          charCount: textLines.fold<int>(0, (sum, l) => sum + l.text.length),
        );

        final resolved = ReadingOrderResolver.resolvePage(page);
        final paragraphs = ParagraphReconstructor.reconstructPage(resolved);

        // Verify paragraphs are NOT collapsed into a single block
        expect(paragraphs.length, greaterThanOrEqualTo(3));

        final blocks = SemanticClassifier.classifyDocument(
          paragraphs: paragraphs,
          totalPages: 1,
          defaultPageHeight: pageHeight,
        );

        // Running header classified appropriately
        final headerBlock = blocks.where(
          (b) => b.type == SemanticBlockType.runningHeader,
        );
        expect(headerBlock, isNotEmpty);

        // Paragraphs retain distinct narrative units
        final bodyBlocks = blocks
            .where(
              (b) =>
                  b.type == SemanticBlockType.bodyParagraph ||
                  b.type == SemanticBlockType.quote,
            )
            .toList();
        expect(bodyBlocks.length, greaterThanOrEqualTo(2));

        final p1 = bodyBlocks.first.text;
        expect(p1, contains('kaki telanjang sementara aku bisa mendengar'));
        expect(p1, contains('dengan cepat.'));
        // Paragraph 1 does not spill into Paragraph 2
        expect(p1.contains('Perjalanan semakin menanjak'), isFalse);

        final p2 = bodyBlocks[1].text;
        expect(p2, contains('Perjalanan semakin menanjak'));
      },
    );

    test(
      '2. Bicara Itu Ada Seninya maintains 100% character fidelity and detects section headings',
      () async {
        final inputLines = [
          (text: 'BAB 2: CARA MENARIK PERHATIAN PENDENGAR', isHeading: true),
          (
            text:
                'Ketika berbicara di depan banyak orang, ada tiga hal utama yang harus Anda perhatikan.',
            isHeading: false,
          ),
          (
            text:
                'Hal pertama adalah kontak mata yang meyakinkan tanpa membuat gugup lawan bicara.',
            isHeading: false,
          ),
        ];

        var idx = 0;
        final lines = inputLines.map((item) {
          return ExtractedTextLine(
            bounds: Rect.fromLTWH(50, 100.0 + (idx * 30), 400, 20),
            text: item.text,
            fontSize: item.isHeading ? 16.0 : 11.0,
            fontStyle: item.isHeading ? [PdfFontStyle.bold] : const [],
            fontName: 'SerifFont',
            lineIndex: idx++,
            pageIndex: 0,
          );
        }).toList();

        final page = ExtractedPageGeometry(
          pageIndex: 0,
          pageSize: const Size(pageWidth, pageHeight),
          lines: lines,
          images: const [],
          layerType: PageLayerType.nativeText,
          charCount: lines.fold<int>(0, (sum, l) => sum + l.text.length),
        );

        final extraction = DocumentExtractionResult(
          bookId: 'bicara-itu-ada-seninya',
          totalPages: 1,
          pages: [page],
          totalTextLines: lines.length,
          totalImages: 0,
          layerBreakdown: {PageLayerType.nativeText: 1},
          hasUsableTextLayer: true,
          warnings: const [],
          durationMs: 120.0,
        );

        final doc = await SemanticDocumentReconstructor.reconstruct(
          extraction: extraction,
          title: 'Bicara Itu Ada Seninya',
          author: 'Oh Su Hyang',
        );

        final bookDoc = doc.toBookDocument();
        expect(bookDoc.chapters, isNotEmpty);

        // Verify Chapter Heading is classified as heading
        final allBlocks = bookDoc.chapters.expand((c) => c.blocks).toList();
        final heading = allBlocks.firstWhere(
          (b) => b.type == BlockType.heading,
        );
        expect(
          heading.text,
          contains('BAB 2: CARA MENARIK PERHATIAN PENDENGAR'),
        );

        // Character accuracy check: all input words present without loss
        final combinedText = allBlocks.map((b) => b.text).join(' ');
        for (final l in inputLines) {
          expect(
            combinedText.contains(l.text),
            isTrue,
            reason: 'Lost text: ${l.text}',
          );
        }
      },
    );

    test(
      '3. Ordered and unordered lists preserve numbering, bullets, and separate block identity',
      () {
        final rawDoc = BookDocument(
          id: 'list_test_doc',
          title: 'Metode Berpikir Kritis',
          author: 'Penulis Cerdas',
          totalPages: 1,
          chapters: [
            BookChapter(
              id: 'ch0',
              index: 0,
              title: 'Langkah Metodologis',
              blocks: [
                const BookBlock(
                  id: 'b1',
                  type: BlockType.paragraph,
                  text:
                      'Berikut adalah prinsip berpikir rasional:\n'
                      '1. Definisikan masalah secara objektif dan terukur.\n'
                      '2. Kumpulkan bukti empiris dari sumber primer.\n'
                      '3. Lakukan pengujian hipotesis tanpa bias konfirmasi.\n'
                      'Langkah di atas didukung oleh poin-poin pendukung:\n'
                      '• Catat setiap anomali yang ditemukan di lapangan.\n'
                      '• Diskusikan temuan dengan rekan sejawat.',
                ),
              ],
            ),
          ],
        );

        final normDoc = BookTextNormalizer.normalizeDocument(rawDoc);
        final blocks = normDoc.chapters.expand((c) => c.blocks).toList();

        // Verify ordered list items are split into distinct orderedList blocks
        final orderedBlocks = blocks
            .where((b) => b.type == BlockType.orderedList)
            .toList();
        expect(orderedBlocks.length, equals(3));
        expect(orderedBlocks[0].text, startsWith('1.'));
        expect(orderedBlocks[1].text, startsWith('2.'));
        expect(orderedBlocks[2].text, startsWith('3.'));

        // Verify unordered list items are split into distinct unorderedList blocks
        final unorderedBlocks = blocks
            .where((b) => b.type == BlockType.unorderedList)
            .toList();
        expect(unorderedBlocks.length, equals(2));
        expect(unorderedBlocks[0].text, startsWith('•'));
        expect(unorderedBlocks[1].text, startsWith('•'));

        // Verify lead-in paragraph remains a paragraph block
        final paraBlocks = blocks
            .where((b) => b.type == BlockType.paragraph)
            .toList();
        expect(
          paraBlocks.any((b) => b.text.contains('Berikut adalah prinsip')),
          isTrue,
        );
      },
    );

    test(
      '4. Copyright, ISBN, and Publisher imprint are isolated from body narrative',
      () {
        final rawDoc = BookDocument(
          id: 'copyright_test_doc',
          title: 'Buku Hebat',
          author: 'Penerbit Utama',
          totalPages: 1,
          chapters: [
            BookChapter(
              id: 'ch0',
              index: 0,
              title: 'Halaman Hak Cipta',
              blocks: [
                const BookBlock(
                  id: 'b1',
                  type: BlockType.paragraph,
                  text:
                      'Hak Cipta Dilindungi Undang-Undang\n'
                      'Dilarang mengutip atau memperbanyak tanpa izin tertulis penerbit.\n'
                      'Katalog Dalam Terbitan (KDT)\n'
                      'ISBN 978-602-03-8591-4\n'
                      'Diterbitkan oleh PT Gramedia Pustaka Utama\n'
                      'Cetakan Pertama: Oktober 2017\n'
                      'Kisah ini berawal di sebuah desa nelayan kecil di pesisir utara Jawa.',
                ),
              ],
            ),
          ],
        );

        final normDoc = BookTextNormalizer.normalizeDocument(rawDoc);
        final blocks = normDoc.chapters.expand((c) => c.blocks).toList();

        // Must have at least one copyrightBlock
        final copyrightBlocks = blocks
            .where((b) => b.type == BlockType.copyrightBlock)
            .toList();
        expect(copyrightBlocks, isNotEmpty);

        final copyrightText = copyrightBlocks.map((b) => b.text).join('\n');
        expect(copyrightText, contains('Hak Cipta Dilindungi Undang-Undang'));
        expect(copyrightText, contains('ISBN 978-602-03-8591-4'));

        // Narrative opening MUST NOT be inside copyright block
        expect(
          copyrightText.contains('Kisah ini berawal di sebuah desa nelayan'),
          isFalse,
        );

        final narrativeBlock = blocks.firstWhere(
          (b) => b.type == BlockType.paragraph,
        );
        expect(
          narrativeBlock.text,
          contains('Kisah ini berawal di sebuah desa nelayan'),
        );
      },
    );

    test(
      '5. Academic Two-Column layout maintains vertical column reading order before right column',
      () {
        // Column 1 (left=50, width=220)
        final col1Lines = [
          (text: '1. PENDAHULUAN', y: 100.0, isBold: true),
          (
            text: 'Penelitian ini meneliti pengaruh visualisasi data',
            y: 125.0,
            isBold: false,
          ),
          (
            text: 'terhadap efisiensi kognitif pengguna saat membaca.',
            y: 145.0,
            isBold: false,
          ),
        ];

        // Column 2 (left=310, width=220)
        final col2Lines = [
          (text: '2. METODOLOGI PENELITIAN', y: 100.0, isBold: true),
          (
            text: 'Sebanyak lima puluh responden diuji secara acak',
            y: 125.0,
            isBold: false,
          ),
          (
            text: 'dengan metode double-blind controlled trial.',
            y: 145.0,
            isBold: false,
          ),
        ];

        var lineIdx = 0;
        final lines = <ExtractedTextLine>[];

        for (final item in col1Lines) {
          lines.add(
            ExtractedTextLine(
              bounds: Rect.fromLTWH(50, item.y, 220, 18),
              text: item.text,
              fontSize: item.isBold ? 13.0 : 10.5,
              fontStyle: item.isBold ? [PdfFontStyle.bold] : const [],
              fontName: 'Times',
              lineIndex: lineIdx++,
              pageIndex: 0,
            ),
          );
        }

        for (final item in col2Lines) {
          lines.add(
            ExtractedTextLine(
              bounds: Rect.fromLTWH(310, item.y, 220, 18),
              text: item.text,
              fontSize: item.isBold ? 13.0 : 10.5,
              fontStyle: item.isBold ? [PdfFontStyle.bold] : const [],
              fontName: 'Times',
              lineIndex: lineIdx++,
              pageIndex: 0,
            ),
          );
        }

        final page = ExtractedPageGeometry(
          pageIndex: 0,
          pageSize: const Size(pageWidth, pageHeight),
          lines: lines,
          images: const [],
          layerType: PageLayerType.nativeText,
          charCount: lines.fold<int>(0, (sum, l) => sum + l.text.length),
        );

        final resolved = ReadingOrderResolver.resolvePage(page);
        expect(resolved.layoutStructure, equals(PageLayoutStructure.twoColumn));

        // Assert Column 1 lines come strictly before Column 2 lines
        final texts = resolved.orderedLines.map((l) => l.text).toList();
        final idxCol1Last = texts.indexOf(
          'terhadap efisiensi kognitif pengguna saat membaca.',
        );
        final idxCol2First = texts.indexOf('2. METODOLOGI PENELITIAN');

        expect(
          idxCol1Last,
          lessThan(idxCol2First),
          reason: 'Column 1 must be completely read before Column 2 commences!',
        );
      },
    );

    test(
      '6. Captions and footnotes are categorized into dedicated semantic blocks',
      () {
        final rawDoc = BookDocument(
          id: 'caption_footnote_doc',
          title: 'Buku Sains Terapan',
          author: 'Dr. Ilmiah',
          totalPages: 1,
          chapters: [
            BookChapter(
              id: 'ch0',
              index: 0,
              title: 'Anatomi Sel',
              blocks: [
                const BookBlock(
                  id: 'b1',
                  type: BlockType.paragraph,
                  text:
                      'Gambar 1.3: Struktur mitokondria pada sel eukariotik.\n'
                      'Mitokondria merupakan organel sel penghasil energi utama dalam bentuk ATP.\n'
                      'Tabel 2.1: Perbandingan laju respirasi seluler pada berbagai jaringan.',
                ),
              ],
            ),
          ],
        );

        final normDoc = BookTextNormalizer.normalizeDocument(rawDoc);
        final blocks = normDoc.chapters.expand((c) => c.blocks).toList();

        final captions = blocks
            .where((b) => b.type == BlockType.caption)
            .toList();
        expect(captions.length, greaterThanOrEqualTo(2));
        expect(captions.any((c) => c.text.contains('Gambar 1.3')), isTrue);
        expect(captions.any((c) => c.text.contains('Tabel 2.1')), isTrue);

        final body = blocks.firstWhere((b) => b.type == BlockType.paragraph);
        expect(body.text, contains('Mitokondria merupakan organel sel'));
      },
    );

    testWidgets(
      '7. ReflowableBookReader renders semantic blocks (OrderedList, UnorderedList, Copyright, Headings) with dedicated UI',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final semanticDoc = BookDocument(
          id: 'rich_semantic_doc',
          title: 'Panduan Eksekutif',
          author: 'Direktur Utama',
          totalPages: 2,
          metadata: {'reconstructionQuality': 'high'},
          chapters: [
            BookChapter(
              id: 'ch0',
              index: 0,
              title: 'Pendahuluan',
              blocks: [
                const BookBlock(
                  id: 'b_title',
                  type: BlockType.documentTitle,
                  text: 'PANDUAN EKSEKUTIF KEPEMIMPINAN',
                ),
                const BookBlock(
                  id: 'b_sec',
                  type: BlockType.sectionHeading,
                  text: 'Prinsip Dasar Integritas',
                ),
                const BookBlock(
                  id: 'b_ord1',
                  type: BlockType.orderedList,
                  text: '1. Bertindak jujur dalam setiap keputusan bisnis.',
                ),
                const BookBlock(
                  id: 'b_ord2',
                  type: BlockType.orderedList,
                  text: '2. Melindungi kerahasiaan data pemangku kepentingan.',
                ),
                const BookBlock(
                  id: 'b_unord',
                  type: BlockType.unorderedList,
                  text:
                      '• Utamakan kesejahteraan tim di atas kepentingan pribadi.',
                ),
                const BookBlock(
                  id: 'b_copy',
                  type: BlockType.copyrightBlock,
                  text:
                      'Hak Cipta Dilindungi Undang-Undang. ISBN 978-0-123456-78-9.',
                ),
                const BookBlock(
                  id: 'b_cap',
                  type: BlockType.caption,
                  text: 'Gambar 1: Matriks Kepemimpinan Situasional.',
                ),
                const BookBlock(
                  id: 'b_foot',
                  type: BlockType.footnote,
                  text:
                      '(1) Diadaptasi dari studi manajemen kontemporer tahun 2024.',
                ),
              ],
            ),
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ReflowableBookReader(
                document: semanticDoc,
                theme: ReadingThemeType.warmPaper,
                typography: const TypographySettings(),
                initialChapterIndex: 0,
                initialPosition: 1,
                onProgressChanged: (ch, p, pct) {},
                onTapContent: () {},
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Verify no rendering overflow exceptions
        expect(tester.takeException(), isNull);

        // Verify Document Title is present
        expect(find.text('PANDUAN EKSEKUTIF KEPEMIMPINAN'), findsOneWidget);

        // Verify Section Heading is present
        expect(find.text('Prinsip Dasar Integritas'), findsOneWidget);

        // Verify List badges / markers
        expect(find.text('1.'), findsOneWidget);
        expect(find.text('2.'), findsOneWidget);
        expect(
          find.text('Bertindak jujur dalam setiap keputusan bisnis.'),
          findsOneWidget,
        );
        expect(
          find.text('Melindungi kerahasiaan data pemangku kepentingan.'),
          findsOneWidget,
        );

        // Verify Copyright banner text
        expect(find.text('INFORMASI PENERBITAN & HAK CIPTA'), findsOneWidget);
        expect(
          find.text(
            'Hak Cipta Dilindungi Undang-Undang. ISBN 978-0-123456-78-9.',
          ),
          findsOneWidget,
        );

        // Verify Caption
        expect(
          find.text('Gambar 1: Matriks Kepemimpinan Situasional.'),
          findsOneWidget,
        );

        // Verify Footnote
        expect(
          find.text(
            '(1) Diadaptasi dari studi manajemen kontemporer tahun 2024.',
          ),
          findsOneWidget,
        );
      },
    );
  });
}
