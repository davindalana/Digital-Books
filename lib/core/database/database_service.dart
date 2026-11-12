import 'package:drift/drift.dart';
import 'app_database.dart';
import '../utils/file_storage_service.dart';
import '../../features/reader/domain/models/book_annotation.dart';

class DatabaseService {
  final AppDatabase db;

  DatabaseService(this.db);

  // --- Books ---
  Stream<List<Book>> watchAllBooks() {
    return (db.select(db.books)..orderBy([
          (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
        ]))
        .watch();
  }

  Stream<List<Book>> watchRecentlyAdded({int limit = 10}) {
    return (db.select(db.books)
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
          ])
          ..limit(limit))
        .watch();
  }

  Stream<List<BookWithProgress>> watchCurrentlyReading() {
    final query =
        db.select(db.books).join([
            innerJoin(
              db.readingProgresses,
              db.readingProgresses.bookId.equalsExp(db.books.id),
            ),
          ])
          ..where(
            db.readingProgresses.progressPercentage.isBiggerThanValue(0.0) &
                db.readingProgresses.progressPercentage.isSmallerThanValue(
                  0.999,
                ),
          )
          ..orderBy([
            OrderingTerm(
              expression: db.readingProgresses.lastReadAt,
              mode: OrderingMode.desc,
            ),
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
    final query =
        db.select(db.books).join([
            innerJoin(
              db.readingProgresses,
              db.readingProgresses.bookId.equalsExp(db.books.id),
            ),
          ])
          ..where(
            db.readingProgresses.progressPercentage.isBiggerOrEqualValue(0.999),
          )
          ..orderBy([
            OrderingTerm(
              expression: db.readingProgresses.lastReadAt,
              mode: OrderingMode.desc,
            ),
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

  Stream<List<Book>> watchUnstartedBooks() {
    final query =
        db.select(db.books).join([
            leftOuterJoin(
              db.readingProgresses,
              db.readingProgresses.bookId.equalsExp(db.books.id),
            ),
          ])
          ..where(
            db.readingProgresses.id.isNull() |
                db.readingProgresses.progressPercentage.isSmallerOrEqualValue(
                  0.0,
                ),
          )
          ..orderBy([
            OrderingTerm(
              expression: db.books.createdAt,
              mode: OrderingMode.desc,
            ),
          ]);

    return query.watch().map((rows) {
      return rows.map((row) => row.readTable(db.books)).toList();
    });
  }

  Future<Book?> getBookById(String id) {
    return (db.select(
      db.books,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
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

  Future<int> updateBookProcessedPath(String bookId, String processedBookPath) {
    return (db.update(db.books)..where((t) => t.id.equals(bookId))).write(
      BooksCompanion(
        processedBookPath: Value(processedBookPath),
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
    final exactMatches =
        await (db.select(db.books)..where(
              (t) =>
                  t.title.lower().equals(trimmedTitle) &
                  t.author.lower().equals(trimmedAuthor),
            ))
            .get();
    if (exactMatches.isNotEmpty) {
      return exactMatches.first;
    }

    // 2. Exact match on title alone (if author was unknown or slightly formatted)
    final titleMatches = await (db.select(
      db.books,
    )..where((t) => t.title.lower().equals(trimmedTitle))).get();
    if (titleMatches.isNotEmpty) {
      return titleMatches.first;
    }

    return null;
  }

  Future<List<Book>> getAllBooks() {
    return db.select(db.books).get();
  }

  Future<Book?> findBookByFileHash(String fileHash) {
    return (db.select(
      db.books,
    )..where((t) => t.fileHash.equals(fileHash))).getSingleOrNull();
  }

  Future<bool> isPathReferencedByOtherBook(
    String path, {
    required String excludeBookId,
  }) async {
    final matches =
        await (db.select(db.books)..where(
              (t) =>
                  t.id.equals(excludeBookId).not() &
                  (t.originalPdfPath.equals(path) |
                      t.coverPath.equals(path) |
                      t.processedBookPath.equals(path)),
            ))
            .get();
    return matches.isNotEmpty;
  }

  Future<int> updateBookPdfPath(
    String bookId,
    String newPdfPath, {
    String? newFileHash,
  }) {
    return (db.update(db.books)..where((t) => t.id.equals(bookId))).write(
      BooksCompanion(
        originalPdfPath: Value(newPdfPath),
        fileHash: newFileHash != null
            ? Value(newFileHash)
            : const Value.absent(),
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
          ..where(
            (t) =>
                t.title.lower().like('%$trimmed%') |
                t.author.lower().like('%$trimmed%'),
          )
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
          ]))
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
    String bookId,
    List<ChaptersCompanion> chapters,
  ) async {
    await db.transaction(() async {
      await (db.delete(
        db.chapters,
      )..where((t) => t.bookId.equals(bookId))).go();
      for (final chapter in chapters) {
        await db.into(db.chapters).insert(chapter);
      }
    });
  }

  /// Commits all state changes produced by a safe reprocess in one transaction.
  ///
  /// Bookmarks, highlights, and reading progress are never deleted: callers
  /// pass updated companions for records that could be relocated and leave the
  /// rest untouched.
  Future<void> applyReprocessingUpdates({
    required String bookId,
    required List<ChaptersCompanion> chapters,
    List<BookmarksCompanion> bookmarks = const [],
    List<HighlightsCompanion> highlights = const [],
    ReadingProgressesCompanion? progress,
  }) async {
    await db.transaction(() async {
      await (db.delete(
        db.chapters,
      )..where((t) => t.bookId.equals(bookId))).go();
      for (final chapter in chapters) {
        await db.into(db.chapters).insert(chapter);
      }
      for (final bookmark in bookmarks) {
        final id = bookmark.id.value;
        await (db.update(
          db.bookmarks,
        )..where((t) => t.id.equals(id))).write(bookmark);
      }
      for (final highlight in highlights) {
        final id = highlight.id.value;
        await (db.update(
          db.highlights,
        )..where((t) => t.id.equals(id))).write(highlight);
      }
      if (progress != null) {
        await upsertProgress(progress);
      }
    });
  }

  // --- Reading Progress ---
  Stream<ReadingProgress?> watchProgress(String bookId) {
    return (db.select(
      db.readingProgresses,
    )..where((t) => t.bookId.equals(bookId))).watchSingleOrNull();
  }

  Future<ReadingProgress?> getProgress(String bookId) {
    return (db.select(
      db.readingProgresses,
    )..where((t) => t.bookId.equals(bookId))).getSingleOrNull();
  }

  Future<int> upsertProgress(ReadingProgressesCompanion progress) async {
    // A single atomic upsert avoids the read-then-insert race where two
    // concurrent saves both observe no row and the second insert violates the
    // unique constraint on reading_progresses.book_id.
    return db
        .into(db.readingProgresses)
        .insert(
          progress,
          onConflict: DoUpdate(
            (_) => ReadingProgressesCompanion(
              currentChapter: progress.currentChapter,
              currentPosition: progress.currentPosition,
              progressPercentage: progress.progressPercentage,
              // An absent value is omitted from the UPDATE, so a caller that
              // does not know the reading mode keeps the persisted one.
              lastReadingMode: progress.lastReadingMode,
              lastReadAt: progress.lastReadAt,
            ),
            target: [db.readingProgresses.bookId],
          ),
        );
  }

  /// Persists a fully imported book, its chapters, and its initial reading
  /// progress in one transaction. Without this, a failure after inserting the
  /// book row leaves an orphaned library entry whose files may already have
  /// been cleaned up by the import pipeline.
  Future<void> importBookAtomic({
    required BooksCompanion book,
    required List<ChaptersCompanion> chapters,
    required ReadingProgressesCompanion progress,
  }) async {
    final bookId = book.id.value;
    await db.transaction(() async {
      await db.into(db.books).insertOnConflictUpdate(book);
      await (db.delete(
        db.chapters,
      )..where((t) => t.bookId.equals(bookId))).go();
      for (final chapter in chapters) {
        await db.into(db.chapters).insert(chapter);
      }
      await upsertProgress(progress);
    });
  }

  // --- Bookmarks ---
  Future<List<Bookmark>> getBookmarksForBook(String bookId) {
    return (db.select(db.bookmarks)
          ..where((t) => t.bookId.equals(bookId))
          ..orderBy([(t) => OrderingTerm(expression: t.position)]))
        .get();
  }

  Stream<List<Bookmark>> watchBookmarks(String bookId) {
    return (db.select(db.bookmarks)
          ..where((t) => t.bookId.equals(bookId))
          ..orderBy([(t) => OrderingTerm(expression: t.position)]))
        .watch();
  }

  Stream<List<BookmarkWithBook>> watchAllBookmarks() {
    final query =
        db.select(db.bookmarks).join([
          innerJoin(db.books, db.books.id.equalsExp(db.bookmarks.bookId)),
        ])..orderBy([
          OrderingTerm(
            expression: db.bookmarks.createdAt,
            mode: OrderingMode.desc,
          ),
        ]);

    return query.watch().map((rows) {
      return rows
          .map(
            (r) => BookmarkWithBook(
              bookmark: r.readTable(db.bookmarks),
              book: r.readTable(db.books),
            ),
          )
          .toList();
    });
  }

  Future<Bookmark?> getBookmarkAtLocation(
    String bookId, {
    int? page,
    String? anchorNodeId,
  }) async {
    if (anchorNodeId != null && anchorNodeId.isNotEmpty) {
      final match =
          await (db.select(db.bookmarks)..where(
                (t) =>
                    t.bookId.equals(bookId) &
                    t.anchorNodeId.equals(anchorNodeId),
              ))
              .get();
      if (match.isNotEmpty) return match.first;
    }
    if (page != null) {
      final match = await (db.select(
        db.bookmarks,
      )..where((t) => t.bookId.equals(bookId) & t.position.equals(page))).get();
      if (match.isNotEmpty) return match.first;
    }
    return null;
  }

  Future<int> addBookmark(BookmarksCompanion bookmark) {
    return db.into(db.bookmarks).insert(bookmark);
  }

  Future<int> deleteBookmark(String id) {
    return (db.delete(db.bookmarks)..where((t) => t.id.equals(id))).go();
  }

  Future<int> deleteBookmarkByLocation(
    String bookId, {
    int? page,
    String? anchorNodeId,
  }) async {
    if (anchorNodeId != null && anchorNodeId.isNotEmpty) {
      return (db.delete(db.bookmarks)..where(
            (t) =>
                t.bookId.equals(bookId) & t.anchorNodeId.equals(anchorNodeId),
          ))
          .go();
    }
    if (page != null) {
      return (db.delete(
        db.bookmarks,
      )..where((t) => t.bookId.equals(bookId) & t.position.equals(page))).go();
    }
    return 0;
  }

  // --- Highlights ---
  Future<List<Highlight>> getHighlightsForBook(String bookId) {
    return (db.select(db.highlights)
          ..where((t) => t.bookId.equals(bookId))
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
        .get();
  }

  Stream<List<Highlight>> watchHighlights(String bookId) {
    return (db.select(db.highlights)
          ..where((t) => t.bookId.equals(bookId))
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
        .watch();
  }

  Stream<List<HighlightWithBook>> watchAllHighlights() {
    final query =
        db.select(db.highlights).join([
          innerJoin(db.books, db.books.id.equalsExp(db.highlights.bookId)),
        ])..orderBy([
          OrderingTerm(
            expression: db.highlights.createdAt,
            mode: OrderingMode.desc,
          ),
        ]);

    return query.watch().map((rows) {
      return rows
          .map(
            (r) => HighlightWithBook(
              highlight: r.readTable(db.highlights),
              book: r.readTable(db.books),
            ),
          )
          .toList();
    });
  }

  Stream<List<HighlightWithBook>> watchAllNotes() {
    final query =
        db.select(db.highlights).join([
            innerJoin(db.books, db.books.id.equalsExp(db.highlights.bookId)),
          ])
          ..where(
            db.highlights.note.isNotNull() &
                db.highlights.note.equals('').not(),
          )
          ..orderBy([
            OrderingTerm(
              expression: db.highlights.createdAt,
              mode: OrderingMode.desc,
            ),
          ]);

    return query.watch().map((rows) {
      return rows
          .map(
            (r) => HighlightWithBook(
              highlight: r.readTable(db.highlights),
              book: r.readTable(db.books),
            ),
          )
          .toList();
    });
  }

  Future<Highlight?> getHighlightById(String id) {
    return (db.select(
      db.highlights,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<int> addHighlight(HighlightsCompanion highlight) {
    return db.into(db.highlights).insert(highlight);
  }

  Future<int> updateHighlightColor(String id, String color) {
    return (db.update(db.highlights)..where((t) => t.id.equals(id))).write(
      HighlightsCompanion(color: Value(color)),
    );
  }

  Future<int> updateHighlightNote(String id, String? note) {
    return (db.update(db.highlights)..where((t) => t.id.equals(id))).write(
      HighlightsCompanion(note: Value(note)),
    );
  }

  Future<int> deleteHighlight(String id) {
    return (db.delete(db.highlights)..where((t) => t.id.equals(id))).go();
  }

  // --- Unified Annotations (Highlights, Notes & Bookmarks) ---
  Stream<List<BookAnnotation>> watchAnnotationsForBook(String bookId) {
    // Combine highlights and bookmarks streams
    return watchHighlights(bookId).asyncMap((highlights) async {
      final bookmarks = await getBookmarksForBook(bookId);
      final all = <BookAnnotation>[];
      for (final h in highlights) {
        all.add(BookAnnotation.fromHighlight(h));
      }
      for (final b in bookmarks) {
        all.add(BookAnnotation.fromBookmark(b));
      }
      all.sort((a, b) {
        final pageCompare = (a.pageIndex ?? 0).compareTo(b.pageIndex ?? 0);
        if (pageCompare != 0) return pageCompare;
        return a.createdAt.compareTo(b.createdAt);
      });
      return all;
    });
  }

  Future<List<BookAnnotation>> getAnnotationsForBook(String bookId) async {
    final highlights = await getHighlightsForBook(bookId);
    final bookmarks = await getBookmarksForBook(bookId);
    final all = <BookAnnotation>[];
    for (final h in highlights) {
      all.add(BookAnnotation.fromHighlight(h));
    }
    for (final b in bookmarks) {
      all.add(BookAnnotation.fromBookmark(b));
    }
    all.sort((a, b) {
      final pageCompare = (a.pageIndex ?? 0).compareTo(b.pageIndex ?? 0);
      if (pageCompare != 0) return pageCompare;
      return a.createdAt.compareTo(b.createdAt);
    });
    return all;
  }

  Future<void> saveAnnotation(BookAnnotation annotation) async {
    if (annotation.isBookmark) {
      await db
          .into(db.bookmarks)
          .insertOnConflictUpdate(annotation.toBookmarkCompanion());
    } else {
      await db
          .into(db.highlights)
          .insertOnConflictUpdate(annotation.toHighlightCompanion());
    }
  }

  Future<void> deleteAnnotation(String id, AnnotationType type) async {
    if (type == AnnotationType.bookmark) {
      await deleteBookmark(id);
    } else {
      await deleteHighlight(id);
    }
  }

  // --- Collections ---
  Future<List<Collection>> getAllCollections() {
    return (db.select(
      db.collections,
    )..orderBy([(t) => OrderingTerm(expression: t.name)])).get();
  }

  Stream<List<Collection>> watchCollections() {
    return (db.select(
      db.collections,
    )..orderBy([(t) => OrderingTerm(expression: t.name)])).watch();
  }

  Future<int> createCollection(CollectionsCompanion collection) {
    return db.into(db.collections).insert(collection);
  }

  Future<int> updateCollection(
    String id, {
    required String name,
    String? description,
  }) {
    return (db.update(db.collections)..where((t) => t.id.equals(id))).write(
      CollectionsCompanion(name: Value(name), description: Value(description)),
    );
  }

  Future<int> deleteCollection(String id) {
    return (db.delete(db.collections)..where((t) => t.id.equals(id))).go();
  }

  Stream<List<Book>> watchBooksInCollection(String collectionId) {
    final query =
        db.select(db.books).join([
            innerJoin(
              db.bookCollections,
              db.bookCollections.bookId.equalsExp(db.books.id),
            ),
          ])
          ..where(db.bookCollections.collectionId.equals(collectionId))
          ..orderBy([
            OrderingTerm(
              expression: db.books.updatedAt,
              mode: OrderingMode.desc,
            ),
          ]);

    return query.watch().map((rows) {
      return rows.map((r) => r.readTable(db.books)).toList();
    });
  }

  Future<List<String>> getCollectionIdsForBook(String bookId) async {
    final rows = await (db.select(
      db.bookCollections,
    )..where((t) => t.bookId.equals(bookId))).get();
    return rows.map((r) => r.collectionId).toList();
  }

  Future<List<BookCollection>> getAllBookCollections() {
    return db.select(db.bookCollections).get();
  }

  Stream<List<String>> watchCollectionIdsForBook(String bookId) {
    return (db.select(db.bookCollections)
          ..where((t) => t.bookId.equals(bookId)))
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
    return db
        .into(db.bookCollections)
        .insertOnConflictUpdate(
          BookCollectionsCompanion(
            bookId: Value(bookId),
            collectionId: Value(collectionId),
          ),
        );
  }

  Future<int> removeBookFromCollection(String bookId, String collectionId) {
    return (db.delete(db.bookCollections)..where(
          (t) => t.bookId.equals(bookId) & t.collectionId.equals(collectionId),
        ))
        .go();
  }

  // --- OCR Pages ---
  Future<int> insertOcrPage(OcrPagesCompanion page) {
    return db.into(db.ocrPages).insertOnConflictUpdate(page);
  }

  Future<OcrPage?> getOcrPage(String bookId, int pageIndex) {
    return (db.select(db.ocrPages)..where(
          (t) => t.bookId.equals(bookId) & t.pageIndex.equals(pageIndex),
        ))
        .getSingleOrNull();
  }

  Future<List<OcrPage>> getOcrPagesForBook(String bookId) {
    return (db.select(db.ocrPages)
          ..where((t) => t.bookId.equals(bookId))
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.pageIndex, mode: OrderingMode.asc),
          ]))
        .get();
  }

  Stream<List<OcrPage>> watchOcrPagesForBook(String bookId) {
    return (db.select(db.ocrPages)
          ..where((t) => t.bookId.equals(bookId))
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.pageIndex, mode: OrderingMode.asc),
          ]))
        .watch();
  }

  Future<int> deleteOcrPagesForBook(String bookId) {
    return (db.delete(db.ocrPages)..where((t) => t.bookId.equals(bookId))).go();
  }

  Future<int> getCompletedOcrPageCount(String bookId) async {
    final count = db.ocrPages.id.count();
    final query = db.selectOnly(db.ocrPages)
      ..addColumns([count])
      ..where(
        db.ocrPages.bookId.equals(bookId) &
            db.ocrPages.status.equals('completed'),
      );
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  // --- Book Search Pages ---
  Future<int> insertSearchPage(BookSearchPagesCompanion page) {
    return db.into(db.bookSearchPages).insertOnConflictUpdate(page);
  }

  Future<BookSearchPage?> getSearchPage(String bookId, int pageIndex) {
    return (db.select(db.bookSearchPages)..where(
          (t) => t.bookId.equals(bookId) & t.pageIndex.equals(pageIndex),
        ))
        .getSingleOrNull();
  }

  Future<List<BookSearchPage>> getSearchPagesForBook(String bookId) {
    return (db.select(db.bookSearchPages)
          ..where((t) => t.bookId.equals(bookId))
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.pageIndex, mode: OrderingMode.asc),
          ]))
        .get();
  }

  Future<int> deleteSearchPagesForBook(String bookId) {
    return (db.delete(
      db.bookSearchPages,
    )..where((t) => t.bookId.equals(bookId))).go();
  }

  Future<int> getIndexedSearchPageCount(String bookId) async {
    final count = db.bookSearchPages.id.count();
    final query = db.selectOnly(db.bookSearchPages)
      ..addColumns([count])
      ..where(db.bookSearchPages.bookId.equals(bookId));
    final result = await query.getSingle();
    return result.read(count) ?? 0;
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
