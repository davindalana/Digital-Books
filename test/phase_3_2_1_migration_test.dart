// ignore_for_file: depend_on_referenced_packages

import 'dart:io';
import 'dart:ui' show Rect;
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/core/utils/file_storage_service.dart';
import 'package:digital_books/features/reader/domain/services/book_search_indexer.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as raw_sqlite;
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String dbPath;

  File createTestPdf(Directory dir, String filename, int pageCount) {
    final file = File(p.join(dir.path, filename));
    final doc = sf.PdfDocument();
    final font = sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 12);
    for (int i = 0; i < pageCount; i++) {
      final page = doc.pages.add();
      page.graphics.drawString(
        'Halaman ${i + 1} dengan teks penting untuk verifikasi indexing.',
        font,
        bounds: const Rect.fromLTWH(50, 80, 400, 30),
      );
    }
    file.writeAsBytesSync(doc.saveSync());
    doc.dispose();
    return file;
  }

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('db_migration_v4_v5_');
    dbPath = p.join(tempDir.path, 'v4_fixture.db');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Phase 3.2.1 — Schema v4 to v5 Migration & Index Integrity Audit', () {
    test(
      '1. Full Schema v4 to v5 Migration preserves all existing data and creates BookSearchPages',
      () async {
        // Step A: Create a realistic v4 database with raw SQLite
        final rawDb = raw_sqlite.sqlite3.open(dbPath);
        rawDb.execute('PRAGMA user_version = 4;');
        rawDb.execute('PRAGMA foreign_keys = ON;');

        // 1. Books
        rawDb.execute('''
        CREATE TABLE books (
          id TEXT NOT NULL PRIMARY KEY,
          title TEXT NOT NULL,
          author TEXT NOT NULL,
          publisher TEXT,
          description TEXT,
          cover_path TEXT,
          original_pdf_path TEXT NOT NULL,
          processed_book_path TEXT,
          file_hash TEXT,
          total_pages INTEGER NOT NULL DEFAULT 0,
          is_scanned INTEGER NOT NULL DEFAULT 0,
          last_reading_mode TEXT NOT NULL DEFAULT 'reflowable',
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        );
      ''');

        // 2. Chapters
        rawDb.execute('''
        CREATE TABLE chapters (
          id TEXT NOT NULL PRIMARY KEY,
          book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
          title TEXT NOT NULL,
          chapter_index INTEGER NOT NULL,
          start_position INTEGER NOT NULL DEFAULT 0,
          end_position INTEGER NOT NULL DEFAULT 0
        );
      ''');

        // 3. Reading Progresses
        rawDb.execute('''
        CREATE TABLE reading_progresses (
          id TEXT NOT NULL PRIMARY KEY,
          book_id TEXT NOT NULL UNIQUE REFERENCES books(id) ON DELETE CASCADE,
          current_chapter INTEGER NOT NULL DEFAULT 0,
          current_position INTEGER NOT NULL DEFAULT 0,
          progress_percentage REAL NOT NULL DEFAULT 0.0,
          last_read_at INTEGER NOT NULL
        );
      ''');

        // 4. Bookmarks
        rawDb.execute('''
        CREATE TABLE bookmarks (
          id TEXT NOT NULL PRIMARY KEY,
          book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
          chapter_id TEXT,
          position INTEGER NOT NULL,
          label TEXT NOT NULL,
          anchor_node_id TEXT,
          character_offset INTEGER NOT NULL DEFAULT 0,
          progress_percentage REAL NOT NULL DEFAULT 0.0,
          created_at INTEGER NOT NULL
        );
      ''');

        // 5. Highlights
        rawDb.execute('''
        CREATE TABLE highlights (
          id TEXT NOT NULL PRIMARY KEY,
          book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
          chapter_id TEXT,
          selected_text TEXT NOT NULL,
          start_position INTEGER NOT NULL,
          end_position INTEGER NOT NULL,
          color TEXT NOT NULL DEFAULT 'yellow',
          note TEXT,
          anchor_node_id TEXT,
          start_offset INTEGER NOT NULL DEFAULT 0,
          end_offset INTEGER NOT NULL DEFAULT 0,
          prefix_context TEXT,
          suffix_context TEXT,
          anchor_version INTEGER NOT NULL DEFAULT 1,
          created_at INTEGER NOT NULL
        );
      ''');

        // 6. Collections
        rawDb.execute('''
        CREATE TABLE collections (
          id TEXT NOT NULL PRIMARY KEY,
          name TEXT NOT NULL,
          description TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        );
      ''');

        // 7. Book Collections
        rawDb.execute('''
        CREATE TABLE book_collections (
          book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
          collection_id TEXT NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
          PRIMARY KEY (book_id, collection_id)
        );
      ''');

        // 8. OcrPages
        rawDb.execute('''
        CREATE TABLE ocr_pages (
          id TEXT NOT NULL PRIMARY KEY,
          book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
          page_index INTEGER NOT NULL,
          status TEXT NOT NULL DEFAULT 'completed',
          confidence REAL NOT NULL DEFAULT 1.0,
          char_count INTEGER NOT NULL DEFAULT 0,
          duration_ms REAL NOT NULL DEFAULT 0.0,
          lines_json TEXT NOT NULL,
          created_at INTEGER NOT NULL
        );
      ''');

        // Populate test data into all 8 tables
        final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        rawDb.execute('''
        INSERT INTO books (id, title, author, original_pdf_path, file_hash, total_pages, is_scanned, created_at, updated_at)
        VALUES ('book_v4_test', 'Laut Bercerita', 'Leila S. Chudori', '/path/to/laut.pdf', 'hash_v4_initial', 10, 1, $nowSec, $nowSec);
      ''');

        rawDb.execute('''
        INSERT INTO chapters (id, book_id, title, chapter_index, start_position, end_position)
        VALUES ('ch_1', 'book_v4_test', 'Bab 1', 0, 0, 100);
      ''');

        rawDb.execute('''
        INSERT INTO reading_progresses (id, book_id, current_chapter, current_position, progress_percentage, last_read_at)
        VALUES ('prog_1', 'book_v4_test', 0, 42, 0.42, $nowSec);
      ''');

        rawDb.execute('''
        INSERT INTO bookmarks (id, book_id, chapter_id, position, label, anchor_node_id, character_offset, progress_percentage, created_at)
        VALUES ('bm_1', 'book_v4_test', 'ch_1', 10, 'Halaman Awal', 'node_1', 0, 0.1, $nowSec);
      ''');

        rawDb.execute('''
        INSERT INTO highlights (id, book_id, chapter_id, selected_text, start_position, end_position, color, note, anchor_node_id, start_offset, end_offset, created_at)
        VALUES ('hl_1', 'book_v4_test', 'ch_1', 'Kutipan Paling Berkesan', 0, 100, 'yellow', 'Catatan penting', 'node_1', 12, 28, $nowSec);
      ''');

        rawDb.execute('''
        INSERT INTO collections (id, name, created_at, updated_at)
        VALUES ('col_1', 'Favorit Saya', $nowSec, $nowSec);
      ''');

        rawDb.execute('''
        INSERT INTO book_collections (book_id, collection_id)
        VALUES ('book_v4_test', 'col_1');
      ''');

        rawDb.execute('''
        INSERT INTO ocr_pages (id, book_id, page_index, status, confidence, char_count, duration_ms, lines_json, created_at)
        VALUES ('ocr_p0', 'book_v4_test', 0, 'completed', 0.99, 150, 120.0, '[]', $nowSec);
      ''');

        rawDb.close();

        // Step B: Open database via Drift AppDatabase (triggers onUpgrade from v4 to v5)
        final driftDb = AppDatabase(NativeDatabase(File(dbPath)));
        final dbService = DatabaseService(driftDb);

        expect(driftDb.schemaVersion, greaterThanOrEqualTo(5));

        // Step C: Verify all 8 legacy tables remain 100% intact
        final book = await dbService.getBookById('book_v4_test');
        expect(book, isNotNull);
        expect(book!.title, equals('Laut Bercerita'));
        expect(book.author, equals('Leila S. Chudori'));
        expect(book.fileHash, equals('hash_v4_initial'));

        final chapters = await dbService.getChaptersForBook('book_v4_test');
        expect(chapters.length, equals(1));
        expect(chapters.first.title, equals('Bab 1'));

        final progress = await dbService.getProgress('book_v4_test');
        expect(progress, isNotNull);
        expect(progress!.currentPosition, equals(42));
        expect(progress.progressPercentage, closeTo(0.42, 0.001));

        final bookmarks = await dbService.getBookmarksForBook('book_v4_test');
        expect(bookmarks.length, equals(1));
        expect(bookmarks.first.label, equals('Halaman Awal'));

        final highlights = await dbService.getHighlightsForBook('book_v4_test');
        expect(highlights.length, equals(1));
        expect(
          highlights.first.selectedText,
          equals('Kutipan Paling Berkesan'),
        );

        final collections = await dbService.getAllCollections();
        expect(collections.length, equals(1));
        expect(collections.first.name, equals('Favorit Saya'));

        final ocrPages = await dbService.getOcrPagesForBook('book_v4_test');
        expect(ocrPages.length, equals(1));
        expect(ocrPages.first.status, equals('completed'));

        // Step D: Verify BookSearchPages table exists and is empty
        final searchPages = await dbService.getSearchPagesForBook(
          'book_v4_test',
        );
        expect(searchPages, isEmpty);

        // Step E: Verify new insertions into BookSearchPages work post-migration
        final insertedRows = await dbService.insertSearchPage(
          BookSearchPagesCompanion(
            id: const drift.Value('book_v4_test_p0'),
            bookId: const drift.Value('book_v4_test'),
            pageIndex: const drift.Value(0),
            plainText: const drift.Value(
              'Teks pencarian setelah migrasi berhasil.',
            ),
            rawText: const drift.Value(
              'Teks pencarian setelah migrasi berhasil.',
            ),
            geometryJson: const drift.Value('[]'),
            isOcr: const drift.Value(true),
            fileHash: const drift.Value('hash_v4_initial'),
            indexVersion: const drift.Value(1),
            indexedAt: drift.Value(DateTime.now()),
          ),
        );
        expect(insertedRows, equals(1));

        final updatedSearch = await dbService.getSearchPagesForBook(
          'book_v4_test',
        );
        expect(updatedSearch.length, equals(1));
        expect(updatedSearch.first.plainText, contains('setelah migrasi'));

        // Step F: Verify Foreign Key and Cascade Delete (Deleting Book deletes SearchPages too)
        await dbService.safeDeleteBook('book_v4_test');

        final searchAfterDelete = await dbService.getSearchPagesForBook(
          'book_v4_test',
        );
        expect(
          searchAfterDelete,
          isEmpty,
          reason: 'Cascade delete must purge search pages!',
        );

        final ocrAfterDelete = await dbService.getOcrPagesForBook(
          'book_v4_test',
        );
        expect(
          ocrAfterDelete,
          isEmpty,
          reason: 'Cascade delete must purge ocr pages!',
        );

        await driftDb.close();
      },
    );

    test(
      '2. Hash change staleness invalidation & re-indexing idempotency',
      () async {
        final pdf1 = createTestPdf(tempDir, 'document_v1.pdf', 3);
        final pdf2 = createTestPdf(tempDir, 'document_v2.pdf', 3);
        final hash1 = await FileStorageService.computeFileSha256(pdf1);

        final db = AppDatabase(NativeDatabase.memory());
        final dbService = DatabaseService(db);

        const bookId = 'book_hash_stale_test';
        await dbService.insertBook(
          BooksCompanion(
            id: const drift.Value(bookId),
            title: const drift.Value('Dokumen Hash Test'),
            author: const drift.Value('Penulis Test'),
            originalPdfPath: drift.Value(pdf1.path),
            fileHash: drift.Value(hash1),
            totalPages: const drift.Value(3),
            createdAt: drift.Value(DateTime.now()),
            updatedAt: drift.Value(DateTime.now()),
          ),
        );

        final indexer = BookSearchIndexer(dbService: dbService);

        // Initial index with pdf1
        final initialIndexed = await indexer.indexBook(
          bookId: bookId,
          pdfPath: pdf1.path,
        );
        expect(initialIndexed, equals(3));
        expect(await dbService.getIndexedSearchPageCount(bookId), equals(3));

        // Simulate document replacement: book file updated to pdf2 (new hash)
        // When indexBook runs, it detects the file hash discrepancy and purges stale pages
        await dbService.insertBook(
          (await dbService.getBookById(bookId))!
              .toCompanion(true)
              .copyWith(originalPdfPath: drift.Value(pdf2.path)),
        );

        // Re-run indexing with pdf2
        final reIndexed = await indexer.indexBook(
          bookId: bookId,
          pdfPath: pdf2.path,
        );

        expect(reIndexed, equals(3));
        final currentPages = await dbService.getSearchPagesForBook(bookId);
        expect(currentPages.length, equals(3));

        // Check no page index duplication occurred
        final pageIndices = currentPages.map((p) => p.pageIndex).toList();
        expect(pageIndices, equals([0, 1, 2]));

        await db.close();
      },
    );

    test('3. Partial indexing recovery and interrupt-resumption audit', () async {
      final pdf = createTestPdf(tempDir, 'document_resume.pdf', 6);
      final db = AppDatabase(NativeDatabase.memory());
      final dbService = DatabaseService(db);

      const bookId = 'book_resume_test';
      await dbService.insertBook(
        BooksCompanion(
          id: const drift.Value(bookId),
          title: const drift.Value('Dokumen Resumption'),
          author: const drift.Value('Penulis Test'),
          originalPdfPath: drift.Value(pdf.path),
          totalPages: const drift.Value(6),
          createdAt: drift.Value(DateTime.now()),
          updatedAt: drift.Value(DateTime.now()),
        ),
      );

      final indexer = BookSearchIndexer(dbService: dbService);

      // Run 1: Interrupted at page 2 (pages 0, 1 indexed, cancelled on 2)
      int progressCallCount = 0;
      final run1 = await indexer.indexBook(
        bookId: bookId,
        pdfPath: pdf.path,
        startPage: 0,
        endPage: 5,
        isCancelled: () {
          progressCallCount++;
          return progressCallCount >= 3; // Cancel after 2 pages
        },
      );
      expect(run1, equals(2));
      expect(await dbService.getIndexedSearchPageCount(bookId), equals(2));

      // Run 2: Resume without cancellation — must skip pages 0 and 1, indexing remaining 4 pages (2..5)
      final run2 = await indexer.indexBook(
        bookId: bookId,
        pdfPath: pdf.path,
        startPage: 0,
        endPage: 5,
      );
      expect(run2, equals(4));
      expect(await dbService.getIndexedSearchPageCount(bookId), equals(6));

      // Verify no duplicates
      final finalPages = await dbService.getSearchPagesForBook(bookId);
      expect(finalPages.length, equals(6));
      expect(finalPages.map((p) => p.pageIndex).toSet().length, equals(6));

      await db.close();
    });
  });
}
