import 'package:drift/drift.dart';
import 'app_database.dart';

class DatabaseService {
  final AppDatabase db;

  DatabaseService(this.db);

  // --- Books ---
  Stream<List<Book>> watchAllBooks() {
    return (db.select(db.books)
          ..orderBy([(t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc)]))
        .watch();
  }

  Stream<List<Book>> watchRecentlyAdded({int limit = 10}) {
    return (db.select(db.books)
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)])
          ..limit(limit))
        .watch();
  }

  Stream<List<BookWithProgress>> watchCurrentlyReading() {
    final query = db.select(db.books).join([
      innerJoin(
        db.readingProgresses,
        db.readingProgresses.bookId.equalsExp(db.books.id),
      ),
    ])
      ..where(db.readingProgresses.progressPercentage.isBiggerThanValue(0.0) &
          db.readingProgresses.progressPercentage.isSmallerThanValue(0.999))
      ..orderBy([
        OrderingTerm(
            expression: db.readingProgresses.lastReadAt, mode: OrderingMode.desc)
      ]);

    return query.watch().map((rows) {
      return rows.map((row) {
        return BookWithProgress(
          book: row.readTable(db.books),
          progress: row.readTable(db.readingProgresses),
        );
      }).toList();
    });
  }

  Stream<List<BookWithProgress>> watchFinishedBooks() {
    final query = db.select(db.books).join([
      innerJoin(
        db.readingProgresses,
        db.readingProgresses.bookId.equalsExp(db.books.id),
      ),
    ])
      ..where(
          db.readingProgresses.progressPercentage.isBiggerOrEqualValue(0.999))
      ..orderBy([
        OrderingTerm(
            expression: db.readingProgresses.lastReadAt, mode: OrderingMode.desc)
      ]);

    return query.watch().map((rows) {
      return rows.map((row) {
        return BookWithProgress(
          book: row.readTable(db.books),
          progress: row.readTable(db.readingProgresses),
        );
      }).toList();
    });
  }

  Future<Book?> getBookById(String id) {
    return (db.select(db.books)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<int> insertBook(BooksCompanion book) {
    return db.into(db.books).insertOnConflictUpdate(book);
  }

  Future<bool> updateBook(BooksCompanion book) {
    return db.update(db.books).replace(book);
  }

  Future<int> deleteBook(String id) {
    return (db.delete(db.books)..where((t) => t.id.equals(id))).go();
  }

  Stream<List<Book>> searchBooks(String query) {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return watchAllBooks();
    return (db.select(db.books)
          ..where((t) =>
              t.title.lower().like('%$trimmed%') |
              t.author.lower().like('%$trimmed%'))
          ..orderBy([(t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc)]))
        .watch();
  }

  // --- Chapters ---
  Future<List<Chapter>> getChaptersForBook(String bookId) {
    return (db.select(db.chapters)
          ..where((t) => t.bookId.equals(bookId))
          ..orderBy([(t) => OrderingTerm(expression: t.chapterIndex)]))
        .get();
  }

  Future<void> replaceChaptersForBook(
      String bookId, List<ChaptersCompanion> chapters) async {
    await db.transaction(() async {
      await (db.delete(db.chapters)..where((t) => t.bookId.equals(bookId))).go();
      for (final chapter in chapters) {
        await db.into(db.chapters).insert(chapter);
      }
    });
  }

  // --- Reading Progress ---
  Stream<ReadingProgress?> watchProgress(String bookId) {
    return (db.select(db.readingProgresses)
          ..where((t) => t.bookId.equals(bookId)))
        .watchSingleOrNull();
  }

  Future<ReadingProgress?> getProgress(String bookId) {
    return (db.select(db.readingProgresses)
          ..where((t) => t.bookId.equals(bookId)))
        .getSingleOrNull();
  }

  Future<int> upsertProgress(ReadingProgressesCompanion progress) async {
    final bookIdVal = progress.bookId.value;
    final existing = await getProgress(bookIdVal);
    if (existing != null) {
      return (db.update(db.readingProgresses)
            ..where((t) => t.bookId.equals(bookIdVal)))
          .write(
        ReadingProgressesCompanion(
          currentChapter: progress.currentChapter,
          currentPosition: progress.currentPosition,
          progressPercentage: progress.progressPercentage,
          lastReadAt: progress.lastReadAt,
        ),
      );
    } else {
      return db.into(db.readingProgresses).insert(progress);
    }
  }

  // --- Bookmarks ---
  Stream<List<Bookmark>> watchBookmarks(String bookId) {
    return (db.select(db.bookmarks)
          ..where((t) => t.bookId.equals(bookId))
          ..orderBy([(t) => OrderingTerm(expression: t.position)]))
        .watch();
  }

  Future<int> addBookmark(BookmarksCompanion bookmark) {
    return db.into(db.bookmarks).insert(bookmark);
  }

  Future<int> deleteBookmark(String id) {
    return (db.delete(db.bookmarks)..where((t) => t.id.equals(id))).go();
  }

  // --- Highlights ---
  Stream<List<Highlight>> watchHighlights(String bookId) {
    return (db.select(db.highlights)
          ..where((t) => t.bookId.equals(bookId))
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
        .watch();
  }

  Future<int> addHighlight(HighlightsCompanion highlight) {
    return db.into(db.highlights).insert(highlight);
  }

  Future<int> deleteHighlight(String id) {
    return (db.delete(db.highlights)..where((t) => t.id.equals(id))).go();
  }

  // --- Collections ---
  Stream<List<Collection>> watchCollections() {
    return (db.select(db.collections)
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
        .watch();
  }

  Future<int> createCollection(CollectionsCompanion collection) {
    return db.into(db.collections).insert(collection);
  }

  Future<int> deleteCollection(String id) {
    return (db.delete(db.collections)..where((t) => t.id.equals(id))).go();
  }

  Future<int> addBookToCollection(String bookId, String collectionId) {
    return db.into(db.bookCollections).insertOnConflictUpdate(
          BookCollectionsCompanion(
            bookId: Value(bookId),
            collectionId: Value(collectionId),
          ),
        );
  }

  Future<int> removeBookFromCollection(String bookId, String collectionId) {
    return (db.delete(db.bookCollections)
          ..where(
              (t) => t.bookId.equals(bookId) & t.collectionId.equals(collectionId)))
        .go();
  }
}

class BookWithProgress {
  final Book book;
  final ReadingProgress? progress;

  const BookWithProgress({required this.book, this.progress});
}

