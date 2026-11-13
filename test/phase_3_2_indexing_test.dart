import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Rect;
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/core/services/file_storage_service.dart';
import 'package:digital_books/features/processing/models/ocr_page_result.dart';
import 'package:digital_books/features/reader/domain/models/search_geometry.dart';
import 'package:digital_books/features/reader/domain/services/book_search_indexer.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

void main() {
  late Directory tempDir;
  late AppDatabase db;
  late DatabaseService dbService;

  File createDigitalPdf(Directory dir, String filename) {
    final file = File('${dir.path}/$filename');
    final doc = sf.PdfDocument();
    final font = sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 14);

    final texts = [
      'Bab Satu: Penyelidikan kasus dimulai pada malam hari.',
      'Detektif menemukan sepucuk surat misterius di atas meja.',
      'Kunci jawaban tersimpan di dalam lemari besi tua.',
      'Saksi kunci menolak memberikan kesaksian palsu.',
      'Akhir penyelidikan mengungkap fakta yang sangat mengejutkan.',
    ];

    for (final text in texts) {
      final page = doc.pages.add();
      page.graphics.drawString(
        text,
        font,
        bounds: const Rect.fromLTWH(50, 100, 400, 30),
      );
    }

    file.writeAsBytesSync(doc.saveSync());
    doc.dispose();
    return file;
  }

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('indexing_test_');
    db = AppDatabase(NativeDatabase.memory());
    dbService = DatabaseService(db);
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Phase 3.2 — BookSearchIndexer Dual-Source & Staleness Test', () {
    test(
      '1. Digital PDF extraction and indexing with bounding boxes',
      () async {
        final digitalPdf = createDigitalPdf(tempDir, 'digital_sample.pdf');
        const bookId = 'book_digital_index_test';
        final fileHash = await FileStorageService.computeFileSha256(digitalPdf);

        await dbService.insertBook(
          BooksCompanion(
            id: const drift.Value(bookId),
            title: const drift.Value('Buku Digital'),
            author: const drift.Value('Penulis Digital'),
            originalPdfPath: drift.Value(digitalPdf.path),
            fileHash: drift.Value(fileHash),
            totalPages: const drift.Value(5),
            createdAt: drift.Value(DateTime.now()),
            updatedAt: drift.Value(DateTime.now()),
          ),
        );

        final indexer = BookSearchIndexer(dbService: dbService);

        // Index first 5 pages (pages 0..4)
        final indexedCount = await indexer.indexBook(
          bookId: bookId,
          pdfPath: digitalPdf.path,
          startPage: 0,
          endPage: 4,
        );

        expect(indexedCount, equals(5));

        final pages = await dbService.getSearchPagesForBook(bookId);
        expect(pages.length, equals(5));

        for (final p in pages) {
          expect(p.plainText, isNotEmpty);
          expect(p.geometryJson, isNotEmpty);
          expect(p.isOcr, isFalse);

          final tokens = (jsonDecode(p.geometryJson) as List<dynamic>)
              .map(
                (item) =>
                    SearchTokenGeometry.fromJson(item as Map<String, dynamic>),
              )
              .toList();

          expect(tokens, isNotEmpty);
          for (final t in tokens) {
            // Bounding boxes must be strictly inside normalized [0, 1] range
            expect(t.box.left, inInclusiveRange(0.0, 1.0));
            expect(t.box.top, inInclusiveRange(0.0, 1.0));
            expect(t.box.width, inInclusiveRange(0.0, 1.0));
            expect(t.box.height, inInclusiveRange(0.0, 1.0));
          }
        }
      },
    );

    test('2. Resumable indexing: Already indexed pages are skipped', () async {
      final digitalPdf = createDigitalPdf(tempDir, 'digital_resumable.pdf');
      const bookId = 'book_resumable_test';
      final fileHash = await FileStorageService.computeFileSha256(digitalPdf);

      await dbService.insertBook(
        BooksCompanion(
          id: const drift.Value(bookId),
          title: const drift.Value('Buku Resumable'),
          author: const drift.Value('Penulis Resumable'),
          originalPdfPath: drift.Value(digitalPdf.path),
          fileHash: drift.Value(fileHash),
          totalPages: const drift.Value(5),
          createdAt: drift.Value(DateTime.now()),
          updatedAt: drift.Value(DateTime.now()),
        ),
      );

      final indexer = BookSearchIndexer(dbService: dbService);

      // Run 1: Index pages 0..2 (3 pages)
      final run1 = await indexer.indexBook(
        bookId: bookId,
        pdfPath: digitalPdf.path,
        startPage: 0,
        endPage: 2,
      );
      expect(run1, equals(3));

      // Run 2: Re-run pages 0..4 (should skip 0..2, index 3..4 -> only 2 newly indexed)
      final run2 = await indexer.indexBook(
        bookId: bookId,
        pdfPath: digitalPdf.path,
        startPage: 0,
        endPage: 4,
      );
      expect(run2, equals(2));

      // Run 3: Re-run pages 0..4 (should index 0 newly indexed)
      final run3 = await indexer.indexBook(
        bookId: bookId,
        pdfPath: digitalPdf.path,
        startPage: 0,
        endPage: 4,
      );
      expect(run3, equals(0));
    });

    test(
      '3. Staleness invalidation: PDF hash mismatch purges old index',
      () async {
        final digitalPdf = createDigitalPdf(tempDir, 'digital_staleness.pdf');
        const bookId = 'book_staleness_test';
        const oldHash = 'outdated_stale_hash_123';

        await dbService.insertBook(
          BooksCompanion(
            id: const drift.Value(bookId),
            title: const drift.Value('Buku Staleness'),
            author: const drift.Value('Penulis Staleness'),
            originalPdfPath: drift.Value(digitalPdf.path),
            fileHash: const drift.Value(oldHash),
            totalPages: const drift.Value(5),
            createdAt: drift.Value(DateTime.now()),
            updatedAt: drift.Value(DateTime.now()),
          ),
        );

        // Insert dummy stale search page
        await dbService.insertSearchPage(
          BookSearchPagesCompanion(
            id: const drift.Value('${bookId}_p0'),
            bookId: const drift.Value(bookId),
            pageIndex: const drift.Value(0),
            plainText: const drift.Value('Stale text from old version'),
            rawText: const drift.Value('Stale text from old version'),
            geometryJson: const drift.Value('[]'),
            isOcr: const drift.Value(false),
            fileHash: const drift.Value(oldHash),
            indexVersion: const drift.Value(1),
            indexedAt: drift.Value(DateTime.now()),
          ),
        );

        expect(await dbService.getIndexedSearchPageCount(bookId), equals(1));

        // Run indexer with real PDF (whose hash is different from oldHash)
        final indexer = BookSearchIndexer(dbService: dbService);
        final indexed = await indexer.indexBook(
          bookId: bookId,
          pdfPath: digitalPdf.path,
          startPage: 0,
          endPage: 1,
        );

        expect(indexed, equals(2));
        final updatedPages = await dbService.getSearchPagesForBook(bookId);
        expect(updatedPages.length, equals(2));
        // Stale text must be gone
        expect(updatedPages.first.plainText, isNot(contains('Stale text')));
      },
    );

    test(
      '4. Apple Vision OCR page indexing prioritizes completed OCR lines',
      () async {
        final digitalPdf = createDigitalPdf(tempDir, 'digital_ocr.pdf');
        const bookId = 'book_ocr_source_test';
        final fileHash = await FileStorageService.computeFileSha256(digitalPdf);

        await dbService.insertBook(
          BooksCompanion(
            id: const drift.Value(bookId),
            title: const drift.Value('Buku OCR Uji'),
            author: const drift.Value('Penulis Uji'),
            originalPdfPath: drift.Value(digitalPdf.path),
            fileHash: drift.Value(fileHash),
            totalPages: const drift.Value(2),
            createdAt: drift.Value(DateTime.now()),
            updatedAt: drift.Value(DateTime.now()),
          ),
        );

        final ocrLines = [
          const OcrLine(
            text: 'KOMUNIKASI EFEKTIF DARI HASIL OCR',
            box: Rect.fromLTWH(0.2, 0.1, 0.6, 0.05),
            confidence: 0.98,
          ),
          const OcrLine(
            text: 'Bab pertama membahas dasar berbicara di depan umum.',
            box: Rect.fromLTWH(0.1, 0.2, 0.7, 0.04),
            confidence: 0.95,
          ),
        ];

        // Insert completed OCR page
        await dbService.insertOcrPage(
          OcrPagesCompanion(
            id: const drift.Value('${bookId}_ocr_0'),
            bookId: const drift.Value(bookId),
            pageIndex: const drift.Value(0),
            status: const drift.Value('completed'),
            linesJson: drift.Value(
              jsonEncode(ocrLines.map((l) => l.toJson()).toList()),
            ),
            createdAt: drift.Value(DateTime.now()),
          ),
        );

        final indexer = BookSearchIndexer(dbService: dbService);
        final indexed = await indexer.indexBook(
          bookId: bookId,
          pdfPath: digitalPdf.path,
          startPage: 0,
          endPage: 0,
        );

        expect(indexed, equals(1));
        final page = await dbService.getSearchPage(bookId, 0);
        expect(page, isNotNull);
        expect(page!.isOcr, isTrue);
        expect(page.plainText, contains('KOMUNIKASI EFEKTIF DARI HASIL OCR'));
        expect(page.plainText, contains('Bab pertama membahas dasar'));
      },
    );
  });
}
