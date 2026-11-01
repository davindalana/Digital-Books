import 'dart:convert';
import 'dart:ui' show Rect;
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/features/processing/models/ocr_page_result.dart';

void main() {
  late AppDatabase db;
  late DatabaseService dbService;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dbService = DatabaseService(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('Phase 3.1 Checkpoint B: OCR Persistence & Drift Schema v4', () {
    test('Database schema version is 4', () {
      expect(db.schemaVersion, equals(4));
    });

    test('Can insert, query, update, and delete OcrPage records', () async {
      final now = DateTime.now();
      // Insert a test book first to satisfy foreign key
      await dbService.insertBook(
        BooksCompanion(
          id: const Value('book_ocr_test_1'),
          title: const Value('Laut Bercerita'),
          author: const Value('Leila S. Chudori'),
          originalPdfPath: const Value('/path/to/test.pdf'),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      final dummyLines = [
        const OcrLine(
          text: 'Malam itu, di sebuah rumah sepi di pinggir kota...',
          confidence: 0.998,
          box: Rect.fromLTWH(0.1, 0.15, 0.8, 0.03),
        ),
        const OcrLine(
          text: 'Kami mendengar suara derit ban mengerem mendadak.',
          confidence: 0.995,
          box: Rect.fromLTWH(0.1, 0.19, 0.78, 0.03),
        ),
      ];

      final linesJson = jsonEncode(dummyLines.map((l) => l.toJson()).toList());

      // 1. Insert page 0
      await dbService.insertOcrPage(
        OcrPagesCompanion(
          id: const Value('book_ocr_test_1_0'),
          bookId: const Value('book_ocr_test_1'),
          pageIndex: const Value(0),
          status: const Value('completed'),
          confidence: const Value(0.9965),
          charCount: const Value(96),
          durationMs: const Value(245.5),
          linesJson: Value(linesJson),
          createdAt: Value(now),
        ),
      );

      // 2. Insert page 1
      await dbService.insertOcrPage(
        OcrPagesCompanion(
          id: const Value('book_ocr_test_1_1'),
          bookId: const Value('book_ocr_test_1'),
          pageIndex: const Value(1),
          status: const Value('completed'),
          confidence: const Value(0.999),
          charCount: const Value(150),
          durationMs: const Value(210.0),
          linesJson: Value(linesJson),
          createdAt: Value(now),
        ),
      );

      // 3. Query single page
      final page0 = await dbService.getOcrPage('book_ocr_test_1', 0);
      expect(page0, isNotNull);
      expect(page0!.pageIndex, equals(0));
      expect(page0.confidence, closeTo(0.9965, 0.001));
      expect(page0.charCount, equals(96));

      // Deserialize lines
      final decodedLines = (jsonDecode(page0.linesJson) as List)
          .map((item) => OcrLine.fromJson(item as Map<String, dynamic>))
          .toList();
      expect(decodedLines.length, equals(2));
      expect(decodedLines.first.text, startsWith('Malam itu'));

      // 4. Query all pages for book ordered by pageIndex
      final pages = await dbService.getOcrPagesForBook('book_ocr_test_1');
      expect(pages.length, equals(2));
      expect(pages[0].pageIndex, equals(0));
      expect(pages[1].pageIndex, equals(1));

      // 5. Query count of completed pages
      final count = await dbService.getCompletedOcrPageCount('book_ocr_test_1');
      expect(count, equals(2));

      // 6. Test upsert / update page on conflict
      await dbService.insertOcrPage(
        OcrPagesCompanion(
          id: const Value('book_ocr_test_1_0'),
          bookId: const Value('book_ocr_test_1'),
          pageIndex: const Value(0),
          status: const Value('completed'),
          confidence: const Value(1.0),
          charCount: const Value(120),
          durationMs: const Value(190.0),
          linesJson: Value(linesJson),
          createdAt: Value(now),
        ),
      );

      final updatedPage0 = await dbService.getOcrPage('book_ocr_test_1', 0);
      expect(updatedPage0!.confidence, equals(1.0));
      expect(updatedPage0.charCount, equals(120));

      // 7. Test delete pages for book
      final deleted = await dbService.deleteOcrPagesForBook('book_ocr_test_1');
      expect(deleted, equals(2));
      final remaining = await dbService.getOcrPagesForBook('book_ocr_test_1');
      expect(remaining, isEmpty);
    });

    test('Cascading delete: deleting a book removes all its OCR pages', () async {
      final now = DateTime.now();
      await dbService.insertBook(
        BooksCompanion(
          id: const Value('book_ocr_cascade'),
          title: const Value('Cascade Test Book'),
          author: const Value('Author'),
          originalPdfPath: const Value('/path/cascade.pdf'),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      await dbService.insertOcrPage(
        OcrPagesCompanion(
          id: const Value('book_ocr_cascade_0'),
          bookId: const Value('book_ocr_cascade'),
          pageIndex: const Value(0),
          status: const Value('completed'),
          linesJson: const Value('[]'),
          createdAt: Value(now),
        ),
      );

      final before = await dbService.getOcrPagesForBook('book_ocr_cascade');
      expect(before.length, equals(1));

      // Delete the book
      await (db.delete(db.books)..where((t) => t.id.equals('book_ocr_cascade'))).go();

      final after = await dbService.getOcrPagesForBook('book_ocr_cascade');
      expect(after, isEmpty);
    });
  });
}
