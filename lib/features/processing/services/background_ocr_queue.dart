import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:pdfrx/pdfrx.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/database_service.dart';
import '../../../core/services/file_storage_service.dart';
import '../models/ocr_queue_state.dart';
import 'apple_vision_ocr_service.dart';
import 'ocr_semantic_pipeline.dart';

/// Background OCR Queue that coordinates page-by-page OCR recognition.
///
/// Ensures:
/// 1. Low peak memory: Processes only 1 page at a time; immediately releases native textures and bitmaps.
/// 2. Resumability: Skips pages already marked 'completed' in the database.
/// 3. Interactivity: Supports pause, resume, cancel, and retrying failed pages.
/// 4. UI responsiveness: Yields execution between pages to avoid UI thread starvation.
class BackgroundOcrQueue {
  final DatabaseService dbService;
  final AppleVisionOcrService ocrService;
  final OcrSemanticPipeline? semanticPipeline;

  OcrQueueProgress _state = OcrQueueProgress.idle();
  final _progressController = StreamController<OcrQueueProgress>.broadcast();

  bool _isCancelled = false;
  bool _isPaused = false;
  Completer<void>? _pauseCompleter;
  bool _isRunning = false;

  BackgroundOcrQueue({
    required this.dbService,
    required this.ocrService,
    this.semanticPipeline,
  });

  /// The current snapshot of queue progress.
  OcrQueueProgress get state => _state;

  /// Live broadcast stream of queue progress events.
  Stream<OcrQueueProgress> get progressStream => _progressController.stream;

  bool get isRunning => _isRunning;

  void _emit(OcrQueueProgress progress) {
    _state = progress;
    if (!_progressController.isClosed) {
      _progressController.add(progress);
    }
  }

  /// Pauses queue processing after current page completes.
  void pause() {
    if (_isRunning && !_isPaused) {
      _isPaused = true;
      _pauseCompleter = Completer<void>();
      _emit(_state.copyWith(status: OcrQueueStatus.paused));
    }
  }

  /// Resumes queue processing if currently paused.
  void resume() {
    if (_isRunning && _isPaused) {
      _isPaused = false;
      _pauseCompleter?.complete();
      _pauseCompleter = null;
      _emit(_state.copyWith(status: OcrQueueStatus.running));
    }
  }

  /// Cancels active queue processing.
  void cancel() {
    if (_isRunning) {
      _isCancelled = true;
      if (_isPaused) {
        _isPaused = false;
        _pauseCompleter?.complete();
        _pauseCompleter = null;
      }
      _emit(_state.copyWith(status: OcrQueueStatus.cancelled));
    }
  }

