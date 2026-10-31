// ignore_for_file: depend_on_referenced_packages
import 'dart:io';
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as raw_sqlite;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('db_migration_test_');
    dbPath = p.join(tempDir.path, 'migration_v1_to_v2.db');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('Database Migration from Schema v1 to v2 preserves all data and adds new columns', () async {
    // Step 1: Create a raw SQLite database with Schema v1 (before fileHash and lastReadingMode existed)
    final rawDb = raw_sqlite.sqlite3.open(dbPath);
    rawDb.execute('PRAGMA user_version = 1;');
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
        total_pages INTEGER NOT NULL DEFAULT 0,
        is_scanned INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');
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
    rawDb.execute('''
      CREATE TABLE bookmarks (
        id TEXT NOT NULL PRIMARY KEY,
        book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
        chapter_id TEXT,
        position INTEGER NOT NULL,
        label TEXT NOT NULL,
        created_at INTEGER NOT NULL
      );
    ''');
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
        created_at INTEGER NOT NULL
      );
    ''');
    rawDb.execute('''
      CREATE TABLE collections (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        created_at INTEGER NOT NULL
      );
    ''');
    rawDb.execute('''
      CREATE TABLE book_collections (
        book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
        collection_id TEXT NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
        PRIMARY KEY (book_id, collection_id)
      );
    ''');

    final nowEpoch = DateTime(2026, 1, 1).millisecondsSinceEpoch;

    // Seed v1 Data
    rawDb.execute('''
      INSERT INTO books (id, title, author, publisher, description, cover_path, original_pdf_path, total_pages, is_scanned, created_at, updated_at)
      VALUES ('b-v1-legacy', 'Legacy Book Title', 'Legacy Author', 'Legacy Press', 'Original description from v1', '/path/cover.png', '/path/original.pdf', 320, 0, $nowEpoch, $nowEpoch);
    ''');
    rawDb.execute('''
      INSERT INTO chapters (id, book_id, title, chapter_index, start_position, end_position)
      VALUES ('ch-v1-1', 'b-v1-legacy', 'Chapter 1: The Beginning', 0, 0, 100);
    ''');
    rawDb.execute('''
      INSERT INTO reading_progresses (id, book_id, current_chapter, current_position, progress_percentage, last_read_at)
      VALUES ('prog-v1-1', 'b-v1-legacy', 0, 42, 0.15, $nowEpoch);
    ''');
    rawDb.execute('''
      INSERT INTO bookmarks (id, book_id, position, label, created_at)
      VALUES ('bm-v1-1', 'b-v1-legacy', 42, 'Important Bookmark', $nowEpoch);
    ''');
    rawDb.execute('''
      INSERT INTO highlights (id, book_id, selected_text, start_position, end_position, created_at)
      VALUES ('hl-v1-1', 'b-v1-legacy', 'Great quote from v1', 10, 30, $nowEpoch);
    ''');
    rawDb.execute('''
      INSERT INTO collections (id, name, description, created_at)
      VALUES ('col-v1-1', 'Classics', 'Classic books collection', $nowEpoch);
    ''');
    rawDb.execute('''
      INSERT INTO book_collections (book_id, collection_id)
      VALUES ('b-v1-legacy', 'col-v1-1');
    ''');

    // Close raw SQLite connection
    rawDb.close();

    // Step 2: Open database with AppDatabase (Drift) which triggers MigrationStrategy:
    // user_version is currently 1, schemaVersion is 2 -> onUpgrade runs:
    // m.addColumn(books, books.fileHash);
    // m.addColumn(readingProgresses, readingProgresses.lastReadingMode);
    final file = File(dbPath);
    final driftDb = AppDatabase(NativeDatabase(file));
    final dbService = DatabaseService(driftDb);

    try {
      // Step 3: Verify all existing v1 data remains completely intact
      final migratedBook = await dbService.getBookById('b-v1-legacy');
      expect(migratedBook, isNotNull);
      expect(migratedBook!.title, 'Legacy Book Title');
      expect(migratedBook.author, 'Legacy Author');
      expect(migratedBook.publisher, 'Legacy Press');
      expect(migratedBook.description, 'Original description from v1');
      expect(migratedBook.totalPages, 320);

      // Verify new column fileHash exists on Books and is null for legacy record
      expect(migratedBook.fileHash, isNull);

      final chapters = await dbService.getChaptersForBook('b-v1-legacy');
      expect(chapters.length, 1);
      expect(chapters.first.title, 'Chapter 1: The Beginning');

      final progress = await dbService.getProgress('b-v1-legacy');
      expect(progress, isNotNull);
      expect(progress!.currentPosition, 42);
      expect(progress.progressPercentage, 0.15);
      // Verify new column lastReadingMode exists on ReadingProgresses and is null for legacy record
      expect(progress.lastReadingMode, isNull);

      final bookmarks = await dbService.watchBookmarks('b-v1-legacy').first;
      expect(bookmarks.length, 1);
      expect(bookmarks.first.label, 'Important Bookmark');

      final highlights = await dbService.watchHighlights('b-v1-legacy').first;
      expect(highlights.length, 1);
      expect(highlights.first.selectedText, 'Great quote from v1');

      final collections = await dbService.watchCollections().first;
      expect(collections.length, 1);
      expect(collections.first.name, 'Classics');

      final bookCollections = await dbService.getCollectionIdsForBook('b-v1-legacy');
      expect(bookCollections.length, 1);
      expect(bookCollections.first, 'col-v1-1');

      // Step 4: Verify writing to new v2 columns succeeds
      await dbService.insertBook(
        BooksCompanion(
          id: const drift.Value('b-v2-new'),
          title: const drift.Value('Modern Book v2'),
          author: const drift.Value('Modern Author'),
          originalPdfPath: const drift.Value('/path/v2.pdf'),
          fileHash: const drift.Value('abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789'),
          createdAt: drift.Value(DateTime.now()),
          updatedAt: drift.Value(DateTime.now()),
        ),
      );

      final newBook = await dbService.getBookById('b-v2-new');
      expect(newBook, isNotNull);
      expect(newBook!.fileHash, 'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789');

      await dbService.upsertProgress(
        ReadingProgressesCompanion(
          id: const drift.Value('prog-v2-new'),
          bookId: const drift.Value('b-v2-new'),
          currentChapter: const drift.Value(1),
          currentPosition: const drift.Value(55),
          progressPercentage: const drift.Value(0.33),
          lastReadingMode: const drift.Value('reflowable'),
          lastReadAt: drift.Value(DateTime.now()),
        ),
      );

      final newProgress = await dbService.getProgress('b-v2-new');
      expect(newProgress, isNotNull);
      expect(newProgress!.lastReadingMode, 'reflowable');

      // Step 5: Verify foreign keys are enabled and cascading deletes work on migrated database
      final fkResult = await driftDb.customSelect('PRAGMA foreign_keys;').getSingle();
      final fkEnabled = fkResult.data['foreign_keys'];
      expect(fkEnabled, 1, reason: 'PRAGMA foreign_keys must be 1 (ON)');

      // Verify foreign key enforcement rejects invalid references
      expect(
        () async {
          await driftDb.into(driftDb.chapters).insert(
            const ChaptersCompanion(
              id: drift.Value('orphan-ch'),
              bookId: drift.Value('non-existent-book-id'),
              title: drift.Value('Invalid Chapter'),
              chapterIndex: drift.Value(0),
            ),
          );
        },
        throwsA(isA<raw_sqlite.SqliteException>()),
        reason: 'Inserting chapter with invalid bookId must throw foreign key exception',
      );

      // Verify cascading delete on the legacy migrated book
      await dbService.deleteBook('b-v1-legacy');

      final chaptersAfter = await dbService.getChaptersForBook('b-v1-legacy');
      final progressAfter = await dbService.getProgress('b-v1-legacy');
      final bookmarksAfter = await dbService.watchBookmarks('b-v1-legacy').first;
      final highlightsAfter = await dbService.watchHighlights('b-v1-legacy').first;
      final bookColAfter = await dbService.getCollectionIdsForBook('b-v1-legacy');

      expect(chaptersAfter, isEmpty);
      expect(progressAfter, isNull);
      expect(bookmarksAfter, isEmpty);
      expect(highlightsAfter, isEmpty);
      expect(bookColAfter, isEmpty);
    } finally {
      await driftDb.close();
    }
  });
}
