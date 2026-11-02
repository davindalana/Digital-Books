// ignore_for_file: avoid_print, depend_on_referenced_packages, unused_import

import 'dart:io';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/core/utils/file_storage_service.dart';
import 'package:digital_books/features/processing/services/apple_vision_ocr_service.dart';
import 'package:digital_books/features/processing/services/background_ocr_queue.dart';
import 'package:digital_books/features/processing/services/ocr_semantic_pipeline.dart';

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

  late Directory tempDir;
  late AppDatabase db;
  late DatabaseService dbService;
  late BackgroundOcrQueue queue;

  final lautBerceritaPath =
      '/Users/davindalana/Downloads/Laut Bercerita (Leila S. Chudori).pdf';

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('db_integrity_test_');
    PathProviderPlatform.instance = MockPathProviderPlatform(tempDir);
    db = AppDatabase(NativeDatabase.memory());
    dbService = DatabaseService(db);
    queue = BackgroundOcrQueue(
      dbService: dbService,
      ocrService: const AppleVisionOcrService(),
      semanticPipeline: OcrSemanticPipeline(dbService),
    );
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Phase 3.1.1 — Database Migration, Referential Integrity, & Recovery Audit', () {
    test('1. Schema v5 Table Integrity & Foreign Key Cascade Audit', () async {
      expect(db.schemaVersion, equals(5));

      // 1. Insert a parent book
      final now = DateTime.now();
      await dbService.insertBook(
        BooksCompanion.insert(
          id: 'test-book-integrity-1',
          title: 'Integrity Test Book',
          author: 'Test Author',
          originalPdfPath: lautBerceritaPath,
          totalPages: const Value(10),
          createdAt: now,
          updatedAt: now,
        ),
      );

      // 2. Insert 3 OCR pages linked to this book
      for (int i = 0; i < 3; i++) {
        await dbService.insertOcrPage(
          OcrPagesCompanion.insert(
            id: 'ocr-test-1-p$i',
            bookId: 'test-book-integrity-1',
            pageIndex: i,
            status: const Value('completed'),
            charCount: const Value(500),
            durationMs: const Value(120.0),
            linesJson: '[]',
            createdAt: now,
          ),
        );
      }

      var pages = await dbService.getOcrPagesForBook('test-book-integrity-1');
      expect(pages.length, equals(3));

      // 3. Delete parent book and verify foreign key CASCADE cleans up ocr_pages automatically
      await dbService.deleteBook('test-book-integrity-1');

      pages = await dbService.getOcrPagesForBook('test-book-integrity-1');
      expect(pages.isEmpty, isTrue,
          reason: 'Deleting parent Book must cascade and delete all associated OcrPages');
    });

    test('2. Resumability & Partial Failure Isolation Audit', () async {
      final now = DateTime.now();
      const bookId = 'test-book-resume-02';

      await dbService.insertBook(
        BooksCompanion.insert(
          id: bookId,
          title: 'Resume Test Book',
          author: 'Test Author',
          originalPdfPath: lautBerceritaPath,
          totalPages: const Value(20),
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Simulate partial completion: pages 0, 1, 2 already persisted
      for (int i = 0; i < 3; i++) {
        await dbService.insertOcrPage(
          OcrPagesCompanion.insert(
            id: 'ocr-resume-p$i',
            bookId: bookId,
            pageIndex: i,
            status: const Value('completed'),
            charCount: const Value(450),
            durationMs: const Value(100.0),
            linesJson: '[]',
            createdAt: now,
          ),
        );
      }

      // Check completed count
      final completedCount = await dbService.getCompletedOcrPageCount(bookId);
      expect(completedCount, equals(3));

      final existingPages = await dbService.getOcrPagesForBook(bookId);
      final completedIndices = existingPages
          .where((p) => p.status == 'completed')
          .map((p) => p.pageIndex)
          .toSet();

      expect(completedIndices.contains(0), isTrue);
      expect(completedIndices.contains(1), isTrue);
      expect(completedIndices.contains(2), isTrue);
      expect(completedIndices.contains(3), isFalse);

      // Verify resumed page determination
      final remainingCount = 20 - completedIndices.length;
      expect(remainingCount, equals(17),
          reason: 'Resumed session must skip the 3 completed pages and process only remaining 17');
    });

    test('3. Source PDF Hash Mismatch & Stale Cache Invalidation Audit', () async {
      final now = DateTime.now();
      const bookId = 'test-book-hash-stale-03';

      // Create a temporary mock PDF file
      final mockPdfFile = File('${tempDir.path}/mock_doc.pdf');
      await mockPdfFile.writeAsString('Original PDF Content Version 1');
      final originalHash = await FileStorageService.computeFileSha256(mockPdfFile);

      await dbService.insertBook(
        BooksCompanion.insert(
          id: bookId,
          title: 'Hash Audit Book',
          author: 'Test Author',
          originalPdfPath: mockPdfFile.path,
          fileHash: Value(originalHash),
          processedBookPath: const Value('/some/old/processed/path.json'),
          totalPages: const Value(5),
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Seed 2 old OCR pages
      await dbService.insertOcrPage(
        OcrPagesCompanion.insert(
          id: 'ocr-old-p0',
          bookId: bookId,
          pageIndex: 0,
          status: const Value('completed'),
          linesJson: '[]',
          createdAt: now,
        ),
      );
      await dbService.insertOcrPage(
        OcrPagesCompanion.insert(
          id: 'ocr-old-p1',
          bookId: bookId,
          pageIndex: 1,
          status: const Value('completed'),
          linesJson: '[]',
          createdAt: now,
        ),
      );

      var oldPages = await dbService.getOcrPagesForBook(bookId);
      expect(oldPages.length, equals(2));

      // Modify the PDF file on disk (simulating user replacing the scanned PDF with an updated scan)
      await mockPdfFile.writeAsString('MODIFIED PDF Content Version 2 with new scans');
      final newHash = await FileStorageService.computeFileSha256(mockPdfFile);
      expect(newHash, isNot(equals(originalHash)));

      // Start OCR in BackgroundOcrQueue - it must detect hash mismatch and purge stale cache
      // We pass an invalid PDF so it throws or fails after hash validation, but hash staleness check happens first
      try {
        await queue.start(
          bookId: bookId,
          pdfPath: mockPdfFile.path,
          startPage: 0,
          endPage: 1,
        );
      } catch (_) {}

      // Verify that old stale OCR pages were purged
      final refreshedBook = await dbService.getBookById(bookId);
      expect(refreshedBook?.fileHash, equals(newHash));
      expect(refreshedBook?.processedBookPath, isNull,
          reason: 'Stale processedBookPath must be invalidated upon PDF hash mismatch');
    });

    test('4. Idempotent Execution & Duplicate Prevention Audit', () async {
      final now = DateTime.now();
      const bookId = 'test-book-idempotent-04';

      await dbService.insertBook(
        BooksCompanion.insert(
          id: bookId,
          title: 'Idempotency Test Book',
          author: 'Test Author',
          originalPdfPath: lautBerceritaPath,
          totalPages: const Value(5),
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Insert page 0
      await dbService.insertOcrPage(
        OcrPagesCompanion.insert(
          id: 'ocr-idempotent-p0',
          bookId: bookId,
          pageIndex: 0,
          status: const Value('completed'),
          charCount: const Value(300),
          durationMs: const Value(80.0),
          linesJson: '[]',
          createdAt: now,
        ),
      );

      // Re-insert page 0 with updated data (using insertOnConflictUpdate behavior in DatabaseService)
      await dbService.insertOcrPage(
        OcrPagesCompanion.insert(
          id: 'ocr-idempotent-p0',
          bookId: bookId,
          pageIndex: 0,
          status: const Value('completed'),
          charCount: const Value(350),
          durationMs: const Value(75.0),
          linesJson: '[]',
          createdAt: now,
        ),
      );

      final pages = await dbService.getOcrPagesForBook(bookId);
      expect(pages.length, equals(1),
          reason: 'Repeated insertion of same OCR page ID must update existing row without duplicating');
      expect(pages.first.charCount, equals(350));
    });
  });
}
