import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/reader/domain/models/book_annotation.dart';
import '../database/app_database.dart';
import '../database/database_service.dart';

enum LibraryViewMode { grid, list }

enum BookSortOption {
  dateAddedDesc('Recently Added', Icons.access_time),
  dateAddedAsc('Oldest Added', Icons.history),
  titleAsc('Title (A to Z)', Icons.sort_by_alpha),
  titleDesc('Title (Z to A)', Icons.sort_by_alpha),
  authorAsc('Author (A to Z)', Icons.person_outline),
  progressDesc('Progress (High to Low)', Icons.trending_up),
  progressAsc('Progress (Low to High)', Icons.trending_down);

  final String label;
  final IconData icon;
  const BookSortOption(this.label, this.icon);
}

final libraryViewModeProvider = StateProvider<LibraryViewMode>(
  (ref) => LibraryViewMode.grid,
);

final bookSortOptionProvider = StateProvider<BookSortOption>(
  (ref) => BookSortOption.dateAddedDesc,
);

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

final databaseServiceProvider = Provider<DatabaseService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return DatabaseService(db);
});

final allBooksStreamProvider = StreamProvider<List<Book>>((ref) {
  final dbService = ref.watch(databaseServiceProvider);
  return dbService.watchAllBooks();
});

final recentlyAddedStreamProvider = StreamProvider<List<Book>>((ref) {
  final dbService = ref.watch(databaseServiceProvider);
  return dbService.watchRecentlyAdded();
});

final currentlyReadingStreamProvider = StreamProvider<List<BookWithProgress>>((
  ref,
) {
  final dbService = ref.watch(databaseServiceProvider);
  return dbService.watchCurrentlyReading();
});

final finishedBooksStreamProvider = StreamProvider<List<BookWithProgress>>((
  ref,
) {
  final dbService = ref.watch(databaseServiceProvider);
  return dbService.watchFinishedBooks();
});

final collectionsStreamProvider = StreamProvider<List<Collection>>((ref) {
  final dbService = ref.watch(databaseServiceProvider);
  return dbService.watchCollections();
});

final bookProgressStreamProvider =
    StreamProvider.family<ReadingProgress?, String>((ref, bookId) {
      final dbService = ref.watch(databaseServiceProvider);
      return dbService.watchProgress(bookId);
    });

final bookBookmarksStreamProvider =
    StreamProvider.family<List<Bookmark>, String>((ref, bookId) {
      final dbService = ref.watch(databaseServiceProvider);
      return dbService.watchBookmarks(bookId);
    });

final bookHighlightsStreamProvider =
    StreamProvider.family<List<Highlight>, String>((ref, bookId) {
      final dbService = ref.watch(databaseServiceProvider);
      return dbService.watchHighlights(bookId);
    });

final bookChaptersProvider = FutureProvider.family<List<Chapter>, String>((
  ref,
  bookId,
) {
  final dbService = ref.watch(databaseServiceProvider);
  return dbService.getChaptersForBook(bookId);
});

final searchQueryProvider = StateProvider<String>((ref) => '');

final searchBooksStreamProvider = StreamProvider<List<Book>>((ref) {
  final query = ref.watch(searchQueryProvider);
  final dbService = ref.watch(databaseServiceProvider);
  return dbService.searchBooks(query);
});

final allBookmarksStreamProvider = StreamProvider<List<BookmarkWithBook>>((
  ref,
) {
  final dbService = ref.watch(databaseServiceProvider);
  return dbService.watchAllBookmarks();
});

final allHighlightsStreamProvider = StreamProvider<List<HighlightWithBook>>((
  ref,
) {
  final dbService = ref.watch(databaseServiceProvider);
  return dbService.watchAllHighlights();
});

final allNotesStreamProvider = StreamProvider<List<HighlightWithBook>>((ref) {
  final dbService = ref.watch(databaseServiceProvider);
  return dbService.watchAllNotes();
});

final collectionBookCountsStreamProvider = StreamProvider<Map<String, int>>((
  ref,
) {
  final dbService = ref.watch(databaseServiceProvider);
  return dbService.watchCollectionBookCounts();
});

final booksInCollectionStreamProvider =
    StreamProvider.family<List<Book>, String>((ref, collectionId) {
      final dbService = ref.watch(databaseServiceProvider);
      return dbService.watchBooksInCollection(collectionId);
    });

final bookCollectionIdsStreamProvider =
    StreamProvider.family<List<String>, String>((ref, bookId) {
      final dbService = ref.watch(databaseServiceProvider);
      return dbService.watchCollectionIdsForBook(bookId);
    });

final bookAnnotationsStreamProvider =
    StreamProvider.family<List<BookAnnotation>, String>((ref, bookId) {
      final dbService = ref.watch(databaseServiceProvider);
      return dbService.watchAnnotationsForBook(bookId);
    });
