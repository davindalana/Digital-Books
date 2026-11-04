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
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON;');
    },
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      Future<void> addColumnSafe(
        TableInfo table,
        GeneratedColumn column,
      ) async {
        try {
          await m.addColumn(table, column);
        } catch (e) {
          if (!e.toString().contains('duplicate column name')) {
            rethrow;
          }
        }
      }

      Future<void> createTableSafe(TableInfo table) async {
        try {
          await m.createTable(table);
        } catch (e) {
          if (!e.toString().contains('already exists')) {
            rethrow;
          }
        }
      }

      if (from < 2) {
        await addColumnSafe(books, books.fileHash);
        await addColumnSafe(
          readingProgresses,
          readingProgresses.lastReadingMode,
        );
      }
      if (from < 3) {
        await addColumnSafe(bookmarks, bookmarks.anchorNodeId);
        await addColumnSafe(bookmarks, bookmarks.characterOffset);
        await addColumnSafe(bookmarks, bookmarks.progressPercentage);
        await addColumnSafe(highlights, highlights.anchorNodeId);
        await addColumnSafe(highlights, highlights.startOffset);
        await addColumnSafe(highlights, highlights.endOffset);
        await addColumnSafe(highlights, highlights.prefixContext);
        await addColumnSafe(highlights, highlights.suffixContext);
        await addColumnSafe(highlights, highlights.anchorVersion);
      }
      if (from < 4) {
        await createTableSafe(ocrPages);
      }
      if (from < 5) {
        await createTableSafe(bookSearchPages);
      }
      if (from < 6) {
        await addColumnSafe(highlights, highlights.pageIndex);
        await addColumnSafe(highlights, highlights.boundingBoxesJson);
        await addColumnSafe(highlights, highlights.anchorStatus);
        await addColumnSafe(highlights, highlights.updatedAt);
        await addColumnSafe(bookmarks, bookmarks.pageIndex);
        await addColumnSafe(bookmarks, bookmarks.updatedAt);
      }
    },
  );
}
