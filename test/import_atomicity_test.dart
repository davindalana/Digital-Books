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

  BooksCompanion buildBook(String id) {
    final now = DateTime.now();
    return BooksCompanion(
      id: Value(id),
      title: const Value('Atomic Import'),
      author: const Value('Tester'),
      originalPdfPath: const Value('/tmp/atomic.pdf'),
      totalPages: const Value(10),
      createdAt: Value(now),
      updatedAt: Value(now),
    );
  }

  ReadingProgressesCompanion buildProgress(String bookId, String id) {
    return ReadingProgressesCompanion(
      id: Value(id),
      bookId: Value(bookId),
      currentChapter: const Value(0),
      currentPosition: const Value(0),
      progressPercentage: const Value(0.0),
      lastReadAt: Value(DateTime.now()),
    );
  }

  test(
    'importBookAtomic rolls back the book when chapter insertion fails',
    () async {
      const bookId = 'atomic-book';
      await expectLater(
        dbService.importBookAtomic(
          book: buildBook(bookId),
          chapters: [
            ChaptersCompanion(
              id: const Value('duplicate-chapter'),
              bookId: const Value(bookId),
              title: const Value('One'),
              chapterIndex: const Value(0),
            ),
            ChaptersCompanion(
              id: const Value('duplicate-chapter'),
              bookId: const Value(bookId),
              title: const Value('Two'),
              chapterIndex: const Value(1),
            ),
          ],
          progress: buildProgress(bookId, 'atomic-progress'),
        ),
        throwsA(anything),
      );

      expect(await dbService.getBookById(bookId), isNull);
      expect(await dbService.getChaptersForBook(bookId), isEmpty);
      expect(await dbService.getProgress(bookId), isNull);
    },
  );

  test(
    'concurrent progress upserts do not violate the unique book id',
    () async {
      const bookId = 'progress-book';
      await dbService.insertBook(buildBook(bookId));

      // Both writes may start before either row exists. The old read-then-insert
      // implementation could let the second insert violate UNIQUE(book_id).
      await Future.wait([
        dbService.upsertProgress(buildProgress(bookId, 'progress-a')),
        dbService.upsertProgress(buildProgress(bookId, 'progress-b')),
      ]);

      final progress = await dbService.getProgress(bookId);
      expect(progress, isNotNull);
      expect(progress!.bookId, bookId);

      final rows = await db.select(db.readingProgresses).get();
      expect(rows.where((r) => r.bookId == bookId).length, equals(1));
    },
  );

  test('progress upsert preserves lastReadingMode when not supplied', () async {
    const bookId = 'mode-book';
    await dbService.insertBook(buildBook(bookId));

    await dbService.upsertProgress(
      ReadingProgressesCompanion(
        id: const Value('mode-progress'),
        bookId: const Value(bookId),
        currentChapter: const Value(4),
        currentPosition: const Value(12),
        progressPercentage: const Value(0.4),
        lastReadingMode: const Value('reflowable_paginated'),
        lastReadAt: Value(DateTime.now()),
      ),
    );

    await dbService.upsertProgress(
      ReadingProgressesCompanion(
        id: const Value('mode-progress-2'),
        bookId: const Value(bookId),
        currentChapter: const Value(5),
        currentPosition: const Value(2),
        progressPercentage: const Value(0.5),
        lastReadAt: Value(DateTime.now()),
      ),
    );

    final progress = await dbService.getProgress(bookId);
    expect(progress!.lastReadingMode, equals('reflowable_paginated'));
    expect(progress.currentChapter, equals(5));
    expect(progress.currentPosition, equals(2));
  });
}
