import 'dart:ui' show Rect, Size;
import 'package:flutter_test/flutter_test.dart';

import 'package:digital_books/features/processing/models/extracted_page_geometry.dart';
import 'package:digital_books/features/processing/services/reading_order_resolver.dart';
import 'package:digital_books/features/processing/services/paragraph_reconstructor.dart';
import 'package:digital_books/features/processing/services/semantic_classifier.dart';
import 'package:digital_books/features/processing/services/semantic_document_reconstructor.dart';

void main() {
  group('Phase 3.0: Scanned PDF Intelligence — OCR Reconstruction Spike', () {
    test(
      '1. Vision OCR lines from real scanned page (Laut Bercerita) reconstruct into clean paragraphs',
      () async {
        const pageWidth = 595.0;
        const pageHeight = 842.0;

        // Realistic OCR output from Laut Bercerita Page 15
        final ocrItems = [
          // Running Header (top of page)
          (text: '4', x: 0.13, y: 0.94, w: 0.02, h: 0.01),
          (text: 'LAUT BERCERITA', x: 0.43, y: 0.94, w: 0.13, h: 0.01),
          // Paragraph 1 continuation
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
            y: 0.73,
            w: 0.67,
            h: 0.02,
          ),
          (
            text:
                'bukit karang yang tak terlalu tinggi. Aku masih bisa mendengar',
            x: 0.13,
            y: 0.70,
            w: 0.72,
            h: 0.02,
          ),
          (
            text: 'bunyi ombak yang datang dan pergi.',
            x: 0.13,
            y: 0.67,
            w: 0.42,
            h: 0.02,
          ),
          // Dialogue
          (
            text: '"Matilah engkau mati..."',
            x: 0.18,
            y: 0.35,
            w: 0.25,
            h: 0.02,
          ),
          (
            text: 'Kini mereka mengikat tanganku dengan besi pemberat.',
            x: 0.18,
            y: 0.32,
            w: 0.68,
            h: 0.02,
          ),
        ];

        var lineIdx = 0;
        final textLines = ocrItems.map((item) {
          final top = (1.0 - (item.y + item.h)) * pageHeight;
          final left = item.x * pageWidth;
          final width = item.w * pageWidth;
          final height = item.h * pageHeight;
          return ExtractedTextLine(
            bounds: Rect.fromLTWH(left, top, width, height),
            text: item.text,
            fontSize: 11.0,
            fontName: 'AppleVisionOCR',
            lineIndex: lineIdx++,
            pageIndex: 14,
          );
        }).toList();

        final pageGeometry = ExtractedPageGeometry(
          pageIndex: 14,
          pageSize: const Size(pageWidth, pageHeight),
          lines: textLines,
          images: const [],
          layerType: PageLayerType.nativeText,
          charCount: textLines.fold(0, (sum, l) => sum + l.text.length),
        );

        // Execute downstream reading order & paragraph reconstruction
        final resolved = ReadingOrderResolver.resolvePage(pageGeometry);
        expect(resolved.orderedLines, isNotEmpty);

        final paragraphs = ParagraphReconstructor.reconstructPage(resolved);
        expect(paragraphs.length, greaterThanOrEqualTo(2));

        // Classify semantic elements
        final blocks = SemanticClassifier.classifyDocument(
          paragraphs: paragraphs,
          totalPages: 1,
          defaultPageHeight: pageHeight,
        );
        expect(blocks, isNotEmpty);

        final allText = blocks.map((b) => b.text).join(' ');
        expect(
          allText,
          contains('kaki telanjang sementara aku bisa mendengar suara ombak'),
        );
        expect(allText, contains('Perjalanan semakin menanjak'));
        expect(allText, contains('Matilah engkau mati'));
      },
    );

    test(
      '2. Bicara Itu Ada Seninya (Page 33) reconstructed document verifies zero text loss',
      () async {
        const pageWidth = 595.0;
        const pageHeight = 842.0;

        final p33Items = [
          (
            text: 'selamanya. Lelaki tadi kemudian pulang ke kampung halaman',
            x: 0.15,
            y: 0.85,
            w: 0.70,
            h: 0.02,
          ),
          (
            text:
                'dan membuat roti bagel setiap kali merindukan istrinya. Setelah',
            x: 0.15,
            y: 0.82,
            w: 0.70,
            h: 0.02,
          ),
          (
            text:
                'itu, roti bagel menjadi terkenal ke seluruh dunia karena cerita',
            x: 0.15,
            y: 0.79,
            w: 0.70,
            h: 0.02,
          ),
          (text: 'ini.', x: 0.15, y: 0.76, w: 0.05, h: 0.02),
          (
            text: 'Sayangnya kisah roti bagel ini adalah rekaan. Namun karena',
            x: 0.18,
            y: 0.72,
            w: 0.67,
            h: 0.02,
          ),
          (
            text:
                'storytelling-nya begitu kuat, publik sudah tidak peduli lagi',
            x: 0.15,
            y: 0.69,
            w: 0.70,
            h: 0.02,
          ),
          (text: 'tentang keasliannya.', x: 0.15, y: 0.66, w: 0.25, h: 0.02),
        ];

        var lineIdx = 0;
        final lines = p33Items.map((item) {
          final top = (1.0 - (item.y + item.h)) * pageHeight;
          final left = item.x * pageWidth;
          final width = item.w * pageWidth;
          final height = item.h * pageHeight;
          return ExtractedTextLine(
            bounds: Rect.fromLTWH(left, top, width, height),
            text: item.text,
            fontSize: 11.5,
            fontName: 'AppleVisionOCR',
            lineIndex: lineIdx++,
            pageIndex: 32,
          );
        }).toList();

        final page = ExtractedPageGeometry(
          pageIndex: 32,
          pageSize: const Size(pageWidth, pageHeight),
          lines: lines,
          images: const [],
          layerType: PageLayerType.nativeText,
          charCount: lines.fold(0, (sum, l) => sum + l.text.length),
        );

        final extraction = DocumentExtractionResult(
          bookId: 'test-bicara-itu-ada-seninya',
          totalPages: 1,
          pages: [page],
          totalTextLines: lines.length,
          totalImages: 0,
          layerBreakdown: {PageLayerType.nativeText: 1},
          hasUsableTextLayer: true,
          warnings: const [],
          durationMs: 250.0,
        );

        final reconstructed = await SemanticDocumentReconstructor.reconstruct(
          extraction: extraction,
          title: 'Bicara Itu Ada Seninya',
          author: 'Oh Su Hyang',
        );

        final bookDoc = reconstructed.toBookDocument();
        expect(bookDoc.chapters, isNotEmpty);
        final fullText = bookDoc.chapters.first.blocks
            .map((b) => b.text)
            .join(' ');
        expect(fullText, contains('roti bagel'));
        expect(fullText, contains('storytelling-nya begitu kuat'));
      },
    );
  });
}
