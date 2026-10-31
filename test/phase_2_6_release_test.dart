import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/core/services/backup_restore_service.dart';

void main() {
  group('Phase 2.6 — Release Candidate: 12 Backup & Restore Validation Scenarios', () {
    late AppDatabase db;
    late DatabaseService dbService;
    late Directory tempDir;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      dbService = DatabaseService(db);
      tempDir = await Directory.systemTemp.createTemp('db_release_test_');
    });

    tearDown(() async {
      await db.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    // SCENARIO 1: Backup and restore into an empty database
    test(
      'Scenario 1: Backup and restore into a completely empty database',
      () async {
        final now = DateTime.now();
        await dbService.insertBook(
          BooksCompanion.insert(
            id: 'sc1_book',
            title: 'Meditations',
            author: 'Marcus Aurelius',
            originalPdfPath: '/tmp/meditations.pdf',
            fileHash: const drift.Value('hash_sc1'),
            createdAt: now,
            updatedAt: now,
          ),
        );

        await dbService.addBookmark(
          BookmarksCompanion.insert(
            id: 'sc1_bm',
            bookId: 'sc1_book',
            position: 10,
            label: 'Book 4: The inner citadel',
            createdAt: now,
          ),
        );

        final jsonBackup = await BackupRestoreService.generateBackupJson(
          dbService: dbService,
        );

        final targetDb = AppDatabase(NativeDatabase.memory());
        final targetDbService = DatabaseService(targetDb);

        final result = await BackupRestoreService.executeRestore(
          backupJson: jsonBackup,
          dbService: targetDbService,
          policy: RestoreConflictPolicy.skipExisting,
        );

        expect(result.booksRestored, 1);
        expect(result.bookmarksRestored, 1);

        final restoredBooks = await targetDbService.getAllBooks();
        expect(restoredBooks.length, 1);
        expect(restoredBooks.first.title, 'Meditations');

        await targetDb.close();
      },
    );

    // SCENARIO 2: Restore into a database containing existing books
    test(
      'Scenario 2: Restore into a database containing existing books',
      () async {
        final now = DateTime.now();
        // Database already has Book A
        await dbService.insertBook(
          BooksCompanion.insert(
            id: 'book_a',
            title: 'Book A (Local)',
            author: 'Author A',
            originalPdfPath: '/tmp/a.pdf',
            createdAt: now,
            updatedAt: now,
          ),
        );

        // Backup has Book A and Book B
        final backupPayload = {
          'metadata': {'formatVersion': '1.0', 'appVersion': '1.0.0'},
          'collections': [],
          'books': [
            {
              'id': 'book_a',
              'title': 'Book A (Backup)',
              'author': 'Author A',
              'originalPdfPath': '/tmp/a.pdf',
              'bookmarks': [],
              'highlights': [],
            },
            {
              'id': 'book_b',
              'title': 'Book B (New)',
              'author': 'Author B',
              'originalPdfPath': '/tmp/b.pdf',
              'bookmarks': [],
              'highlights': [],
            },
          ],
        };

        final result = await BackupRestoreService.executeRestore(
          backupJson: jsonEncode(backupPayload),
          dbService: dbService,
          policy: RestoreConflictPolicy.skipExisting,
        );

        expect(result.booksRestored, 1); // Book B
        expect(result.booksSkipped, 1); // Book A
        final all = await dbService.getAllBooks();
        expect(all.length, 2);
      },
    );

    // SCENARIO 3 & 4: Skip existing vs Merge/update existing
    test(
      'Scenario 3 & 4: skipExisting keeps original metadata; mergeUpdateExisting updates metadata',
      () async {
        final now = DateTime.now();
        await dbService.insertBook(
          BooksCompanion.insert(
            id: 'book_edit',
            title: 'Original Title',
            author: 'Author X',
            originalPdfPath: '/tmp/x.pdf',
            createdAt: now,
            updatedAt: now,
          ),
        );

        final updatePayload = {
          'metadata': {'formatVersion': '1.0', 'appVersion': '1.0.0'},
          'collections': [],
          'books': [
            {
              'id': 'book_edit',
              'title': 'Updated Title in Backup',
              'author': 'Author X & Co',
              'originalPdfPath': '/tmp/x.pdf',
              'bookmarks': [],
              'highlights': [],
            },
          ],
        };

        // 3. skipExisting: does NOT update title
        await BackupRestoreService.executeRestore(
          backupJson: jsonEncode(updatePayload),
          dbService: dbService,
          policy: RestoreConflictPolicy.skipExisting,
        );
        var book = await dbService.getBookById('book_edit');
        expect(book!.title, 'Original Title');

        // 4. mergeUpdateExisting: updates title
        await BackupRestoreService.executeRestore(
          backupJson: jsonEncode(updatePayload),
          dbService: dbService,
          policy: RestoreConflictPolicy.mergeUpdateExisting,
        );
        book = await dbService.getBookById('book_edit');
        expect(book!.title, 'Updated Title in Backup');
      },
    );

    // SCENARIO 5: Backup contains NEWER reading progress
    test(
      'Scenario 5: Restoring when backup contains strictly newer reading progress updates progress',
      () async {
        final olderTime = DateTime(2026, 10, 1);
        final newerTime = DateTime(2026, 10, 31);

        await dbService.insertBook(
          BooksCompanion.insert(
            id: 'prog_test_book',
            title: 'Test Book',
            author: 'Author',
            originalPdfPath: '/tmp/test.pdf',
            createdAt: olderTime,
            updatedAt: olderTime,
          ),
        );

        await dbService.upsertProgress(
          ReadingProgressesCompanion.insert(
            id: 'p_local',
            bookId: 'prog_test_book',
            currentChapter: const drift.Value(1),
            currentPosition: const drift.Value(10),
            progressPercentage: const drift.Value(0.20),
            lastReadAt: olderTime,
          ),
        );

        final newerBackupPayload = {
          'metadata': {'formatVersion': '1.0', 'appVersion': '1.0.0'},
          'collections': [],
          'books': [
            {
              'id': 'prog_test_book',
              'title': 'Test Book',
              'author': 'Author',
              'originalPdfPath': '/tmp/test.pdf',
              'readingProgress': {
                'currentChapter': 5,
                'currentPosition': 50,
                'progressPercentage': 0.85,
                'lastReadingMode': 'reflowable_paginated',
                'lastReadAt': newerTime.toIso8601String(),
              },
              'bookmarks': [],
              'highlights': [],
            },
          ],
        };

        await BackupRestoreService.executeRestore(
          backupJson: jsonEncode(newerBackupPayload),
          dbService: dbService,
          policy: RestoreConflictPolicy.mergeUpdateExisting,
        );

        final prog = await dbService.getProgress('prog_test_book');
        expect(prog!.currentChapter, 5);
        expect(prog.progressPercentage, 0.85);
        expect(prog.lastReadAt.year, 2026);
        expect(prog.lastReadAt.day, 31);
      },
    );

    // SCENARIO 6: Local database contains NEWER reading progress
    test(
      'Scenario 6: Restoring when local database has newer progress preserves local progress',
      () async {
        final olderBackupTime = DateTime(2026, 10, 1);
        final newerLocalTime = DateTime(2026, 10, 31);

        await dbService.insertBook(
          BooksCompanion.insert(
            id: 'prog_local_newer',
            title: 'Local Newer Book',
            author: 'Author',
            originalPdfPath: '/tmp/test.pdf',
            createdAt: olderBackupTime,
            updatedAt: newerLocalTime,
          ),
        );

        // Local progress is at chapter 8 (newer)
        await dbService.upsertProgress(
          ReadingProgressesCompanion.insert(
            id: 'p_newer_local',
            bookId: 'prog_local_newer',
            currentChapter: const drift.Value(8),
            currentPosition: const drift.Value(80),
            progressPercentage: const drift.Value(0.90),
            lastReadAt: newerLocalTime,
          ),
        );

        // Backup has older progress from last week at chapter 2 (0.25)
        final olderBackupPayload = {
          'metadata': {'formatVersion': '1.0', 'appVersion': '1.0.0'},
          'collections': [],
          'books': [
            {
              'id': 'prog_local_newer',
              'title': 'Local Newer Book',
              'author': 'Author',
              'originalPdfPath': '/tmp/test.pdf',
              'readingProgress': {
                'currentChapter': 2,
                'currentPosition': 20,
                'progressPercentage': 0.25,
                'lastReadingMode': 'reflowable_paginated',
                'lastReadAt': olderBackupTime.toIso8601String(),
              },
              'bookmarks': [],
              'highlights': [],
            },
          ],
        };

        await BackupRestoreService.executeRestore(
          backupJson: jsonEncode(olderBackupPayload),
          dbService: dbService,
          policy: RestoreConflictPolicy.mergeUpdateExisting,
        );

        // Local progress MUST NOT be regressed!
        final prog = await dbService.getProgress('prog_local_newer');
        expect(prog!.currentChapter, 8);
        expect(prog.progressPercentage, 0.90);
        expect(prog.lastReadAt, newerLocalTime);
      },
    );

    // SCENARIO 7: Merging annotations non-destructively
    test(
      'Scenario 7: Non-destructive annotation merge preserves local notes and adds backup notes',
      () async {
        final now = DateTime.now();
        await dbService.insertBook(
          BooksCompanion.insert(
            id: 'merge_anno_book',
            title: 'Annotation Merge Book',
            author: 'Author',
            originalPdfPath: '/tmp/test.pdf',
            createdAt: now,
            updatedAt: now,
          ),
        );

        // Local highlight
        await dbService.addHighlight(
          HighlightsCompanion.insert(
            id: 'hl_local_1',
            bookId: 'merge_anno_book',
            selectedText: 'Local important quotation',
            startPosition: 1,
            endPosition: 1,
            color: const drift.Value('yellow'),
            note: const drift.Value('Local personal note'),
            anchorNodeId: const drift.Value('node_1'),
            startOffset: const drift.Value(0),
            endOffset: const drift.Value(24),
            createdAt: now,
          ),
        );

        // Backup highlight (different position & text)
        final mergeBackupPayload = {
          'metadata': {'formatVersion': '1.0', 'appVersion': '1.0.0'},
          'collections': [],
          'books': [
            {
              'id': 'merge_anno_book',
              'title': 'Annotation Merge Book',
              'author': 'Author',
              'originalPdfPath': '/tmp/test.pdf',
              'bookmarks': [
                {
                  'id': 'bm_backup_1',
                  'position': 5,
                  'label': 'Page 5 bookmark from backup',
                  'anchorNodeId': 'node_5',
                  'createdAt': now.toIso8601String(),
                },
              ],
              'highlights': [
                {
                  'id': 'hl_backup_2',
                  'selectedText': 'Backup quotation from chapter 2',
                  'startPosition': 2,
                  'endPosition': 2,
                  'color': 'green',
                  'note': 'Backup note',
                  'anchorNodeId': 'node_2',
                  'startOffset': 0,
                  'endOffset': 30,
                  'createdAt': now.toIso8601String(),
                },
              ],
            },
          ],
        };

        final result = await BackupRestoreService.executeRestore(
          backupJson: jsonEncode(mergeBackupPayload),
          dbService: dbService,
          policy: RestoreConflictPolicy.mergeUpdateExisting,
        );

        expect(result.bookmarksRestored, 1);
        expect(result.highlightsRestored, 1);

        final highlights = await dbService.getHighlightsForBook(
          'merge_anno_book',
        );
        expect(highlights.length, 2);
        expect(
          highlights.any((h) => h.selectedText == 'Local important quotation'),
          isTrue,
        );
        expect(
          highlights.any(
            (h) => h.selectedText == 'Backup quotation from chapter 2',
          ),
          isTrue,
        );
      },
    );

    // SCENARIO 8: Restore with missing source PDF files
    test(
      'Scenario 8: Restore safely registers book when source PDF does not exist on disk',
      () async {
        final missingPdfPayload = {
          'metadata': {'formatVersion': '1.0', 'appVersion': '1.0.0'},
          'collections': [],
          'books': [
            {
              'id': 'book_missing_pdf',
              'title': 'Missing PDF Book',
              'author': 'Unknown',
              'originalPdfPath': '/nonexistent/path/never_existed.pdf',
              'fileHash': 'hash_missing_123',
              'bookmarks': [],
              'highlights': [],
            },
          ],
        };

        final result = await BackupRestoreService.executeRestore(
          backupJson: jsonEncode(missingPdfPayload),
          dbService: dbService,
          policy: RestoreConflictPolicy.skipExisting,
        );

        expect(result.booksRestored, 1);
        final book = await dbService.getBookById('book_missing_pdf');
        expect(book, isNotNull);
        expect(book!.originalPdfPath, '/nonexistent/path/never_existed.pdf');
      },
    );

    // SCENARIO 9: Corrupted or incomplete JSON
    test(
      'Scenario 9: Corrupted or incomplete backup throws FormatException without altering database',
      () async {
        const corruptJson =
            '{"metadata": {"formatVersion": "1.0"}, "broken": true}';

        expect(
          () => BackupRestoreService.previewBackup(
            corruptJson,
            dbService: dbService,
          ),
          throwsA(isA<FormatException>()),
        );

        expect(
          () => BackupRestoreService.executeRestore(
            backupJson: corruptJson,
            dbService: dbService,
          ),
          throwsA(isA<FormatException>()),
        );
      },
    );

    // SCENARIO 10: Unsupported backup schema version
    test(
      'Scenario 10: Unsupported schema version throws descriptive FormatException',
      () async {
        final futureVersionPayload = {
          'metadata': {'formatVersion': '99.0', 'appVersion': '99.0.0'},
          'books': [],
        };

        expect(
          () => BackupRestoreService.previewBackup(
            jsonEncode(futureVersionPayload),
            dbService: dbService,
          ),
          throwsA(isA<FormatException>()),
        );
      },
    );

    // SCENARIO 11: Transaction rollback on failure leaves database untainted
    test(
      'Scenario 11: Mid-transaction failure completely rolls back changes',
      () async {
        final now = DateTime.now();
        await dbService.insertBook(
          BooksCompanion.insert(
            id: 'existing_book_sc11',
            title: 'Untouched Book',
            author: 'Author',
            originalPdfPath: '/tmp/sc11.pdf',
            createdAt: now,
            updatedAt: now,
          ),
        );

        final failingPayload = {
          'metadata': {'formatVersion': '1.0', 'appVersion': '1.0.0'},
          'collections': [],
          'books': [
            {
              'id': 'partially_inserted_book',
              'title': 'Should Be Rolled Back',
              'author': 'Author',
              'originalPdfPath': '/tmp/fail.pdf',
              // Invalid bookmarks structure that will cause runtime cast error inside transaction
              'bookmarks': 'not_a_list_will_crash',
            },
          ],
        };

        try {
          await BackupRestoreService.executeRestore(
            backupJson: jsonEncode(failingPayload),
            dbService: dbService,
          );
          fail('Should have thrown an exception');
        } catch (_) {
          // Expected
        }

        // Verify partially inserted book is NOT in database
        final books = await dbService.getAllBooks();
        expect(books.length, 1);
        expect(books.first.id, 'existing_book_sc11');
      },
    );

    // SCENARIO 12: Full Library Bundle export
    test(
      'Scenario 12: exportFullLibraryBundle copies manifest and physical PDF files',
      () async {
        final fakePdf = File(p.join(tempDir.path, 'source_test.pdf'));
        await fakePdf.writeAsString('%PDF-1.4 Fake PDF Content for Export');

        final now = DateTime.now();
        await dbService.insertBook(
          BooksCompanion.insert(
            id: 'bundle_book_1',
            title: 'Bundle Book',
            author: 'Bundle Author',
            originalPdfPath: fakePdf.path,
            createdAt: now,
            updatedAt: now,
          ),
        );

        final exportDir = Directory(p.join(tempDir.path, 'export_target'));
        await exportDir.create();

        final result = await BackupRestoreService.exportFullLibraryBundle(
          dbService: dbService,
          targetDirectoryPath: exportDir.path,
        );

        expect(result.copiedPdfsCount, 1);
        expect(result.manifestFile.existsSync(), isTrue);
        expect(result.bundleDirectory.existsSync(), isTrue);

        final copiedPdf = File(
          p.join(result.bundleDirectory.path, 'originals', 'bundle_book_1.pdf'),
        );
        expect(copiedPdf.existsSync(), isTrue);
        expect(copiedPdf.readAsStringSync(), contains('%PDF-1.4'));
      },
    );
  });
}
