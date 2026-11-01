// ignore_for_file: avoid_print, depend_on_referenced_packages

import 'dart:io';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/core/utils/file_storage_service.dart';
import 'package:digital_books/features/processing/services/apple_vision_ocr_service.dart';
import 'package:digital_books/features/processing/services/background_ocr_queue.dart';
import 'package:digital_books/features/processing/services/ocr_semantic_pipeline.dart';
import 'package:digital_books/features/reader/models/book_document.dart';

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

  late Directory tempAppDir;
  late AppDatabase db;
  late DatabaseService dbService;
  late AppleVisionOcrService ocrService;
  late OcrSemanticPipeline pipeline;
  late BackgroundOcrQueue queue;

  final lautPdf = File(
    '/Users/davindalana/Downloads/Laut Bercerita (Leila S. Chudori).pdf',
  );

  setUp(() async {
    tempAppDir = Directory.systemTemp.createTempSync('digital_books_ocr_test_');
    PathProviderPlatform.instance = MockPathProviderPlatform(tempAppDir);

    db = AppDatabase(NativeDatabase.memory());
    dbService = DatabaseService(db);
    ocrService = const AppleVisionOcrService();
    pipeline = OcrSemanticPipeline(dbService);
    queue = BackgroundOcrQueue(
      dbService: dbService,
      ocrService: ocrService,
      semanticPipeline: pipeline,
    );

    // Seed test book in DB
    await dbService.insertBook(
      BooksCompanion(
        id: const Value('book_semantic_test'),
        title: const Value('Laut Bercerita'),
        author: const Value('Leila S. Chudori'),
        originalPdfPath: Value(lautPdf.path),
        totalPages: const Value(379),
        isScanned: const Value(true),
        createdAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  });

  tearDown(() async {
    queue.dispose();
    await db.close();
    try {
      tempAppDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('Phase 3.1 Checkpoint D: OCR Semantic Pipeline & BookDocument Reconstruction', () {
    test('Processes pages 14-16, synthesizes BookDocument, and updates DB & disk', () async {
      expect(lautPdf.existsSync(), isTrue);

      // 1. Run queue on pages 14, 15, 16 with autoReconstruct = true
      await queue.start(
        bookId: 'book_semantic_test',
        pdfPath: lautPdf.path,
        startPage: 14,
        endPage: 16,
        autoReconstruct: true,
      );

      print('DEBUG: Queue status: ${queue.state.status}');
      if (queue.state.errorMessage != null) {
        print('DEBUG: Queue error: ${queue.state.errorMessage}');
      }

      // 2. Verify book in DB now has processedBookPath
      final updatedBook = await dbService.getBookById('book_semantic_test');
      expect(updatedBook, isNotNull);
      expect(updatedBook!.processedBookPath, isNotNull);
      final jsonPath = updatedBook.processedBookPath!;
      expect(File(jsonPath).existsSync(), isTrue);

      // 3. Read and deserialize BookDocument from disk
      final jsonContent = await FileStorageService.readProcessedBook(jsonPath);
      expect(jsonContent, isNotNull);
      final bookDoc = BookDocument.fromJsonString(jsonContent!);

      // 4. Verify semantic structure
      expect(bookDoc.title, equals('Laut Bercerita'));
      expect(bookDoc.author, equals('Leila S. Chudori'));
      expect(bookDoc.chapters.isNotEmpty, isTrue);

      // Total blocks across all chapters
      final allBlocks = bookDoc.chapters.expand((c) => c.blocks).toList();
      expect(allBlocks.isNotEmpty, isTrue);

      // Check original page number bindings (should be 15, 16, or 17)
      final pageNumbers = allBlocks.map((b) => b.originalPageNumber).toSet();
      expect(pageNumbers.any((p) => p == 15), isTrue);

      // Check text content quality: should have real Indonesian words
      final fullText = allBlocks.map((b) => b.text).join(' ');
      expect(fullText, contains('mobil'));
      expect(fullText, contains('kami'));

      // Check chapter persistence in DB
      final dbChapters = await dbService.getChaptersForBook('book_semantic_test');
      expect(dbChapters.isNotEmpty, isTrue);
      expect(dbChapters.first.title, isNotEmpty);

      // 5. Verify provenance metadata
      expect(bookDoc.metadata['ocrSource'], equals('apple_vision_offline'));
      expect(bookDoc.metadata['ocrCompletedPages'], equals(3));
      expect(bookDoc.metadata.containsKey('reconstructionQuality'), isTrue);

      print('\n===============================================================');
      print('CHECKPOINT D: SEMANTIC BOOK RECONSTRUCTION AUDIT');
      print('===============================================================');
      print('Chapters created: ${bookDoc.chapters.length}');
      print('Total semantic blocks: ${allBlocks.length}');
      print('Original page anchors: $pageNumbers');
      print('Saved JSON path: $jsonPath (${File(jsonPath).lengthSync()} bytes)');
      print('First block sample: "${allBlocks.first.text.substring(0, allBlocks.first.text.length.clamp(0, 80))}..."');
    });
  });
}
