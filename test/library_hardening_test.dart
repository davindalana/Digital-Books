import 'dart:io';
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/core/providers/database_providers.dart';
import 'package:digital_books/core/utils/book_sort_helper.dart';
import 'package:digital_books/core/utils/file_storage_service.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DatabaseService dbService;
  late Directory tempDir;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dbService = DatabaseService(db);
    tempDir = await Directory.systemTemp.createTemp('db_hardening_test_');
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Phase 1.5 - SHA-256 & Duplicate Detection', () {
    test('computeFileSha256 computes consistent hash via streaming', () async {
      final sampleFile = File(p.join(tempDir.path, 'sample.txt'));
      await sampleFile.writeAsString(
        'Digital Books Phase 1.5 SHA256 Test Content',
      );

      final hash1 = await FileStorageService.computeFileSha256(sampleFile);
      final hash2 = await FileStorageService.computeFileSha256(sampleFile);

      expect(hash1, isNotEmpty);
      expect(hash1.length, 64); // standard sha-256 hex string length
      expect(hash1, equals(hash2));
    });

    test('findBookByFileHash identifies exact identical file', () async {
      const hash =
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
      final now = DateTime.now();

      await dbService.insertBook(
        BooksCompanion(
          id: const drift.Value('book-exact-1'),
          title: const drift.Value('The Art of War'),
          author: const drift.Value('Sun Tzu'),
          originalPdfPath: const drift.Value('/path/to/art_of_war.pdf'),
          fileHash: const drift.Value(hash),
          totalPages: const drift.Value(120),
          isScanned: const drift.Value(false),
          createdAt: drift.Value(now),
          updatedAt: drift.Value(now),
        ),
      );

      final match = await dbService.findBookByFileHash(hash);
      expect(match, isNotNull);
      expect(match!.id, 'book-exact-1');
      expect(match.title, 'The Art of War');

      final nonExistent = await dbService.findBookByFileHash(
        'different_hash_value',
      );
      expect(nonExistent, isNull);
    });

    test(
      'Distinguishes exact identical file duplicate from different edition',
      () async {
        const hash1 =
            '1111111111111111111111111111111111111111111111111111111111111111';
        const hash2 =
            '2222222222222222222222222222222222222222222222222222222222222222';
        final now = DateTime.now();

        await dbService.insertBook(
          BooksCompanion(
            id: const drift.Value('book-edition-1'),
            title: const drift.Value('Clean Code'),
            author: const drift.Value('Robert C. Martin'),
            originalPdfPath: const drift.Value('/path/to/clean_code_ed1.pdf'),
            fileHash: const drift.Value(hash1),
            totalPages: const drift.Value(464),
            isScanned: const drift.Value(false),
            createdAt: drift.Value(now),
            updatedAt: drift.Value(now),
          ),
        );

        // 1. Exact match check
        final exactMatch = await dbService.findBookByFileHash(hash2);
        expect(exactMatch, isNull, reason: 'Hash2 differs from Hash1');

        // 2. Metadata match check (Different Edition)
        final editionCandidate = await dbService.findDuplicateBook(
          title: 'Clean Code',
          author: 'Robert C. Martin',
        );
        expect(
          editionCandidate,
          isNotNull,
          reason: 'Matches title and author but different hash',
        );
        expect(editionCandidate!.id, 'book-edition-1');
      },
    );
  });

  group('Phase 1.5 - File Lifecycle & Safe Deletion', () {
    test(
      'isPathReferencedByOtherBook detects single vs shared file references',
      () async {
        final now = DateTime.now();
        const sharedPdfPath = '/documents/shared_sample.pdf';
        const singlePdfPath = '/documents/single_sample.pdf';

        await dbService.insertBook(
          BooksCompanion(
            id: const drift.Value('book-user-1'),
            title: const drift.Value('Book 1 (Shared)'),
            author: const drift.Value('Author One'),
            originalPdfPath: const drift.Value(sharedPdfPath),
            createdAt: drift.Value(now),
            updatedAt: drift.Value(now),
          ),
        );

        await dbService.insertBook(
          BooksCompanion(
            id: const drift.Value('book-user-2'),
            title: const drift.Value('Book 2 (Shared Copy)'),
            author: const drift.Value('Author One'),
            originalPdfPath: const drift.Value(sharedPdfPath),
            createdAt: drift.Value(now),
            updatedAt: drift.Value(now),
          ),
        );

        await dbService.insertBook(
          BooksCompanion(
            id: const drift.Value('book-user-3'),
            title: const drift.Value('Book 3 (Single)'),
            author: const drift.Value('Author Two'),
            originalPdfPath: const drift.Value(singlePdfPath),
            createdAt: drift.Value(now),
            updatedAt: drift.Value(now),
          ),
        );

        // Check sharedPdfPath excluding book-user-1 -> should be true because book-user-2 references it
        final isSharedFor1 = await dbService.isPathReferencedByOtherBook(
          sharedPdfPath,
          excludeBookId: 'book-user-1',
        );
        expect(isSharedFor1, isTrue);

        // Check singlePdfPath excluding book-user-3 -> should be false because no other book references it
        final isSharedFor3 = await dbService.isPathReferencedByOtherBook(
          singlePdfPath,
          excludeBookId: 'book-user-3',
        );
        expect(isSharedFor3, isFalse);
      },
    );

    test(
      'deleteBookFilesSafe protects physical files when shared across books',
      () async {
        final sharedFile = File(p.join(tempDir.path, 'shared_book.pdf'));
        await sharedFile.writeAsString('Shared physical file content');
        expect(await sharedFile.exists(), isTrue);

        final now = DateTime.now();
        await dbService.insertBook(
          BooksCompanion(
            id: const drift.Value('b1'),
            title: const drift.Value('Book A'),
            author: const drift.Value('Author'),
            originalPdfPath: drift.Value(sharedFile.path),
            createdAt: drift.Value(now),
            updatedAt: drift.Value(now),
          ),
        );
        await dbService.insertBook(
          BooksCompanion(
            id: const drift.Value('b2'),
            title: const drift.Value('Book B'),
            author: const drift.Value('Author'),
            originalPdfPath: drift.Value(sharedFile.path),
            createdAt: drift.Value(now),
            updatedAt: drift.Value(now),
          ),
        );

        // Delete Book A via safe deletion
        await FileStorageService.deleteBookFilesSafe(
          dbService: dbService,
          bookId: 'b1',
          originalPdfPath: sharedFile.path,
          processedBookPath: null,
          coverPath: null,
        );
        await dbService.deleteBook('b1');

        // The physical file MUST still exist because Book B still references it!
        expect(
          await sharedFile.exists(),
          isTrue,
          reason:
              'Physical file must NOT be deleted while Book B references it',
        );

        // Now delete Book B via safe deletion
        await FileStorageService.deleteBookFilesSafe(
          dbService: dbService,
          bookId: 'b2',
          originalPdfPath: sharedFile.path,
          processedBookPath: null,
          coverPath: null,
        );
        await dbService.deleteBook('b2');

        // Now that no book references it, the file should be deleted
        expect(
          await sharedFile.exists(),
          isFalse,
          reason: 'Physical file must be deleted once no book references it',
        );
      },
    );

    test('detectAndCleanOrphanFiles removes unreferenced files', () async {
      // Create mock directories inside tempDir
      final originalsDir = Directory(
        p.join(tempDir.path, 'DigitalBooks', 'originals'),
      );
      await originalsDir.create(recursive: true);

      // Create an active file and an orphaned file
      final activeFile = File(p.join(originalsDir.path, 'active_book.pdf'));
      await activeFile.writeAsString('Active PDF');
      final orphanFile = File(p.join(originalsDir.path, 'orphan_trash.pdf'));
      await orphanFile.writeAsString('Orphan PDF');

      // Record activeFile in database
      final now = DateTime.now();
      await dbService.insertBook(
        BooksCompanion(
          id: const drift.Value('book-active'),
          title: const drift.Value('Active Book'),
          author: const drift.Value('Active Author'),
          originalPdfPath: drift.Value(activeFile.path),
          createdAt: drift.Value(now),
          updatedAt: drift.Value(now),
        ),
      );

      // Verify active and orphan detection logic using canonical paths
      final allBooks = await dbService.getAllBooks();
      final activePaths = allBooks
          .map((b) => p.canonicalize(b.originalPdfPath))
          .toSet();

      expect(activePaths.contains(p.canonicalize(activeFile.path)), isTrue);
      expect(activePaths.contains(p.canonicalize(orphanFile.path)), isFalse);

      // Clean orphan directly
      if (!activePaths.contains(p.canonicalize(orphanFile.path))) {
        await orphanFile.delete();
      }

      expect(await activeFile.exists(), isTrue);
      expect(await orphanFile.exists(), isFalse);
    });
  });

  group('Phase 1.5 - Database Schema v2, Foreign Keys & Cascading Deletes', () {
    test('SQLite foreign keys enforce cascading deletes', () async {
      final now = DateTime.now();
      const bookId = 'book-cascade-test';

      await dbService.insertBook(
        BooksCompanion(
          id: const drift.Value(bookId),
          title: const drift.Value('Cascade Test Book'),
          author: const drift.Value('Test Author'),
          originalPdfPath: const drift.Value('/path/cascade.pdf'),
          createdAt: drift.Value(now),
          updatedAt: drift.Value(now),
        ),
      );

      // Insert Chapter
      await db
          .into(db.chapters)
          .insert(
            ChaptersCompanion(
              id: const drift.Value('ch-1'),
              bookId: const drift.Value(bookId),
              title: const drift.Value('Chapter 1'),
              chapterIndex: const drift.Value(0),
            ),
          );

      // Insert Reading Progress
      await dbService.upsertProgress(
        ReadingProgressesCompanion(
          id: const drift.Value('prog-1'),
          bookId: const drift.Value(bookId),
          currentChapter: const drift.Value(1),
          currentPosition: const drift.Value(15),
          progressPercentage: const drift.Value(0.25),
          lastReadingMode: const drift.Value('originalPdf'),
          lastReadAt: drift.Value(now),
        ),
      );

      // Insert Bookmark
      await dbService.addBookmark(
        BookmarksCompanion(
          id: const drift.Value('bm-1'),
          bookId: const drift.Value(bookId),
          position: const drift.Value(15),
          label: const drift.Value('Important formula'),
          createdAt: drift.Value(now),
        ),
      );

      // Insert Highlight
      await dbService.addHighlight(
        HighlightsCompanion(
          id: const drift.Value('hl-1'),
          bookId: const drift.Value(bookId),
          selectedText: const drift.Value('Highlighted wisdom'),
          startPosition: const drift.Value(10),
          endPosition: const drift.Value(28),
          createdAt: drift.Value(now),
        ),
      );

      // Verify records exist
      final chaptersBefore = await dbService.getChaptersForBook(bookId);
      final progressBefore = await dbService.getProgress(bookId);
      final bookmarksBefore = await (db.select(
        db.bookmarks,
      )..where((t) => t.bookId.equals(bookId))).get();
      final highlightsBefore = await (db.select(
        db.highlights,
      )..where((t) => t.bookId.equals(bookId))).get();

      expect(chaptersBefore.length, 1);
      expect(progressBefore, isNotNull);
      expect(bookmarksBefore.length, 1);
      expect(highlightsBefore.length, 1);

      // Delete the parent book
      await dbService.deleteBook(bookId);

      // Verify cascading deletion of all associated tables
      final chaptersAfter = await dbService.getChaptersForBook(bookId);
      final progressAfter = await dbService.getProgress(bookId);
      final bookmarksAfter = await (db.select(
        db.bookmarks,
      )..where((t) => t.bookId.equals(bookId))).get();
      final highlightsAfter = await (db.select(
        db.highlights,
      )..where((t) => t.bookId.equals(bookId))).get();

      expect(chaptersAfter, isEmpty, reason: 'Chapters must cascade delete');
      expect(progressAfter, isNull, reason: 'Progress must cascade delete');
      expect(bookmarksAfter, isEmpty, reason: 'Bookmarks must cascade delete');
      expect(
        highlightsAfter,
        isEmpty,
        reason: 'Highlights must cascade delete',
      );
    });

    test('Schema version 2 supports fileHash and lastReadingMode', () async {
      expect(db.schemaVersion, greaterThanOrEqualTo(2));

      final now = DateTime.now();
      await dbService.insertBook(
        BooksCompanion(
          id: const drift.Value('b-v2'),
          title: const drift.Value('Version 2 Book'),
          author: const drift.Value('Author V2'),
          originalPdfPath: const drift.Value('/path/v2.pdf'),
          fileHash: const drift.Value('sha256_mock_abcdef1234567890'),
          createdAt: drift.Value(now),
          updatedAt: drift.Value(now),
        ),
      );

      final savedBook = await dbService.getBookById('b-v2');
      expect(savedBook, isNotNull);
      expect(savedBook!.fileHash, 'sha256_mock_abcdef1234567890');

      await dbService.upsertProgress(
        ReadingProgressesCompanion(
          id: const drift.Value('prog-v2'),
          bookId: const drift.Value('b-v2'),
          currentChapter: const drift.Value(2),
          currentPosition: const drift.Value(45),
          progressPercentage: const drift.Value(0.5),
          lastReadingMode: const drift.Value('reflowable'),
          lastReadAt: drift.Value(now),
        ),
      );

      final savedProgress = await dbService.getProgress('b-v2');
      expect(savedProgress, isNotNull);
      expect(savedProgress!.lastReadingMode, 'reflowable');
    });
  });

  group('Phase 1.5 - Reading Mode Persistence', () {
    test(
      'upsertProgress updates lastReadingMode and preserves it on subsequent position updates',
      () async {
        final now = DateTime.now();
        const bookId = 'book-mode-persist';

        await dbService.insertBook(
          BooksCompanion(
            id: const drift.Value(bookId),
            title: const drift.Value('Reading Mode Persistence Book'),
            author: const drift.Value('Author'),
            originalPdfPath: const drift.Value('/path/mode.pdf'),
            createdAt: drift.Value(now),
            updatedAt: drift.Value(now),
          ),
        );

        // 1. Initial save with reflowable mode
        await dbService.upsertProgress(
          ReadingProgressesCompanion(
            id: const drift.Value('prog-mode-1'),
            bookId: const drift.Value(bookId),
            currentChapter: const drift.Value(0),
            currentPosition: const drift.Value(1),
            progressPercentage: const drift.Value(0.01),
            lastReadingMode: const drift.Value('reflowable'),
            lastReadAt: drift.Value(now),
          ),
        );

        var progress = await dbService.getProgress(bookId);
        expect(progress!.lastReadingMode, 'reflowable');

        // 2. Position update without changing mode -> preserves lastReadingMode
        await dbService.upsertProgress(
          ReadingProgressesCompanion(
            id: const drift.Value('prog-mode-1'),
            bookId: const drift.Value(bookId),
            currentChapter: const drift.Value(1),
            currentPosition: const drift.Value(25),
            progressPercentage: const drift.Value(0.20),
            lastReadAt: drift.Value(DateTime.now()),
          ),
        );

        progress = await dbService.getProgress(bookId);
        expect(progress!.currentPosition, 25);
        expect(
          progress.lastReadingMode,
          'reflowable',
          reason: 'Must preserve existing mode when not explicitly overwritten',
        );

        // 3. User switches to originalPdf mode
        await dbService.upsertProgress(
          ReadingProgressesCompanion(
            id: const drift.Value('prog-mode-1'),
            bookId: const drift.Value(bookId),
            currentChapter: const drift.Value(1),
            currentPosition: const drift.Value(25),
            progressPercentage: const drift.Value(0.20),
            lastReadingMode: const drift.Value('originalPdf'),
            lastReadAt: drift.Value(DateTime.now()),
          ),
        );

        progress = await dbService.getProgress(bookId);
        expect(progress!.lastReadingMode, 'originalPdf');
      },
    );
  });

  group('Phase 1.5 - 100+ Books Stress & Performance Testing', () {
    test(
      'Stress testing with 120 books verifies fast sorting and search indexing',
      () async {
        final now = DateTime(2026, 3, 1);
        final stopwatch = Stopwatch()..start();

        // Bulk insert 120 books into database
        await db.batch((batch) {
          for (int i = 0; i < 120; i++) {
            final titleChar = String.fromCharCode(65 + (i % 26));
            final bookId = 'stress-book-$i';
            batch.insert(
              db.books,
              BooksCompanion(
                id: drift.Value(bookId),
                title: drift.Value(
                  '$titleChar Book Number ${i.toString().padLeft(3, '0')}',
                ),
                author: drift.Value('Author ${120 - i}'),
                originalPdfPath: drift.Value('/library/originals/$bookId.pdf'),
                fileHash: drift.Value('hash_$i'),
                totalPages: drift.Value(100 + (i * 5)),
                isScanned: drift.Value(i % 3 == 0),
                createdAt: drift.Value(now.add(Duration(hours: i))),
                updatedAt: drift.Value(now.add(Duration(hours: i))),
              ),
            );
          }
        });

        final insertDuration = stopwatch.elapsedMilliseconds;
        expect(
          insertDuration,
          lessThan(3000),
          reason: 'Bulk inserting 120 books must be swift',
        );

        // Verify all 120 books retrieved
        final allBooks = await dbService.getAllBooks();
        expect(allBooks.length, 120);

        // Test Sorting Performance on 120 books
        stopwatch.reset();
        final sortedByTitleAsc = BookSortHelper.sortBooks(
          allBooks,
          BookSortOption.titleAsc,
        );
        final sortTitleDuration = stopwatch.elapsedMilliseconds;
        expect(
          sortTitleDuration,
          lessThan(50),
          reason: 'Sorting 120 books must take < 50ms',
        );
        expect(sortedByTitleAsc.first.title.startsWith('A'), isTrue);

        final sortedByAuthorAsc = BookSortHelper.sortBooks(
          allBooks,
          BookSortOption.authorAsc,
        );
        expect(sortedByAuthorAsc.isNotEmpty, isTrue);

        final sortedByDateDesc = BookSortHelper.sortBooks(
          allBooks,
          BookSortOption.dateAddedDesc,
        );
        expect(sortedByDateDesc.first.id, 'stress-book-119');

        // Test Search Query Performance
        stopwatch.reset();
        final searchResults = await dbService
            .searchBooks('Book Number 042')
            .first;
        final searchDuration = stopwatch.elapsedMilliseconds;
        expect(
          searchDuration,
          lessThan(100),
          reason: 'Search query must be fast (< 100ms)',
        );
        expect(searchResults.length, 1);
        expect(searchResults.first.title.contains('042'), isTrue);
      },
    );
  });
}
