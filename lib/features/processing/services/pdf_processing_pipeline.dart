import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/database_service.dart';
import '../../../core/utils/cover_generator.dart';
import '../../../core/utils/file_storage_service.dart';
import '../../reader/models/book_document.dart';
import '../../reader/services/book_text_normalizer.dart';
import '../models/processing_status.dart';

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
        onProgress(ProcessingProgress(
          stage: stage,
          progress: progress,
          message: message,
        ));
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
      notify(ProcessingStage.extractingMetadata, 0.15, 'Reading document metadata...');
      final bytes = await pdfFile.readAsBytes();
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      final totalPages = document.pages.count;

      String title = customTitle?.trim() ?? '';
      String author = customAuthor?.trim() ?? '';
      String? publisher;
      String? description;

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

      // Fallback title to filename if still empty
      if (title.isEmpty) {
        final baseName = p.basenameWithoutExtension(pdfFile.path);
        title = sanitizeFilenameToTitle(baseName);
      }
      if (author.isEmpty) {
        author = 'Unknown Author';
      }

      if (_isCancelled) {
        document.dispose();
        throw Exception('Operation cancelled by user.');
      }

      // 3. Extract Text & Detect Scan
      notify(ProcessingStage.extractingText, 0.25, 'Extracting text and structure...');
      final extractor = PdfTextExtractor(document);
      final List<String> pageTexts = [];
      int totalChars = 0;

      for (int i = 0; i < totalPages; i++) {
        if (_isCancelled) {
          document.dispose();
          throw Exception('Operation cancelled by user.');
        }

        final pageProgress = 0.25 + (0.35 * (i / (totalPages > 0 ? totalPages : 1)));
        notify(
          ProcessingStage.extractingText,
          pageProgress,
          'Extracting page ${i + 1} of $totalPages...',
        );

        try {
          final text = extractor.extractText(startPageIndex: i, endPageIndex: i);
          pageTexts.add(text);
          totalChars += text.trim().length;
        } catch (_) {
          pageTexts.add('');
        }
      }

      final avgCharsPerPage = totalPages > 0 ? (totalChars / totalPages) : 0;
      bool isScanned = avgCharsPerPage < 35 && totalPages > 0;

      // Automatic Neural OCR fallback on macOS Vision Framework
      if (isScanned && Platform.isMacOS) {
        notify(ProcessingStage.extractingText, 0.55, 'Running Apple Vision OCR on scanned pages...');
        final ocrTexts = await _runVisionOcrOnMac(pdfFile.path, totalPages);
        if (ocrTexts.isNotEmpty && ocrTexts.any((t) => t.trim().isNotEmpty)) {
          pageTexts.clear();
          pageTexts.addAll(ocrTexts);
          // We keep isScanned = true so visual, diagram-heavy scanned books default to Original PDF Mode
          // while still retaining OCR digital text for search and reflowable reading.
        }
      }

      if (_isCancelled) {
        document.dispose();
        throw Exception('Operation cancelled by user.');
      }

      // 4. Detect Chapters & Structure
      notify(ProcessingStage.detectingChapters, 0.65, 'Analyzing chapter structure...');
      final List<BookChapter> chapters = _buildChaptersFromPages(
        document: document,
        pageTexts: pageTexts,
        bookTitle: title,
        isScanned: isScanned,
      );

      // 5. High-Resolution Page 1 Cover Generation (Upscaled with Sharpening)
      notify(ProcessingStage.generatingCover, 0.80, 'Creating crisp high-resolution cover from Page 1...');
      final coverFile = await CoverGenerator.generateCover(
        bookId: bookId,
        pdfPath: pdfFile.path,
        title: title,
        author: author,
      );
      createdCoverFile = coverFile;
      FileStorageService.lockPath(coverFile.path);

      if (_isCancelled) {
        document.dispose();
        throw Exception('Operation cancelled by user.');
      }

      // 6. Generate Internal Book Document & Save Original PDF
      notify(ProcessingStage.generatingBook, 0.90, 'Generating digital book format...');
      final storedPdf = await FileStorageService.copyPdfToStorage(pdfFile, bookId);
      createdStoredPdf = storedPdf;
      FileStorageService.lockPath(storedPdf.path);

      final rawBookDoc = BookDocument(
        id: bookId,
        title: title,
        author: author,
        totalPages: totalPages,
        isScanned: isScanned,
        chapters: chapters,
        metadata: {
          'publisher': publisher ?? '',
          'description': description ?? '',
          'importedAt': DateTime.now().toIso8601String(),
        },
      );

      final bookDoc = BookTextNormalizer.normalizeDocument(rawBookDoc);

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

      await _dbService.insertBook(bookCompanion);

      // Save chapters to DB
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

      await _dbService.replaceChaptersForBook(bookId, chapterCompanions);

      // Initialize reading progress
      await _dbService.upsertProgress(ReadingProgressesCompanion(
        id: Value(const Uuid().v4()),
        bookId: Value(bookId),
        currentChapter: const Value(0),
        currentPosition: const Value(0),
        progressPercentage: const Value(0.0),
        lastReadAt: Value(now),
      ));

      document.dispose();

      notify(ProcessingStage.completed, 1.0, 'Book successfully ready!');
      final createdBook = await _dbService.getBookById(bookId);
      return createdBook!;
    } catch (e) {
      // Safe cleanup of intermediate files on failed or cancelled import
      try {
        if (createdStoredPdf != null && await createdStoredPdf.exists()) {
          await createdStoredPdf.delete();
        }
        if (createdProcessedBook != null && await createdProcessedBook.exists()) {
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
    return clean.split(' ').map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  static Future<({String title, String author})> peekPdfMetadata(File pdfFile) async {
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

  static List<BookChapter> _buildChaptersFromPages({
    required PdfDocument document,
    required List<String> pageTexts,
    required String bookTitle,
    required bool isScanned,
  }) {
    if (isScanned || pageTexts.isEmpty) {
      // For scanned books, check if any real text was extracted
      final List<BookBlock> realBlocks = [];
      for (int i = 0; i < pageTexts.length; i++) {
        final text = pageTexts[i].trim();
        if (text.isNotEmpty) {
          realBlocks.add(BookBlock(
            id: const Uuid().v4(),
            type: BlockType.paragraph,
            text: text,
            originalPageNumber: i + 1,
          ));
        }
      }

      if (realBlocks.isEmpty) {
        realBlocks.add(BookBlock(
          id: const Uuid().v4(),
          type: BlockType.paragraph,
          text: 'This document contains visual scanned pages. Read in Original PDF Mode for full layout and illustrations.',
          originalPageNumber: 1,
        ));
      }

      return [
        BookChapter(
          id: const Uuid().v4(),
          index: 0,
          title: bookTitle,
          blocks: realBlocks,
        ),
      ];
    }

    final List<BookChapter> chapters = [];
    final chapterRegex = RegExp(
      r'^(chapter|bab|hukum|law|part|bagian|book|act|section)\s+([0-9ivxlcdm]+|[a-z]+)(:|\.|\s-|\s–)?\s*(.*)$',
      caseSensitive: false,
    );
    final standaloneHeadingRegex = RegExp(
      r'^(introduction|prologue|epilogue|preface|foreword|acknowledgments|table of contents|contents|conclusion|afterword|appendix|glossary|index)$',
      caseSensitive: false,
    );

    String currentChapterTitle = 'Introduction';
    List<BookBlock> currentBlocks = [];
    int chapterIndex = 0;

    for (int pageIdx = 0; pageIdx < pageTexts.length; pageIdx++) {
      final pageNum = pageIdx + 1;
      final rawPage = pageTexts[pageIdx];
      final lines = rawPage.split('\n');

      for (int lineIdx = 0; lineIdx < lines.length; lineIdx++) {
        final line = lines[lineIdx].trim();
        if (line.isEmpty) continue;

        // Filter out repeating running headers, footers, publisher marks, page numbers
        final lower = line.toLowerCase();
        final isRunningHeader = lower == bookTitle.toLowerCase() ||
            RegExp(r'^(teka[- ]teki|rumah aneh|uketsu|gramedia|penerbit|kompas|sfile|mobi|halaman\s*\d+|\d+)$', caseSensitive: false).hasMatch(line);
        if (isRunningHeader) continue;

        // Check if line looks like a real chapter header
        final isMatchChapter = chapterRegex.hasMatch(line);
        final isMatchStandalone = standaloneHeadingRegex.hasMatch(line);
        final isChapterKeyword = RegExp(
          r'^(bab\s+[0-9ivxlcdm]+|chapter\s+[0-9ivxlcdm]+|bagian\s+[0-9ivxlcdm]+|prolog|epilog|catatan|denah\s+rumah)',
          caseSensitive: false,
        ).hasMatch(line);

        if ((isMatchChapter || isMatchStandalone || isChapterKeyword) &&
            currentBlocks.isNotEmpty) {
          // Finish previous chapter
          chapters.add(BookChapter(
            id: const Uuid().v4(),
            index: chapterIndex++,
            title: currentChapterTitle,
            blocks: List.from(currentBlocks),
          ));
          currentBlocks.clear();
          currentChapterTitle = line;
          currentBlocks.add(BookBlock(
            id: const Uuid().v4(),
            type: BlockType.heading,
            text: line,
            headingLevel: 1,
            originalPageNumber: pageNum,
          ));
        } else {
          // Regular text block or heading inside chapter
          currentBlocks.add(BookBlock(
            id: const Uuid().v4(),
            type: BlockType.paragraph,
            text: line,
            originalPageNumber: pageNum,
          ));
        }
      }
    }

    // Add trailing chapter
    if (currentBlocks.isNotEmpty) {
      chapters.add(BookChapter(
        id: const Uuid().v4(),
        index: chapterIndex,
        title: currentChapterTitle,
        blocks: List.from(currentBlocks),
      ));
    }

    if (chapters.isEmpty) {
      chapters.add(BookChapter(
        id: const Uuid().v4(),
        index: 0,
        title: bookTitle,
        blocks: [
          BookBlock(
            id: const Uuid().v4(),
            type: BlockType.paragraph,
            text: 'Empty document content.',
            originalPageNumber: 1,
          ),
        ],
      ));
    }

    return chapters;
  }

  static Future<List<String>> _runVisionOcrOnMac(String pdfPath, int totalPages) async {
    try {
      final script = '''
import Foundation
import PDFKit
import Vision
import AppKit

let pdfPath = "$pdfPath"
guard let doc = PDFDocument(url: URL(fileURLWithPath: pdfPath)) else { exit(1) }

var results: [String] = []
for pageIndex in 0..<doc.pageCount {
    autoreleasepool {
        guard let page = doc.page(at: pageIndex) else { results.append(""); return }
        let thumb = page.thumbnail(of: CGSize(width: 1400, height: 1900), for: .mediaBox)
        var proposedRect = CGRect(origin: .zero, size: thumb.size)
        guard let cgImage = thumb.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else { results.append(""); return }
        
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["id", "en"]
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        
        let observations = request.results ?? []
        let sorted = observations.sorted { \$0.boundingBox.origin.y > \$1.boundingBox.origin.y }
        let lines = sorted.compactMap { \$0.topCandidates(1).first?.string }
        results.append(lines.joined(separator: "\\n"))
    }
}
let encoder = JSONEncoder()
if let data = try? encoder.encode(results), let s = String(data: data, encoding: .utf8) {
    print(s)
}
''';
      final res = await Process.run('swift', ['-e', script]);
      if (res.exitCode == 0 && res.stdout.toString().trim().isNotEmpty) {
        final List<dynamic> list = jsonDecode(res.stdout.toString().trim());
        return list.map((e) => e.toString()).toList();
      }
    } catch (_) {}
    return [];
  }
}
