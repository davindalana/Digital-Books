import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Size;
import 'package:drift/drift.dart' hide isNotNull;
import 'package:pdfrx/pdfrx.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/database_service.dart';
import '../../../core/utils/file_storage_service.dart';
import '../../reader/models/book_document.dart';
import '../models/extracted_page_geometry.dart';
import '../models/ocr_page_result.dart';
import 'semantic_document_reconstructor.dart';

/// Bridges stored OCR page results with the Semantic Document Reconstructor
/// to synthesize a structured, searchable, reflowable [BookDocument].
class OcrSemanticPipeline {
  final DatabaseService dbService;

  const OcrSemanticPipeline(this.dbService);

  /// Reconstructs a full reflowable [BookDocument] from the completed OCR pages of [bookId].
  ///
  /// Preserves the immutable original PDF while producing a structured derivative
  /// that is saved as JSON and linked via [Books.processedBookPath].
  Future<BookDocument?> reconstructBook({
    required String bookId,
    required String pdfPath,
    String? title,
    String? author,
  }) async {
    final pdfFile = File(pdfPath);
    if (!pdfFile.existsSync()) {
      throw ArgumentError('PDF file not found at $pdfPath');
    }

    final book = await dbService.getBookById(bookId);
    final effectiveTitle = title ?? book?.title ?? 'Untitled Book';
    final effectiveAuthor = author ?? book?.author ?? 'Unknown Author';

    // 1. Fetch all completed OCR pages for this book
    final ocrPages = await dbService.getOcrPagesForBook(bookId);
    final completedOcrPages = ocrPages
        .where((p) => p.status == 'completed')
        .toList();

    if (completedOcrPages.isEmpty) {
      return null;
    }

    // Sort by pageIndex ascending
    completedOcrPages.sort((a, b) => a.pageIndex.compareTo(b.pageIndex));

    // 2. Open PDF to map page geometry dimensions
    PdfDocument? doc;
    final extractedPages = <ExtractedPageGeometry>[];
    double totalOcrDurationMs = 0.0;
    int totalDocPages = completedOcrPages.length;

    try {
      doc = await PdfDocument.openFile(pdfPath);
      totalDocPages = doc.pages.length;

      for (final ocrPage in completedOcrPages) {
        final pageIdx = ocrPage.pageIndex;
        Size pageSize = const Size(595, 842); // Default A4 fallback
        if (pageIdx >= 0 && pageIdx < totalDocPages) {
          final p = doc.pages[pageIdx];
          pageSize = Size(p.width, p.height);
        }

        final rawLines = (jsonDecode(ocrPage.linesJson) as List)
            .cast<Map<String, dynamic>>();
        final lines = rawLines.map((j) => OcrLine.fromJson(j)).toList();

        final ocrResult = OcrPageResult(
          imagePath: '',
          width: pageSize.width.round(),
          height: pageSize.height.round(),
          durationMs: ocrPage.durationMs,
          lines: lines,
        );

        totalOcrDurationMs += ocrPage.durationMs;

        final geom = ocrResult.toExtractedPageGeometry(
          pageIndex: pageIdx,
          pageSize: pageSize,
        );
        extractedPages.add(geom);
      }
    } finally {
      await doc?.dispose();
    }

    // 3. Assemble geometry extraction result
    final totalLines = extractedPages.fold<int>(
      0,
      (sum, p) => sum + p.lines.length,
    );
    final totalImages = extractedPages.fold<int>(
      0,
      (sum, p) => sum + p.images.length,
    );

    final extraction = DocumentExtractionResult(
      bookId: bookId,
      totalPages: book?.totalPages ?? totalDocPages,
      pages: extractedPages,
      totalTextLines: totalLines,
      totalImages: totalImages,
      layerBreakdown: {PageLayerType.nativeText: extractedPages.length},
      hasUsableTextLayer: totalLines > 0,
      warnings: const [],
      durationMs: totalOcrDurationMs,
    );

    // 4. Run Semantic Document Reconstructor
    final reconstructed = await SemanticDocumentReconstructor.reconstruct(
      extraction: extraction,
      title: effectiveTitle,
      author: effectiveAuthor,
    );

    // 5. Generate domain BookDocument
    final bookDoc = reconstructed.toBookDocument(
      extraMetadata: {
        'ocrSource': 'apple_vision_offline',
        'ocrCompletedPages': completedOcrPages.length,
        'reconstructedAt': DateTime.now().toIso8601String(),
      },
    );

    // 6. Save derivative JSON to storage
    final savedJsonFile = await FileStorageService.saveProcessedBook(
      bookId,
      bookDoc.toJsonString(),
    );

    // 7. Update database record with processed path
    await dbService.updateBookProcessedPath(bookId, savedJsonFile.path);

    // 8. Replace chapters in database
    if (bookDoc.chapters.isNotEmpty) {
      final chapterCompanions = bookDoc.chapters.asMap().entries.map((entry) {
        return ChaptersCompanion(
          id: Value(entry.value.id),
          bookId: Value(bookId),
          title: Value(entry.value.title),
          chapterIndex: Value(entry.key),
          startPosition: const Value(0),
          endPosition: const Value(0),
        );
      }).toList();
      await dbService.replaceChaptersForBook(bookId, chapterCompanions);
    }

    return bookDoc;
  }
}
