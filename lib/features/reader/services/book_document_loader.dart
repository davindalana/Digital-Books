import '../../../core/services/file_storage_service.dart';
import '../domain/engines/reflowable_engine.dart';
import '../domain/models/reader_content.dart';
import '../domain/models/book_document.dart';
import 'book_text_normalizer.dart';

/// Result of loading a processed book document from disk.
class BookDocumentLoadResult {
  final BookDocument? document;
  final ReaderDocument? readerDocument;
  final String? error;

  const BookDocumentLoadResult._({
    this.document,
    this.readerDocument,
    this.error,
  });

  bool get isSuccess => document != null;

  factory BookDocumentLoadResult.success(
    BookDocument document,
    ReaderDocument readerDocument,
  ) => BookDocumentLoadResult._(
    document: document,
    readerDocument: readerDocument,
  );

  factory BookDocumentLoadResult.failure(String error) =>
      BookDocumentLoadResult._(error: error);
}

/// Loads, normalises, and validates a processed Book Mode document.
///
/// Keeping this outside the widget makes the failure path testable and ensures
/// the reader never has to guess whether a missing file means "not converted
/// yet" or "conversion output is corrupt".
class BookDocumentLoader {
  static Future<BookDocumentLoadResult> load(String? path) async {
    if (path == null || path.isEmpty) {
      return BookDocumentLoadResult.failure(
        'Book Mode is not available for this book.',
      );
    }

    try {
      final jsonStr = await FileStorageService.readProcessedBook(path);
      if (jsonStr == null || jsonStr.trim().isEmpty) {
        return BookDocumentLoadResult.failure(
          'Book Mode could not be loaded: the processed book file is empty '
          'or missing.',
        );
      }

      final loadedDoc = BookDocument.fromJsonString(jsonStr);
      final normalizedDoc =
          loadedDoc.metadata.containsKey('reconstructionQuality')
          ? loadedDoc
          : BookTextNormalizer.normalizeDocument(loadedDoc);
      final readerDoc = ReflowableEngine.normalizeDocument(normalizedDoc);
      return BookDocumentLoadResult.success(normalizedDoc, readerDoc);
    } catch (e) {
      return BookDocumentLoadResult.failure(
        'Book Mode could not be loaded: $e',
      );
    }
  }
}
