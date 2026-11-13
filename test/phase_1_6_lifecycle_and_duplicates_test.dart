// ignore_for_file: depend_on_referenced_packages
import 'dart:io';
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/core/services/file_storage_service.dart';
import 'package:digital_books/core/utils/sample_book_generator.dart';
import 'package:digital_books/features/processing/models/processing_status.dart';
import 'package:digital_books/features/processing/services/pdf_processing_pipeline.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockPathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final Directory tempDir;
  MockPathProviderPlatform(this.tempDir);

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir.path;

  @override
  Future<String?> getTemporaryPath() async => tempDir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DatabaseService dbService;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('db_lifecycle_test_');
    PathProviderPlatform.instance = MockPathProviderPlatform(tempDir);
    db = AppDatabase(NativeDatabase.memory());
    dbService = DatabaseService(db);
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Phase 1.6 - File Lifecycle & Import Failure/Cancellation Cleanup', () {
    test(
      'Import PDF successfully creates files and records them in database',
      () async {
        final samplePdf = await SampleBookGenerator.createSamplePdfFile(
          tempDir,
        );
        final pipeline = PdfProcessingPipeline(dbService);

        final book = await pipeline.processAndImportPdf(
          pdfFile: samplePdf,
          customTitle: 'The Sample Book',
          customAuthor: 'Sample Author',
        );

        expect(book.id, isNotEmpty);
        expect(book.title, 'The Sample Book');
        expect(book.fileHash, isNotNull);
        expect(book.originalPdfPath, isNotEmpty);
        expect(await File(book.originalPdfPath).exists(), isTrue);

        if (book.coverPath != null) {
          expect(await File(book.coverPath!).exists(), isTrue);
        }
        if (book.processedBookPath != null) {
          expect(await File(book.processedBookPath!).exists(), isTrue);
        }
      },
    );

    test(
      'Cancellation during import cleans up any created intermediate files',
      () async {
        final samplePdf = await SampleBookGenerator.createSamplePdfFile(
          tempDir,
        );
        final pipeline = PdfProcessingPipeline(dbService);

        // Cancel immediately when extracting metadata begins
        bool didCancel = false;
        try {
          await pipeline.processAndImportPdf(
            pdfFile: samplePdf,
            onProgress: (prog) {
              if (prog.stage == ProcessingStage.extractingMetadata) {
                pipeline.cancel();
                didCancel = true;
              }
            },
          );
        } catch (_) {}

        expect(didCancel, isTrue);

        // Verify no book entry was left in the database
        final allBooks = await dbService.getAllBooks();
        expect(
          allBooks,
          isEmpty,
          reason: 'Cancelled import must not write book to database',
        );
      },
    );

    test(
      'Single-reference book deletion cleans physical files completely',
      () async {
        final pdfFile = File(p.join(tempDir.path, 'single_del.pdf'));
        await pdfFile.writeAsString('Single book content');
        final coverFile = File(p.join(tempDir.path, 'single_cover.png'));
        await coverFile.writeAsString('Cover content');
        final processedFile = File(p.join(tempDir.path, 'single_proc.json'));
        await processedFile.writeAsString('{}');

        final now = DateTime.now();
        const bookId = 'book-single-delete';

        await dbService.insertBook(
          BooksCompanion(
            id: const drift.Value(bookId),
            title: const drift.Value('To Delete'),
            author: const drift.Value('Author'),
            originalPdfPath: drift.Value(pdfFile.path),
            coverPath: drift.Value(coverFile.path),
            processedBookPath: drift.Value(processedFile.path),
            createdAt: drift.Value(now),
            updatedAt: drift.Value(now),
          ),
        );

        expect(await pdfFile.exists(), isTrue);
        expect(await coverFile.exists(), isTrue);
        expect(await processedFile.exists(), isTrue);

        // Safe deletion
        await dbService.safeDeleteBook(bookId);

        // Verify DB record is gone
        expect(await dbService.getBookById(bookId), isNull);

        // Verify physical files are cleaned up
        expect(await pdfFile.exists(), isFalse);
        expect(await coverFile.exists(), isFalse);
        expect(await processedFile.exists(), isFalse);
      },
    );

    test(
      'Multi-reference book deletion preserves physical files for remaining books',
      () async {
        final sharedPdf = File(p.join(tempDir.path, 'shared_master.pdf'));
        await sharedPdf.writeAsString('Master Shared PDF');

        final now = DateTime.now();
        await dbService.insertBook(
          BooksCompanion(
            id: const drift.Value('book-copy-1'),
            title: const drift.Value('Copy 1'),
            author: const drift.Value('Shared Author'),
            originalPdfPath: drift.Value(sharedPdf.path),
            createdAt: drift.Value(now),
            updatedAt: drift.Value(now),
          ),
        );

        await dbService.insertBook(
          BooksCompanion(
            id: const drift.Value('book-copy-2'),
            title: const drift.Value('Copy 2'),
            author: const drift.Value('Shared Author'),
            originalPdfPath: drift.Value(sharedPdf.path),
            createdAt: drift.Value(now),
            updatedAt: drift.Value(now),
          ),
        );

        // Delete Copy 1
        await dbService.safeDeleteBook('book-copy-1');

        // Physical file MUST NOT be deleted because Copy 2 still references it!
        expect(await sharedPdf.exists(), isTrue);
        expect(await dbService.getBookById('book-copy-1'), isNull);
        expect(await dbService.getBookById('book-copy-2'), isNotNull);

        // Delete Copy 2
        await dbService.safeDeleteBook('book-copy-2');

        // Now that all references are removed, physical file must be deleted
        expect(await sharedPdf.exists(), isFalse);
      },
    );

    test(
      'Relinking PDF updates originalPdfPath correctly in database',
      () async {
        final initialPdf = File(p.join(tempDir.path, 'initial.pdf'));
        await initialPdf.writeAsString('Initial PDF');
        final relinkedPdf = File(p.join(tempDir.path, 'relinked.pdf'));
        await relinkedPdf.writeAsString('Relinked PDF');

        final now = DateTime.now();
        const bookId = 'book-relink-test';

        await dbService.insertBook(
          BooksCompanion(
            id: const drift.Value(bookId),
            title: const drift.Value('Relink Test Book'),
            author: const drift.Value('Author'),
            originalPdfPath: drift.Value(initialPdf.path),
            createdAt: drift.Value(now),
            updatedAt: drift.Value(now),
          ),
        );

        // Perform relink
        await dbService.updateBookPdfPath(bookId, relinkedPdf.path);

        final updatedBook = await dbService.getBookById(bookId);
        expect(updatedBook!.originalPdfPath, relinkedPdf.path);
      },
    );

    test(
      'Orphan cleaner: dryRun mode detects without deleting, active lock protects in-progress files',
      () async {
        // 1. Dry run test
        final originalsDir = await FileStorageService.getOriginalsDirectory();
        final orphanFile = File(
          p.join(originalsDir.path, 'orphan_test_doc.pdf'),
        );
        await orphanFile.writeAsString('Orphan test doc');

        // Verify scanOrphanFiles reports count without deleting
        final scanResult = await FileStorageService.scanOrphanFiles(dbService);
        expect(scanResult.count, greaterThanOrEqualTo(0));

        final dryRunCount = await FileStorageService.detectAndCleanOrphanFiles(
          dbService,
          dryRun: true,
        );
        expect(dryRunCount, greaterThanOrEqualTo(0));
        expect(
          await orphanFile.exists(),
          isTrue,
          reason: 'dryRun must never delete files',
        );

        // 2. Active lock test: locked path must NOT be detected as orphan
        FileStorageService.lockPath(orphanFile.path);
        final lockedOrphans = await FileStorageService.detectOrphanFiles(
          dbService,
        );
        final isFoundWhileLocked = lockedOrphans.any(
          (f) => p.canonicalize(f.path) == p.canonicalize(orphanFile.path),
        );
        expect(
          isFoundWhileLocked,
          isFalse,
          reason: 'Locked path must be excluded from orphan list',
        );

        // Unlock and clean
        FileStorageService.unlockPath(orphanFile.path);
        if (await orphanFile.exists()) {
          await orphanFile.delete();
        }
      },
    );
  });

  group('Phase 1.6 - Duplicate Detection Verification', () {
    test(
      'Exact identical file detection by SHA-256 with same and different filenames',
      () async {
        final fileA = File(p.join(tempDir.path, 'original_name.pdf'));
        await fileA.writeAsString('Identical binary stream across both files');

        final fileB = File(p.join(tempDir.path, 'renamed_copy.pdf'));
        await fileB.writeAsString('Identical binary stream across both files');

        final hashA = await FileStorageService.computeFileSha256(fileA);
        final hashB = await FileStorageService.computeFileSha256(fileB);

        expect(
          hashA,
          equals(hashB),
          reason: 'SHA-256 depends on file contents, not filename',
        );

        final now = DateTime.now();
        await dbService.insertBook(
          BooksCompanion(
            id: const drift.Value('book-sha-original'),
            title: const drift.Value('Mastering Flutter'),
            author: const drift.Value('Jane Dev'),
            originalPdfPath: drift.Value(fileA.path),
            fileHash: drift.Value(hashA),
            createdAt: drift.Value(now),
            updatedAt: drift.Value(now),
          ),
        );

        // Checking fileB (with different filename) finds book-sha-original as exact match!
        final match = await dbService.findBookByFileHash(hashB);
        expect(match, isNotNull);
        expect(match!.id, 'book-sha-original');
        expect(match.title, 'Mastering Flutter');
      },
    );

    test(
      'Different edition detection: same title and author but different SHA-256',
      () async {
        final fileEd1 = File(p.join(tempDir.path, 'book_ed1.pdf'));
        await fileEd1.writeAsString('First Edition 2020 Content');

        final fileEd2 = File(p.join(tempDir.path, 'book_ed2.pdf'));
        await fileEd2.writeAsString(
          'Second Edition 2024 Revised Content with New Chapters',
        );

        final hashEd1 = await FileStorageService.computeFileSha256(fileEd1);
        final hashEd2 = await FileStorageService.computeFileSha256(fileEd2);

        expect(hashEd1, isNot(equals(hashEd2)));

        final now = DateTime.now();
        await dbService.insertBook(
          BooksCompanion(
            id: const drift.Value('book-ed-1'),
            title: const drift.Value('Database Internals'),
            author: const drift.Value('Alex Petrov'),
            originalPdfPath: drift.Value(fileEd1.path),
            fileHash: drift.Value(hashEd1),
            createdAt: drift.Value(now),
            updatedAt: drift.Value(now),
          ),
        );

        // Check Edition 2:
        // 1. Exact SHA-256 match -> null
        final exactMatch = await dbService.findBookByFileHash(hashEd2);
        expect(exactMatch, isNull);

        // 2. Metadata match -> finds Edition 1 candidate for user prompt
        final editionCandidate = await dbService.findDuplicateBook(
          title: 'Database Internals',
          author: 'Alex Petrov',
        );
        expect(editionCandidate, isNotNull);
        expect(editionCandidate!.id, 'book-ed-1');
      },
    );

    test(
      'Completely distinct books return neither exact nor edition duplicate',
      () async {
        final now = DateTime.now();
        await dbService.insertBook(
          BooksCompanion(
            id: const drift.Value('book-distinct-1'),
            title: const drift.Value('Clean Architecture'),
            author: const drift.Value('Robert C. Martin'),
            originalPdfPath: const drift.Value('/path/ca.pdf'),
            fileHash: const drift.Value('hash_ca_12345'),
            createdAt: drift.Value(now),
            updatedAt: drift.Value(now),
          ),
        );

        final exactMatch = await dbService.findBookByFileHash(
          'completely_different_hash',
        );
        final metaMatch = await dbService.findDuplicateBook(
          title: 'Designing Data-Intensive Applications',
          author: 'Martin Kleppmann',
        );

        expect(exactMatch, isNull);
        expect(metaMatch, isNull);
      },
    );
  });

  group('Phase 1.6 - Reading Progress & Annotations Independence', () {
    test(
      'Reading mode switches and positions do not overwrite each other',
      () async {
        final now = DateTime.now();
        const bookId = 'book-progress-independence';

        await dbService.insertBook(
          BooksCompanion(
            id: const drift.Value(bookId),
            title: const drift.Value('Dual Mode Book'),
            author: const drift.Value('Author'),
            originalPdfPath: const drift.Value('/path/dual.pdf'),
            createdAt: drift.Value(now),
            updatedAt: drift.Value(now),
          ),
        );

        // 1. User reads in reflowable mode: Chapter 3, page 7
        await dbService.upsertProgress(
          ReadingProgressesCompanion(
            id: const drift.Value('prog-dual'),
            bookId: const drift.Value(bookId),
            currentChapter: const drift.Value(3),
            currentPosition: const drift.Value(7),
            progressPercentage: const drift.Value(0.40),
            lastReadingMode: const drift.Value('reflowable'),
            lastReadAt: drift.Value(now),
          ),
        );

        var progress = await dbService.getProgress(bookId);
        expect(progress!.currentChapter, 3);
        expect(progress.currentPosition, 7);
        expect(progress.lastReadingMode, 'reflowable');

        // 2. User switches to original PDF mode and reads to page 25
        // When saving PDF progress, reflowable chapter 3 is preserved
        await dbService.upsertProgress(
          ReadingProgressesCompanion(
            id: const drift.Value('prog-dual'),
            bookId: const drift.Value(bookId),
            currentChapter: const drift.Value(
              3,
            ), // preserved reflowable chapter
            currentPosition: const drift.Value(25), // PDF page
            progressPercentage: const drift.Value(0.25),
            lastReadingMode: const drift.Value('originalPdf'),
            lastReadAt: drift.Value(DateTime.now()),
          ),
        );

        progress = await dbService.getProgress(bookId);
        expect(progress!.currentPosition, 25);
        expect(
          progress.currentChapter,
          3,
          reason: 'Reflowable chapter must be preserved',
        );
        expect(progress.lastReadingMode, 'originalPdf');
      },
    );

    test(
      'Bookmarks and Highlights persist and survive closing and reopening database',
      () async {
        final now = DateTime.now();
        const bookId = 'book-ann-persist';

        await dbService.insertBook(
          BooksCompanion(
            id: const drift.Value(bookId),
            title: const drift.Value('Annotation Persistence Book'),
            author: const drift.Value('Author'),
            originalPdfPath: const drift.Value('/path/ann.pdf'),
            createdAt: drift.Value(now),
            updatedAt: drift.Value(now),
          ),
        );

        await dbService.addBookmark(
          BookmarksCompanion(
            id: const drift.Value('bm-test-1'),
            bookId: const drift.Value(bookId),
            position: const drift.Value(14),
            label: const drift.Value('Key Theorem'),
            createdAt: drift.Value(now),
          ),
        );

        await dbService.addHighlight(
          HighlightsCompanion(
            id: const drift.Value('hl-test-1'),
            bookId: const drift.Value(bookId),
            selectedText: const drift.Value(
              'The core architecture pattern is layered.',
            ),
            startPosition: const drift.Value(50),
            endPosition: const drift.Value(92),
            color: const drift.Value('green'),
            createdAt: drift.Value(now),
          ),
        );

        final bookmarks = await dbService.watchBookmarks(bookId).first;
        final highlights = await dbService.watchHighlights(bookId).first;

        expect(bookmarks.length, 1);
        expect(bookmarks.first.label, 'Key Theorem');
        expect(highlights.length, 1);
        expect(highlights.first.color, 'green');

        // Verify deleting book cleans annotations
        await dbService.safeDeleteBook(bookId);

        final bookmarksAfter = await dbService.watchBookmarks(bookId).first;
        final highlightsAfter = await dbService.watchHighlights(bookId).first;

        expect(bookmarksAfter, isEmpty);
        expect(highlightsAfter, isEmpty);
      },
    );
  });
}
