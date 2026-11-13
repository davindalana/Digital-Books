import 'dart:io';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_service.dart';
import '../../../core/services/file_storage_service.dart';
import '../../reader/domain/models/book_document.dart';
import '../models/processing_manifest.dart';
import 'geometry_aware_pdf_extractor.dart';
import 'ocr_semantic_pipeline.dart';
import 'semantic_document_reconstructor.dart';

/// Rebuilds a Book Mode document from the immutable original PDF.
///
/// Native-text books are re-extracted and semantically reconstructed. Scanned
/// books reuse completed OCR pages; if none exist the rebuild returns `null`
/// instead of inventing content.
class BookDocumentRebuilder {
  static Future<BookDocument?> rebuild({
    required Book book,
    required DatabaseService dbService,
    void Function(double progress, String message)? onProgress,
  }) async {
    final source = File(book.originalPdfPath);
    if (!await source.exists()) return null;

    if (book.isScanned) {
      onProgress?.call(0.1, 'Reconstructing from completed OCR pages...');
      final pipeline = OcrSemanticPipeline(dbService);
      return pipeline.reconstructDocument(
        bookId: book.id,
        pdfPath: book.originalPdfPath,
        title: book.title,
        author: book.author,
      );
    }

    onProgress?.call(0.1, 'Extracting text, geometry, and images...');
    final imagesDir = await FileStorageService.getImagesDirectory();
    final extraction = await GeometryAwarePdfExtractor.extractDocument(
      pdfFile: source,
      bookId: book.id,
      imageOutputDir: imagesDir,
      extractImagesToDisk: true,
      onProgress: (progress, message) =>
          onProgress?.call(0.1 + progress * 0.7, message),
    );

    onProgress?.call(0.8, 'Reconstructing chapters and reading order...');
    final reconstructed = await SemanticDocumentReconstructor.reconstruct(
      extraction: extraction,
      title: book.title,
      author: book.author,
    );

    return reconstructed.toBookDocument(
      extraMetadata: {
        'publisher': book.publisher ?? '',
        'description': book.description ?? '',
        'sourceFileSize': await source.length(),
        'sourceTotalPages': extraction.totalPages,
        'reprocessedBy': 'book_rebuilder',
        'pipelineVersion': ProcessingManifest.currentPipelineVersion,
      },
    );
  }
}
