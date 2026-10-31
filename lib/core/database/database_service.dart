import 'package:drift/drift.dart';
import 'app_database.dart';
import '../utils/file_storage_service.dart';

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

  Future<int> updateBookMetadata(
    String bookId, {
    required String title,
    required String author,
    String? description,
  }) {
    return (db.update(db.books)..where((t) => t.id.equals(bookId))).write(
      BooksCompanion(
        title: Value(title),
        author: Value(author),
        description: Value(description),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<Book?> findDuplicateBook({
    required String title,
    required String author,
  }) async {
    final trimmedTitle = title.trim().toLowerCase();
    final trimmedAuthor = author.trim().toLowerCase();

    // 1. Exact match on title and author
    final exactMatches = await (db.select(db.books)
          ..where((t) =>
              t.title.lower().equals(trimmedTitle) &
              t.author.lower().equals(trimmedAuthor)))
        .get();
    if (exactMatches.isNotEmpty) {
      return exactMatches.first;
    }

    // 2. Exact match on title alone (if author was unknown or slightly formatted)
    final titleMatches = await (db.select(db.books)
          ..where((t) => t.title.lower().equals(trimmedTitle)))
        .get();
    if (titleMatches.isNotEmpty) {
      return titleMatches.first;
    }

    return null;
  }

  Future<List<Book>> getAllBooks() {
    return db.select(db.books).get();
  }

  Future<Book?> findBookByFileHash(String fileHash) {
    return (db.select(db.books)..where((t) => t.fileHash.equals(fileHash)))
        .getSingleOrNull();
  }

  Future<bool> isPathReferencedByOtherBook(
    String path, {
    required String excludeBookId,
  }) async {
    final matches = await (db.select(db.books)
          ..where((t) =>
              t.id.equals(excludeBookId).not() &
              (t.originalPdfPath.equals(path) |
                  t.coverPath.equals(path) |
                  t.processedBookPath.equals(path))))
        .get();
    return matches.isNotEmpty;
  }

  Future<int> updateBookPdfPath(String bookId, String newPdfPath) {
    return (db.update(db.books)..where((t) => t.id.equals(bookId))).write(
      BooksCompanion(
        originalPdfPath: Value(newPdfPath),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<int> deleteBook(String id) {
    return (db.delete(db.books)..where((t) => t.id.equals(id))).go();
  }

  Future<void> safeDeleteBook(String bookId) async {
    final book = await getBookById(bookId);
    if (book == null) return;

    await FileStorageService.deleteBookFilesSafe(
      dbService: this,
      bookId: book.id,
      originalPdfPath: book.originalPdfPath,
      processedBookPath: book.processedBookPath,
      coverPath: book.coverPath,
    );

    await deleteBook(bookId);
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
          lastReadingMode: progress.lastReadingMode.present
              ? progress.lastReadingMode
              : Value(existing.lastReadingMode),
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

  Stream<List<BookmarkWithBook>> watchAllBookmarks() {
    final query = db.select(db.bookmarks).join([
      innerJoin(
        db.books,
        db.books.id.equalsExp(db.bookmarks.bookId),
      ),
    ])..orderBy([
        OrderingTerm(expression: db.bookmarks.createdAt, mode: OrderingMode.desc),
      ]);

    return query.watch().map((rows) {
      return rows.map((r) => BookmarkWithBook(
        bookmark: r.readTable(db.bookmarks),
        book: r.readTable(db.books),
      )).toList();
    });
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

  Stream<List<HighlightWithBook>> watchAllHighlights() {
    final query = db.select(db.highlights).join([
      innerJoin(
        db.books,
        db.books.id.equalsExp(db.highlights.bookId),
      ),
    ])..orderBy([
        OrderingTerm(expression: db.highlights.createdAt, mode: OrderingMode.desc),
      ]);

    return query.watch().map((rows) {
      return rows.map((r) => HighlightWithBook(
        highlight: r.readTable(db.highlights),
        book: r.readTable(db.books),
      )).toList();
    });
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
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .watch();
  }

  Future<int> createCollection(CollectionsCompanion collection) {
    return db.into(db.collections).insert(collection);
  }

  Future<int> updateCollection(String id, {required String name, String? description}) {
    return (db.update(db.collections)..where((t) => t.id.equals(id))).write(
      CollectionsCompanion(
        name: Value(name),
        description: Value(description),
      ),
    );
  }

  Future<int> deleteCollection(String id) {
    return (db.delete(db.collections)..where((t) => t.id.equals(id))).go();
  }

  Stream<List<Book>> watchBooksInCollection(String collectionId) {
    final query = db.select(db.books).join([
      innerJoin(
        db.bookCollections,
        db.bookCollections.bookId.equalsExp(db.books.id),
      ),
    ])
      ..where(db.bookCollections.collectionId.equals(collectionId))
      ..orderBy([
        OrderingTerm(expression: db.books.updatedAt, mode: OrderingMode.desc),
      ]);

    return query.watch().map((rows) {
      return rows.map((r) => r.readTable(db.books)).toList();
    });
  }

  Future<List<String>> getCollectionIdsForBook(String bookId) async {
    final rows = await (db.select(db.bookCollections)
          ..where((t) => t.bookId.equals(bookId)))
        .get();
    return rows.map((r) => r.collectionId).toList();
  }

  Stream<List<String>> watchCollectionIdsForBook(String bookId) {
    return (db.select(db.bookCollections)..where((t) => t.bookId.equals(bookId)))
        .watch()
        .map((rows) => rows.map((r) => r.collectionId).toList());
  }

  Stream<Map<String, int>> watchCollectionBookCounts() {
    return db.select(db.bookCollections).watch().map((rows) {
      final counts = <String, int>{};
      for (final r in rows) {
        counts[r.collectionId] = (counts[r.collectionId] ?? 0) + 1;
      }
      return counts;
    });
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

class BookmarkWithBook {
  final Bookmark bookmark;
  final Book book;

  const BookmarkWithBook({required this.bookmark, required this.book});
}

class HighlightWithBook {
  final Highlight highlight;
  final Book book;

  const HighlightWithBook({required this.highlight, required this.book});
}