  /// Starts or resumes OCR processing for [bookId] on the PDF at [pdfPath].
  ///
  /// If [startPage] or [endPage] are provided, only that subset of pages is processed.
  /// Already completed pages in Drift are preserved and skipped.
  Future<void> start({
    required String bookId,
    required String pdfPath,
    int? startPage,
    int? endPage,
    List<String> languages = const ['id-ID', 'en-US'],
    bool accurate = true,
    double renderScale = 1.5,
    bool autoReconstruct = false,
  }) async {
    if (_isRunning) {
      if (_state.bookId == bookId) {
        // Already running this book
        return;
      }
      throw StateError(
        'BackgroundOcrQueue is already actively processing book ${_state.bookId}',
      );
    }

    final file = File(pdfPath);
    if (!file.existsSync()) {
      _emit(
        OcrQueueProgress(
          bookId: bookId,
          status: OcrQueueStatus.error,
          currentPageIndex: 0,
          totalPages: 0,
          completedPages: 0,
          errorMessage: 'PDF file not found at $pdfPath',
        ),
      );
      return;
    }

    _isRunning = true;
    _isCancelled = false;
    _isPaused = false;
    _pauseCompleter = null;

    // Validate PDF freshness against stored fileHash to avoid stale OCR cache
    final book = await dbService.getBookById(bookId);
    if (book != null && book.fileHash != null) {
      final currentHash = await FileStorageService.computeFileSha256(file);
      if (currentHash != book.fileHash) {
        // File was modified or replaced: invalidate stale OCR pages and old processed derivative
        await dbService.deleteOcrPagesForBook(bookId);
        await dbService.insertBook(
          book
              .toCompanion(true)
              .copyWith(
                fileHash: Value(currentHash),
                processedBookPath: const Value(null),
                updatedAt: Value(DateTime.now()),
              ),
        );
      }
    }

    PdfDocument? doc;
    try {
      doc = await PdfDocument.openFile(pdfPath);
      final totalBookPages = doc.pages.length;
      final effectiveStart = (startPage ?? 0).clamp(0, totalBookPages - 1);
      final effectiveEnd = (endPage ?? (totalBookPages - 1)).clamp(
        effectiveStart,
        totalBookPages - 1,
      );
      final targetPageCount = effectiveEnd - effectiveStart + 1;

      // Check existing completed pages in database
      final existingPages = await dbService.getOcrPagesForBook(bookId);
      final completedIndices = existingPages
          .where((p) => p.status == 'completed')
          .map((p) => p.pageIndex)
          .toSet();

      int completedCount = 0;
      for (int i = effectiveStart; i <= effectiveEnd; i++) {
        if (completedIndices.contains(i)) {
          completedCount++;
        }
      }

      double totalDurationMs = 0.0;
      int newlyProcessed = 0;

      _emit(
        OcrQueueProgress(
          bookId: bookId,
          status: OcrQueueStatus.running,
          currentPageIndex: effectiveStart,
          totalPages: targetPageCount,
          completedPages: completedCount,
        ),
      );

      for (int pageIdx = effectiveStart; pageIdx <= effectiveEnd; pageIdx++) {
        if (_isCancelled) {
          _emit(_state.copyWith(status: OcrQueueStatus.cancelled));
          break;
        }

        if (_isPaused && _pauseCompleter != null) {
          await _pauseCompleter!.future;
          if (_isCancelled) {
            _emit(_state.copyWith(status: OcrQueueStatus.cancelled));
            break;
          }
        }

        // Skip if already successfully completed
        if (completedIndices.contains(pageIdx)) {
          continue;
        }

        _emit(
          _state.copyWith(
            status: OcrQueueStatus.running,
            currentPageIndex: pageIdx,
            completedPages: completedCount,
            averagePageDurationMs: newlyProcessed > 0
                ? totalDurationMs / newlyProcessed
                : 0.0,
          ),
        );

        final page = doc.pages[pageIdx];
        final ocrResult = await ocrService.processPdfPage(
          page,
          scale: renderScale,
          languages: languages,
          accurate: accurate,
        );

        final now = DateTime.now();
        final recordId = '${bookId}_$pageIdx';

        if (ocrResult.hasError) {
          // Record failed page to drift
          await dbService.insertOcrPage(
            OcrPagesCompanion(
              id: Value(recordId),
              bookId: Value(bookId),
              pageIndex: Value(pageIdx),
              status: const Value('failed'),
              confidence: const Value(0.0),
              charCount: const Value(0),
              durationMs: Value(ocrResult.durationMs),
              linesJson: const Value('[]'),
              createdAt: Value(now),
            ),
          );
        } else {
          // Success
          final linesJson = jsonEncode(
            ocrResult.lines.map((l) => l.toJson()).toList(),
          );
          final charCount = ocrResult.lines.fold<int>(
            0,
            (acc, l) => acc + l.text.length,
          );
          final avgConfidence = ocrResult.lines.isEmpty
              ? 1.0
              : ocrResult.lines
                        .map((l) => l.confidence)
                        .reduce((a, b) => a + b) /
                    ocrResult.lines.length;

          await dbService.insertOcrPage(
            OcrPagesCompanion(
              id: Value(recordId),
              bookId: Value(bookId),
              pageIndex: Value(pageIdx),
              status: const Value('completed'),
              confidence: Value(avgConfidence),
              charCount: Value(charCount),
              durationMs: Value(ocrResult.durationMs),
              linesJson: Value(linesJson),
              createdAt: Value(now),
            ),
          );

          totalDurationMs += ocrResult.durationMs;
          newlyProcessed++;
          completedCount++;
        }

        _emit(
          _state.copyWith(
            status: OcrQueueStatus.running,
            currentPageIndex: pageIdx,
            completedPages: completedCount,
            averagePageDurationMs: newlyProcessed > 0
                ? totalDurationMs / newlyProcessed
                : 0.0,
          ),
        );

        // Yield execution to the event loop so UI / other tasks stay butter-smooth
        await Future.delayed(const Duration(milliseconds: 10));
      }

      if (!_isCancelled) {
        if (autoReconstruct && semanticPipeline != null) {
          try {
            await semanticPipeline!.reconstructBook(
              bookId: bookId,
              pdfPath: pdfPath,
            );
          } catch (e, st) {
            // Keep error visible in state or log
            _emit(
              _state.copyWith(
                status: OcrQueueStatus.error,
                errorMessage: 'Reconstruction error: $e\n$st',
              ),
            );
            return;
          }
        }

        _emit(
          _state.copyWith(
            status: OcrQueueStatus.completed,
            completedPages: completedCount,
          ),
        );
      }
    } catch (e, stack) {
      _emit(
        _state.copyWith(
          status: OcrQueueStatus.error,
          errorMessage: 'OCR Queue failed: $e\n$stack',
        ),
      );
    } finally {
      _isRunning = false;
      await doc?.dispose();
    }
  }

  /// Retries any pages for [bookId] that have `status == 'failed'`.
  Future<void> retryFailed({
    required String bookId,
    required String pdfPath,
    List<String> languages = const ['id-ID', 'en-US'],
    bool accurate = true,
  }) async {
    final existingPages = await dbService.getOcrPagesForBook(bookId);
    final failedPages = existingPages
        .where((p) => p.status == 'failed')
        .map((p) => p.pageIndex)
        .toList();

    if (failedPages.isEmpty) return;

    for (final pageIdx in failedPages) {
      // Re-run start on single page or reprocess
      await start(
        bookId: bookId,
        pdfPath: pdfPath,
        startPage: pageIdx,
        endPage: pageIdx,
        languages: languages,
        accurate: accurate,
      );
    }
  }

  void dispose() {
    _progressController.close();
  }
}
