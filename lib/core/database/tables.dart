import 'package:drift/drift.dart';

class Books extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get author => text()();
  TextColumn get publisher => text().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get coverPath => text().nullable()();
  TextColumn get originalPdfPath => text()();
  TextColumn get processedBookPath => text().nullable()();
  TextColumn get fileHash => text().nullable()();
  IntColumn get totalPages => integer().withDefault(const Constant(0))();
  BoolColumn get isScanned => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Chapters extends Table {
  TextColumn get id => text()();
  TextColumn get bookId => text().references(Books, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text()();
  IntColumn get chapterIndex => integer()();
  IntColumn get startPosition => integer().withDefault(const Constant(0))();
  IntColumn get endPosition => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ReadingProgress')
class ReadingProgresses extends Table {
  TextColumn get id => text()();
  TextColumn get bookId => text().references(Books, #id, onDelete: KeyAction.cascade).unique()();
  IntColumn get currentChapter => integer().withDefault(const Constant(0))();
  IntColumn get currentPosition => integer().withDefault(const Constant(0))();
  RealColumn get progressPercentage => real().withDefault(const Constant(0.0))();
  TextColumn get lastReadingMode => text().nullable()();
  DateTimeColumn get lastReadAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Bookmarks extends Table {
  TextColumn get id => text()();
  TextColumn get bookId => text().references(Books, #id, onDelete: KeyAction.cascade)();
  TextColumn get chapterId => text().nullable()();
  IntColumn get position => integer()();
  TextColumn get label => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Highlights extends Table {
  TextColumn get id => text()();
  TextColumn get bookId => text().references(Books, #id, onDelete: KeyAction.cascade)();
  TextColumn get chapterId => text().nullable()();
  TextColumn get selectedText => text()();
  IntColumn get startPosition => integer()();
  IntColumn get endPosition => integer()();
  TextColumn get color => text().withDefault(const Constant('yellow'))();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Collections extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class BookCollections extends Table {
  TextColumn get bookId => text().references(Books, #id, onDelete: KeyAction.cascade)();
  TextColumn get collectionId => text().references(Collections, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {bookId, collectionId};
}
