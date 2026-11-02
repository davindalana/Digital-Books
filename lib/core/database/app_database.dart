import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Books,
    Chapters,
    ReadingProgresses,
    Bookmarks,
    Highlights,
    Collections,
    BookCollections,
    OcrPages,
    BookSearchPages,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e])
    : super(e ?? driftDatabase(name: 'digital_books_db'));

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON;');
    },
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(books, books.fileHash);
        await m.addColumn(readingProgresses, readingProgresses.lastReadingMode);
      }
      if (from < 3) {
        await m.addColumn(bookmarks, bookmarks.anchorNodeId);
        await m.addColumn(bookmarks, bookmarks.characterOffset);
        await m.addColumn(bookmarks, bookmarks.progressPercentage);
        await m.addColumn(highlights, highlights.anchorNodeId);
        await m.addColumn(highlights, highlights.startOffset);
        await m.addColumn(highlights, highlights.endOffset);
        await m.addColumn(highlights, highlights.prefixContext);
        await m.addColumn(highlights, highlights.suffixContext);
        await m.addColumn(highlights, highlights.anchorVersion);
      }
      if (from < 4) {
        await m.createTable(ocrPages);
      }
      if (from < 5) {
        await m.createTable(bookSearchPages);
      }
    },
  );
}
