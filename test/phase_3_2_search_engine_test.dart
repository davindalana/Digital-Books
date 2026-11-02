import 'dart:convert';
import 'dart:ui' show Rect;
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/features/reader/domain/engines/in_book_search_engine.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';
import 'package:digital_books/features/reader/domain/models/search_geometry.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late DatabaseService dbService;

  const testBookId = 'test_book_search_123';

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dbService = DatabaseService(db);

    // Create parent book record to satisfy foreign key
    await dbService.insertBook(
      BooksCompanion(
        id: const drift.Value(testBookId),
        title: const drift.Value('Buku Uji Pencarian'),
        author: const drift.Value('Penulis Uji'),
        originalPdfPath: const drift.Value('/dummy/test.pdf'),
        fileHash: const drift.Value('dummyhash'),
        totalPages: const drift.Value(3),
        createdAt: drift.Value(DateTime.now()),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('Phase 3.2 — InBookSearchEngine & Full-Text Search Core', () {
    test('1. Exact word & Substring search (Case-insensitive)', () async {
      final tokens = [
        const SearchTokenGeometry(
          text: 'Laut',
          start: 0,
          end: 4,
          box: Rect.fromLTWH(0.1, 0.2, 0.15, 0.05),
        ),
        const SearchTokenGeometry(
          text: 'Bercerita',
          start: 5,
          end: 14,
          box: Rect.fromLTWH(0.3, 0.2, 0.25, 0.05),
        ),
      ];

      await dbService.insertSearchPage(
        BookSearchPagesCompanion(
          id: const drift.Value('${testBookId}_p0'),
          bookId: const drift.Value(testBookId),
          pageIndex: const drift.Value(0),
          plainText: const drift.Value('Laut Bercerita'),
          rawText: const drift.Value('Laut Bercerita'),
          geometryJson: drift.Value(
            jsonEncode(tokens.map((t) => t.toJson()).toList()),
          ),
          isOcr: const drift.Value(false),
          indexVersion: const drift.Value(1),
          indexedAt: drift.Value(DateTime.now()),
        ),
      );

      // Lowercase search
      final res1 = await InBookSearchEngine.searchIndexedBook(
        bookId: testBookId,
        dbService: dbService,
        query: 'laut',
      );
      expect(res1.length, equals(1));
      expect(res1.first.matchedText, equals('Laut'));
      expect(res1.first.sourcePdfPage, equals(1)); // 1-based page
      expect(res1.first.boundingBoxes.length, equals(1));
      expect(res1.first.boundingBoxes.first, equals(const Rect.fromLTWH(0.1, 0.2, 0.15, 0.05)));

      // Substring search
      final res2 = await InBookSearchEngine.searchIndexedBook(
        bookId: testBookId,
        dbService: dbService,
        query: 'cerita',
      );
      expect(res2.length, equals(1));
      expect(res2.first.matchedText, equals('cerita'));
      expect(res2.first.boundingBoxes.length, equals(1));
    });

    test('2. Phrase search with whitespace normalization', () async {
      await dbService.insertSearchPage(
        BookSearchPagesCompanion(
          id: const drift.Value('${testBookId}_p0'),
          bookId: const drift.Value(testBookId),
          pageIndex: const drift.Value(0),
          plainText: const drift.Value('Kamar itu terasa sangat dingin di malam hari.'),
          rawText: const drift.Value('Kamar itu terasa sangat dingin di malam hari.'),
          geometryJson: const drift.Value('[]'),
          isOcr: const drift.Value(false),
          indexVersion: const drift.Value(1),
          indexedAt: drift.Value(DateTime.now()),
        ),
      );

      // Search with extra spaces and newline in query
      final results = await InBookSearchEngine.searchIndexedBook(
        bookId: testBookId,
        dbService: dbService,
        query: '  sangat   dingin \n di  ',
      );
      expect(results.length, equals(1));
      expect(results.first.matchedText, equals('sangat dingin di'));
    });

    test('3. Dehyphenation across line breaks with dual token bounding boxes', () async {
      // Line 1: 'men-' at box1, Line 2: 'jadi' at box2 -> PlainText: 'menjadi'
      const box1 = Rect.fromLTWH(0.8, 0.3, 0.15, 0.04);
      const box2 = Rect.fromLTWH(0.1, 0.35, 0.18, 0.04);

      final tokens = [
        const SearchTokenGeometry(text: 'men', start: 0, end: 3, box: box1),
        const SearchTokenGeometry(text: 'jadi', start: 3, end: 7, box: box2),
      ];

      await dbService.insertSearchPage(
        BookSearchPagesCompanion(
          id: const drift.Value('${testBookId}_p0'),
          bookId: const drift.Value(testBookId),
          pageIndex: const drift.Value(0),
          plainText: const drift.Value('menjadi kenyataan'),
          rawText: const drift.Value('men-\njadi kenyataan'),
          geometryJson: drift.Value(
            jsonEncode(tokens.map((t) => t.toJson()).toList()),
          ),
          isOcr: const drift.Value(true),
          indexVersion: const drift.Value(1),
          indexedAt: drift.Value(DateTime.now()),
        ),
      );

      // Search for unhyphenated word
      final res1 = await InBookSearchEngine.searchIndexedBook(
        bookId: testBookId,
        dbService: dbService,
        query: 'menjadi',
      );
      expect(res1.length, equals(1));
      expect(res1.first.matchedText, equals('menjadi'));
      expect(res1.first.boundingBoxes.length, equals(2));
      expect(res1.first.boundingBoxes[0], equals(box1));
      expect(res1.first.boundingBoxes[1], equals(box2));

      // Search for hyphenated query variant "men-jadi"
      final res2 = await InBookSearchEngine.searchIndexedBook(
        bookId: testBookId,
        dbService: dbService,
        query: 'men-jadi',
      );
      expect(res2.length, equals(1));
      expect(res2.first.matchedText, equals('menjadi'));
      expect(res2.first.boundingBoxes.length, equals(2));
    });

    test('4. Cross-page phrase search across page boundary', () async {
      const boxPage0 = Rect.fromLTWH(0.7, 0.9, 0.25, 0.04);
      const boxPage1 = Rect.fromLTWH(0.1, 0.1, 0.28, 0.04);

      // Page 0 ends with "Laut"
      await dbService.insertSearchPage(
        BookSearchPagesCompanion(
          id: const drift.Value('${testBookId}_p0'),
          bookId: const drift.Value(testBookId),
          pageIndex: const drift.Value(0),
          plainText: const drift.Value('Di kedalaman Laut'),
          rawText: const drift.Value('Di kedalaman Laut'),
          geometryJson: drift.Value(
            jsonEncode([
              const SearchTokenGeometry(
                text: 'Laut',
                start: 13,
                end: 17,
                box: boxPage0,
              ).toJson(),
            ]),
          ),
          isOcr: const drift.Value(true),
          indexVersion: const drift.Value(1),
          indexedAt: drift.Value(DateTime.now()),
        ),
      );

      // Page 1 begins with "Bercerita"
      await dbService.insertSearchPage(
        BookSearchPagesCompanion(
          id: const drift.Value('${testBookId}_p1'),
          bookId: const drift.Value(testBookId),
          pageIndex: const drift.Value(1),
          plainText: const drift.Value('Bercerita tentang mereka'),
          rawText: const drift.Value('Bercerita tentang mereka'),
          geometryJson: drift.Value(
            jsonEncode([
              const SearchTokenGeometry(
                text: 'Bercerita',
                start: 0,
                end: 9,
                box: boxPage1,
              ).toJson(),
            ]),
          ),
          isOcr: const drift.Value(true),
          indexVersion: const drift.Value(1),
          indexedAt: drift.Value(DateTime.now()),
        ),
      );

      final results = await InBookSearchEngine.searchIndexedBook(
        bookId: testBookId,
        dbService: dbService,
        query: 'Laut Bercerita',
      );

      expect(results.length, equals(1));
      final r = results.first;
      expect(r.isCrossPage, isTrue);
      expect(r.matchedText, equals('Laut Bercerita'));
      expect(r.sourcePdfPage, equals(1)); // Primary page 1
      expect(r.boundingBoxes.length, equals(2));
      expect(r.boundingBoxes[0], equals(boxPage0));
      expect(r.boundingBoxes[1], equals(boxPage1));
    });

    test('5. Chrome filtering (Running headers & Standalone page numbers)', () async {
      final tokens = [
        // Running header chrome
        const SearchTokenGeometry(
          text: 'BAB I',
          start: 0,
          end: 5,
          box: Rect.fromLTWH(0.4, 0.02, 0.2, 0.03),
          isChrome: true,
        ),
        // Content
        const SearchTokenGeometry(
          text: 'BAB ini menceritakan kisah',
          start: 6,
          end: 32,
          box: Rect.fromLTWH(0.1, 0.2, 0.6, 0.04),
          isChrome: false,
        ),
      ];

      await dbService.insertSearchPage(
        BookSearchPagesCompanion(
          id: const drift.Value('${testBookId}_p0'),
          bookId: const drift.Value(testBookId),
          pageIndex: const drift.Value(0),
          plainText: const drift.Value('BAB I BAB ini menceritakan kisah'),
          rawText: const drift.Value('BAB I\nBAB ini menceritakan kisah'),
          geometryJson: drift.Value(
            jsonEncode(tokens.map((t) => t.toJson()).toList()),
          ),
          isOcr: const drift.Value(false),
          indexVersion: const drift.Value(1),
          indexedAt: drift.Value(DateTime.now()),
        ),
      );

      // When includeChrome = false (default)
      final filtered = await InBookSearchEngine.searchIndexedBook(
        bookId: testBookId,
        dbService: dbService,
        query: 'BAB',
        includeChrome: false,
      );
      // Only the content 'BAB' should be returned, chrome 'BAB I' filtered out
      expect(filtered.length, equals(1));
      expect(filtered.first.startOffset, equals(6));

      // When includeChrome = true
      final unfiltered = await InBookSearchEngine.searchIndexedBook(
        bookId: testBookId,
        dbService: dbService,
        query: 'BAB',
        includeChrome: true,
      );
      expect(unfiltered.length, equals(2));
    });

    test('6. Result ordering by page ascending and offset ascending', () async {
      await dbService.insertSearchPage(
        BookSearchPagesCompanion(
          id: const drift.Value('${testBookId}_p2'),
          bookId: const drift.Value(testBookId),
          pageIndex: const drift.Value(2),
          plainText: const drift.Value('Kunci di halaman tiga'),
          rawText: const drift.Value('Kunci di halaman tiga'),
          geometryJson: const drift.Value('[]'),
          isOcr: const drift.Value(false),
          indexVersion: const drift.Value(1),
          indexedAt: drift.Value(DateTime.now()),
        ),
      );

      await dbService.insertSearchPage(
        BookSearchPagesCompanion(
          id: const drift.Value('${testBookId}_p0'),
          bookId: const drift.Value(testBookId),
          pageIndex: const drift.Value(0),
          plainText: const drift.Value('Kunci pertama dan kunci kedua'),
          rawText: const drift.Value('Kunci pertama dan kunci kedua'),
          geometryJson: const drift.Value('[]'),
          isOcr: const drift.Value(false),
          indexVersion: const drift.Value(1),
          indexedAt: drift.Value(DateTime.now()),
        ),
      );

      final results = await InBookSearchEngine.searchIndexedBook(
        bookId: testBookId,
        dbService: dbService,
        query: 'kunci',
      );

      expect(results.length, equals(3));
      // First result: Page 1, offset 0
      expect(results[0].sourcePdfPage, equals(1));
      expect(results[0].startOffset, equals(0));
      // Second result: Page 1, offset 18
      expect(results[1].sourcePdfPage, equals(1));
      expect(results[1].startOffset, equals(18));
      // Third result: Page 3, offset 0
      expect(results[2].sourcePdfPage, equals(3));
      expect(results[2].startOffset, equals(0));
    });

    test('7. Snippet generation with ellipsis and surrounding context', () async {
      await dbService.insertSearchPage(
        BookSearchPagesCompanion(
          id: const drift.Value('${testBookId}_p0'),
          bookId: const drift.Value(testBookId),
          pageIndex: const drift.Value(0),
          plainText: const drift.Value(
            'Hari itu matahari bersinar terik sekali ketika kami sedang berjalan melintasi pasar tradisional yang riuh dan penuh sesak oleh orang-orang yang berbelanja.',
          ),
          rawText: const drift.Value(
            'Hari itu matahari bersinar terik sekali ketika kami sedang berjalan melintasi pasar tradisional yang riuh dan penuh sesak oleh orang-orang yang berbelanja.',
          ),
          geometryJson: const drift.Value('[]'),
          isOcr: const drift.Value(false),
          indexVersion: const drift.Value(1),
          indexedAt: drift.Value(DateTime.now()),
        ),
      );

      final results = await InBookSearchEngine.searchIndexedBook(
        bookId: testBookId,
        dbService: dbService,
        query: 'pasar tradisional',
      );

      expect(results.length, equals(1));
      final res = results.first;
      expect(res.snippet, contains('pasar tradisional'));
      expect(res.snippet, startsWith('…'));
      expect(res.snippet, endsWith('…'));
      expect(res.prefixContext, contains('berjalan melintasi '));
      expect(res.suffixContext, contains(' yang riuh'));
    });

    test('8. Empty, whitespace-only query, and cancellation', () async {
      final empty1 = await InBookSearchEngine.searchIndexedBook(
        bookId: testBookId,
        dbService: dbService,
        query: '',
      );
      expect(empty1, isEmpty);

      final empty2 = await InBookSearchEngine.searchIndexedBook(
        bookId: testBookId,
        dbService: dbService,
        query: '    \n\t  ',
      );
      expect(empty2, isEmpty);

      final cancelled = await InBookSearchEngine.searchIndexedBook(
        bookId: testBookId,
        dbService: dbService,
        query: 'kunci',
        isCancelled: () => true,
      );
      expect(cancelled, isEmpty);
    });

    test('9. ReaderDocument node and chapter mapping', () async {
      final readerDoc = ReaderDocument(
        bookId: testBookId,
        title: 'Buku Uji Pencarian',
        author: 'Penulis Uji',
        chapters: [
          const ReaderChapter(
            id: 'ch_1',
            index: 0,
            title: 'Bab Satu: Penyelidikan',
            nodes: [
              ContentNode(
                id: 'node_p1_1',
                type: ContentNodeType.paragraph,
                text: 'Kunci pertama ditemukan di laci meja kerja.',
                sourcePdfPage: 1,
              ),
              ContentNode(
                id: 'node_p1_2',
                type: ContentNodeType.paragraph,
                text: 'Catatan penting tertulis dengan tinta biru.',
                sourcePdfPage: 1,
              ),
            ],
          ),
        ],
      );

      await dbService.insertSearchPage(
        BookSearchPagesCompanion(
          id: const drift.Value('${testBookId}_p0'),
          bookId: const drift.Value(testBookId),
          pageIndex: const drift.Value(0),
          plainText: const drift.Value(
            'Kunci pertama ditemukan di laci meja kerja. Catatan penting tertulis dengan tinta biru.',
          ),
          rawText: const drift.Value(
            'Kunci pertama ditemukan di laci meja kerja.\nCatatan penting tertulis dengan tinta biru.',
          ),
          geometryJson: const drift.Value('[]'),
          isOcr: const drift.Value(false),
          indexVersion: const drift.Value(1),
          indexedAt: drift.Value(DateTime.now()),
        ),
      );

      final results = await InBookSearchEngine.searchIndexedBook(
        bookId: testBookId,
        dbService: dbService,
        query: 'Kunci pertama',
        readerDocument: readerDoc,
      );

      expect(results.length, equals(1));
      final res = results.first;
      expect(res.chapterIndex, equals(0));
      expect(res.chapterId, equals('ch_1'));
      expect(res.chapterTitle, equals('Bab Satu: Penyelidikan'));
      expect(res.nodeId, equals('node_p1_1'));
      expect(res.startOffset, equals(0));
      expect(res.endOffset, equals(13));
    });
  });
}
