import 'dart:convert';
import 'dart:io';

import 'package:digital_books/core/database/app_database.dart';
import 'package:digital_books/core/database/database_service.dart';
import 'package:digital_books/core/utils/file_storage_service.dart';
import 'package:digital_books/features/processing/models/processing_manifest.dart';
import 'package:digital_books/features/processing/services/book_reprocessor.dart';
import 'package:digital_books/features/processing/services/processed_artifact_inspector.dart';
import 'package:digital_books/features/reader/models/book_document.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DatabaseService dbService;
  late Directory tempDir;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dbService = DatabaseService(db);
    tempDir = await Directory.systemTemp.createTemp('phase38_artifact_');
    FileStorageService.customAppBaseDirectory = tempDir;
  });

  tearDown(() async {
    await db.close();
    FileStorageService.customAppBaseDirectory = null;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  BookBlock block(String id, String text, {int page = 1}) => BookBlock(
    id: id,
    type: BlockType.paragraph,
    text: text,
    originalPageNumber: page,
  );

  BookDocument document({
    required String title,
    required List<BookChapter> chapters,
    Map<String, dynamic> metadata = const {},
    int totalPages = 10,
  }) => BookDocument(
    id: 'doc-$title',
    title: title,
    author: 'Penulis',
    totalPages: totalPages,
    chapters: chapters,
    metadata: metadata,
  );

  BookDocument currentArtifact({
    List<BookChapter>? chapters,
    Map<String, dynamic> extraMetadata = const {},
  }) => document(
    title: 'Buku Uji',
    chapters:
        chapters ??
        [
          BookChapter(
            id: 'ch-1',
            index: 0,
            title: 'Bab Satu',
            blocks: [
              block('ch-1-b1', 'Pembukaan cerita yang panjang dan tenang.'),
              block('ch-1-b2', 'Kalimat kedua dengan pilihan kata.'),
            ],
          ),
        ],
    metadata: {
      ...ProcessingManifest(
        pipelineVersion: ProcessingManifest.currentPipelineVersion,
        artifactSchemaVersion: ProcessingManifest.currentArtifactSchemaVersion,
        processedAt: DateTime.now().toIso8601String(),
        source: 'nativeText',
      ).toMetadata(),
      ...extraMetadata,
    },
  );

  Future<File> writeArtifact(String path, BookDocument doc) async {
    final file = File(path);
    await file.writeAsString(doc.toJsonString(), flush: true);
    return file;
  }

  Future<String> writeSourcePdf() async {
    final source = File('${tempDir.path}/original.pdf');
    await source.writeAsBytes(List<int>.generate(2048, (i) => i % 251));
    return source.path;
  }

  BooksCompanion bookRow({
    required String id,
    required String sourcePath,
    required String artifactPath,
  }) => BooksCompanion(
    id: Value(id),
    title: const Value('Buku Uji'),
    author: const Value('Penulis'),
    originalPdfPath: Value(sourcePath),
    processedBookPath: Value(artifactPath),
    totalPages: const Value(10),
    createdAt: Value(DateTime.now()),
    updatedAt: Value(DateTime.now()),
  );

  group('stale artifact detection', () {
    test('artifact without manifest metadata is stale', () async {
      final status = await ProcessedArtifactInspector.inspectJson(
        document(
          title: 'Legacy',
          chapters: [
            BookChapter(
              id: 'c',
              index: 0,
              title: 'Bab',
              blocks: [block('b', 'Teks lama.')],
            ),
          ],
        ).toJsonString(),
      );

      expect(status.state, ProcessedArtifactState.stale);
      expect(status.manifest, isNull);
      expect(status.needsReprocessing, isTrue);
      expect(status.message, contains('pipeline version'));
    });

    test('artifact from an older pipeline version is stale', () async {
      final status = await ProcessedArtifactInspector.inspectJson(
        document(
          title: 'Lama',
          chapters: [
            BookChapter(
              id: 'c',
              index: 0,
              title: 'Bab',
              blocks: [block('b', 'Teks lama.')],
            ),
          ],
          metadata: const {
            'pipelineVersion': '3.7.0',
            'artifactSchemaVersion': 2,
          },
        ).toJsonString(),
      );

      expect(status.state, ProcessedArtifactState.stale);
      expect(status.message, contains('3.7.0'));
    });

    test('artifact with an older schema version is stale', () async {
      final status = await ProcessedArtifactInspector.inspectJson(
        document(
          title: 'Lama',
          chapters: [
            BookChapter(
              id: 'c',
              index: 0,
              title: 'Bab',
              blocks: [block('b', 'Teks lama.')],
            ),
          ],
          metadata: const {
            'pipelineVersion': ProcessingManifest.currentPipelineVersion,
            'artifactSchemaVersion': 1,
          },
        ).toJsonString(),
      );

      expect(status.state, ProcessedArtifactState.stale);
    });

    test('current artifact is reported as current', () async {
      final status = await ProcessedArtifactInspector.inspectJson(
        currentArtifact().toJsonString(),
      );

      expect(status.state, ProcessedArtifactState.current);
      expect(status.needsReprocessing, isFalse);
      expect(
        status.manifest?.pipelineVersion,
        ProcessingManifest.currentPipelineVersion,
      );
      expect(status.chapterCount, 1);
      expect(status.blockCount, 2);
    });

    test('newer artifact is not silently downgraded', () async {
      final status = await ProcessedArtifactInspector.inspectJson(
        document(
          title: 'Masa Depan',
          chapters: [
            BookChapter(
              id: 'c',
              index: 0,
              title: 'Bab',
              blocks: [block('b', 'Teks.')],
            ),
          ],
          metadata: const {
            'pipelineVersion': '9.0.0',
            'artifactSchemaVersion': 99,
          },
        ).toJsonString(),
      );

      expect(status.state, ProcessedArtifactState.newer);
      expect(status.needsReprocessing, isFalse);
      expect(status.isUsable, isTrue);
    });

    test(
      'artifact marked requiresOcr is incomplete instead of usable',
      () async {
        final status = await ProcessedArtifactInspector.inspectJson(
          currentArtifact(
            extraMetadata: {'processingStatus': 'requiresOcr'},
          ).toJsonString(),
        );

        expect(status.state, ProcessedArtifactState.incomplete);
        expect(status.needsReprocessing, isTrue);
      },
    );

    test('unreadable JSON is reported, not treated as current', () async {
      final status = await ProcessedArtifactInspector.inspectJson('{not json');
      expect(status.state, ProcessedArtifactState.unreadable);
    });

    test('changed source size marks the artifact stale', () async {
      final artifactPath = '${tempDir.path}/artifact.json';
      final sourcePath = await writeSourcePdf();
      final doc = document(
        title: 'Sumber Berubah',
        chapters: [
          BookChapter(
            id: 'c',
            index: 0,
            title: 'Bab',
            blocks: [block('b', 'Teks.')],
          ),
        ],
        metadata: {
          ...ProcessingManifest(
            pipelineVersion: ProcessingManifest.currentPipelineVersion,
            artifactSchemaVersion:
                ProcessingManifest.currentArtifactSchemaVersion,
            sourceFileSize: 10,
          ).toMetadata(),
        },
      );
      await writeArtifact(artifactPath, doc);

      final status = await ProcessedArtifactInspector.inspectPath(
        artifactPath,
        currentSourcePath: sourcePath,
      );

      expect(status.state, ProcessedArtifactState.stale);
      expect(status.message, contains('size changed'));
    });
  });

  group('safe reprocessing', () {
    test('reprocessing updates the artifact and preserves user data', () async {
      const bookId = 'book-reprocess';
      final sourcePath = await writeSourcePdf();
      final artifactPath = '${tempDir.path}/$bookId.json';

      final oldDoc = document(
        title: 'Buku Uji',
        chapters: [
          BookChapter(
            id: 'old-ch-1',
            index: 0,
            title: 'Bab Satu',
            blocks: [
              block('old-b1', 'Pembukaan cerita yang panjang dan tenang.'),
              block('old-b2', 'Kalimat kedua dengan pilihan kata.'),
            ],
          ),
        ],
        metadata: const {
          'pipelineVersion': '3.7.0',
          'artifactSchemaVersion': 2,
        },
      );
      await writeArtifact(artifactPath, oldDoc);

      await dbService.insertBook(
        bookRow(id: bookId, sourcePath: sourcePath, artifactPath: artifactPath),
      );
      await dbService.addBookmark(
        BookmarksCompanion(
          id: const Value('bookmark-1'),
          bookId: const Value(bookId),
          chapterId: const Value('old-ch-1'),
          position: const Value(1),
          label: const Value('Bab Satu'),
          anchorNodeId: const Value('old-b2'),
          characterOffset: const Value(0),
          pageIndex: const Value(1),
          createdAt: Value(DateTime.now()),
        ),
      );
      await dbService.addHighlight(
        HighlightsCompanion(
          id: const Value('highlight-1'),
          bookId: const Value(bookId),
          chapterId: const Value('old-ch-1'),
          selectedText: const Value('kedua'),
          startPosition: const Value(1),
          endPosition: const Value(1),
          anchorNodeId: const Value('old-b2'),
          startOffset: const Value(8),
          endOffset: const Value(13),
          pageIndex: const Value(1),
          createdAt: Value(DateTime.now()),
        ),
      );
      await dbService.upsertProgress(
        ReadingProgressesCompanion(
          id: const Value('progress-1'),
          bookId: const Value(bookId),
          currentChapter: const Value(0),
          currentPosition: const Value(1),
          progressPercentage: const Value(0.42),
          lastReadingMode: const Value('reflowable'),
          lastReadAt: Value(DateTime.now()),
        ),
      );

      final sourceBefore = await File(sourcePath).readAsBytes();
      final book = (await dbService.getBookById(bookId))!;

      final newDoc = document(
        title: 'Buku Uji',
        chapters: [
          BookChapter(
            id: 'new-ch-1',
            index: 0,
            title: 'Bab Satu',
            blocks: [
              block('new-b1', 'Pembukaan cerita yang panjang dan tenang.'),
              block('new-b2', 'Kalimat kedua dengan pilihan kata.'),
            ],
          ),
          BookChapter(
            id: 'new-ch-2',
            index: 1,
            title: 'Bab Dua',
            blocks: [block('new-b3', 'Isi bab kedua.')],
          ),
        ],
      );

      final outcome = await BookReprocessor(
        dbService,
      ).reprocess(book: book, buildDocument: () async => newDoc);

      expect(outcome.status, ReprocessStatus.reprocessed);
      expect(outcome.relocatedBookmarks, 1);
      expect(outcome.relocatedHighlights, 1);
      expect(outcome.progressMapped, isTrue);
      expect(outcome.after?.state, ProcessedArtifactState.current);

      final saved = BookDocument.fromJsonString(
        await File(artifactPath).readAsString(),
      );
      expect(
        saved.metadata['pipelineVersion'],
        ProcessingManifest.currentPipelineVersion,
      );
      expect(saved.chapters.map((c) => c.title), ['Bab Satu', 'Bab Dua']);

      final bookmarks = await dbService.getBookmarksForBook(bookId);
      expect(bookmarks, hasLength(1));
      expect(bookmarks.single.id, 'bookmark-1');
      expect(bookmarks.single.chapterId, 'new-ch-1');
      expect(bookmarks.single.anchorNodeId, 'new-b2');

      final highlights = await dbService.getHighlightsForBook(bookId);
      expect(highlights, hasLength(1));
      expect(highlights.single.id, 'highlight-1');
      expect(highlights.single.chapterId, 'new-ch-1');
      expect(highlights.single.anchorNodeId, 'new-b2');
      expect(highlights.single.startOffset, 8);
      expect(highlights.single.endOffset, 13);
      expect(highlights.single.anchorStatus, 'resolved');

      final progress = await dbService.getProgress(bookId);
      expect(progress, isNotNull);
      expect(progress!.currentChapter, 0);
      expect(progress.currentPosition, 1);
      expect(progress.progressPercentage, closeTo(0.42, 0.0001));

      final chapters = await dbService.getChaptersForBook(bookId);
      expect(chapters.map((c) => c.title), ['Bab Satu', 'Bab Dua']);

      expect(await File(sourcePath).readAsBytes(), sourceBefore);
    });

    test('incomplete candidate never replaces the previous artifact', () async {
      const bookId = 'book-reject';
      final sourcePath = await writeSourcePdf();
      final artifactPath = '${tempDir.path}/$bookId.json';
      await writeArtifact(artifactPath, currentArtifact());
      await dbService.insertBook(
        bookRow(id: bookId, sourcePath: sourcePath, artifactPath: artifactPath),
      );
      final before = await File(artifactPath).readAsBytes();
      final book = (await dbService.getBookById(bookId))!;

      final outcome = await BookReprocessor(dbService).reprocess(
        book: book,
        buildDocument: () async => document(
          title: 'Buku Uji',
          chapters: [
            BookChapter(
              id: 'bad',
              index: 0,
              title: 'Bab',
              blocks: [block('bad-b', 'Teks.')],
            ),
          ],
          metadata: const {
            'pipelineVersion': '3.8.0',
            'artifactSchemaVersion': 2,
            'processingStatus': 'requiresOcr',
          },
        ),
        force: true,
      );

      expect(outcome.status, ReprocessStatus.rejectedIncompleteOutput);
      expect(await File(artifactPath).readAsBytes(), before);
    });

    test('database failure restores the previous artifact bytes', () async {
      const bookId = 'book-rollback';
      final sourcePath = await writeSourcePdf();
      final artifactPath = '${tempDir.path}/$bookId.json';
      await writeArtifact(artifactPath, currentArtifact());
      await dbService.insertBook(
        bookRow(id: bookId, sourcePath: sourcePath, artifactPath: artifactPath),
      );
      final before = await File(artifactPath).readAsBytes();
      final book = (await dbService.getBookById(bookId))!;

      // Duplicate chapter IDs make the database transaction fail after the
      // artifact has already been swapped on disk.
      final outcome = await BookReprocessor(dbService).reprocess(
        book: book,
        buildDocument: () async => document(
          title: 'Buku Uji',
          chapters: [
            BookChapter(
              id: 'duplicate',
              index: 0,
              title: 'Bab Satu',
              blocks: [block('a', 'Isi bab satu.')],
            ),
            BookChapter(
              id: 'duplicate',
              index: 1,
              title: 'Bab Dua',
              blocks: [block('b', 'Isi bab dua.')],
            ),
          ],
        ),
        force: true,
      );

      expect(outcome.status, ReprocessStatus.failed);
      expect(outcome.rolledBack, isTrue);
      expect(await File(artifactPath).readAsBytes(), before);
      expect(await File('$artifactPath.reprocess').exists(), isFalse);
      expect(await File('$artifactPath.bak').exists(), isFalse);
    });

    test('reconstruction failure leaves the artifact untouched', () async {
      const bookId = 'book-throw';
      final sourcePath = await writeSourcePdf();
      final artifactPath = '${tempDir.path}/$bookId.json';
      await writeArtifact(artifactPath, currentArtifact());
      await dbService.insertBook(
        bookRow(id: bookId, sourcePath: sourcePath, artifactPath: artifactPath),
      );
      final before = await File(artifactPath).readAsBytes();
      final book = (await dbService.getBookById(bookId))!;

      final outcome = await BookReprocessor(dbService).reprocess(
        book: book,
        buildDocument: () async => throw StateError('extractor exploded'),
        force: true,
      );

      expect(outcome.status, ReprocessStatus.failed);
      expect(outcome.message, contains('extractor exploded'));
      expect(await File(artifactPath).readAsBytes(), before);
    });

    test('reprocessing is idempotent when the artifact is current', () async {
      const bookId = 'book-idempotent';
      final sourcePath = await writeSourcePdf();
      final artifactPath = '${tempDir.path}/$bookId.json';
      final newDoc = currentArtifact();
      await writeArtifact(artifactPath, newDoc);
      await dbService.insertBook(
        bookRow(id: bookId, sourcePath: sourcePath, artifactPath: artifactPath),
      );
      final book = (await dbService.getBookById(bookId))!;
      final before = await File(artifactPath).readAsBytes();

      final outcome = await BookReprocessor(
        dbService,
      ).reprocess(book: book, buildDocument: () async => newDoc);

      expect(outcome.status, ReprocessStatus.alreadyCurrent);
      expect(await File(artifactPath).readAsBytes(), before);
    });

    test(
      'missing source PDF is reported without touching the artifact',
      () async {
        const bookId = 'book-missing-source';
        final artifactPath = '${tempDir.path}/$bookId.json';
        await writeArtifact(artifactPath, currentArtifact());
        await dbService.insertBook(
          bookRow(
            id: bookId,
            sourcePath: '${tempDir.path}/does-not-exist.pdf',
            artifactPath: artifactPath,
          ),
        );
        final book = (await dbService.getBookById(bookId))!;
        final before = await File(artifactPath).readAsBytes();

        final outcome = await BookReprocessor(dbService).reprocess(
          book: book,
          buildDocument: () async => currentArtifact(),
          force: true,
        );

        expect(outcome.status, ReprocessStatus.missingSource);
        expect(await File(artifactPath).readAsBytes(), before);
      },
    );

    test(
      'reprocessing recovers an interrupted swap before deciding freshness',
      () async {
        const bookId = 'book-interrupted';
        final sourcePath = await writeSourcePdf();
        final artifactPath = '${tempDir.path}/$bookId.json';

        final stale = document(
          title: 'Buku Uji',
          chapters: [
            BookChapter(
              id: 'old-ch',
              index: 0,
              title: 'Bab Satu',
              blocks: [block('old-b', 'Teks lama yang masih valid.')],
            ),
          ],
          metadata: const {
            'pipelineVersion': '3.7.0',
            'artifactSchemaVersion': 2,
          },
        );
        await writeArtifact('$artifactPath.bak', stale);
        await File(
          '$artifactPath.reprocess',
        ).writeAsString(jsonEncode({'bookId': bookId}));
        await File(artifactPath).writeAsString('{"interrupted":', flush: true);

        await dbService.insertBook(
          bookRow(
            id: bookId,
            sourcePath: sourcePath,
            artifactPath: artifactPath,
          ),
        );
        final book = (await dbService.getBookById(bookId))!;

        final outcome = await BookReprocessor(dbService).reprocess(
          book: book,
          buildDocument: () async => document(
            title: 'Buku Uji',
            chapters: [
              BookChapter(
                id: 'new-ch',
                index: 0,
                title: 'Bab Satu',
                blocks: [block('new-b', 'Teks baru hasil pemrosesan ulang.')],
              ),
            ],
          ),
        );

        expect(outcome.status, ReprocessStatus.reprocessed);
        final saved = BookDocument.fromJsonString(
          await File(artifactPath).readAsString(),
        );
        expect(
          saved.chapters.single.blocks.single.text,
          'Teks baru hasil pemrosesan ulang.',
        );
        expect(await File('$artifactPath.reprocess').exists(), isFalse);
        expect(await File('$artifactPath.bak').exists(), isFalse);
      },
    );
  });

  group('interrupted processing recovery', () {
    test('an unfinished reprocess restores the backup artifact', () async {
      final artifactPath = '${tempDir.path}/recover.json';
      await writeArtifact(artifactPath, currentArtifact());
      final oldBytes = await File(artifactPath).readAsBytes();

      await File('$artifactPath.bak').writeAsBytes(oldBytes, flush: true);
      await File(
        '$artifactPath.reprocess',
      ).writeAsString(jsonEncode({'bookId': 'x', 'startedAt': 'now'}));
      await File(artifactPath).writeAsString('{"broken":', flush: true);

      final result = await ProcessedArtifactInspector.recoverInterrupted(
        artifactPath,
      );

      expect(result, ArtifactRecoveryResult.restoredBackup);
      expect(await File(artifactPath).readAsBytes(), oldBytes);
      expect(await File('$artifactPath.reprocess').exists(), isFalse);
      expect(await File('$artifactPath.bak').exists(), isFalse);
    });

    test('a completed artifact is kept and its stale backup removed', () async {
      final artifactPath = '${tempDir.path}/recover-clean.json';
      await writeArtifact(artifactPath, currentArtifact());
      await File('$artifactPath.bak').writeAsString('old');

      final result = await ProcessedArtifactInspector.recoverInterrupted(
        artifactPath,
      );

      expect(result, ArtifactRecoveryResult.cleanedBackup);
      expect(await File('$artifactPath.bak').exists(), isFalse);
      final status = await ProcessedArtifactInspector.inspectPath(artifactPath);
      expect(status.state, ProcessedArtifactState.current);
    });

    test('a committed reprocess keeps the new artifact on recovery', () async {
      final artifactPath = '${tempDir.path}/recover-committed.json';
      await writeArtifact(artifactPath, currentArtifact());
      final newBytes = await File(artifactPath).readAsBytes();
      await File('$artifactPath.bak').writeAsString('{"old":true}');
      await File(
        '$artifactPath.reprocess',
      ).writeAsString(jsonEncode({'bookId': 'x', 'phase': 'committed'}));

      final result = await ProcessedArtifactInspector.recoverInterrupted(
        artifactPath,
      );

      expect(result, ArtifactRecoveryResult.cleanedBackup);
      expect(await File(artifactPath).readAsBytes(), newBytes);
      expect(await File('$artifactPath.reprocess').exists(), isFalse);
      expect(await File('$artifactPath.bak').exists(), isFalse);
    });
  });
}
