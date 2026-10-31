import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/core/providers/database_providers.dart';
import 'package:digital_books/core/utils/book_sort_helper.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DatabaseService dbService;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dbService = DatabaseService(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('Phase 1.6 - Performance & Stress Benchmarks', () {
    test('100 Books Benchmark: Insert, Query, Sort, and Search', () async {
      final now = DateTime(2026, 3, 1);
      final sw = Stopwatch()..start();

      await db.batch((batch) {
        for (int i = 0; i < 100; i++) {
          final id = 'book-100-$i';
          batch.insert(
            db.books,
            BooksCompanion(
              id: drift.Value(id),
              title: drift.Value('Book Title ${i.toString().padLeft(3, '0')}'),
              author: drift.Value('Author ${(100 - i) % 20}'),
              originalPdfPath: drift.Value('/path/$id.pdf'),
              fileHash: drift.Value('hash_100_$i'),
              totalPages: drift.Value(100 + i),
              isScanned: drift.Value(i % 4 == 0),
              createdAt: drift.Value(now.add(Duration(minutes: i))),
              updatedAt: drift.Value(now.add(Duration(minutes: i))),
            ),
          );
        }
      });
      final insertMs = sw.elapsedMilliseconds;

      sw.reset();
      final allBooks = await dbService.getAllBooks();
      final fetchMs = sw.elapsedMilliseconds;
      expect(allBooks.length, 100);

      sw.reset();
      final sortedByTitle = BookSortHelper.sortBooks(allBooks, BookSortOption.titleAsc);
      final sortTitleMs = sw.elapsedMilliseconds;
      expect(sortedByTitle.first.title, 'Book Title 000');

      sw.reset();
      final sortedByAuthor = BookSortHelper.sortBooks(allBooks, BookSortOption.authorAsc);
      final sortAuthorMs = sw.elapsedMilliseconds;
      expect(sortedByAuthor.isNotEmpty, isTrue);

      sw.reset();
      final searchResults = await dbService.searchBooks('042').first;
      final searchMs = sw.elapsedMilliseconds;
      expect(searchResults.length, 1);

      // Print real metrics for audit report
      // ignore: avoid_print
      print('[BENCHMARK 100 BOOKS] Insert: ${insertMs}ms | Fetch: ${fetchMs}ms | SortTitle: ${sortTitleMs}ms | SortAuthor: ${sortAuthorMs}ms | Search: ${searchMs}ms');

      expect(sortTitleMs, lessThan(30));
      expect(searchMs, lessThan(50));
    });

    test('1,000 Books Benchmark: Bulk Insert, Sort, and Search', () async {
      final now = DateTime(2026, 3, 1);
      final sw = Stopwatch()..start();

      await db.batch((batch) {
        for (int i = 0; i < 1000; i++) {
          final id = 'book-1k-$i';
          batch.insert(
            db.books,
            BooksCompanion(
              id: drift.Value(id),
              title: drift.Value('Volume ${(i % 50).toString().padLeft(3, '0')} - Book Title $i'),
              author: drift.Value('Author ${i % 100}'),
              originalPdfPath: drift.Value('/library/books/$id.pdf'),
              fileHash: drift.Value('hash_1k_$i'),
              totalPages: drift.Value(50 + (i % 500)),
              isScanned: drift.Value(i % 5 == 0),
              createdAt: drift.Value(now.add(Duration(minutes: i))),
              updatedAt: drift.Value(now.add(Duration(minutes: i))),
            ),
          );
        }
      });
      final insert1kMs = sw.elapsedMilliseconds;

      sw.reset();
      final allBooks = await dbService.getAllBooks();
      final fetch1kMs = sw.elapsedMilliseconds;
      expect(allBooks.length, 1000);

      sw.reset();
      final sortedByTitle = BookSortHelper.sortBooks(allBooks, BookSortOption.titleAsc);
      final sort1kTitleMs = sw.elapsedMilliseconds;
      expect(sortedByTitle.length, 1000);

      sw.reset();
      final sortedByDate = BookSortHelper.sortBooks(allBooks, BookSortOption.dateAddedDesc);
      final sort1kDateMs = sw.elapsedMilliseconds;
      expect(sortedByDate.first.id, 'book-1k-999');

      sw.reset();
      final searchResults = await dbService.searchBooks('Book Title 777').first;
      final search1kMs = sw.elapsedMilliseconds;
      expect(searchResults.length, 1);

      // Print real metrics for audit report
      // ignore: avoid_print
      print('[BENCHMARK 1,000 BOOKS] Insert: ${insert1kMs}ms | Fetch: ${fetch1kMs}ms | SortTitle: ${sort1kTitleMs}ms | SortDate: ${sort1kDateMs}ms | Search: ${search1kMs}ms');

      expect(sort1kTitleMs, lessThan(80));
      expect(search1kMs, lessThan(100));
    });

    test('5,000 Books Stress Benchmark: Bulk Scale Scalability', () async {
      final now = DateTime(2026, 3, 1);
      final sw = Stopwatch()..start();

      await db.batch((batch) {
        for (int i = 0; i < 5000; i++) {
          final id = 'book-5k-$i';
          batch.insert(
            db.books,
            BooksCompanion(
              id: drift.Value(id),
              title: drift.Value('Encyclopedic Entry ${i.toString().padLeft(4, '0')}'),
              author: drift.Value('Scholar ${(i % 200)}'),
              originalPdfPath: drift.Value('/vault/$id.pdf'),
              fileHash: drift.Value('hash_5k_$i'),
              totalPages: drift.Value(200 + (i % 800)),
              isScanned: drift.Value(i % 10 == 0),
              createdAt: drift.Value(now.add(Duration(seconds: i * 30))),
              updatedAt: drift.Value(now.add(Duration(seconds: i * 30))),
            ),
          );
        }
      });
      final insert5kMs = sw.elapsedMilliseconds;

      sw.reset();
      final allBooks = await dbService.getAllBooks();
      final fetch5kMs = sw.elapsedMilliseconds;
      expect(allBooks.length, 5000);

      sw.reset();
      final sortedByTitle = BookSortHelper.sortBooks(allBooks, BookSortOption.titleAsc);
      final sort5kTitleMs = sw.elapsedMilliseconds;
      expect(sortedByTitle.length, 5000);

      sw.reset();
      final searchResults = await dbService.searchBooks('Entry 4999').first;
      final search5kMs = sw.elapsedMilliseconds;
      expect(searchResults.length, 1);

      // Print real metrics for audit report
      // ignore: avoid_print
      print('[BENCHMARK 5,000 BOOKS] Insert: ${insert5kMs}ms | Fetch: ${fetch5kMs}ms | SortTitle: ${sort5kTitleMs}ms | Search: ${search5kMs}ms');

      expect(sort5kTitleMs, lessThan(350));
      expect(search5kMs, lessThan(200));
    });

    test('Repeated Reader Open/Close Loop (100 Iterations)', () async {
      final sw = Stopwatch()..start();
      const bookId = 'book-reader-loop';
      final now = DateTime.now();

      await dbService.insertBook(
        BooksCompanion(
          id: const drift.Value(bookId),
          title: const drift.Value('Loop Book'),
          author: const drift.Value('Author'),
          originalPdfPath: const drift.Value('/path/loop.pdf'),
          createdAt: drift.Value(now),
          updatedAt: drift.Value(now),
        ),
      );

      // Simulate 100 open-read-save-close cycles
      for (int i = 0; i < 100; i++) {
        final progress = await dbService.getProgress(bookId);
        final nextPos = (progress?.currentPosition ?? 0) + 1;
        await dbService.upsertProgress(
          ReadingProgressesCompanion(
            id: const drift.Value('prog-loop'),
            bookId: const drift.Value(bookId),
            currentChapter: const drift.Value(0),
            currentPosition: drift.Value(nextPos),
            progressPercentage: drift.Value((nextPos / 200).clamp(0.0, 1.0)),
            lastReadingMode: drift.Value(i % 2 == 0 ? 'originalPdf' : 'reflowable'),
            lastReadAt: drift.Value(DateTime.now()),
          ),
        );
      }

      final totalLoopMs = sw.elapsedMilliseconds;
      final finalProgress = await dbService.getProgress(bookId);
      expect(finalProgress!.currentPosition, 100);

      // Print real metrics for audit report
      // ignore: avoid_print
      print('[BENCHMARK 100 OPEN/CLOSE LOOPS] Completed in: ${totalLoopMs}ms (avg ${(totalLoopMs / 100).toStringAsFixed(2)}ms per cycle)');

      expect(totalLoopMs, lessThan(2000), reason: '100 database open-save cycles must complete under 2 seconds');
    });

    test('Repeated Search and Sort Stress (50 Iterations)', () async {
      // Use existing 100 books from helper
      final now = DateTime.now();
      await db.batch((batch) {
        for (int i = 0; i < 200; i++) {
          batch.insert(
            db.books,
            BooksCompanion(
              id: drift.Value('stress-$i'),
              title: drift.Value('Knowledge Item $i'),
              author: drift.Value('Author ${i % 10}'),
              originalPdfPath: drift.Value('/p/$i.pdf'),
              createdAt: drift.Value(now.add(Duration(minutes: i))),
              updatedAt: drift.Value(now.add(Duration(minutes: i))),
            ),
          );
        }
      });

      final books = await dbService.getAllBooks();
      final sw = Stopwatch()..start();

      for (int i = 0; i < 50; i++) {
        final option = BookSortOption.values[i % BookSortOption.values.length];
        final sorted = BookSortHelper.sortBooks(books, option);
        expect(sorted.length, 200);

        final queryResults = await dbService.searchBooks('Item ${i * 3}').first;
        expect(queryResults, isNotNull);
      }

      final totalStressMs = sw.elapsedMilliseconds;
      // ignore: avoid_print
      print('[BENCHMARK 50 RAPID SEARCH/SORT OPERATIONS] Completed in: ${totalStressMs}ms (avg ${(totalStressMs / 50).toStringAsFixed(2)}ms per op)');

      expect(totalStressMs, lessThan(1500));
    });
  });
}
