import 'dart:async';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/features/processing/models/ocr_queue_state.dart';
import 'package:digital_books/features/processing/services/apple_vision_ocr_service.dart';
import 'package:digital_books/features/processing/services/background_ocr_queue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DatabaseService dbService;
  late AppleVisionOcrService ocrService;
  late BackgroundOcrQueue queue;

  final testPdf = File(
    '/Users/davindalana/Downloads/Laut Bercerita (Leila S. Chudori).pdf',
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dbService = DatabaseService(db);
    ocrService = const AppleVisionOcrService();
    queue = BackgroundOcrQueue(
      dbService: dbService,
      ocrService: ocrService,
    );

    // Seed test book in DB
    await dbService.insertBook(
      BooksCompanion(
        id: const Value('book_queue_test'),
        title: const Value('Laut Bercerita (Queue Test)'),
        author: const Value('Leila S. Chudori'),
        originalPdfPath: Value(testPdf.path),
        totalPages: const Value(5),
        createdAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  });

  tearDown(() async {
    queue.dispose();
    await db.close();
  });

  group('Phase 3.1 Checkpoint C: Background OCR Queue', () {
    test('1. Runs page-by-page OCR and updates DB & progress stream', () async {
      expect(queue.state.status, equals(OcrQueueStatus.idle));

      final progressEvents = <OcrQueueProgress>[];
      final sub = queue.progressStream.listen((p) {
        progressEvents.add(p);
      });

      // Run on page 14 and 15
      await queue.start(
        bookId: 'book_queue_test',
        pdfPath: testPdf.path,
        startPage: 14,
        endPage: 15,
      );

      await sub.cancel();

      expect(queue.state.status, equals(OcrQueueStatus.completed));
      expect(queue.state.completedPages, equals(2));

      // Check DB
      final savedPages = await dbService.getOcrPagesForBook('book_queue_test');
      expect(savedPages.length, equals(2));
      expect(savedPages[0].pageIndex, equals(14));
      expect(savedPages[0].status, equals('completed'));
      expect(savedPages[0].charCount, greaterThan(0));
      expect(savedPages[1].pageIndex, equals(15));
      expect(savedPages[1].status, equals('completed'));
      expect(savedPages[1].charCount, greaterThan(0));

      // Verify stream emitted progression
      expect(progressEvents.isNotEmpty, isTrue);
      expect(progressEvents.any((p) => p.status == OcrQueueStatus.running), isTrue);
      expect(progressEvents.last.status, equals(OcrQueueStatus.completed));
    });

    test('2. Resumability: Skips already completed pages', () async {
      // Pre-populate page 14 as completed
      await dbService.insertOcrPage(
        OcrPagesCompanion(
          id: const Value('book_queue_test_14'),
          bookId: const Value('book_queue_test'),
          pageIndex: const Value(14),
          status: const Value('completed'),
          confidence: const Value(1.0),
          charCount: const Value(500),
          durationMs: const Value(150.0),
          linesJson: const Value('[]'),
          createdAt: Value(DateTime.now()),
        ),
      );

      final sw = Stopwatch()..start();
      // Run on pages 14 through 15
      await queue.start(
        bookId: 'book_queue_test',
        pdfPath: testPdf.path,
        startPage: 14,
        endPage: 15,
      );
      sw.stop();

      final savedPages = await dbService.getOcrPagesForBook('book_queue_test');
      expect(savedPages.length, equals(2));
      // Page 14 should retain its pre-populated charCount of 500
      final p14 = savedPages.firstWhere((p) => p.pageIndex == 14);
      expect(p14.charCount, equals(500));
      // Page 15 was processed
      final p15 = savedPages.firstWhere((p) => p.pageIndex == 15);
      expect(p15.charCount, greaterThan(0));
    });

    test('3. Pause and Resume flow', () async {
      final pauseTriggered = Completer<void>();

      final sub = queue.progressStream.listen((p) {
        if (p.status == OcrQueueStatus.running && p.currentPageIndex == 14 && !pauseTriggered.isCompleted) {
          queue.pause();
          pauseTriggered.complete();
        }
      });

      final queueFuture = queue.start(
        bookId: 'book_queue_test',
        pdfPath: testPdf.path,
        startPage: 14,
        endPage: 15,
      );

      await pauseTriggered.future;
      await Future.delayed(const Duration(milliseconds: 50));
      expect(queue.state.status, equals(OcrQueueStatus.paused));

      // Resume
      queue.resume();
      await queueFuture;
      await sub.cancel();

      expect(queue.state.status, equals(OcrQueueStatus.completed));
    });

    test('4. Cancellation flow terminates gracefully', () async {
      final sub = queue.progressStream.listen((p) {
        if (p.status == OcrQueueStatus.running) {
          queue.cancel();
        }
      });

      await queue.start(
        bookId: 'book_queue_test',
        pdfPath: testPdf.path,
        startPage: 14,
        endPage: 16,
      );

      await sub.cancel();
      expect(queue.state.status, equals(OcrQueueStatus.cancelled));
    });
  });
}
