// ignore_for_file: depend_on_referenced_packages

import 'dart:io';
import 'dart:ui' show Rect;
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/features/reader/domain/models/book_annotation.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as raw_sqlite;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('db_migration_v5_v6_');
    dbPath = p.join(tempDir.path, 'v5_fixture.db');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Phase 3.3 — Schema v5 to v6 Migration & Annotation Integrity Audit', () {
    test(
      '1. Full Schema v5 to v6 Migration preserves existing highlights/bookmarks and adds v6 columns',
      () async {
        // Step A: Create a realistic v5 database with raw SQLite
        final rawDb = raw_sqlite.sqlite3.open(dbPath);
        rawDb.execute('PRAGMA user_version = 5;');
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

        // 4. Bookmarks (v5 schema without page_index or updated_at)
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

        // 5. Highlights (v5 schema without page_index, bounding_boxes_json, anchor_status, updated_at)
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

        // 6. OcrPages
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

        // 7. BookSearchPages (v5)
        rawDb.execute('''
        CREATE TABLE book_search_pages (
          id TEXT NOT NULL PRIMARY KEY,
          book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE,
          page_index INTEGER NOT NULL,
          plain_text TEXT NOT NULL,
          raw_text TEXT NOT NULL,
          geometry_json TEXT NOT NULL
        );
      ''');

        final nowMs = DateTime.now().millisecondsSinceEpoch;

        // Insert pre-existing v5 book
        rawDb.execute('''
        INSERT INTO books (id, title, author, original_pdf_path, created_at, updated_at)
        VALUES ('book-v5-legacy', 'Laut Bercerita (Edisi Lawas)', 'Leila S. Chudori', '/path/to/legacy.pdf', $nowMs, $nowMs);
      ''');

        // Insert pre-existing v5 bookmark
        rawDb.execute('''
        INSERT INTO bookmarks (id, book_id, chapter_id, position, label, anchor_node_id, character_offset, progress_percentage, created_at)
        VALUES ('bm-legacy-1', 'book-v5-legacy', 'ch-1', 42, 'Bab 1 Penanda', 'node-101', 120, 0.15, $nowMs);
      ''');

        // Insert pre-existing v5 highlight
        rawDb.execute('''
        INSERT INTO highlights (id, book_id, chapter_id, selected_text, start_position, end_position, color, note, anchor_node_id, start_offset, end_offset, prefix_context, suffix_context, anchor_version, created_at)
        VALUES ('hl-legacy-1', 'book-v5-legacy', 'ch-1', 'Matanya menatap ombak yang berkejaran di kejauhan.', 42, 42, 'yellow', 'Kutipan penting halaman awal', 'node-101', 50, 102, 'Di sana, ', ' dan membisu.', 1, $nowMs);
      ''');

        rawDb.close();

        // Step B: Open through Drift AppDatabase and trigger migration to v6
        final appDb = AppDatabase(NativeDatabase(File(dbPath)));
        final dbService = DatabaseService(appDb);

        // Verify PRAGMA user_version is updated to 6
        final versionResult = await appDb
            .customSelect('PRAGMA user_version;')
            .getSingle();
        final currentVersion = versionResult.data['user_version'] as int;
        expect(
          currentVersion,
          equals(6),
          reason: 'Database schema version must be bumped to 6',
        );

        // Verify legacy highlight is intact and v6 default columns are populated
        final highlights = await dbService.getHighlightsForBook(
          'book-v5-legacy',
        );
        expect(highlights.length, equals(1));
        final legacyHl = highlights.first;
        expect(legacyHl.id, equals('hl-legacy-1'));
        expect(
          legacyHl.selectedText,
          equals('Matanya menatap ombak yang berkejaran di kejauhan.'),
        );
        expect(legacyHl.note, equals('Kutipan penting halaman awal'));
        expect(legacyHl.color, equals('yellow'));
        expect(
          legacyHl.anchorStatus,
          equals('resolved'),
          reason:
              'Default anchor_status for migrated highlights must be resolved',
        );
        expect(legacyHl.boundingBoxesJson, isNull);
        expect(legacyHl.pageIndex, isNull);

        // Verify legacy bookmark is intact
        final bookmarks = await dbService.getBookmarksForBook('book-v5-legacy');
        expect(bookmarks.length, equals(1));
        final legacyBm = bookmarks.first;
        expect(legacyBm.id, equals('bm-legacy-1'));
        expect(legacyBm.label, equals('Bab 1 Penanda'));
        expect(legacyBm.position, equals(42));
        expect(legacyBm.pageIndex, isNull);

        // Step C: Test insertion of new v6 annotation with bounding boxes and updated timestamp
        final v6Annotation = BookAnnotation(
          id: 'ann-v6-new-1',
          bookId: 'book-v5-legacy',
          type: AnnotationType.note,
          selectedText: 'Teks dengan bounding box dan catatan v6',
          pageIndex: 5,
          boundingBoxes: const [
            Rect.fromLTWH(0.1, 0.2, 0.8, 0.05),
            Rect.fromLTWH(0.1, 0.26, 0.6, 0.05),
          ],
          color: 'pink',
          note: 'Catatan multi-baris pada mode PDF asli.',
          anchorStatus: AnchorStatus.resolved,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        await dbService.saveAnnotation(v6Annotation);

        // Retrieve via unified domain API
        final allAnnotations = await dbService.getAnnotationsForBook(
          'book-v5-legacy',
        );
        expect(
          allAnnotations.length,
          equals(3),
          reason: 'Legacy highlight + legacy bookmark + new v6 annotation',
        );

        final retrievedV6 = allAnnotations.firstWhere(
          (a) => a.id == 'ann-v6-new-1',
        );
        expect(retrievedV6.color, equals('pink'));
        expect(retrievedV6.pageIndex, equals(5));
        expect(retrievedV6.boundingBoxes.length, equals(2));
        expect(retrievedV6.boundingBoxes.first.left, closeTo(0.1, 0.001));
        expect(retrievedV6.hasNote, isTrue);
        expect(
          retrievedV6.note,
          equals('Catatan multi-baris pada mode PDF asli.'),
        );

        // Step D: Test foreign key cascading deletion
        await dbService.deleteBook('book-v5-legacy');

        final remainingAnnotations = await dbService.getAnnotationsForBook(
          'book-v5-legacy',
        );
        expect(
          remainingAnnotations.isEmpty,
          isTrue,
          reason: 'Annotations must be cascade-deleted when book is deleted',
        );

        await appDb.close();
      },
    );
  });
}
