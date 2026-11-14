// ignore_for_file: avoid_print, prefer_interpolation_to_compose_strings, depend_on_referenced_packages, unused_import

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/core/theme/typography_settings.dart';
import 'package:digital_books/features/processing/models/extracted_page_geometry.dart';
import 'package:digital_books/features/processing/models/semantic_reconstruction_models.dart';
import 'package:digital_books/features/processing/services/apple_vision_ocr_service.dart';
import 'package:digital_books/features/processing/services/semantic_document_reconstructor.dart';
import 'package:digital_books/features/reader/domain/engines/pagination_engine.dart';
import 'package:digital_books/features/reader/domain/engines/reflowable_engine.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'package:digital_books/features/reader/domain/models/book_document.dart';
import 'helpers/real_book_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final ocrService = AppleVisionOcrService();
  late Directory tempDir;

  final lautBerceritaPath =
      p.join(RealBookFixtures.downloadsDir, 'Laut Bercerita (Leila S. Chudori).pdf');
  final bicaraSeninyaPath =
      p.join(RealBookFixtures.downloadsDir, 'Bicara Itu Ada Seninya (Oh Su Hyang).pdf');
  final mrXPath =
      p.join(RealBookFixtures.downloadsDir, 'Kesetiaan Mr X The Devotion Of Suspect X (Keigo Higashino).pdf');

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('db_reading_quality_test_');
    await ocrService.ensureBinaryAvailable();
  });

  tearDownAll(() async {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Future<DocumentExtractionResult> extractOcrGeometry(
    String pdfPath,
    List<int> pageIndices,
  ) async {
    final pdfDoc = await PdfDocument.openFile(pdfPath);
    final pagesGeom = <ExtractedPageGeometry>[];
    double totalDuration = 0;

    for (final pIdx in pageIndices) {
      final page = pdfDoc.pages[pIdx];
      final img = await page.render(
        width: (page.width * 1.5).round(),
        height: (page.height * 1.5).round(),
      );
      final uiImg = await img?.createImage();
      final byteData = await uiImg?.toByteData(format: ui.ImageByteFormat.png);
      final tempPng = p.join(
        tempDir.path,
        'geom_${pIdx}_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      File(tempPng).writeAsBytesSync(byteData!.buffer.asUint8List());

      final sw = Stopwatch()..start();
      final ocrRes = await ocrService.processImage(tempPng);
      sw.stop();
      totalDuration += sw.elapsedMilliseconds;

      final geom = ocrRes.toExtractedPageGeometry(
        pageIndex: pIdx,
        pageSize: Size(page.width, page.height),
      );
      pagesGeom.add(geom);

      if (File(tempPng).existsSync()) {
        File(tempPng).deleteSync();
      }
    }

    await pdfDoc.dispose();

    return DocumentExtractionResult(
      bookId: p.basenameWithoutExtension(pdfPath),
      totalPages: pagesGeom.length,
      pages: pagesGeom,
      totalTextLines: pagesGeom.fold(0, (s, p) => s + p.lines.length),
      totalImages: 0,
      layerBreakdown: const {PageLayerType.nativeText: 1},
      hasUsableTextLayer: true,
      warnings: const [],
      durationMs: totalDuration,
    );
  }

  group('Phase 3.1.2 — Full-Book OCR Reading Quality Validation', () {
    test(
      '1. Multi-Section Representative Quality & Integrity Audit across 3 Books',
      () async {
        if (!checkFixtureOrSkip(lautBerceritaPath) ||
            !checkFixtureOrSkip(bicaraSeninyaPath) ||
            !checkFixtureOrSkip(mrXPath)) {
          return;
        }
        final testCases = [
          {
            'book': 'Laut Bercerita (Fiction / Photocopy)',
            'path': lautBerceritaPath,
            'pages': [14, 15, 150, 360], // Beginning, dialogue, middle, end
            'title': 'Laut Bercerita',
            'author': 'Leila S. Chudori',
          },
          {
            'book': 'Bicara Itu Ada Seninya (Non-Fiction / Structured)',
            'path': bicaraSeninyaPath,
            'pages': [
              3,
              8,
              32,
              120,
            ], // Imprint/lists (p.4), Chapter heading (p.9), middle body (p.33 & 121)
            'title': 'Bicara Itu Ada Seninya',
            'author': 'Oh Su Hyang',
          },
          {
            'book': 'Kesetiaan Mr X (Narrative Prose & Dialogue)',
            'path': mrXPath,
            'pages': [10, 11, 140, 280], // Title/chapter, dialogue, middle, end
            'title': 'Kesetiaan Mr. X',
            'author': 'Keigo Higashino',
          },
        ];

        print('\n' + '=' * 85);
        print(
          'PHASE 3.1.2: MULTI-SECTION READING QUALITY & TEXT INTEGRITY AUDIT',
        );
        print('=' * 85);

        for (final tc in testCases) {
          final bookName = tc['book'] as String;
          final pdfPath = tc['path'] as String;
          final pages = tc['pages'] as List<int>;
          final title = tc['title'] as String;
          final author = tc['author'] as String;

          final extraction = await extractOcrGeometry(pdfPath, pages);
          expect(extraction.pages.length, equals(pages.length));

          final reconstructed = await SemanticDocumentReconstructor.reconstruct(
            extraction: extraction,
            title: title,
            author: author,
          );

          final doc = reconstructed.toBookDocument();
          final readerDoc = ReflowableEngine.normalizeDocument(doc);

          expect(readerDoc.chapters, isNotEmpty);
          final totalNodes = readerDoc.chapters.fold<int>(
            0,
            (s, c) => s + c.nodes.length,
          );
          final totalWords = readerDoc.chapters.fold<int>(
            0,
            (s, c) =>
                s +
                c.nodes.fold<int>(
                  0,
                  (ns, n) =>
                      ns +
                      n.text
                          .split(RegExp(r'\s+'))
                          .where((w) => w.isNotEmpty)
                          .length,
                ),
          );

          // Verification A: Text Integrity Checks
          expect(totalNodes, greaterThan(0));
          expect(totalWords, greaterThan(200));

          // Ensure no empty text nodes or NaN boundaries
          for (final ch in readerDoc.chapters) {
            for (final node in ch.nodes) {
              expect(
                node.text.trim(),
                isNotEmpty,
                reason: 'No empty content nodes allowed',
              );
              expect(
                node.sourcePdfPage,
                greaterThan(0),
                reason:
                    'Every reconstructed node must have a source PDF citation',
              );
            }
          }

          // Verification B: Semantic Node Distribution
          final nodeTypeCounts = <ContentNodeType, int>{};
          for (final ch in readerDoc.chapters) {
            for (final node in ch.nodes) {
              nodeTypeCounts[node.type] = (nodeTypeCounts[node.type] ?? 0) + 1;
            }
          }

          print('Book: $bookName');
          print('  - Pages Sampled:        ${pages.join(', ')}');
          print('  - Reconstructed Words:  $totalWords');
          print(
            '  - Content Nodes:        $totalNodes across ${readerDoc.chapters.length} chapters',
          );
          print(
            '  - Node Type Breakdown:  ${nodeTypeCounts.entries.map((e) => "${e.key.name}: ${e.value}").join(", ")}',
          );
          print('-' * 85);

          // Check that non-fiction preserves structured nodes (headings, lists)
          if (title.contains('Bicara')) {
            expect(
              nodeTypeCounts.containsKey(ContentNodeType.heading) ||
                  nodeTypeCounts.containsKey(ContentNodeType.sectionHeading) ||
                  nodeTypeCounts.containsKey(ContentNodeType.orderedList),
              isTrue,
              reason:
                  'Bicara Itu Ada Seninya must preserve headings and lists in reader document',
            );
          }
        }
        print('=' * 85 + '\n');
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      '2. Layout & Pagination Engine: Orphan Heading Prevention & Budget Precision',
      () {
        const typo = TypographySettings(
          fontSize: 18.0,
          lineSpacing: 1.6,
          paragraphSpacing: 14.0,
        );

        // Create a test chapter with a heading placed near the bottom of a page budget
        final nodes = [
          const ContentNode(
            id: 'p1',
            type: ContentNodeType.paragraph,
            text:
                'Paragraf pembuka pertama yang mengisi sebagian besar halaman pembuka pada buku dan mengonsumsi sebagian tinggi viewport secara terukur.',
            sourcePdfPage: 1,
          ),
          const ContentNode(
            id: 'p2',
            type: ContentNodeType.paragraph,
            text:
                'Paragraf kedua yang mengisi sisa ruang halaman sehingga hanya tersisa ruang tipis di bagian bawah halaman buku.',
            sourcePdfPage: 1,
          ),
          // Section heading that should trigger orphan prevention because it cannot fit with following text
          const ContentNode(
            id: 'h_section',
            type: ContentNodeType.sectionHeading,
            text: '1. Babak Baru Komunikasi',
            sourcePdfPage: 1,
          ),
          const ContentNode(
            id: 'p3',
            type: ContentNodeType.paragraph,
            text:
                'Ini adalah paragraf penjelas yang menyertai subjudul di atas dengan beberapa baris penjelasan penting.',
            sourcePdfPage: 1,
          ),
        ];

        final chapter = ReaderChapter(
          id: 'test_ch',
          index: 0,
          title: 'Bab Uji Orphan',
          nodes: nodes,
        );

        // Paginate with a constrained height budget (e.g. 260 pt viewport height)
        final pages = PaginationEngine.paginateChapter(
          chapter: chapter,
          viewportWidth: 500.0,
          viewportHeight: 260.0,
          typography: typo,
        );

        for (int i = 0; i < pages.length; i++) {
          print(
            'Page $i slices: ${pages[i].slices.map((s) => "${s.node.id} (${s.node.type.name})").toList()}',
          );
        }

        expect(pages.length, greaterThanOrEqualTo(2));

        // Find the page index that contains 'h_section'
        final headingPageIndex = pages.indexWhere(
          (p) => p.slices.any((s) => s.node.id == 'h_section'),
        );
        expect(
          headingPageIndex,
          greaterThanOrEqualTo(1),
          reason:
              'Heading must be pushed away from the preceding page where it could not fit',
        );

        // Verify that the preceding page does not end with an orphaned heading
        final prevPageSlices = pages[headingPageIndex - 1].slices;
        expect(
          prevPageSlices.last.node.type != ContentNodeType.sectionHeading &&
              prevPageSlices.last.node.type != ContentNodeType.heading,
          isTrue,
          reason: 'Previous page must not end with an orphaned heading',
        );

        // Verify: The heading starts cleanly on its page together with following text
        final headingPageNodes = pages[headingPageIndex].slices
            .map((s) => s.node.id)
            .toList();
        expect(headingPageNodes.contains('h_section'), isTrue);
        expect(
          headingPageNodes.contains('p3'),
          isTrue,
          reason:
              'Heading must be kept with at least initial following body text',
        );
      },
    );

    test('3. Dedicated Semantic Widget Rendering in Reflowable Output', () {
      // Test that all ContentNodeType entries are recognized in ReflowableEngine
      final doc = BookDocument(
        id: 'test_semantic_types',
        title: 'Buku Struktur Semantik',
        author: 'Penulis',
        totalPages: 1,
        chapters: [
          BookChapter(
            id: 'ch1',
            index: 0,
            title: 'Bab 1',
            blocks: [
              const BookBlock(
                id: 'b1',
                type: BlockType.documentTitle,
                text: 'BUKU STRUKTUR SEMANTIK',
                originalPageNumber: 1,
              ),
              const BookBlock(
                id: 'b2',
                type: BlockType.sectionHeading,
                text: '1. Mengapa Kesan Pertama Sangat Penting',
                originalPageNumber: 1,
              ),
              const BookBlock(
                id: 'b3',
                type: BlockType.orderedList,
                text: '1. Tatap mata lawan bicara dengan hangat.',
                originalPageNumber: 1,
              ),
              const BookBlock(
                id: 'b4',
                type: BlockType.unorderedList,
                text: '• Berikan senyum yang wajar.',
                originalPageNumber: 1,
              ),
              const BookBlock(
                id: 'b5',
                type: BlockType.copyrightBlock,
                text: 'Hak cipta dilindungi undang-undang. ISBN 978-000-111.',
                originalPageNumber: 1,
              ),
              const BookBlock(
                id: 'b6',
                type: BlockType.caption,
                text: 'Gambar 1.1 Diagram Bahasa Tubuh',
                originalPageNumber: 1,
              ),
            ],
          ),
        ],
      );

      final readerDoc = ReflowableEngine.normalizeDocument(doc);
      final ch0Nodes = readerDoc.chapters.first.nodes;

      expect(ch0Nodes[0].type, equals(ContentNodeType.documentTitle));
      expect(ch0Nodes[1].type, equals(ContentNodeType.sectionHeading));
      expect(ch0Nodes[2].type, equals(ContentNodeType.orderedList));
      expect(ch0Nodes[3].type, equals(ContentNodeType.unorderedList));
      expect(ch0Nodes[4].type, equals(ContentNodeType.copyrightBlock));
      expect(ch0Nodes[5].type, equals(ContentNodeType.caption));

      // Verify that none were degraded to paragraph!
      for (final node in ch0Nodes) {
        expect(node.type, isNot(equals(ContentNodeType.paragraph)));
      }
    });
  });
}
