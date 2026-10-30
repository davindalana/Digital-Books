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
        title = _sanitizeFilenameToTitle(baseName);
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
      final bool isScanned = avgCharsPerPage < 35 && totalPages > 0;

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

      // 5. Procedural Cover Generation
      notify(ProcessingStage.generatingCover, 0.80, 'Creating Apple Books style cover...');
      final coverFile = await CoverGenerator.generateProceduralCover(
        bookId: bookId,
        title: title,
        author: author,
      );

      if (_isCancelled) {
        document.dispose();
        throw Exception('Operation cancelled by user.');
      }

      // 6. Generate Internal Book Document & Save Original PDF
      notify(ProcessingStage.generatingBook, 0.90, 'Generating digital book format...');
      final storedPdf = await FileStorageService.copyPdfToStorage(pdfFile, bookId);

      final bookDoc = BookDocument(
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

      final processedBookFile = await FileStorageService.saveProcessedBook(
        bookId,
        bookDoc.toJsonString(),
      );

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
        totalPages: Value(totalPages),
        isScanned: Value(isScanned),
        createdAt: Value(now),
        updatedAt: Value(now),
      );

      await _dbService.insertBook(bookCompanion);

      // Save chapters to DB
      final chapterCompanions = chapters.asMap().entries.map((entry) {
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
      if (onProgress != null) {
        onProgress(ProcessingProgress.failed(e.toString()));
      }
      rethrow;
    }
  }

  static String _sanitizeFilenameToTitle(String filename) {
    var clean = filename.replaceAll(RegExp(r'[_\-\.]+'), ' ');
    clean = clean.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return 'Untitled Book';
    // Title Case
    return clean.split(' ').map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  static List<BookChapter> _buildChaptersFromPages({
    required PdfDocument document,
    required List<String> pageTexts,
    required String bookTitle,
    required bool isScanned,
  }) {
    if (isScanned || pageTexts.isEmpty) {
      // For scanned books, map each page as a block for reflowable mode preview
      return [
        BookChapter(
          id: const Uuid().v4(),
          index: 0,
          title: 'Document (Scanned PDF)',
          blocks: List.generate(
            pageTexts.length,
            (index) => BookBlock(
              id: const Uuid().v4(),
              type: BlockType.paragraph,
              text: '[Scanned Page ${index + 1} - Switch to Original PDF Mode for full graphical fidelity or OCR]',
              originalPageNumber: index + 1,
            ),
          ),
        ),
      ];
    }

    final List<BookChapter> chapters = [];
    final chapterRegex = RegExp(
      r'^(chapter|bab|part|bagian|book|act|section)\s+([0-9ivxlcdm]+|[a-z]+)(:|\.|\s-|\s–)?\s*(.*)$',
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

        // Check if line looks like a chapter header
        final isMatchChapter = chapterRegex.hasMatch(line);
        final isMatchStandalone = standaloneHeadingRegex.hasMatch(line);
        final isShortAllCaps = line.length > 3 &&
            line.length < 50 &&
            line == line.toUpperCase() &&
            !line.contains(RegExp(r'[0-9]{3,}')) &&
            !line.endsWith('.');

        if ((isMatchChapter || isMatchStandalone || isShortAllCaps) &&
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
}
