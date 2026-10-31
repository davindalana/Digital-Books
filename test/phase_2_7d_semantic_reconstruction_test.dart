// ignore_for_file: avoid_print

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_books/features/processing/models/semantic_reconstruction_models.dart';
import 'package:digital_books/features/processing/services/geometry_aware_pdf_extractor.dart';
import 'package:digital_books/features/processing/services/reading_order_resolver.dart';
import 'package:digital_books/features/processing/services/paragraph_reconstructor.dart';
import 'package:digital_books/features/processing/services/semantic_classifier.dart';
import 'package:digital_books/features/processing/services/image_placement_resolver.dart';
import 'package:digital_books/features/processing/services/semantic_document_reconstructor.dart';

void main() {
  const corpusDir = 'test/fixtures/corpus';

  group('Phase 2.7D1: Reading Order Reconstruction', () {
    test('resolves two-column academic reading order correctly without interleaving', () async {
      final file = File('$corpusDir/04_two_column_academic.pdf');
      expect(file.existsSync(), isTrue);

      final extraction = await GeometryAwarePdfExtractor.extractDocument(
        pdfFile: file,
        bookId: 'test-academic-04',
      );
      expect(extraction.pages.isNotEmpty, isTrue);

      final resolved = ReadingOrderResolver.resolvePage(extraction.pages.first);
      expect(resolved.layoutStructure, equals(PageLayoutStructure.twoColumn));
      expect(resolved.detectedGutterWidth, isNotNull);
      expect(resolved.detectedGutterWidth!, greaterThanOrEqualTo(14.0));
      expect(resolved.columnConfidence, greaterThan(0.8));

      // Line 0 MUST be the full-width title
      expect(
        resolved.orderedLines.first.text,
        contains('A Comparative Study of Document Layout Models'),
      );

      // Verify column sequence:
      // All lines from Column 1 (Abstract, Introduction) must precede lines from Column 2 (Methodology, Results)
      final allTexts = resolved.orderedLines.map((l) => l.text).toList();

      final abstractIdx = allTexts.indexWhere((t) => t.contains('Abstract'));
      final introIdx = allTexts.indexWhere((t) => t.contains('INTRODUCTION'));
      final methodIdx = allTexts.indexWhere((t) => t.contains('METHODOLOGY'));
      final resultsIdx = allTexts.indexWhere((t) => t.contains('RESULTS'));

      expect(abstractIdx, isNonNegative);
      expect(introIdx, isNonNegative);
      expect(methodIdx, isNonNegative);
      expect(resultsIdx, isNonNegative);

      // Column 1 before Column 2!
      expect(abstractIdx, lessThan(methodIdx), reason: 'Abstract must precede Methodology');
      expect(introIdx, lessThan(methodIdx), reason: 'Introduction must precede Methodology');
      expect(methodIdx, lessThan(resultsIdx), reason: 'Methodology must precede Results');
    });

    test('preserves single-column order in standard novel', () async {
      final file = File('$corpusDir/01_single_column_novel.pdf');
      expect(file.existsSync(), isTrue);

      final extraction = await GeometryAwarePdfExtractor.extractDocument(
        pdfFile: file,
        bookId: 'test-novel-01',
      );

      final resolved = ReadingOrderResolver.resolvePage(extraction.pages.first);
      expect(resolved.layoutStructure, equals(PageLayoutStructure.singleColumn));

      // Title line comes first
      expect(resolved.orderedLines.first.text, contains('Chapter 1: The Beginning'));
      // Subsequent lines strictly descend vertically
      for (var i = 0; i < resolved.orderedLines.length - 1; i++) {
        expect(
          resolved.orderedLines[i].bounds.top,
          lessThanOrEqualTo(resolved.orderedLines[i + 1].bounds.top + 4.0),
        );
      }
    });
  });

  group('Phase 2.7D2: Paragraph Reconstruction', () {
    test('reconstructs multi-line paragraphs and preserves dialogue lines', () async {
      final file = File('$corpusDir/01_single_column_novel.pdf');
      final extraction = await GeometryAwarePdfExtractor.extractDocument(
        pdfFile: file,
        bookId: 'test-novel-01',
      );

      final pageResults = ReadingOrderResolver.resolveDocument(extraction);
      final paragraphs = ParagraphReconstructor.reconstructDocument(pageResults);

      expect(paragraphs, isNotEmpty);
      // Chapter heading should be isolated
      final headingPara = paragraphs.firstWhere((p) => p.text.contains('Chapter 1: The Beginning'));
      expect(headingPara.isBold, isTrue);
      expect(headingPara.fontSize, greaterThan(15.0));

      // Dialogue paragraph should be preserved with quote
      final dialoguePara = paragraphs.firstWhere((p) => p.text.contains('Open the gates!'));
      expect(dialoguePara.isDialogue, isTrue);
      expect(dialoguePara.text, startsWith('"'));

      // Body paragraph should combine lines without arbitrary splits
      final bodyPara = paragraphs.firstWhere((p) => p.text.contains('It was a dark and stormy night'));
      expect(bodyPara.text, contains('change the destiny of the kingdom'));
      expect(bodyPara.lineCount, greaterThan(1));
    });

    test('stitches sentences across page boundaries while isolating running headers', () async {
      final file = File('$corpusDir/05_headers_footers.pdf');
      final extraction = await GeometryAwarePdfExtractor.extractDocument(
        pdfFile: file,
        bookId: 'test-headers-05',
      );

      final pageResults = ReadingOrderResolver.resolveDocument(extraction);
      final paragraphs = ParagraphReconstructor.reconstructDocument(pageResults);

      // Verify that running header lines ("THE ADVENTURES OF SHERLOCK HOLMES") are separated
      final headers = paragraphs.where((p) => p.text.contains('THE ADVENTURES OF SHERLOCK HOLMES')).toList();
      expect(headers, isNotEmpty);
      for (final h in headers) {
        expect(h.lineCount, equals(1));
      }

      // Verify that page numbers ("Page X of 3") are separated
      final pageNumParas = paragraphs.where((p) => RegExp(r'Page \d+ of \d+').hasMatch(p.text)).toList();
      expect(pageNumParas, isNotEmpty);
      for (final p in pageNumParas) {
        expect(p.lineCount, equals(1));
      }
    });
  });

  group('Phase 2.7D3: Semantic Classification', () {
    test('classifies multi-level headings and literary chapter titles without relying solely on regex', () async {
      final file = File('$corpusDir/10_multi_heading_styles.pdf');
      final extraction = await GeometryAwarePdfExtractor.extractDocument(
        pdfFile: file,
        bookId: 'test-headings-10',
      );

      final pageResults = ReadingOrderResolver.resolveDocument(extraction);
      final paragraphs = ParagraphReconstructor.reconstructDocument(pageResults);
      final blocks = SemanticClassifier.classifyDocument(
        paragraphs: paragraphs,
        totalPages: extraction.totalPages,
      );

      // Roman Numeral 'III' (20pt bold vs 10pt body) classified as Heading 1
      final h1Block = blocks.firstWhere((b) => b.text.trim() == 'III');
      expect(h1Block.type, equals(SemanticBlockType.heading1));
      expect(h1Block.headingLevel, equals(1));

      // Plain numeral '4' (22pt bold vs 10pt body) classified as Heading 1
      final num4Block = blocks.firstWhere((b) => b.text.trim() == '4');
      expect(num4Block.type, equals(SemanticBlockType.heading1));

      // Date heading '14 July 1789 — Bastille Day' (13pt bold vs 10pt body) classified as Heading 2
      final dateBlock = blocks.firstWhere((b) => b.text.contains('14 July 1789'));
      expect(dateBlock.type, equals(SemanticBlockType.heading2));

      // Body paragraphs classified correctly
      final bodyBlock = blocks.firstWhere((b) => b.text.contains('The first section under Roman numeral'));
      expect(bodyBlock.type, equals(SemanticBlockType.bodyParagraph));
    });

    test('isolates footnotes at bottom of page with index markers', () async {
      final file = File('$corpusDir/06_footnotes.pdf');
      final extraction = await GeometryAwarePdfExtractor.extractDocument(
        pdfFile: file,
        bookId: 'test-footnotes-06',
      );

      final pageResults = ReadingOrderResolver.resolveDocument(extraction);
      final paragraphs = ParagraphReconstructor.reconstructDocument(pageResults);
      final blocks = SemanticClassifier.classifyDocument(
        paragraphs: paragraphs,
        totalPages: extraction.totalPages,
      );

      final footnotes = blocks.where((b) => b.type == SemanticBlockType.footnote).toList();
      expect(footnotes.length, greaterThanOrEqualTo(2));
      expect(footnotes.any((f) => f.text.contains('Henri Bergson')), isTrue);
      expect(footnotes.any((f) => f.text.contains('Kant')), isTrue);
    });
  });

  group('Phase 2.7D4: Image Placement & Caption Binding', () {
    test('binds proximate caption to embedded illustration', () async {
      final file = File('$corpusDir/02_illustrated_novel.pdf');
      final tempDir = Directory.systemTemp.createTempSync('img_test_');

      try {
        final extraction = await GeometryAwarePdfExtractor.extractDocument(
          pdfFile: file,
          bookId: 'test-img-02',
          imageOutputDir: tempDir,
        );

        final pageResults = ReadingOrderResolver.resolveDocument(extraction);
        final paragraphs = ParagraphReconstructor.reconstructDocument(pageResults);
        final classifiedBlocks = SemanticClassifier.classifyDocument(
          paragraphs: paragraphs,
          totalPages: extraction.totalPages,
        );

        final allImages = extraction.pages.expand((p) => p.images).toList();
        expect(allImages, isNotEmpty);

        final integratedBlocks = ImagePlacementResolver.integrateImages(
          blocks: classifiedBlocks,
          images: allImages,
          pages: extraction.pages,
        );

        // Find image block
        final imageBlock = integratedBlocks.firstWhere(
          (b) => b.type == SemanticBlockType.image,
        );
        expect(imageBlock.image, isNotNull);
        expect(imageBlock.captionText, contains('Figure 2.1: The cottage in the forest'));

        // Standalone caption block was bound and cleaned from stream
        final standaloneCaptions = integratedBlocks.where(
          (b) => b.type == SemanticBlockType.caption,
        ).toList();
        expect(standaloneCaptions, isEmpty);
      } finally {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });

    test('classifies diagram image role with schematic caption', () async {
      final file = File('$corpusDir/03_diagrams_maps.pdf');
      final tempDir = Directory.systemTemp.createTempSync('diag_test_');

      try {
        final extraction = await GeometryAwarePdfExtractor.extractDocument(
          pdfFile: file,
          bookId: 'test-diag-03',
          imageOutputDir: tempDir,
        );

        final pageResults = ReadingOrderResolver.resolveDocument(extraction);
        final paragraphs = ParagraphReconstructor.reconstructDocument(pageResults);
        final classifiedBlocks = SemanticClassifier.classifyDocument(
          paragraphs: paragraphs,
          totalPages: extraction.totalPages,
        );

        final allImages = extraction.pages.expand((p) => p.images).toList();
        expect(allImages, isNotEmpty);

        final integratedBlocks = ImagePlacementResolver.integrateImages(
          blocks: classifiedBlocks,
          images: allImages,
          pages: extraction.pages,
        );

        final imageBlock = integratedBlocks.firstWhere(
          (b) => b.type == SemanticBlockType.image,
        );
        expect(imageBlock.captionText, contains('Diagram 1: First floor plan'));
        expect(imageBlock.metadata['role'], equals('diagram'));
      } finally {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });
  });

  group('Phase 2.7D5: Reconstruction Quality Assessment', () {
    test('evaluates scanned PDF as QualityStatus.poor and recommends Original PDF Reader', () async {
      final file = File('$corpusDir/08_scanned_image_only.pdf');
      final extraction = await GeometryAwarePdfExtractor.extractDocument(
        pdfFile: file,
        bookId: 'test-scan-08',
      );

      final reconstructed = await SemanticDocumentReconstructor.reconstruct(
        extraction: extraction,
        title: 'Scanned Archive Document',
      );

      expect(reconstructed.quality.status, equals(QualityStatus.poor));
      expect(reconstructed.quality.score, lessThan(0.4));
      expect(reconstructed.quality.recommendedTier, contains('Original PDF Reader'));
      expect(reconstructed.quality.reasons.any((r) => r.contains('0 selectable vector text lines')), isTrue);
    });

    test('evaluates hybrid PDF correctly and tracks isolated scanned pages', () async {
      final file = File('$corpusDir/09_hybrid_mixed.pdf');
      final extraction = await GeometryAwarePdfExtractor.extractDocument(
        pdfFile: file,
        bookId: 'test-hybrid-09',
      );

      final reconstructed = await SemanticDocumentReconstructor.reconstruct(
        extraction: extraction,
        title: 'Mixed Technical Report',
      );

      expect(
        reconstructed.quality.status,
        anyOf(equals(QualityStatus.partial), equals(QualityStatus.poor)),
      );
      expect(reconstructed.quality.metrics['scannedPages'], equals(1));
      expect(reconstructed.quality.metrics['nativePages'], equals(1));
      expect(reconstructed.quality.metrics['hybridPages'], equals(1));
    });

    test('evaluates single column novel as QualityStatus.good suitable for reflowable', () async {
      final file = File('$corpusDir/01_single_column_novel.pdf');
      final extraction = await GeometryAwarePdfExtractor.extractDocument(
        pdfFile: file,
        bookId: 'test-good-01',
      );

      final reconstructed = await SemanticDocumentReconstructor.reconstruct(
        extraction: extraction,
        title: 'The Great Tale',
      );

      expect(reconstructed.quality.status, equals(QualityStatus.good));
      expect(reconstructed.quality.score, greaterThanOrEqualTo(0.8));
      expect(reconstructed.quality.isSuitableForReflowable, isTrue);
      expect(reconstructed.chapters.isNotEmpty, isTrue);
      expect(reconstructed.chapters.first.title, contains('Chapter 1: The Beginning'));
    });
  });

  group('Phase 2.7D6: Real-World Scanned Book Evaluation (Laut Bercerita)', () {
    test('protects real scanned book from corrupted reflowable conversion', () async {
      final candidates = [
        File('/Users/davindalana/Documents/DigitalBooks/originals/8565c1aa-0bb7-4876-8fd6-38ce318d3ed4.pdf'),
        File('/Users/davindalana/Documents/DigitalBooks/originals/{SB} Laut Bercerita.pdf'),
        File('/Users/davindalana/Documents/DigitalBooks/originals/Laut Bercerita.pdf'),
      ];

      File? realBookFile;
      for (final candidate in candidates) {
        if (candidate.existsSync()) {
          realBookFile = candidate;
          break;
        }
      }

      if (realBookFile == null) {
        print('Skipping real book test: {SB} Laut Bercerita.pdf not found in local user directories.');
        return;
      }

      final extraction = await GeometryAwarePdfExtractor.extractDocument(
        pdfFile: realBookFile,
        bookId: 'laut-bercerita-real',
        extractImagesToDisk: false,
      );

      final reconstructed = await SemanticDocumentReconstructor.reconstruct(
        extraction: extraction,
        title: 'Laut Bercerita',
        author: 'Leila S. Chudori',
      );

      expect(reconstructed.totalPages, equals(394));
      expect(reconstructed.quality.status, equals(QualityStatus.poor));
      expect(reconstructed.quality.isSuitableForReflowable, isFalse);
      expect(
        reconstructed.quality.recommendedTier,
        contains('Original PDF Reader'),
      );

      // Verify that converting to domain BookDocument marks isScanned = true
      final domainDoc = reconstructed.toBookDocument();
      expect(domainDoc.isScanned, isTrue);
      expect(domainDoc.totalPages, equals(394));
    });
  });
}
