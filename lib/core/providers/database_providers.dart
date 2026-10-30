import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/app_database.dart';
import '../database/database_service.dart';

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

final currentlyReadingStreamProvider = StreamProvider<List<BookWithProgress>>((ref) {
  final dbService = ref.watch(databaseServiceProvider);
  return dbService.watchCurrentlyReading();
});

final finishedBooksStreamProvider = StreamProvider<List<BookWithProgress>>((ref) {
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

final bookChaptersProvider =
    FutureProvider.family<List<Chapter>, String>((ref, bookId) {
  final dbService = ref.watch(databaseServiceProvider);
  return dbService.getChaptersForBook(bookId);
});

final searchQueryProvider = StateProvider<String>((ref) => '');

final searchBooksStreamProvider = StreamProvider<List<Book>>((ref) {
  final query = ref.watch(searchQueryProvider);
  final dbService = ref.watch(databaseServiceProvider);
  return dbService.searchBooks(query);
});

