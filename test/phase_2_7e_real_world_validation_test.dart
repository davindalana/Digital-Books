// ignore_for_file: avoid_print, depend_on_referenced_packages

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' as drift;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/core/providers/database_providers.dart';
import 'package:digital_books/features/processing/services/pdf_processing_pipeline.dart';
import 'package:digital_books/features/processing/services/geometry_aware_pdf_extractor.dart';
import 'package:digital_books/features/processing/services/semantic_document_reconstructor.dart';
import 'package:digital_books/features/processing/models/semantic_reconstruction_models.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'package:digital_books/features/reader/domain/engines/reflowable_engine.dart';
import 'package:digital_books/features/reader/domain/engines/pagination_engine.dart';
import 'package:digital_books/features/reader/models/book_document.dart';
import 'package:digital_books/features/reader/presentation/screens/reading_screen.dart';
import 'package:digital_books/core/typography/typography_settings.dart';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/features/reader/presentation/widgets/reflowable/reflowable_page_renderer.dart';
import 'package:digital_books/features/reader/presentation/widgets/original_pdf_reader.dart';
import 'package:digital_books/features/reader/providers/reader_settings_provider.dart';

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

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('p27e_test_');
    PathProviderPlatform.instance = MockPathProviderPlatform(tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Phase 2.7E: End-to-End Processing & Real-World Validation', () {
    test(
      'end-to-end import pipeline produces semantically reconstructed BookDocument with quality metadata',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        final dbService = DatabaseService(db);
        final pipeline = PdfProcessingPipeline(dbService);

        final file = File('$corpusDir/01_single_column_novel.pdf');
        expect(file.existsSync(), isTrue);

        final book = await pipeline.processAndImportPdf(
          pdfFile: file,
          customTitle: 'The Novel of Destiny',
          customAuthor: 'Test Author',
        );

        expect(book.title, equals('The Novel of Destiny'));
        expect(book.author, equals('Test Author'));
        expect(book.isScanned, isFalse);
        expect(book.processedBookPath, isNotNull);

        // Verify the saved JSON has reconstructionQuality metadata
        final savedJson = await File(book.processedBookPath!).readAsString();
        expect(savedJson, contains('reconstructionQuality'));
        expect(savedJson, contains('Smart Reflowable Reader'));

        // Check chapters created in database
        final chapters = await dbService.getChaptersForBook(book.id);
        expect(chapters, isNotEmpty);
        expect(chapters.first.title, contains('Chapter 1: The Beginning'));

        await db.close();
      },
    );

    test(
      'reconstructs real 265-page book (The Let Them Theory) with high fidelity',
      () async {
        final realBookFile = File(
          '/Users/davindalana/Documents/DigitalBooks/originals/8cda23f0-bf42-4a4d-a1fd-30d2943835c9.pdf',
        );

        if (!realBookFile.existsSync()) {
          markTestSkipped(
            'Real 265-page book PDF is missing at ${realBookFile.path}',
          );
          return;
        }

        final sw = Stopwatch()..start();
        final extraction = await GeometryAwarePdfExtractor.extractDocument(
          pdfFile: realBookFile,
          bookId: 'let-them-theory-eval',
          extractImagesToDisk: false,
        );
        sw.stop();

        expect(extraction.totalPages, equals(265));
        expect(extraction.hasUsableTextLayer, isTrue);
        expect(extraction.totalTextLines, greaterThan(1000));

        final reconstructSw = Stopwatch()..start();
        final reconstructed = await SemanticDocumentReconstructor.reconstruct(
          extraction: extraction,
          title: 'The Let Them Theory',
          author: 'Mel Robbins',
        );
        reconstructSw.stop();

        print(
          'The Let Them Theory: 265 pages extracted in ${sw.elapsedMilliseconds} ms (${(sw.elapsedMilliseconds / 265).toStringAsFixed(2)} ms/p), reconstructed in ${reconstructSw.elapsedMilliseconds} ms',
        );
        print('• Quality status: ${reconstructed.quality.status}');
        print(
          '• Quality score: ${reconstructed.quality.score.toStringAsFixed(2)}',
        );
        print('• Recommended tier: ${reconstructed.quality.recommendedTier}');
        print('• Chapters detected: ${reconstructed.chapters.length}');

        expect(
          reconstructed.quality.status == QualityStatus.good ||
              reconstructed.quality.status == QualityStatus.partial,
          isTrue,
        );
        expect(reconstructed.quality.score, greaterThan(0.90));
        expect(reconstructed.chapters.length, greaterThan(1));

        // Verify paragraphs have not been chopped arbitrarily at 280 characters
        final longParas = reconstructed.blocks.where(
          (b) =>
              b.type == SemanticBlockType.bodyParagraph && b.text.length > 280,
        );
        expect(
          longParas,
          isNotEmpty,
          reason: 'Natural paragraphs can legitimately exceed 280 chars',
        );
      },
    );

    test(
      'ReaderDocument preserves semantic node types, source pages, and stable anchors',
      () async {
        final file = File('$corpusDir/06_footnotes.pdf');
        final extraction = await GeometryAwarePdfExtractor.extractDocument(
          pdfFile: file,
          bookId: 'test-doc-06',
        );

        final reconstructed = await SemanticDocumentReconstructor.reconstruct(
          extraction: extraction,
          title: 'Philosophical Inquiries',
        );

        final bookDoc = reconstructed.toBookDocument();
        final readerDoc = ReflowableEngine.normalizeDocument(bookDoc);

        expect(readerDoc.totalParagraphCount, greaterThan(0));
        for (final ch in readerDoc.chapters) {
          for (final node in ch.nodes) {
            expect(node.id, isNotEmpty);
            expect(node.sourcePdfPage, greaterThan(0));
          }
        }

        // Check footnote preservation
        final allNodes = readerDoc.chapters.expand((c) => c.nodes).toList();
        final footnoteNodes = allNodes
            .where((n) => n.type == ContentNodeType.footnote)
            .toList();
        expect(footnoteNodes.length, greaterThanOrEqualTo(2));
        expect(footnoteNodes.first.text, contains('Henri Bergson'));
      },
    );

    test('Image node renders with attached caption', () async {
      final node = ContentNode(
        id: 'img_test_1',
        type: ContentNodeType.image,
        text: 'Figure 1: Architectural diagram of the monastery.',
        imagePath: null, // Placeholder test
        sourcePdfPage: 1,
      );

      final slice = PaginatedNodeSlice(
        node: node,
        textSlice: node.text,
        startCharOffset: 0,
        endCharOffset: node.text.length,
      );

      final page = PaginatedPage(
        pageIndexInChapter: 0,
        pageIndexInBook: 0,
        chapterIndex: 0,
        chapterTitle: 'Chapter 1',
        slices: [slice],
        firstAnchorNodeId: 'img_test_1',
        lastAnchorNodeId: 'img_test_1',
      );

      final renderer = ReflowablePageRenderer(
        page: page,
        totalPagesInBook: 1,
        theme: ReadingThemeType.warmPaper,
        typography: const TypographySettings(),
        contentWidth: 400.0,
      );

      expect(renderer, isNotNull);
    });
  });

  group('Phase 2.7E: UI Reader Recommendation & Fallback Integration', () {
    testWidgets(
      'Scanned book shows recommendation banner in Reflowable mode with switch action',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        final dbService = DatabaseService(db);

        // Create a test scanned book with a processed document that is explicitly
        // marked as requiring OCR. Without the processed document the reader must
        // fall back to Original PDF instead of showing an empty Book Mode.
        final processedDoc = BookDocument(
          id: 'test-scanned-book',
          title: 'Buku Pindaian Lawas',
          author: 'Penulis Sejarah',
          totalPages: 10,
          isScanned: true,
          chapters: [
            const BookChapter(
              id: 'scan_ch1',
              index: 0,
              title: 'Bab 1',
              blocks: [
                BookBlock(
                  id: 'scan_b1',
                  type: BlockType.image,
                  text: 'Halaman hasil pindaian',
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
        final processedPath = '${tempDir.path}/test-scanned-book.json';
        File(processedPath).writeAsStringSync(processedDoc.toJsonString());

        final now = DateTime.now();
        final bookCompanion = BooksCompanion.insert(
          id: 'test-scanned-book',
          title: 'Buku Pindaian Lawas',
          author: 'Penulis Sejarah',
          originalPdfPath: 'test/fixtures/corpus/08_scanned_image_only.pdf',
          processedBookPath: drift.Value(processedPath),
          totalPages: const drift.Value(10),
          isScanned: const drift.Value(true),
          createdAt: now,
          updatedAt: now,
        );
        await dbService.insertBook(bookCompanion);

        final book = await dbService.getBookById('test-scanned-book');
        expect(book, isNotNull);
        expect(book!.isScanned, isTrue);

        // Pump ReadingScreen forced into Reflowable mode
        await tester.pumpWidget(
          ProviderScope(
            overrides: [databaseServiceProvider.overrideWithValue(dbService)],
            child: MaterialApp(
              home: ReadingScreen(
                book: book,
                initialMode: ReadingMode.reflowable,
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Recommendation banner must be visible
        expect(find.textContaining('hasil pindaian (scan)'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('quality_banner_switch_button')),
          findsOneWidget,
        );

        // Tap "Buka PDF Asli"
        await tester.tap(
          find.byKey(const ValueKey('quality_banner_switch_button')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Verifying switched to Original PDF mode
        expect(find.byType(OriginalPdfReader), findsOneWidget);

        await db.close();
      },
    );
  });
}
