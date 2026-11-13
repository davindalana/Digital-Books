import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:digital_books/core/constants/app_info.dart';
import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/core/services/backup_restore_service.dart';
import 'package:digital_books/core/theme/reading_theme.dart';
import 'package:digital_books/features/reader/domain/engines/in_book_search_engine.dart';
import 'package:digital_books/features/reader/domain/engines/reflowable_highlight_span_builder.dart';
import 'package:digital_books/features/reader/domain/models/reader_content.dart';

void main() {
  group('Phase 2.5 — Local Backup & Restore Service Tests', () {
    late AppDatabase db;
    late DatabaseService dbService;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      dbService = DatabaseService(db);

      // Seed initial book
      final now = DateTime.now();
      await dbService.insertBook(
        BooksCompanion.insert(
          id: 'book_initial_1',
          title: 'The Sign of the Four',
          author: 'Arthur Conan Doyle',
          originalPdfPath: '/storage/originals/book_initial_1.pdf',
          fileHash: const drift.Value('hash_initial_123'),
          totalPages: const drift.Value(150),
          createdAt: now,
          updatedAt: now,
        ),
      );

      await dbService.replaceChaptersForBook('book_initial_1', [
        ChaptersCompanion.insert(
          id: 'ch_1',
          bookId: 'book_initial_1',
          title: 'Chapter 1: The Science of Deduction',
          chapterIndex: 0,
        ),
        ChaptersCompanion.insert(
          id: 'ch_2',
          bookId: 'book_initial_1',
          title: 'Chapter 2: The Statement of the Case',
          chapterIndex: 1,
        ),
      ]);

      await dbService.upsertProgress(
        ReadingProgressesCompanion.insert(
          id: 'prog_1',
          bookId: 'book_initial_1',
          currentChapter: const drift.Value(1),
          currentPosition: const drift.Value(5),
          progressPercentage: const drift.Value(0.45),
          lastReadingMode: const drift.Value('reflowable_paginated'),
          lastReadAt: now,
        ),
      );

      await dbService.addBookmark(
        BookmarksCompanion.insert(
          id: 'bm_1',
          bookId: 'book_initial_1',
          position: 5,
          label: 'Important deduction scene',
          anchorNodeId: const drift.Value('p_1_3'),
          characterOffset: const drift.Value(12),
          createdAt: now,
        ),
      );

      await dbService.addHighlight(
        HighlightsCompanion.insert(
          id: 'hl_1',
          bookId: 'book_initial_1',
          selectedText: 'Eliminate all other factors',
          startPosition: 5,
          endPosition: 5,
          color: const drift.Value('yellow'),
          note: const drift.Value('Key investigative maxim'),
          anchorNodeId: const drift.Value('p_1_3'),
          startOffset: const drift.Value(12),
          endOffset: const drift.Value(38),
          createdAt: now,
        ),
      );

      await dbService.createCollection(
        CollectionsCompanion.insert(
          id: 'col_mysteries',
          name: 'Classic Mysteries',
          description: const drift.Value('Detective and suspense fiction'),
          createdAt: now,
        ),
      );
      await dbService.addBookToCollection('book_initial_1', 'col_mysteries');
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'generateBackupJson exports complete metadata, progress, annotations & collections',
      () async {
        final jsonStr = await BackupRestoreService.generateBackupJson(
          dbService: dbService,
          preferences: {'defaultTheme': 'sepia', 'twoPageSpread': true},
        );

        final data = jsonDecode(jsonStr) as Map<String, dynamic>;
        expect(data['metadata']['formatVersion'], '1.0');
        expect(data['metadata']['appVersion'], AppInfo.technicalVersion);
        expect(data['preferences']['defaultTheme'], 'sepia');

        final books = data['books'] as List;
        expect(books.length, 1);
        final book = books.first;
        expect(book['title'], 'The Sign of the Four');
        expect(book['fileHash'], 'hash_initial_123');
        expect(book['collectionIds'], contains('col_mysteries'));

        final chapters = book['chapters'] as List;
        expect(chapters.length, 2);

        final progress = book['readingProgress'];
        expect(progress['progressPercentage'], 0.45);

        final bookmarks = book['bookmarks'] as List;
        expect(bookmarks.length, 1);
        expect(bookmarks.first['label'], 'Important deduction scene');

        final highlights = book['highlights'] as List;
        expect(highlights.length, 1);
        expect(highlights.first['selectedText'], 'Eliminate all other factors');
        expect(highlights.first['note'], 'Key investigative maxim');

        final collections = data['collections'] as List;
        expect(collections.length, 1);
        expect(collections.first['name'], 'Classic Mysteries');
      },
    );

    test(
      'previewBackup accurately calculates existing and new items without modifying database',
      () async {
        // Create backup json
        final jsonStr = await BackupRestoreService.generateBackupJson(
          dbService: dbService,
        );

        // Preview on the same database
        final preview = await BackupRestoreService.previewBackup(
          jsonStr,
          dbService: dbService,
        );
        expect(preview.totalBooks, 1);
        expect(preview.existingBooks, 1);
        expect(preview.newBooks, 0);
        expect(preview.totalBookmarks, 1);
        expect(preview.totalHighlights, 1);
        expect(preview.totalCollections, 1);
        expect(preview.bookTitles, contains('The Sign of the Four'));

        // Preview on an empty database
        final emptyDb = AppDatabase(NativeDatabase.memory());
        final emptyDbService = DatabaseService(emptyDb);

        final emptyPreview = await BackupRestoreService.previewBackup(
          jsonStr,
          dbService: emptyDbService,
        );
        expect(emptyPreview.totalBooks, 1);
        expect(emptyPreview.existingBooks, 0);
        expect(emptyPreview.newBooks, 1);

        await emptyDb.close();
      },
    );

    test(
      'executeRestore with skipExisting policy preserves existing records and imports new ones safely',
      () async {
        // Create a backup containing book 1 and a new book 2
        final now = DateTime.now();
        final backupPayload = {
          'metadata': {
            'formatVersion': '1.0',
            'appVersion': '0.2.6',
            'exportedAt': now.toIso8601String(),
          },
          'collections': [
            {
              'id': 'col_sci_fi',
              'name': 'Science Fiction',
              'description': 'Futuristic novels',
              'createdAt': now.toIso8601String(),
            },
          ],
          'books': [
            // Book 1: with modified title in backup (should be skipped) and a new bookmark
            {
              'id': 'book_initial_1',
              'title': 'The Sign of the Four (Modified In Backup)',
              'author': 'Arthur Conan Doyle',
              'originalPdfPath': '/storage/originals/book_initial_1.pdf',
              'fileHash': 'hash_initial_123',
              'totalPages': 150,
              'isScanned': false,
              'createdAt': now.toIso8601String(),
              'updatedAt': now.toIso8601String(),
              'collectionIds': ['col_mysteries'],
              'chapters': [],
              'bookmarks': [
                {
                  'id': 'bm_2',
                  'chapterId': 'ch_1',
                  'position': 12,
                  'label': 'New merged bookmark',
                  'anchorNodeId': 'p_1_8',
                  'characterOffset': 0,
                  'progressPercentage': 0.8,
                  'createdAt': now.toIso8601String(),
                },
              ],
              'highlights': [],
            },
            // Book 2: completely new book
            {
              'id': 'book_new_2',
              'title': 'The Time Machine',
              'author': 'H.G. Wells',
              'originalPdfPath': '/storage/originals/time_machine.pdf',
              'fileHash': 'hash_time_machine_456',
              'totalPages': 90,
              'isScanned': false,
              'createdAt': now.toIso8601String(),
              'updatedAt': now.toIso8601String(),
              'collectionIds': ['col_sci_fi'],
              'chapters': [
                {
                  'id': 'tm_ch_1',
                  'title': 'Chapter 1: The Inventor',
                  'chapterIndex': 0,
                  'startPosition': 0,
                  'endPosition': 10,
                },
              ],
              'bookmarks': [],
              'highlights': [
                {
                  'id': 'tm_hl_1',
                  'chapterId': 'tm_ch_1',
                  'selectedText': 'There are really four dimensions',
                  'startPosition': 2,
                  'endPosition': 2,
                  'color': 'cyan',
                  'note': 'Time concept',
                  'anchorNodeId': 'tm_p_1',
                  'startOffset': 0,
                  'endOffset': 30,
                  'createdAt': now.toIso8601String(),
                },
              ],
            },
          ],
        };

        final jsonStr = jsonEncode(backupPayload);
        final result = await BackupRestoreService.executeRestore(
          backupJson: jsonStr,
          dbService: dbService,
          policy: RestoreConflictPolicy.skipExisting,
        );

        expect(result.booksRestored, 1); // Book 2
        expect(result.booksSkipped, 1); // Book 1
        expect(result.bookmarksRestored, 1); // bm_2 merged into book 1
        expect(result.highlightsRestored, 1); // tm_hl_1 for book 2
        expect(result.collectionsRestored, 1); // col_sci_fi

        // Verify book 1 title was NOT overwritten
        final book1 = await dbService.getBookById('book_initial_1');
        expect(book1!.title, 'The Sign of the Four');

        // Verify book 1 now has 2 bookmarks (original + merged)
        final book1Bookmarks = await dbService.getBookmarksForBook(
          'book_initial_1',
        );
        expect(book1Bookmarks.length, 2);

        // Verify book 2 was imported
        final book2 = await dbService.getBookById('book_new_2');
        expect(book2, isNotNull);
        expect(book2!.author, 'H.G. Wells');
        final book2Chapters = await dbService.getChaptersForBook('book_new_2');
        expect(book2Chapters.length, 1);
      },
    );

    test(
      'executeRestore with mergeUpdateExisting policy updates metadata and progress',
      () async {
        final now = DateTime.now();
        final backupPayload = {
          'metadata': {'formatVersion': '1.0', 'appVersion': '0.2.6'},
          'collections': [],
          'books': [
            {
              'id': 'book_initial_1',
              'title': 'The Sign of the Four (Updated Edition)',
              'author': 'Sir Arthur Conan Doyle',
              'originalPdfPath': '/storage/originals/book_initial_1.pdf',
              'fileHash': 'hash_initial_123',
              'totalPages': 150,
              'isScanned': false,
              'createdAt': now.toIso8601String(),
              'updatedAt': now.toIso8601String(),
              'readingProgress': {
                'currentChapter': 2,
                'currentPosition': 10,
                'progressPercentage': 0.95,
                'lastReadingMode': 'reflowable_paginated',
                'lastReadAt': now.toIso8601String(),
              },
              'bookmarks': [],
              'highlights': [],
            },
          ],
        };

        final result = await BackupRestoreService.executeRestore(
          backupJson: jsonEncode(backupPayload),
          dbService: dbService,
          policy: RestoreConflictPolicy.mergeUpdateExisting,
        );

        expect(result.booksUpdated, 1);

        final updatedBook = await dbService.getBookById('book_initial_1');
        expect(updatedBook!.title, 'The Sign of the Four (Updated Edition)');
        expect(updatedBook.author, 'Sir Arthur Conan Doyle');

        final prog = await dbService.getProgress('book_initial_1');
        expect(prog!.progressPercentage, 0.95);
      },
    );
  });

  group('Phase 2.5 — In-Book Search & Scale Stress Tests', () {
    test(
      'Searches massive 500,000-word document within performance SLA with correct context',
      () async {
        final chapters = <ReaderChapter>[];

        for (int ch = 0; ch < 50; ch++) {
          final nodes = <ContentNode>[
            ContentNode(
              id: 'h_$ch',
              type: ContentNodeType.heading,
              text: 'Chapter $ch: The Grand Investigation',
              level: 1,
            ),
            ContentNode(
              id: 'p_${ch}_1',
              type: ContentNodeType.paragraph,
              text:
                  'This is paragraph one of chapter $ch discussing Sherlock Holmes and forensic deductions.',
            ),
            ContentNode(
              id: 'p_${ch}_2',
              type: ContentNodeType.paragraph,
              text:
                  'Another paragraph containing forensic deductions and analytical methods observed in London.',
            ),
          ];

          chapters.add(
            ReaderChapter(
              id: 'ch_$ch',
              index: ch,
              title: 'Chapter $ch',
              nodes: nodes,
            ),
          );
        }

        final doc = ReaderDocument(
          bookId: 'scale_doc',
          title: 'Scale Document',
          author: 'Benchmark',
          chapters: chapters,
        );

        final sw = Stopwatch()..start();
        final results = await InBookSearchEngine.search(
          document: doc,
          query: 'forensic deductions',
        );
        sw.stop();

        // 50 chapters * 2 matches per chapter = 100 matches
        expect(results.length, 100);
        expect(sw.elapsedMilliseconds, lessThan(100)); // Well under 100ms
        expect(results.first.snippet, contains('forensic deductions'));
        expect(results.first.chapterTitle, 'Chapter 0');
      },
    );

    test(
      'ReflowableHighlightSpanBuilder handles dense overlapping highlight boundaries gracefully',
      () {
        final text =
            'Sherlock Holmes carefully inspected the mysterious clue upon the desk in Baker Street.';

        // Generate 20 overlapping highlights
        final userHighlights = List.generate(20, (i) {
          return Highlight(
            id: 'hl_$i',
            bookId: 'test_book',
            selectedText: text.substring(0, 15),
            startPosition: 1,
            endPosition: 1,
            color: 'yellow',
            createdAt: DateTime.now(),
            anchorVersion: 1,
            startOffset: 0,
            endOffset: 15,
          );
        });

        final activeSearch = [
          const ActiveSearchMatch(
            nodeId: 'node_1',
            startOffset: 9,
            endOffset: 15,
          ),
        ];

        final span = ReflowableHighlightSpanBuilder.buildRichSpan(
          text: text,
          sliceStartOffset: 0,
          sliceEndOffset: text.length,
          highlightsForNode: userHighlights,
          searchMatchesForNode: activeSearch,
          baseStyle: const TextStyle(color: Colors.black),
          theme: ReadingThemeType.white,
        );

        expect(span, isNotNull);
        expect(span.toPlainText(), equals(text));
      },
    );
  });
}
