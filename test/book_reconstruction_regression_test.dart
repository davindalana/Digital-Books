import 'dart:io';
import 'dart:ui' show Size;
import 'package:flutter_test/flutter_test.dart';

import 'package:digital_books/features/processing/models/extracted_page_geometry.dart';
import 'package:digital_books/features/reader/models/book_document.dart';
import 'package:digital_books/features/processing/services/apple_vision_ocr_service.dart';
import 'package:digital_books/features/processing/services/paragraph_reconstructor.dart';
import 'package:digital_books/features/processing/services/reading_order_resolver.dart';
import 'package:digital_books/features/processing/services/semantic_classifier.dart';
import 'package:digital_books/features/processing/services/semantic_document_reconstructor.dart';

void main() {
  test(
    'End-to-End Book Reconstruction Regression Test on Bicara Itu Ada Seninya',
    () async {
      const bookId = '447899e1-0e78-4658-ad3d-e5efaa92c46e';
      const imagesDirPath =
          '/Users/davindalana/Documents/DigitalBooks/images/$bookId';
      final imagesDir = Directory(imagesDirPath);
      if (!imagesDir.existsSync()) {
        markTestSkipped(
          'Local OCR test images are missing at ${imagesDir.path}',
        );
        return;
      }

      final ocrService = const AppleVisionOcrService();
      final pagesToTest = [
        0,
        1,
        2,
        3,
        4,
        6,
        8,
        12,
        18,
        19,
        20,
        21,
        25,
        60,
        61,
        62,
        114,
        115,
        116,
        153,
        154,
        155,
        209,
        210,
        211,
      ];

      final extractedPages = <ExtractedPageGeometry>[];
      for (final pIdx in pagesToTest) {
        final files = imagesDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.contains('p${pIdx}_Image-'))
            .toList();
        if (files.isEmpty) continue;
        final ocrRes = await ocrService.processImage(
          files.first.path,
          accurate: false,
        );
        final geom = ocrRes.toExtractedPageGeometry(
          pageIndex: pIdx,
          pageSize: Size(
            ocrRes.width > 0 ? ocrRes.width.toDouble() : 1279,
            ocrRes.height > 0 ? ocrRes.height.toDouble() : 1920,
          ),
        );
        extractedPages.add(geom);
      }

      final docExtraction = DocumentExtractionResult(
        bookId: bookId,
        totalPages: extractedPages.length,
        pages: extractedPages,
        totalTextLines: extractedPages.fold(
          0,
          (sum, p) => sum + p.lines.length,
        ),
        totalImages: 0,
        layerBreakdown: {PageLayerType.nativeText: extractedPages.length},
        hasUsableTextLayer: true,
        warnings: const [],
        durationMs: 0,
      );

      final readingOrders = ReadingOrderResolver.resolveDocument(docExtraction);
      final paragraphs = ParagraphReconstructor.reconstructDocument(
        readingOrders,
      );
      final classified = SemanticClassifier.classifyDocument(
        paragraphs: paragraphs,
        totalPages: extractedPages.length,
      );

      expect(classified.isNotEmpty, isTrue);

      final reconstructed = await SemanticDocumentReconstructor.reconstruct(
        extraction: docExtraction,
        title: 'Bicara Itu Ada Seninya',
        author: 'Oh Su Hyang',
      );

      // Verify Chapter Structure
      expect(reconstructed.chapters.length, greaterThanOrEqualTo(5));

      final titles = reconstructed.chapters.map((c) => c.title).toList();
      expect(titles.any((t) => t.contains('Bagian Awal')), isTrue);
      expect(titles.any((t) => t.toUpperCase().contains('BAB I')), isTrue);
      expect(titles.any((t) => t.toUpperCase().contains('BAB II')), isTrue);

      // Verify Cover Page Exclusion: Page 0 cover image must not be inside chapter body
      for (final ch in reconstructed.chapters) {
        for (final block in ch.blocks) {
          if (block.type == BlockType.image) {
            expect(block.metadata['isCover'], isNot(true));
          }
        }
      }
    },
  );
}
