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
  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade)();
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
  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade).unique()();
  IntColumn get currentChapter => integer().withDefault(const Constant(0))();
  IntColumn get currentPosition => integer().withDefault(const Constant(0))();
  RealColumn get progressPercentage =>
      real().withDefault(const Constant(0.0))();
  TextColumn get lastReadingMode => text().nullable()();
  DateTimeColumn get lastReadAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Bookmarks extends Table {
  TextColumn get id => text()();
  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade)();
  TextColumn get chapterId => text().nullable()();
  IntColumn get position => integer()();
  TextColumn get label => text()();
  TextColumn get anchorNodeId => text().nullable()();
  IntColumn get characterOffset => integer().withDefault(const Constant(0))();
  RealColumn get progressPercentage =>
      real().withDefault(const Constant(0.0))();
  IntColumn get pageIndex => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Highlights extends Table {
  TextColumn get id => text()();
  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade)();
  TextColumn get chapterId => text().nullable()();
  TextColumn get selectedText => text()();
  IntColumn get startPosition => integer()();
  IntColumn get endPosition => integer()();
  TextColumn get color => text().withDefault(const Constant('yellow'))();
  TextColumn get note => text().nullable()();
  TextColumn get anchorNodeId => text().nullable()();
  IntColumn get startOffset => integer().withDefault(const Constant(0))();
  IntColumn get endOffset => integer().withDefault(const Constant(0))();
  TextColumn get prefixContext => text().nullable()();
  TextColumn get suffixContext => text().nullable()();
  IntColumn get anchorVersion => integer().withDefault(const Constant(1))();
  IntColumn get pageIndex => integer().nullable()();
  TextColumn get boundingBoxesJson => text().nullable()();
  TextColumn get anchorStatus =>
      text().nullable().withDefault(const Constant('resolved'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

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
  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade)();
  TextColumn get collectionId =>
      text().references(Collections, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {bookId, collectionId};
}

/// Page-level OCR cache and provenance persistence.
/// Stores recognized text lines, bounding boxes, confidence, and status per page.
class OcrPages extends Table {
  TextColumn get id => text()();
  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade)();
  IntColumn get pageIndex => integer()();
  TextColumn get status => text().withDefault(const Constant('completed'))(); // pending, processing, completed, failed
  RealColumn get confidence => real().withDefault(const Constant(1.0))();
  IntColumn get charCount => integer().withDefault(const Constant(0))();
  RealColumn get durationMs => real().withDefault(const Constant(0.0))();
  TextColumn get linesJson => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Search index persistence per book page.
/// Stores normalized searchable text, raw text, and geometry token mappings
/// for both digital selectable text and OCR recognized text.
class BookSearchPages extends Table {
  TextColumn get id => text()(); // '${bookId}_p${pageIndex}'
  TextColumn get bookId =>
      text().references(Books, #id, onDelete: KeyAction.cascade)();
  IntColumn get pageIndex => integer()();
  TextColumn get plainText => text()();
  TextColumn get rawText => text()();
  TextColumn get geometryJson => text()(); // Serialized List<SearchTokenGeometry> JSON
  BoolColumn get isOcr => boolean().withDefault(const Constant(false))();
  TextColumn get fileHash => text().nullable()();
  IntColumn get indexVersion => integer().withDefault(const Constant(1))();
  DateTimeColumn get indexedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
