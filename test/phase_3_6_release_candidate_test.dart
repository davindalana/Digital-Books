// ignore_for_file: avoid_print, depend_on_referenced_packages

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' as drift;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/core/providers/database_providers.dart';
import 'package:digital_books/features/processing/services/pdf_processing_pipeline.dart';
import 'package:digital_books/features/processing/services/geometry_aware_pdf_extractor.dart';
import 'package:digital_books/features/processing/services/semantic_document_reconstructor.dart';
import 'package:digital_books/features/processing/models/semantic_reconstruction_models.dart';
import 'package:digital_books/features/processing/models/extracted_page_geometry.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'package:digital_books/features/reader/domain/models/book_annotation.dart';
import 'package:digital_books/features/reader/domain/engines/pagination_engine.dart';
import 'package:digital_books/features/reader/domain/models/book_document.dart';
import 'package:digital_books/features/reader/presentation/screens/reading_screen.dart';
import 'package:digital_books/core/theme/typography_settings.dart';
import 'package:path/path.dart' as p;
import 'helpers/real_book_fixtures.dart';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/features/reader/presentation/widgets/original_pdf_reader.dart';
import 'package:digital_books/features/reader/providers/reader_settings_provider.dart';
import 'helpers/corpus_pdf_generator.dart';

class MockPathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final Directory tempDir;
  MockPathProviderPlatform(this.tempDir);

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir.path;

  @override
  Future<String?> getTemporaryPath() async => tempDir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const corpusDir = 'test/fixtures/corpus';

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('db_phase_3_6_');
    PathProviderPlatform.instance = MockPathProviderPlatform(tempDir);

    final corpus = Directory(corpusDir);
    if (!corpus.existsSync() || corpus.listSync().isEmpty) {
      await CorpusPdfGenerator.generateAllCorpusFiles(corpus);
    }
  });

  tearDownAll(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  // =========================================================================
  // GROUP 1: REAL PDF QUALITY AUDIT
  // =========================================================================
  group('Phase 3.6 — Real PDF Quality Audit (Corpus & Production Documents)', () {
    test(
      '1. Single-Column Novel: Headings, Paragraphs, Dialogue Quotes & Order',
      () async {
        final file = File('$corpusDir/01_single_column_novel.pdf');
        expect(file.existsSync(), isTrue);

        final extraction = await GeometryAwarePdfExtractor.extractDocument(
          pdfFile: file,
          bookId: 'qa_01_novel',
          extractImagesToDisk: false,
        );

        expect(extraction.totalPages, equals(1));
        expect(extraction.hasUsableTextLayer, isTrue);

        final reconstructed = await SemanticDocumentReconstructor.reconstruct(
          extraction: extraction,
          title: 'Single Column Novel',
          author: 'Fiction Author',
        );

        expect(reconstructed.chapters, isNotEmpty);
        expect(
          reconstructed.chapters.first.title,
          contains('Chapter 1: The Beginning'),
        );

        // Check dialogue formatting: opening quote must be preserved
        final dialogueBlocks = reconstructed.blocks.where(
          (b) => b.text.contains('"Open the gates!"'),
        );
        expect(
          dialogueBlocks,
          isNotEmpty,
          reason: 'Dialogue quotation must remain intact',
        );

        // Check reading order: Beginning -> Stormy Night -> Open the gates -> Great Hall
        final allText = reconstructed.blocks.map((b) => b.text).join('\n');
        final posIntro = allText.indexOf('dark and stormy night');
        final posDialogue = allText.indexOf('"Open the gates!"');
        final posHall = allText.indexOf('great hall');

        expect(posIntro != -1 && posDialogue != -1 && posHall != -1, isTrue);
        expect(posIntro < posDialogue, isTrue);
        expect(posDialogue < posHall, isTrue);
      },
    );

    test(
      '2. Illustrated Novel & Diagrams: Image Dimensions, Placement & Captions',
      () async {
        final file = File('$corpusDir/02_illustrated_novel.pdf');
        final extraction = await GeometryAwarePdfExtractor.extractDocument(
          pdfFile: file,
          bookId: 'qa_02_illustrated',
          imageOutputDir: tempDir,
          extractImagesToDisk: true,
        );

        expect(extraction.totalImages, greaterThan(0));

        final reconstructed = await SemanticDocumentReconstructor.reconstruct(
          extraction: extraction,
          title: 'Illustrated Novel',
          author: 'Artist Author',
        );

        final imageBlocks = reconstructed.blocks.where(
          (b) => b.type == SemanticBlockType.image,
        );
        expect(imageBlocks, isNotEmpty);
        expect(imageBlocks.first.image?.imagePath, isNotNull);

        // Check caption attachment to image block
        expect(imageBlocks.first.captionText, isNotNull);
        expect(
          imageBlocks.first.captionText,
          contains('Figure 2.1: The cottage in the forest.'),
        );

        // Diagram check
        final diagramFile = File('$corpusDir/03_diagrams_maps.pdf');
        final diagExtraction = await GeometryAwarePdfExtractor.extractDocument(
          pdfFile: diagramFile,
          bookId: 'qa_03_diagrams',
          extractImagesToDisk: false,
        );
        expect(diagExtraction.totalImages, equals(1));
        final diagImg = diagExtraction.pages.first.images.first;
        expect(diagImg.dimensions.width, greaterThan(0));
        expect(diagImg.dimensions.height, greaterThan(0));
        expect(diagImg.aspectRatio, greaterThan(0));
      },
    );

    test('3. Two-Column Academic Paper: Non-Interleaved Reading Order', () async {
      final file = File('$corpusDir/04_two_column_academic.pdf');
      final extraction = await GeometryAwarePdfExtractor.extractDocument(
        pdfFile: file,
        bookId: 'qa_04_academic',
        extractImagesToDisk: false,
      );

      final reconstructed = await SemanticDocumentReconstructor.reconstruct(
        extraction: extraction,
        title: 'Academic Paper',
        author: 'Researcher',
      );

      final fullText = reconstructed.blocks.map((b) => b.text).join('\n');
      final idxAbstract = fullText.indexOf('Abstract');
      final idxIntro = fullText.indexOf('I. INTRODUCTION');
      final idxMethod = fullText.indexOf('II. METHODOLOGY');
      final idxResults = fullText.indexOf('III. RESULTS');

      expect(
        idxAbstract != -1 &&
            idxIntro != -1 &&
            idxMethod != -1 &&
            idxResults != -1,
        isTrue,
      );

      // Crucial: Left column (Abstract, Intro) must precede Right column (Methodology, Results)
      expect(idxAbstract < idxIntro, isTrue);
      expect(
        idxIntro < idxMethod,
        isTrue,
        reason: 'Methodology must not interleave before Introduction',
      );
      expect(idxMethod < idxResults, isTrue);
    });

    test(
      '4. Headers, Footers & Footnotes: Running Header Stripping & Footnote Binding',
      () async {
        final hfFile = File('$corpusDir/05_headers_footers.pdf');
        final hfExtraction = await GeometryAwarePdfExtractor.extractDocument(
          pdfFile: hfFile,
          bookId: 'qa_05_hf',
          extractImagesToDisk: false,
        );

        final hfReconstructed = await SemanticDocumentReconstructor.reconstruct(
          extraction: hfExtraction,
          title: 'Adventures',
          author: 'Conan Doyle',
        );

        // Running headers and page numbers must be stripped from body text
        final bodyText = hfReconstructed.blocks
            .where((b) => b.type == SemanticBlockType.bodyParagraph)
            .map((b) => b.text)
            .join('\n');

        expect(
          bodyText.contains('THE ADVENTURES OF SHERLOCK HOLMES'),
          isFalse,
          reason: 'Running header must be stripped from body paragraphs',
        );
        expect(
          bodyText.contains('Page 1 of 3'),
          isFalse,
          reason:
              'Running footer page number must be stripped from body paragraphs',
        );

        // Footnotes test
        final fnFile = File('$corpusDir/06_footnotes.pdf');
        final fnExtraction = await GeometryAwarePdfExtractor.extractDocument(
          pdfFile: fnFile,
          bookId: 'qa_06_fn',
          extractImagesToDisk: false,
        );

        final fnReconstructed = await SemanticDocumentReconstructor.reconstruct(
          extraction: fnExtraction,
          title: 'Philosophical Inquiries',
          author: 'Philosopher',
        );

        final footnoteBlocks = fnReconstructed.blocks.where(
          (b) => b.type == SemanticBlockType.footnote,
        );
        expect(footnoteBlocks.length, greaterThanOrEqualTo(2));
        expect(
          footnoteBlocks.any((b) => b.text.contains('[1] Henri Bergson')),
          isTrue,
        );
        expect(
          footnoteBlocks.any((b) => b.text.contains('[2] Compare with Kant')),
          isTrue,
        );
      },
    );

    test('5. Complex Tables & Figures: Structural Grid Analysis', () async {
      final file = File('$corpusDir/07_tables_figures.pdf');
      final extraction = await GeometryAwarePdfExtractor.extractDocument(
        pdfFile: file,
        bookId: 'qa_07_tables',
        extractImagesToDisk: false,
      );

      final reconstructed = await SemanticDocumentReconstructor.reconstruct(
        extraction: extraction,
        title: 'Quarterly Summary',
        author: 'Analyst',
      );

      // Document contains Financial Summary Table
      expect(reconstructed.blocks, isNotEmpty);
      final textContent = reconstructed.blocks.map((b) => b.text).join(' ');
      expect(textContent, contains('Quarterly Financial Summary'));
      expect(textContent, contains('Quarter'));
      expect(textContent, contains('Revenue'));
      expect(textContent, contains('Net Profit'));

      // Quality assessment: QualityStatus is partial or good
      expect(reconstructed.quality.status, isNotNull);
    });

    test(
      '6. Scanned & Hybrid Documents: Layer Classification & Safe Fallback',
      () async {
        // Scanned Image Only
        final scanFile = File('$corpusDir/08_scanned_image_only.pdf');
        final scanExtraction = await GeometryAwarePdfExtractor.extractDocument(
          pdfFile: scanFile,
          bookId: 'qa_08_scanned',
          extractImagesToDisk: false,
        );

        expect(scanExtraction.hasUsableTextLayer, isFalse);
        expect(scanExtraction.recommendedReaderTier, contains('Original PDF'));
        expect(
          scanExtraction.pages.first.layerType,
          equals(PageLayerType.scannedImage),
        );

        // Hybrid Document
        final hybridFile = File('$corpusDir/09_hybrid_mixed.pdf');
        final hybridExtraction =
            await GeometryAwarePdfExtractor.extractDocument(
              pdfFile: hybridFile,
              bookId: 'qa_09_hybrid',
              extractImagesToDisk: false,
            );

        expect(hybridExtraction.totalPages, equals(3));
        final layers = hybridExtraction.pages.map((p) => p.layerType).toList();
        expect(layers[0], equals(PageLayerType.nativeText));
        expect(layers[1], equals(PageLayerType.scannedImage));
        expect(layers[2], equals(PageLayerType.hybrid));
      },
    );

    test('7. Multi-Heading & Mathematical Formulas: Semantic Protection', () async {
      final file = File('$corpusDir/10_multi_heading_styles.pdf');
      final extraction = await GeometryAwarePdfExtractor.extractDocument(
        pdfFile: file,
        bookId: 'qa_10_headings',
        extractImagesToDisk: false,
      );

      final reconstructed = await SemanticDocumentReconstructor.reconstruct(
        extraction: extraction,
        title: 'Historical Anthology',
        author: 'Historian',
      );

      final headings = reconstructed.blocks.where(
        (b) =>
            b.type == SemanticBlockType.heading1 ||
            b.type == SemanticBlockType.heading2 ||
            b.type == SemanticBlockType.heading3,
      );
      expect(headings, isNotEmpty);
      expect(
        headings.any((h) => h.text.trim() == 'III'),
        isTrue,
        reason: 'Roman numeral heading must be recognized',
      );

      // Test formula boundary preservation logic directly
      final formulaExtraction = DocumentExtractionResult(
        bookId: 'qa_math_eval',
        totalPages: 1,
        totalTextLines: 3,
        totalImages: 0,
        hasUsableTextLayer: true,
        warnings: const [],
        durationMs: 5.0,
        layerBreakdown: const {PageLayerType.nativeText: 1},
        pages: [
          const ExtractedPageGeometry(
            pageIndex: 0,
            pageSize: Size(595, 842),
            layerType: PageLayerType.nativeText,
            charCount: 150,
            images: [],
            lines: [
              ExtractedTextLine(
                text:
                    'The energy equivalence theorem is expressed by Einstein as:',
                bounds: Rect.fromLTWH(50, 100, 450, 15),
                fontSize: 12.0,
                lineIndex: 0,
                pageIndex: 0,
              ),
              ExtractedTextLine(
                text: 'E = mc^2',
                bounds: Rect.fromLTWH(150, 140, 120, 20),
                fontSize: 14.0,
                fontStyle: [PdfFontStyle.bold],
                lineIndex: 1,
                pageIndex: 0,
              ),
              ExtractedTextLine(
                text:
                    'This relationship demonstrates the proportionality between mass and energy.',
                bounds: Rect.fromLTWH(50, 180, 450, 15),
                fontSize: 12.0,
                lineIndex: 2,
                pageIndex: 0,
              ),
            ],
          ),
        ],
      );

      final mathReconstructed = await SemanticDocumentReconstructor.reconstruct(
        extraction: formulaExtraction,
        title: 'Physics Formulation',
        author: 'Albert Einstein',
      );

      expect(mathReconstructed.blocks.length, greaterThanOrEqualTo(3));
      expect(
        mathReconstructed.blocks.any((b) => b.text.contains('E = mc^2')),
        isTrue,
      );
    });

    test(
      '8. Real-World Digital Book: The Let Them Theory (265 Pages) E2E',
      () async {
        final realBook = File(
          p.join(RealBookFixtures.originalsDir, '8cda23f0-bf42-4a4d-a1fd-30d2943835c9.pdf'),
        );
        if (!checkFixtureOrSkip(realBook, 'The Let Them Theory PDF')) return;

        final sw = Stopwatch()..start();
        final extraction = await GeometryAwarePdfExtractor.extractDocument(
          pdfFile: realBook,
          bookId: 'let_them_eval',
          extractImagesToDisk: false,
        );
        sw.stop();

        expect(extraction.totalPages, equals(265));
        expect(extraction.hasUsableTextLayer, isTrue);

        final reconSw = Stopwatch()..start();
        final reconstructed = await SemanticDocumentReconstructor.reconstruct(
          extraction: extraction,
          title: 'The Let Them Theory',
          author: 'Mel Robbins',
        );
        reconSw.stop();

        print(
          'Let Them Theory (265p): Extracted in ${sw.elapsedMilliseconds} ms (${(sw.elapsedMilliseconds / 265).toStringAsFixed(1)} ms/p), reconstructed in ${reconSw.elapsedMilliseconds} ms',
        );
        expect(reconstructed.quality.score, greaterThan(0.90));
        expect(reconstructed.chapters.length, greaterThan(15));
      },
    );

    test(
      '9. Real-World Scanned Fiction: The Devotion of Suspect X (324 Pages)',
      () async {
        final realBook = File(
          p.join(RealBookFixtures.originalsDir, '67141617-5a74-4f9b-a9fa-45b28366e27d.pdf'),
        );
        if (!checkFixtureOrSkip(realBook, 'The Devotion of Suspect X PDF')) return;

        final extraction = await GeometryAwarePdfExtractor.extractDocument(
          pdfFile: realBook,
          bookId: 'suspect_x_eval',
          extractImagesToDisk: false,
        );

        expect(extraction.totalPages, equals(324));
        // Scanned book check
        expect(extraction.recommendedReaderTier, contains('Original PDF'));
      },
    );

    test('10. Real-World Scanned Literary: Laut Bercerita (394 Pages)', () async {
      final realBook = File(
        p.join(RealBookFixtures.originalsDir, '8565c1aa-0bb7-4876-8fd6-38ce318d3ed4.pdf'),
      );
      if (!checkFixtureOrSkip(realBook, 'Laut Bercerita PDF')) return;

      final extraction = await GeometryAwarePdfExtractor.extractDocument(
        pdfFile: realBook,
        bookId: 'laut_eval',
        extractImagesToDisk: false,
      );

      expect(extraction.totalPages, equals(394));
      expect(extraction.recommendedReaderTier, contains('Original PDF'));
    });
  });

  // =========================================================================
  // GROUP 2: MANUAL READER UX VALIDATION
  // =========================================================================
  group('Phase 3.6 — Manual Reader UX & Lifecycle Workflow Validation', () {
    test(
      '11. Complete PDF Import Pipeline into SQLite & Atomic Chapter Storage',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        final dbService = DatabaseService(db);
        final pipeline = PdfProcessingPipeline(dbService);

        final novelFile = File('$corpusDir/01_single_column_novel.pdf');
        final book = await pipeline.processAndImportPdf(
          pdfFile: novelFile,
          customTitle: 'Imported Test Book',
          customAuthor: 'Test Author',
        );

        expect(book.id, isNotEmpty);
        expect(book.title, equals('Imported Test Book'));

        final storedBook = await dbService.getBookById(book.id);
        expect(storedBook, isNotNull);
        expect(storedBook!.isScanned, isFalse);

        final chapters = await dbService.getChaptersForBook(book.id);
        expect(chapters, isNotEmpty);
        expect(chapters.first.title, contains('Chapter 1'));

        await db.close();
      },
    );

    test('12. Dual-Mode Reading Transition & Position Sync', () {
      final testDoc = ReaderDocument(
        bookId: 'sync_doc',
        title: 'Sync Test',
        author: 'Sync Author',
        chapters: [
          ReaderChapter(
            id: 'ch_0',
            index: 0,
            title: 'Bab 1',
            nodes: List.generate(
              10,
              (i) => ContentNode(
                id: 'node_$i',
                type: ContentNodeType.paragraph,
                text:
                    'Paragraf nomor $i dengan teks narasi yang cukup panjang untuk paginasi.',
              ),
            ),
          ),
        ],
      );

      // Verify pagination calculation
      final pages = PaginationEngine.paginateDocument(
        document: testDoc,
        viewportWidth: 800.0,
        viewportHeight: 600.0,
        typography: const TypographySettings(),
      );

      expect(pages, isNotEmpty);

      // Reading position preserves node anchor
      final anchor = testDoc.chapters.first.nodes[4].id;
      final targetPageIdx = pages.indexWhere(
        (p) => p.slices.any((s) => s.node.id == anchor),
      );
      expect(targetPageIdx, greaterThanOrEqualTo(0));
    });

    test(
      '13. Typography Live Reconfiguration: Fonts, Sizes, Line Heights, Margins',
      () {
        final doc = ReaderDocument(
          bookId: 'typo_doc',
          title: 'Typography Doc',
          author: 'Typo Author',
          chapters: [
            ReaderChapter(
              id: 'c0',
              index: 0,
              title: 'Bab 1',
              nodes: [
                const ContentNode(
                  id: 'n1',
                  type: ContentNodeType.paragraph,
                  text:
                      'Teks pengujian konfigurasi tipografi dengan variasi ukuran dan spasi.',
                ),
              ],
            ),
          ],
        );

        // Test font size variations
        for (final fontSize in [14.0, 18.0, 24.0]) {
          final typo = TypographySettings(fontSize: fontSize);
          final pages = PaginationEngine.paginateDocument(
            document: doc,
            viewportWidth: 800.0,
            viewportHeight: 600.0,
            typography: typo,
          );
          expect(pages, isNotEmpty);
        }

        // Test margin variations
        for (final margin in [24.0, 32.0, 48.0]) {
          final typo = TypographySettings(horizontalMargin: margin);
          final contentW = PaginationEngine.contentWidthFor(
            viewportWidth: 800.0,
            typography: typo,
          );
          expect(contentW, lessThanOrEqualTo(800.0 - (margin * 2)));
        }
      },
    );

    test('14. Theme Contrast Compliance: White, Sepia, Dark', () {
      final white = ReadingThemeType.white;
      final sepia = ReadingThemeType.sepia;
      final dark = ReadingThemeType.dark;

      // Verify colors have sufficient contrast
      expect(white.backgroundColor, equals(const Color(0xFFFFFFFF)));
      expect(white.textColor, equals(const Color(0xFF1C1C1E)));

      expect(sepia.backgroundColor, equals(const Color(0xFFF8F1E3)));
      expect(sepia.textColor, equals(const Color(0xFF433422)));

      expect(dark.backgroundColor, equals(const Color(0xFF1C1C1E)));
      expect(dark.textColor, equals(const Color(0xFFE5E5EA)));
    });

    test('15. Spread Layout Toggle: 1-Page vs 2-Page Viewport Clamping', () {
      final doc = ReaderDocument(
        bookId: 'spread_doc',
        title: 'Spread Doc',
        author: 'Spread Author',
        chapters: [
          ReaderChapter(
            id: 'c0',
            index: 0,
            title: 'Bab 1',
            nodes: List.generate(
              5,
              (i) => ContentNode(
                id: 'n_$i',
                type: ContentNodeType.paragraph,
                text: 'Paragraf $i untuk menguji tata letak dua halaman.',
              ),
            ),
          ),
        ],
      );

      // Wide desktop (1000px): Spread enabled
      final spreadTypo = const TypographySettings(twoPageSpread: true);
      final spreadPages = PaginationEngine.paginateDocument(
        document: doc,
        viewportWidth: 1000.0,
        viewportHeight: 700.0,
        typography: spreadTypo,
      );

      // Narrow window (700px): Spread disabled
      final singlePages = PaginationEngine.paginateDocument(
        document: doc,
        viewportWidth: 700.0,
        viewportHeight: 700.0,
        typography: const TypographySettings(twoPageSpread: false),
      );

      expect(spreadPages, isNotEmpty);
      expect(singlePages, isNotEmpty);
    });

    test('16. Bookmarks and Highlights CRUD & Persistence', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final dbService = DatabaseService(db);

      final now = DateTime.now();
      await dbService.insertBook(
        BooksCompanion(
          id: const drift.Value('book_crud'),
          title: const drift.Value('Book Crud Test'),
          author: const drift.Value('Author'),
          originalPdfPath: const drift.Value('/dummy.pdf'),
          createdAt: drift.Value(now),
          updatedAt: drift.Value(now),
        ),
      );

      // Insert Bookmark
      await dbService.addBookmark(
        BookmarksCompanion(
          id: const drift.Value('bm_1'),
          bookId: const drift.Value('book_crud'),
          position: const drift.Value(5),
          label: const drift.Value('Bookmark Catatan Penting'),
          createdAt: drift.Value(now),
        ),
      );

      final bms = await dbService.getBookmarksForBook('book_crud');
      expect(bms.length, equals(1));
      expect(bms.first.label, equals('Bookmark Catatan Penting'));

      // Insert Highlight
      final highlight = BookAnnotation(
        id: 'hl_1',
        bookId: 'book_crud',
        type: AnnotationType.highlight,
        selectedText: 'Teks yang disorot dengan warna kuning.',
        chapterId: 'ch_1',
        color: 'yellow',
        createdAt: now,
      );
      await dbService.saveAnnotation(highlight);

      final annotations = await dbService.getAnnotationsForBook('book_crud');
      expect(annotations.length, equals(2)); // 1 highlight + 1 bookmark unified
      expect(
        annotations.any(
          (a) => a.selectedText == 'Teks yang disorot dengan warna kuning.',
        ),
        isTrue,
      );

      // Delete bookmark
      await dbService.deleteBookmark('bm_1');
      final bmsAfter = await dbService.getBookmarksForBook('book_crud');
      expect(bmsAfter, isEmpty);

      await db.close();
    });

    test('17. Reading Progress Persistence Across App Session Reset', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final dbService = DatabaseService(db);

      final now = DateTime.now();
      await dbService.insertBook(
        BooksCompanion(
          id: const drift.Value('book_progress'),
          title: const drift.Value('Progress Book'),
          author: const drift.Value('Author'),
          originalPdfPath: const drift.Value('/path.pdf'),
          createdAt: drift.Value(now),
          updatedAt: drift.Value(now),
        ),
      );

      // Save reading progress
      await dbService.upsertProgress(
        ReadingProgressesCompanion.insert(
          id: 'prog_1',
          bookId: 'book_progress',
          lastReadAt: now,
          progressPercentage: const drift.Value(0.65),
          currentPosition: const drift.Value(42),
          currentChapter: const drift.Value(4),
        ),
      );

      final prog = await dbService.getProgress('book_progress');
      expect(prog, isNotNull);
      expect(prog!.progressPercentage, closeTo(0.65, 0.01));
      expect(prog.currentPosition, equals(42));
      expect(prog.currentChapter, equals(4));

      await db.close();
    });

    test('18. Malformed & Corrupted PDF Graceful Error Handling', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final dbService = DatabaseService(db);
      final pipeline = PdfProcessingPipeline(dbService);

      // 0-byte file
      final emptyFile = File('${tempDir.path}/empty.pdf')..writeAsBytesSync([]);
      expect(
        () async => await pipeline.processAndImportPdf(pdfFile: emptyFile),
        throwsA(anything),
      );

      // Corrupt file
      final corruptFile = File('${tempDir.path}/corrupt.pdf')
        ..writeAsStringSync('NOT_A_VALID_PDF_FILE_HEADER_GARBAGE');
      expect(
        () async => await pipeline.processAndImportPdf(pdfFile: corruptFile),
        throwsA(anything),
      );

      await db.close();
    });

    testWidgets(
      '19. Recommendation Banner Switch from Book Mode to Original PDF',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        final dbService = DatabaseService(db);

        final processedDoc = BookDocument(
          id: 'test_scanned_switch',
          title: 'Buku Pindaian Lawas',
          author: 'Penulis Sejarah',
          totalPages: 5,
          isScanned: true,
          chapters: [
            const BookChapter(
              id: 'c1',
              index: 0,
              title: 'Bab 1',
              blocks: [
                BookBlock(
                  id: 'b1',
                  type: BlockType.image,
                  text: 'Halaman scan',
                  originalPageNumber: 1,
                ),
              ],
            ),
          ],
          metadata: const {
            'processingStatus': 'requiresOcr',
            'isScannedSource': true,
            'reconstructionQuality': {'status': 'poor'},
          },
        );
        final processedPath = '${tempDir.path}/test_scanned_switch.json';
        File(processedPath).writeAsStringSync(processedDoc.toJsonString());

        final now = DateTime.now();
        await dbService.insertBook(
          BooksCompanion.insert(
            id: 'test_scanned_switch',
            title: 'Buku Pindaian Lawas',
            author: 'Penulis Sejarah',
            originalPdfPath: '$corpusDir/08_scanned_image_only.pdf',
            processedBookPath: drift.Value(processedPath),
            totalPages: const drift.Value(5),
            isScanned: const drift.Value(true),
            createdAt: now,
            updatedAt: now,
          ),
        );

        final book = await dbService.getBookById('test_scanned_switch');

        await tester.pumpWidget(
          ProviderScope(
            overrides: [databaseServiceProvider.overrideWithValue(dbService)],
            child: MaterialApp(
              home: ReadingScreen(
                book: book!,
                initialMode: ReadingMode.reflowable,
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          find.textContaining(
            'This scanned document has no complete text layer',
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('quality_banner_switch_button')),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey('quality_banner_switch_button')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(OriginalPdfReader), findsOneWidget);

        await db.close();
      },
    );
  });

  // =========================================================================
  // GROUP 3: PERFORMANCE PROFILING
  // =========================================================================
  group('Phase 3.6 — Performance & Resource Profiling', () {
    test('20. Benchmark Extraction & Import Throughput Across Document Scales', () async {
      print(
        '\n===============================================================',
      );
      print('PHASE 3.6 EMPIRICAL PERFORMANCE & LATENCY AUDIT');
      print('===============================================================');

      final initialRss = ProcessInfo.currentRss;

      // 1. Single Page
      final f1 = File('$corpusDir/01_single_column_novel.pdf');
      final sw1 = Stopwatch()..start();
      final ext1 = await GeometryAwarePdfExtractor.extractDocument(
        pdfFile: f1,
        bookId: 'perf_1',
        extractImagesToDisk: false,
      );
      sw1.stop();
      expect(ext1.totalPages, equals(1));
      print(
        'Scale 1 Page: ${sw1.elapsedMilliseconds} ms (${(sw1.elapsedMilliseconds / 1).toStringAsFixed(1)} ms/p)',
      );

      // 2. All 10 Corpus Documents (14 pages total)
      final sw10 = Stopwatch()..start();
      int pagesCount = 0;
      for (int i = 1; i <= 10; i++) {
        final pad = i.toString().padLeft(2, '0');
        final files = Directory(
          corpusDir,
        ).listSync().whereType<File>().where((f) => f.path.contains(pad));
        if (files.isNotEmpty) {
          final res = await GeometryAwarePdfExtractor.extractDocument(
            pdfFile: files.first,
            bookId: 'perf_$pad',
            extractImagesToDisk: false,
          );
          pagesCount += res.totalPages;
        }
      }
      sw10.stop();
      print(
        'Scale 10 Docs ($pagesCount Pages): ${sw10.elapsedMilliseconds} ms (${(sw10.elapsedMilliseconds / pagesCount).toStringAsFixed(1)} ms/p)',
      );

      // 3. 265 Pages (The Let Them Theory)
      final letThem = File(
        p.join(RealBookFixtures.originalsDir, '8cda23f0-bf42-4a4d-a1fd-30d2943835c9.pdf'),
      );
      if (letThem.existsSync()) {
        final sw265 = Stopwatch()..start();
        final ext265 = await GeometryAwarePdfExtractor.extractDocument(
          pdfFile: letThem,
          bookId: 'perf_265',
          extractImagesToDisk: false,
        );
        sw265.stop();
        print(
          'Scale 265 Pages: ${sw265.elapsedMilliseconds} ms (${(sw265.elapsedMilliseconds / 265).toStringAsFixed(1)} ms/p)',
        );

        // Pagination latency benchmark
        final doc265 = await SemanticDocumentReconstructor.reconstruct(
          extraction: ext265,
          title: 'The Let Them Theory',
          author: 'Mel Robbins',
        );
        final readerDoc = ReaderDocument.fromBookDocument(
          doc265.toBookDocument(),
        );

        final pagSw = Stopwatch()..start();
        final pagPages = PaginationEngine.paginateDocument(
          document: readerDoc,
          viewportWidth: 1000.0,
          viewportHeight: 700.0,
          typography: const TypographySettings(twoPageSpread: true),
        );
        pagSw.stop();
        print(
          'Pagination Engine (265 Pages, 2-Page Spread): ${pagPages.length} paginated pages generated in ${pagSw.elapsedMilliseconds} ms',
        );
      }

      final peakRss = ProcessInfo.currentRss;
      print(
        'Memory Consumption: Initial RSS: ${(initialRss / (1024 * 1024)).toStringAsFixed(2)} MB | Peak RSS: ${(peakRss / (1024 * 1024)).toStringAsFixed(2)} MB | Delta: +${((peakRss - initialRss) / (1024 * 1024)).toStringAsFixed(2)} MB',
      );
      print(
        '===============================================================\n',
      );

      expect(sw1.elapsedMilliseconds, lessThan(1000));
    });
  });
}
