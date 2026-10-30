import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [
  Books,
  Chapters,
  ReadingProgresses,
  Bookmarks,
  Highlights,
  Collections,
  BookCollections,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e])
      : super(e ?? driftDatabase(name: 'digital_books_db'));

  @override
  int get schemaVersion => 1;
}

