import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

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

  group('DatabaseService Tests', () {
    test('Insert, query, and delete book', () async {
      final now = DateTime.now();
      const bookId = 'book-001';

      await dbService.insertBook(
        BooksCompanion(
          id: const Value(bookId),
          title: const Value('Pride and Prejudice'),
          author: const Value('Jane Austen'),
          originalPdfPath: const Value('/path/to/pride.pdf'),
          totalPages: const Value(350),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      final book = await dbService.getBookById(bookId);
      expect(book, isNotNull);
      expect(book!.title, 'Pride and Prejudice');
      expect(book.author, 'Jane Austen');

      // Test reading progress
      await dbService.upsertProgress(
        ReadingProgressesCompanion(
          id: const Value('prog-001'),
          bookId: const Value(bookId),
          currentChapter: const Value(2),
          currentPosition: const Value(45),
          progressPercentage: const Value(0.15),
          lastReadAt: Value(now),
        ),
      );

      final prog = await dbService.getProgress(bookId);
      expect(prog, isNotNull);
      expect(prog!.currentPosition, 45);
      expect(prog.progressPercentage, 0.15);

      // Test bookmarks
      await dbService.addBookmark(
        BookmarksCompanion(
          id: const Value('bm-001'),
          bookId: const Value(bookId),
          position: const Value(45),
          label: const Value('Favorite passage'),
          createdAt: Value(now),
        ),
      );

      final bookmarks = await dbService.watchBookmarks(bookId).first;
      expect(bookmarks.length, 1);
      expect(bookmarks.first.label, 'Favorite passage');

      // Delete book
      await dbService.deleteBook(bookId);
      final deleted = await dbService.getBookById(bookId);
      expect(deleted, isNull);
    });
  });
}
