import 'dart:io';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_service.dart';
import '../../../core/utils/cover_generator.dart';
import '../../../core/utils/file_storage_service.dart';
import '../models/processing_status.dart';
import 'geometry_aware_pdf_extractor.dart';
import 'semantic_document_reconstructor.dart';

class PdfProcessingPipeline {
  final DatabaseService _dbService;
  bool _isCancelled = false;

  PdfProcessingPipeline(this._dbService);

  void cancel() {
    _isCancelled = true;
  }

  Future<Book> processAndImportPdf({
    required File pdfFile,
    String? customTitle,
    String? customAuthor,
    void Function(ProcessingProgress progress)? onProgress,
  }) async {
    _isCancelled = false;
    final bookId = const Uuid().v4();
    File? createdCoverFile;
    File? createdStoredPdf;
    File? createdProcessedBook;

    void notify(ProcessingStage stage, double progress, String message) {
      if (!_isCancelled && onProgress != null) {
        onProgress(
          ProcessingProgress(
            stage: stage,
            progress: progress,
            message: message,
          ),
        );
      }
    }

    try {
      // 1. Validation
      notify(ProcessingStage.validating, 0.05, 'Validating PDF file...');
      if (!await pdfFile.exists()) {
        throw Exception('The selected file does not exist.');
      }
      final fileLength = await pdfFile.length();
      if (fileLength < 100) {
        throw Exception('File is too small to be a valid PDF document.');
      }

      final headerBytes = await pdfFile.openRead(0, 10).first;
      final headerStr = String.fromCharCodes(headerBytes);
      if (!headerStr.contains('%PDF-')) {
        throw Exception('Invalid file format. The file is not a valid PDF.');
      }

      final fileHash = await FileStorageService.computeFileSha256(pdfFile);

      if (_isCancelled) throw Exception('Operation cancelled by user.');

      // 2. Extract Metadata
      notify(
        ProcessingStage.extractingMetadata,
        0.15,
        'Reading document metadata...',
      );
      final bytes = await pdfFile.readAsBytes();
      final PdfDocument document;
      try {
        document = PdfDocument(inputBytes: bytes);
      } catch (e) {
        throw Exception(
          'Unable to open PDF. The file may be encrypted, password-protected, '
          'or corrupted. ($e)',
        );
      }

      final int totalPages;
      String title = customTitle?.trim() ?? '';
      String author = customAuthor?.trim() ?? '';
      String? publisher;
      String? description;

      try {
        totalPages = document.pages.count;
        if (totalPages <= 0) {
          throw Exception(
            'The PDF has no pages. The file may be corrupted or incomplete.',
          );
        }

        try {
          final info = document.documentInformation;
          if (title.isEmpty && info.title.isNotEmpty) {
            title = info.title.trim();
          }
          if (author.isEmpty && info.author.isNotEmpty) {
            author = info.author.trim();
          }
          if (info.subject.isNotEmpty) {
            description = info.subject.trim();
          }
          if (info.creator.isNotEmpty || info.producer.isNotEmpty) {
            publisher = info.creator.isNotEmpty ? info.creator : info.producer;
          }
        } catch (_) {}
      } finally {
        document.dispose();
      }

      // Fallback title to filename if still empty
      if (title.isEmpty) {
        final baseName = p.basenameWithoutExtension(pdfFile.path);
        title = sanitizeFilenameToTitle(baseName);
      }
      if (author.isEmpty) {
        author = 'Unknown Author';
      }

      if (_isCancelled) {
        throw Exception('Operation cancelled by user.');
      }

      // 3. Geometry-Aware Content & Image Extraction
      notify(
        ProcessingStage.extractingText,
        0.25,
        'Extracting geometry, text lines, and image assets...',
      );
      final imagesDir = await FileStorageService.getImagesDirectory();
      final extraction = await GeometryAwarePdfExtractor.extractDocument(
        pdfFile: pdfFile,
        bookId: bookId,
        imageOutputDir: imagesDir,
        extractImagesToDisk: true,
        onProgress: (p, msg) =>
            notify(ProcessingStage.extractingText, 0.25 + (p * 0.40), msg),
      );

      if (_isCancelled) {
        throw Exception('Operation cancelled by user.');
      }

      // 4. Semantic Reconstruction (Reading Order, Paragraphs, Headings, Images, Quality)
      notify(
        ProcessingStage.detectingChapters,
        0.70,
        'Reconstructing reading order, paragraphs, headings, and images...',
      );
      final reconstructed = await SemanticDocumentReconstructor.reconstruct(
        extraction: extraction,
        title: title,
        author: author,
      );

      final isScanned =
          reconstructed.isScannedSource || !extraction.hasUsableTextLayer;
      final bookDoc = reconstructed.toBookDocument(
        extraMetadata: {
          'publisher': publisher ?? '',
          'description': description ?? '',
          'importedAt': DateTime.now().toIso8601String(),
        },
      );

      if (_isCancelled) {
        throw Exception('Operation cancelled by user.');
      }

      // 5. High-Resolution Page 1 Cover Generation (Upscaled with Sharpening)
      notify(
        ProcessingStage.generatingCover,
        0.85,
        'Creating crisp high-resolution cover from Page 1...',
      );
      final coverFile = await CoverGenerator.generateCover(
        bookId: bookId,
        pdfPath: pdfFile.path,
        title: title,
        author: author,
      );
      createdCoverFile = coverFile;
      FileStorageService.lockPath(coverFile.path);

      if (_isCancelled) {
        throw Exception('Operation cancelled by user.');
      }

      // 6. Generate Internal Book Document & Save Original PDF
      notify(
        ProcessingStage.generatingBook,
        0.92,
        'Saving digital book format...',
      );
      final storedPdf = await FileStorageService.copyPdfToStorage(
        pdfFile,
        bookId,
      );
      createdStoredPdf = storedPdf;
      FileStorageService.lockPath(storedPdf.path);

      final processedBookFile = await FileStorageService.saveProcessedBook(
        bookId,
        bookDoc.toJsonString(),
      );
      createdProcessedBook = processedBookFile;
      FileStorageService.lockPath(processedBookFile.path);

      // 7. Save to Database
      final now = DateTime.now();
      final bookCompanion = BooksCompanion(
        id: Value(bookId),
        title: Value(title),
        author: Value(author),
        publisher: Value(publisher),
        description: Value(description),
        coverPath: Value(coverFile.path),
        originalPdfPath: Value(storedPdf.path),
        processedBookPath: Value(processedBookFile.path),
        fileHash: Value(fileHash),
        totalPages: Value(totalPages),
        isScanned: Value(isScanned),
        createdAt: Value(now),
        updatedAt: Value(now),
      );

      final chapterCompanions = bookDoc.chapters.asMap().entries.map((entry) {
        final index = entry.key;
        final ch = entry.value;
        return ChaptersCompanion(
          id: Value(ch.id),
          bookId: Value(bookId),
          title: Value(ch.title),
          chapterIndex: Value(index),
          startPosition: Value(0),
          endPosition: Value(ch.blocks.length),
        );
      }).toList();

      // Book, chapters, and initial progress are committed together so a
      // failure cannot leave a library row pointing at files that the catch
      // block then deletes.
      await _dbService.importBookAtomic(
        book: bookCompanion,
        chapters: chapterCompanions,
        progress: ReadingProgressesCompanion(
          id: Value(const Uuid().v4()),
          bookId: Value(bookId),
          currentChapter: const Value(0),
          currentPosition: const Value(0),
          progressPercentage: const Value(0.0),
          lastReadAt: Value(now),
        ),
      );

      notify(ProcessingStage.completed, 1.0, 'Book successfully ready!');
      final createdBook = await _dbService.getBookById(bookId);
      return createdBook!;
    } catch (e) {
      // Safe cleanup of intermediate files on failed or cancelled import
      try {
        if (createdStoredPdf != null && await createdStoredPdf.exists()) {
          await createdStoredPdf.delete();
        }
        if (createdProcessedBook != null &&
            await createdProcessedBook.exists()) {
          await createdProcessedBook.delete();
        }
        if (createdCoverFile != null && await createdCoverFile.exists()) {
          await createdCoverFile.delete();
        }
        final imagesDir = await FileStorageService.getImagesDirectory();
        final bookImages = Directory(p.join(imagesDir.path, bookId));
        if (await bookImages.exists()) {
          await bookImages.delete(recursive: true);
        }
      } catch (_) {}

      if (onProgress != null) {
        onProgress(ProcessingProgress.failed(e.toString()));
      }
      rethrow;
    } finally {
      if (createdStoredPdf != null) {
        FileStorageService.unlockPath(createdStoredPdf.path);
      }
      if (createdCoverFile != null) {
        FileStorageService.unlockPath(createdCoverFile.path);
      }
      if (createdProcessedBook != null) {
        FileStorageService.unlockPath(createdProcessedBook.path);
      }
    }
  }

  static String sanitizeFilenameToTitle(String filename) {
    var clean = filename.replaceAll(RegExp(r'[_\-\.]+'), ' ');
    clean = clean.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return 'Untitled Book';
    // Title Case
    return clean
        .split(' ')
        .map((word) {
          if (word.isEmpty) return '';
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        })
        .join(' ');
  }

  static Future<({String title, String author})> peekPdfMetadata(
    File pdfFile,
  ) async {
    try {
      final bytes = await pdfFile.readAsBytes();
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      String title = '';
      String author = '';
      try {
        final info = document.documentInformation;
        if (info.title.isNotEmpty) {
          title = info.title.trim();
        }
        if (info.author.isNotEmpty) {
          author = info.author.trim();
        }
      } finally {
        document.dispose();
      }
      if (title.isEmpty) {
        final baseName = p.basenameWithoutExtension(pdfFile.path);
        title = sanitizeFilenameToTitle(baseName);
      }
      if (author.isEmpty) {
        author = 'Unknown Author';
      }
      return (title: title, author: author);
    } catch (_) {
      final baseName = p.basenameWithoutExtension(pdfFile.path);
      return (
        title: sanitizeFilenameToTitle(baseName),
        author: 'Unknown Author',
      );
    }
  }
}
